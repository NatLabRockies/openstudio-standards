require 'openstudio'

module OpenStudioLighting
  module Costing
    # Lighting fixture costing — port of legacy cost_audit_lighting: per tagged
    # space, the lighting_sets row (template x building_type x space_type x
    # CFL/LED) picks a fixture type by average ceiling-height bin
    # (<7.88 ft / 7.88-15.75 / >15.75); the fixture's id_layers x quantity
    # multipliers price through materials_lighting -> costs -> regional factors,
    # x floor area (ft2) x zone multiplier.
    #
    # Fidelity notes (audited):
    # - legacy detect ignores the sets sheet's min/max_stories columns (first
    #   match wins) — preserved;
    # - legacy FORCES light type LED whenever the template is NECB2020 regardless
    #   of the modeled lights; this port detects the ACTUAL Lights definitions
    #   ('- LED lighting' suffix) and only falls back to the template assumption
    #   when a type cannot be detected — deviation audited;
    # - daylighting-sensor costing is NOT ported (it derives sensor counts from
    #   the 8.4.4.5 daylighting-area geometry this gem family does not model):
    #   models WITHOUT daylighting controls cost $0 there exactly like legacy;
    #   models WITH controls get a LOUD warning instead of a silent zero.
    module Fixtures
      module_function

      HEIGHT_COLUMNS = [
        [7.88, 'Fixture_type_less_than_7.88ft_ht'],
        [15.75, 'Fixture_type_7.88_to_15.75ft_ht'],
        [Float::INFINITY, 'Fixture_type_greater_than_>15.75ft_ht']
      ].freeze

      def cost(model, database:, vintage:, province_state:, city:, audit:)
        template = "NECB#{vintage}"
        section = { 'space_report' => [], 'fixture_report' => [], 'total_lighting_cost' => 0.0 }
        total = 0.0

        model.getThermalZones.sort_by(&:nameString).each do |zone|
          zone.spaces.sort_by(&:nameString).each do |space|
            line = cost_space(space, zone, database, template, province_state, city, audit)
            next if line.nil?

            total += line['cost']
            section['space_report'] << line
            accumulate_fixture(section['fixture_report'], line)
          end
        end

        total += daylighting_note(model, database, template, province_state, city, section, audit)
        section['total_lighting_cost'] = total.round(2)
        audit.decision(:costing_lighting, 'lighting fixtures costed by space (ceiling-height fixture bins)',
                       inputs: { spaces: section['space_report'].size, template: template },
                       value: "$#{total.round(2)}")
        section
      end

      def cost_space(space, zone, database, template, province_state, city, audit)
        if space.spaceType.empty? || space.spaceType.get.standardsSpaceType.empty? ||
           space.spaceType.get.standardsBuildingType.empty?
          audit.warn(:costing_lighting, "space '#{space.nameString}' has no standards space type — not costed")
          return nil
        end

        space_type = space.spaceType.get.standardsSpaceType.get
        building_type = space.spaceType.get.standardsBuildingType.get
        light_type = detect_light_type(space, template, audit)

        match = lambda do |type|
          database.lighting_sets.find do |row|
            row['template'].to_s.gsub(/\s*/, '') == template &&
              row['building_type'].to_s.downcase == building_type.downcase &&
              row['space_type'].to_s.downcase == space_type.downcase &&
              (type.nil? || row['Type'].to_s.casecmp(type).zero?)
          end
        end
        set = match.call(light_type)
        if set.nil? && light_type
          # the NECB2020 sets are LED-only (which is why legacy hard-forces LED
          # for that template) — fall back to whatever type the sheet carries
          set = match.call(nil)
          if set
            audit.info(:costing_lighting,
                       "no #{light_type} lighting set for #{template} — costed with the sheet's " \
                       "#{set['Type']} set (the #{template} catalog carries only #{set['Type']})",
                       target: space.nameString)
            light_type = set['Type']
          end
        end
        if set.nil?
          audit.warn(:costing_lighting,
                     "no lighting_sets row for [#{template}, #{building_type}, #{space_type}, #{light_type}] — not costed",
                     target: space.nameString)
          return nil
        end

        floor_area_m2 = space.floorArea
        return nil if floor_area_m2 <= 0

        ceiling_ft = OpenStudio.convert(space.volume / floor_area_m2, 'm', 'ft').get
        floor_ft2 = OpenStudio.convert(floor_area_m2, 'm^2', 'ft^2').get
        column = HEIGHT_COLUMNS.find { |limit, _| ceiling_ft < limit }[1]
        fixture_type = set[column]
        return zero_line(space, zone, fixture_type, ceiling_ft, floor_ft2) if fixture_type.to_s == 'Nil' || fixture_type.to_s.empty?

        fixture = database.lighting.find { |row| row['lighting_type_id'].to_s == fixture_type.to_s }
        raise(ArgumentError, "no lighting row for fixture type id #{fixture_type}") if fixture.nil?

        multiplier = zone.multiplier
        material_total = 0.0
        labour_total = 0.0
        regional = [100.0, 100.0]
        ids = fixture['id_layers'].to_s.split(/\s*,\s*/)
        mults = fixture['Id_layers_quantity_multipliers'].to_s.split(/\s*,\s*/)
        ids.zip(mults).each do |layer_id, layer_mult|
          material = database.materials_lighting.find { |row| row['lighting_type_id'].to_s == layer_id.to_s }
          raise(ArgumentError, "lighting material #{layer_id} not in materials_lighting") if material.nil?

          costs = database.cost_record(material['id'])
          material_total += costs['materialOpCost'] * layer_mult.to_f * floor_ft2 * multiplier
          labour_total += costs['laborOpCost'] * layer_mult.to_f * floor_ft2 * multiplier
          regional = database.regional_factors(province_state, city, material['id'])
        end
        cost = material_total * regional[0] / 100.0 + labour_total * regional[1] / 100.0

        audit.info(:costing_lighting, 'space lighting fixtures costed',
                   target: space.nameString,
                   inputs: { fixture_type: fixture_type, light_type: light_type || set['Type'],
                             ceiling_ft: ceiling_ft.round(1), floor_ft2: (floor_ft2 * multiplier).round(1) },
                   value: "$#{cost.round(2)}", evidence: fixture['description'].to_s[0, 80])
        { 'space' => space.nameString, 'zone' => zone.nameString,
          'building_type' => building_type, 'space_type' => space_type,
          'zone_multiplier' => multiplier, 'fixture_type' => fixture_type,
          'fixture_description' => fixture['description'],
          'height_avg_ft' => ceiling_ft.round(1),
          'floor_area_ft2' => (floor_ft2 * multiplier).round(1),
          'cost' => cost.round(2),
          'cost_per_ft2' => (cost / (floor_ft2 * multiplier)).round(2) }
      end

      # Actual-model detection first; template assumption only as fallback (legacy
      # unconditionally forces LED for NECB2020 — deviation audited at cost()).
      def detect_light_type(space, template, _audit)
        return nil if space.spaceType.empty?

        lights = space.spaceType.get.lights
        return (template == 'NECB2020' || template == 'NECB2025' ? 'LED' : 'CFL') if lights.empty?

        lights.any? { |l| l.lightsDefinition.nameString.include?('LED lighting') } ? 'LED' : 'CFL'
      end

      def zero_line(space, zone, fixture_type, ceiling_ft, floor_ft2)
        { 'space' => space.nameString, 'zone' => zone.nameString,
          'building_type' => space.spaceType.get.standardsBuildingType.get,
          'space_type' => space.spaceType.get.standardsSpaceType.get,
          'zone_multiplier' => zone.multiplier, 'fixture_type' => fixture_type.to_s,
          'fixture_description' => '', 'height_avg_ft' => ceiling_ft.round(1),
          'floor_area_ft2' => (floor_ft2 * zone.multiplier).round(1),
          'cost' => 0.0, 'cost_per_ft2' => 0.0 }
      end

      def accumulate_fixture(report, line)
        row = report.find { |r| r['fixture_type'] == line['fixture_type'] }
        if row.nil?
          report << { 'fixture_type' => line['fixture_type'],
                      'fixture_description' => line['fixture_description'],
                      'floor_area_ft2' => line['floor_area_ft2'], 'cost' => line['cost'],
                      'spaces' => [line['space']], 'number_of_spaces' => 1 }
        else
          row['floor_area_ft2'] = (row['floor_area_ft2'] + line['floor_area_ft2']).round(1)
          row['cost'] = (row['cost'] + line['cost']).round(2)
          row['spaces'] << line['space']
          row['number_of_spaces'] = row['spaces'].size
        end
      end

      # Daylighting-sensor costing (port of cost_audit_daylighting_sensor_control's
      # per-sensor BOM: sensor row 407 + wiring row 10 x 0.3 CLF + PVC conduit row
      # 17 x 30 LF + box row 14, per sensor x zone multiplier). Sensor counts:
      # ceil(fixtures / 4) per zone — DEVIATION (audited): legacy derives the
      # fixture count from the DAYLIGHTED-AREA portion (primary sidelighted /
      # under-skylight geometry, not yet ported); this port uses the zone's whole
      # floor area x the fixture density, an upper bound.
      SENSOR_BOM = [[407, 1.0, 'daylight sensor (remote, dimming)'],
                    [10, 30.0 / 100.0, 'sensor wiring (30 ft)'],
                    [17, 30.0, 'sensor PVC conduit (30 ft)'],
                    [14, 1.0, 'sensor box']].freeze

      def daylighting_note(model, database, template, province_state, city, section, audit)
        zones = model.getThermalZones.sort_by(&:nameString).select { |z| z.primaryDaylightingControl.is_initialized }
        if zones.empty?
          audit.info(:costing_lighting, 'no daylighting controls in the model — daylighting-sensor costing $0 (matches legacy)')
          return 0.0
        end

        total = 0.0
        sensors_total = 0
        zones.each do |zone|
          fixtures = zone_fixture_count(zone, database, template)
          sensors = (fixtures / 4.0).ceil * zone.multiplier
          next if sensors.zero?

          sensors_total += sensors
          SENSOR_BOM.each do |layer_id, quantity, label|
            material = database.materials_lighting.find { |row| row['lighting_type_id'].to_s == layer_id.to_s }
            next if material.nil?

            costs = database.cost_record(material['id'])
            regional = database.regional_factors(province_state, city, material['id'])
            line = (costs['materialOpCost'] * regional[0] / 100.0 +
                    costs['laborOpCost'] * regional[1] / 100.0) * quantity * sensors
            total += line
            audit.info(:costing_lighting, "daylighting #{label}", target: zone.nameString,
                       inputs: { sensors: sensors, quantity_each: quantity }, value: "$#{line.round(2)}")
          end
        end
        audit.decision(:costing_lighting,
                       'daylighting sensors costed (ceil(fixtures/4) per controlled zone; fixture count from ' \
                       'WHOLE zone area — legacy restricts to the daylighted-area portion, not yet ported: upper bound)',
                       inputs: { zones: zones.size, sensors: sensors_total }, value: "$#{total.round(2)}")
        section['daylighting_sensor_cost'] = total.round(2)
        total
      end

      def zone_fixture_count(zone, database, template)
        count = 0.0
        zone.spaces.each do |space|
          next if space.spaceType.empty? || space.spaceType.get.standardsSpaceType.empty?

          space_type = space.spaceType.get.standardsSpaceType.get
          building_type = space.spaceType.get.standardsBuildingType.get
          set = database.lighting_sets.find do |row|
            row['template'].to_s.gsub(/\s*/, '') == template &&
              row['building_type'].to_s.downcase == building_type.downcase &&
              row['space_type'].to_s.downcase == space_type.downcase
          end
          next if set.nil?

          floor_ft2 = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get
          ceiling_ft = space.floorArea.positive? ? OpenStudio.convert(space.volume / space.floorArea, 'm', 'ft').get : 0
          column = HEIGHT_COLUMNS.find { |limit, _| ceiling_ft < limit }[1]
          fixture = database.lighting.find { |row| row['lighting_type_id'].to_s == set[column].to_s }
          next if fixture.nil?

          count += floor_ft2 / 1000.0 * fixture['Fix_1000ft'].to_f
        end
        count
      end
    end
  end
end
