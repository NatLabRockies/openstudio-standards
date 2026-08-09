module OpenStudioLoads
  module NECB
    # The loads pass — port of the legacy NECB space_type_apply_internal_loads
    # (beps_compliance_path.rb) MINUS lights (openstudio-lighting territory) and
    # of the parent space_type_apply_internal_load_schedules /
    # space_type_apply_thermostat_schedules (Standards.SpaceType.rb), against the
    # vendored data. Unit conversions are legacy-exact (data is IP; see the data
    # provenance block).
    module Apply
      module_function

      # Bare-geometry on-ramp: create/tag NECB space types and assign spaces.
      # @param map [Hash{String => Array(String, String)}] space name ->
      #   [building_type, space_type] (must exist in the vendored data)
      def assign_space_types(model, map, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        cache = {}
        assigned = 0
        model.getSpaces.sort_by(&:nameString).each do |space|
          pair = map[space.nameString]
          next if pair.nil?

          record = SpaceTypes.record(building_type: pair[0], space_type: pair[1], vintage: vintage)
          space_type = cache[pair] ||= begin
            st = OpenStudio::Model::SpaceType.new(model)
            st.setName("#{pair[0]} #{pair[1]}")
            st.setStandardsBuildingType(record['building_type'])
            st.setStandardsSpaceType(record['space_type'])
            st
          end
          space.setSpaceType(space_type)
          assigned += 1
        end
        unmapped = model.getSpaces.reject { |s| map.key?(s.nameString) }.map(&:nameString)
        audit.decision(:loads, 'NECB space types assigned',
                       inputs: { spaces_assigned: assigned, space_types_created: cache.size, vintage: vintage })
        unless unmapped.empty?
          audit.warn(:loads, "spaces with no space-type mapping (no loads will be applied): #{unmapped.join(', ')}")
        end
        audit
      end

      # Apply NECB internal loads + schedules + thermostats to every tagged space
      # type in the model. NO Lights, NO service water heating (sibling gems).
      def apply_loads(model, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        rules = NECB.rules(vintage)
        prefix = rules['schedule_table_prefix']
        applied = 0

        model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
          result = apply_to_space_type(model, space_type, vintage, prefix, audit)
          applied += 1 if result
        end
        audit.decision(:loads, 'NECB internal loads applied (people, plug/gas equipment, ventilation OA, ' \
                               'modelling infiltration, schedules, thermostats — lighting and SHW excluded by scope)',
                       inputs: { space_types_applied: applied, vintage: vintage },
                       article: '8.4.3.2.(1)-(2)')
        assign_zone_thermostats(model, audit)
        emit_article_coverage(vintage, audit)
        audit
      end

      def apply_to_space_type(model, space_type, vintage, prefix, audit)
        name = space_type.nameString
        if name.downcase.include?('plenum') ||
           (space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum'))
          audit.info(:loads, 'plenum space type skipped (legacy behavior)', target: name)
          return false
        end

        building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
        standards_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
        record = SpaceTypes.find(building_type: building_type, space_type: standards_type, vintage: vintage)
        if record.nil?
          audit.warn(:loads, "space type not in the NECB #{vintage} data (standards tags " \
                             "[#{building_type.inspect}, #{standards_type.inspect}]) — no loads applied", target: name)
          return false
        end
        if SpaceTypes.undefined?(record)
          audit.info(:loads, "'- undefined -' space type — no loads applied (legacy behavior)", target: name)
          return false
        end

        apply_people(space_type, record, audit)
        apply_equipment(space_type, record, audit)
        apply_ventilation(space_type, record, prefix, audit)
        apply_infiltration(space_type, record, audit)
        apply_schedule_set(model, space_type, record, vintage, audit)
        apply_thermostat(model, space_type, record, vintage, audit)
        true
      end

      # People: people/1000ft2 -> people/m2, FractionRadiant 0.3, comfort schedules.
      def apply_people(space_type, record, audit)
        occupancy_per_area = record['occupancy_per_area'].to_f
        return if occupancy_per_area.zero?

        instance = single_instance(space_type.people, audit) do
          definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
          definition.setName("#{space_type.nameString} People Definition")
          people = OpenStudio::Model::People.new(definition)
          people.setName("#{space_type.nameString} People")
          people.setSpaceType(space_type)
          people
        end
        definition = instance.peopleDefinition
        definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy_per_area / 1000, 'people/ft^2', 'people/m^2').get)
        definition.setFractionRadiant(0.3)
        instance.setClothingInsulationSchedule(comfort_schedule(space_type.model, :clothing))
        instance.setAirVelocitySchedule(comfort_schedule(space_type.model, :air_velocity))
        instance.setWorkEfficiencySchedule(comfort_schedule(space_type.model, :work_efficiency))
        audit.info(:loads, 'people set', target: space_type.nameString,
                   inputs: { occupancy_per_1000ft2: occupancy_per_area, fraction_radiant: 0.3 },
                   article: '8.4.3.2.(2)')
      end

      # Electric (W/ft2) and gas (Btu/hr.ft2) equipment with latent/radiant/lost fractions.
      def apply_equipment(space_type, record, audit)
        electric = record['electric_equipment_per_area'].to_f
        unless electric.zero?
          instance = single_instance(space_type.electricEquipment, audit) do
            definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
            definition.setName("#{space_type.nameString} Elec Equip Definition")
            equip = OpenStudio::Model::ElectricEquipment.new(definition)
            equip.setName("#{space_type.nameString} Elec Equip")
            equip.setSpaceType(space_type)
            equip
          end
          definition = instance.electricEquipmentDefinition
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(electric, 'W/ft^2', 'W/m^2').get)
          set_fractions(definition, record, 'electric_equipment')
          audit.info(:loads, 'electric equipment set', target: space_type.nameString,
                     inputs: { w_per_ft2: electric }, article: '8.4.3.2.(2)')
        end

        gas = record['gas_equipment_per_area'].to_f
        return if gas.zero?

        instance = single_instance(space_type.gasEquipment, audit) do
          definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
          definition.setName("#{space_type.nameString} Gas Equip Definition")
          equip = OpenStudio::Model::GasEquipment.new(definition)
          equip.setName("#{space_type.nameString} Gas Equip")
          equip.setSpaceType(space_type)
          equip
        end
        definition = instance.gasEquipmentDefinition
        definition.setWattsperSpaceFloorArea(OpenStudio.convert(gas, 'Btu/hr*ft^2', 'W/m^2').get)
        set_fractions(definition, record, 'gas_equipment')
        audit.info(:loads, 'gas equipment set', target: space_type.nameString,
                   inputs: { btu_hr_ft2: gas }, article: '8.4.3.2.(2)')
      end

      # DesignSpecificationOutdoorAir (method Sum) with the legacy per-person
      # RESCALE: the ventilation standard's occupant density differs from NECB's,
      # so per-person is scaled by (ventilation occupancy)/(NECB occupancy) so the
      # summed OA total matches the ventilation-standard intent at NECB occupancy.
      def apply_ventilation(space_type, record, prefix, audit)
        per_area = record['ventilation_per_area'].to_f
        per_person = record['ventilation_per_person'].to_f
        ach = record['ventilation_air_changes'].to_f
        vent_occupancy = record['ventilation_occupancy_rate_people_per_1000ft2'].to_f
        occupancy_per_area = record['occupancy_per_area'].to_f

        ventilation = space_type.designSpecificationOutdoorAir
        ventilation = if ventilation.is_initialized
                        ventilation.get
                      else
                        dsoa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
                        dsoa.setName("#{space_type.nameString} Ventilation")
                        space_type.setDesignSpecificationOutdoorAir(dsoa)
                        dsoa
                      end

        if per_area.zero? && per_person.zero? && ach.zero?
          # every space type needs a DSOA (zeros) for ventilation controls
          ventilation.setOutdoorAirFlowperFloorArea(0)
          ventilation.setOutdoorAirFlowperPerson(0)
          ventilation.setOutdoorAirFlowAirChangesperHour(0)
          audit.info(:loads, 'no ventilation data — zero DSOA created (required for OA controls)',
                     target: space_type.nameString)
          return
        end

        ventilation.setOutdoorAirMethod('Sum')
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(per_area, 'ft^3/min*ft^2', 'm^3/s*m^2').get) unless per_area.zero?
        mod_per_person = nil
        unless per_person.zero?
          mod_per_person = per_person * vent_occupancy / occupancy_per_area
          ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(mod_per_person, 'ft^3/min*person', 'm^3/s*person').get)
        end
        ventilation.setOutdoorAirFlowAirChangesperHour(ach) unless ach.zero?

        notes = ventilation.additionalProperties
        notes.setFeature('Ref OA per area', per_area)
        notes.setFeature('Ref OA per person', per_person)
        notes.setFeature('Ref OA ach', ach)
        notes.setFeature('Ref occupancy per 1000ft2', vent_occupancy)
        notes.setFeature('Ref standard', record['ventilation_occupancy_standard'].to_s)
        notes.setFeature('Ref space type', record['ventilation_standard_space_type'].to_s)

        audit.info(:loads, 'ventilation outdoor air set',
                   target: space_type.nameString,
                   inputs: { cfm_per_ft2: per_area, cfm_per_person_standard: per_person,
                             cfm_per_person_rescaled: mod_per_person&.round(4), ach: ach,
                             ventilation_standard: record['ventilation_standard'] },
                   value: per_person.zero? ? nil : 'per-person rescaled x (standard occupancy / NECB occupancy) so summed OA matches the standard at NECB density',
                   article: "8.4.3.2.(1)-(2); OA basis #{record['ventilation_standard']}")
      end

      # Space-type modelling infiltration (NOT the envelope gem's 8.4.3.3 air-leakage rule).
      def apply_infiltration(space_type, record, audit)
        per_ext_area = record['infiltration_per_exterior_area'].to_f
        per_ext_wall = record['infiltration_per_exterior_wall_area'].to_f
        ach = record['infiltration_air_changes'].to_f
        return if per_ext_area.zero? && per_ext_wall.zero? && ach.zero?

        instance = single_instance(space_type.spaceInfiltrationDesignFlowRates, audit) do
          infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space_type.model)
          infiltration.setName("#{space_type.nameString} Infiltration")
          infiltration.setSpaceType(space_type)
          infiltration
        end
        instance.setFlowperExteriorSurfaceArea(OpenStudio.convert(per_ext_area, 'ft^3/min*ft^2', 'm^3/s*m^2').get) unless per_ext_area.zero?
        instance.setFlowperExteriorWallArea(OpenStudio.convert(per_ext_wall, 'ft^3/min*ft^2', 'm^3/s*m^2').get) unless per_ext_wall.zero?
        instance.setAirChangesperHour(ach) unless ach.zero?
        schedule_name = record['infiltration_schedule']
        instance.setSchedule(Schedules.add(space_type.model, schedule_name, audit: audit)) if schedule_name
        audit.info(:loads, 'space-type modelling infiltration set (distinct from envelope 8.4.3.3 air leakage)',
                   target: space_type.nameString,
                   inputs: { cfm_per_ft2_exterior: per_ext_area, cfm_per_ft2_ext_wall: per_ext_wall, ach: ach })
      end

      # DefaultScheduleSet wiring: occupancy + activity + equipment (NOT lighting).
      def apply_schedule_set(model, space_type, record, vintage, audit)
        schedule_set = if space_type.defaultScheduleSet.is_initialized
                         space_type.defaultScheduleSet.get
                       else
                         set = OpenStudio::Model::DefaultScheduleSet.new(model)
                         set.setName("#{space_type.nameString} Schedule Set")
                         space_type.setDefaultScheduleSet(set)
                         set
                       end
        wire = lambda do |key, setter|
          name = record[key]
          return if name.nil?

          schedule_set.send(setter, Schedules.add(model, name, vintage: vintage, audit: audit))
        end
        wire.call('occupancy_schedule', :setNumberofPeopleSchedule)
        wire.call('occupancy_activity_schedule', :setPeopleActivityLevelSchedule)
        wire.call('electric_equipment_schedule', :setElectricEquipmentSchedule)
        wire.call('gas_equipment_schedule', :setGasEquipmentSchedule)
        audit.info(:loads, "schedule set wired (letter #{record['necb_schedule_type']}; lighting schedule excluded by scope)",
                   target: space_type.nameString, article: '8.4.3.2.(1)')
      end

      # A dual-setpoint thermostat per space type from the setpoint schedules
      # (legacy: created unattached; assign_zone_thermostats hooks zones lacking one).
      def apply_thermostat(model, space_type, record, vintage, audit)
        existing = model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == "#{space_type.nameString} Thermostat" }
        return if existing

        thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
        thermostat.setName("#{space_type.nameString} Thermostat")
        heating = record['heating_setpoint_schedule']
        cooling = record['cooling_setpoint_schedule']
        thermostat.setHeatingSetpointTemperatureSchedule(Schedules.add(model, heating, vintage: vintage, audit: audit)) if heating
        thermostat.setCoolingSetpointTemperatureSchedule(Schedules.add(model, cooling, vintage: vintage, audit: audit)) if cooling
        audit.info(:loads, 'space-type thermostat created', target: space_type.nameString,
                   inputs: { heating: heating, cooling: cooling }, article: '8.4.3.2.(1)')
      end

      # Zones without a thermostat get their (dominant) space type's thermostat —
      # makes bare-geometry models simulable; never overwrites an existing one.
      def assign_zone_thermostats(model, audit)
        hooked = 0
        model.getThermalZones.sort_by(&:nameString).each do |zone|
          next if zone.thermostatSetpointDualSetpoint.is_initialized

          space = zone.spaces.min_by(&:nameString)
          next if space.nil? || space.spaceType.empty?

          name = "#{space.spaceType.get.nameString} Thermostat"
          thermostat = model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == name }
          next if thermostat.nil?

          zone.setThermostatSetpointDualSetpoint(thermostat)
          hooked += 1
        end
        audit.info(:loads, 'space-type thermostats assigned to zones lacking one', inputs: { zones: hooked }) if hooked.positive?
      end

      def emit_article_coverage(vintage, audit)
        coverage = NECB.rules(vintage)['article_coverage']
        return if coverage.nil?

        cited = Hash.new(0)
        audit.entries.each { |e| e[:article].to_s.scan(/\d+\.\d+(?:\.\d+)*\./) { |a| cited[a] += 1 } }
        coverage['articles'].each do |article|
          applied = cited.select { |a, _| a.start_with?(article['article'].to_s.sub(/\s*\(.*\z/, '').sub(/\.\z/, '')) }.values.sum  # strip ' (slice label)'/'(N)' suffixes + trailing dot — keep the SIX copies of this line identical
          inputs = { status: article['status'], decisions_citing: applied }
          inputs[:gap_owner] = article['gap_owner'] if article['gap_owner']
          if %w[implemented satisfied_by_clone host_scope].include?(article['status'])
            audit.info(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}#{article['how'] ? ": #{article['how']}" : ''}",
                       inputs: inputs, article: article['article'])
          elsif article['gap_owner'] == 'modeller' # scope note, not a warning (D-09)
            audit.info(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}, modeller scope" \
                                  "#{article['how'] ? ". Applied: #{article['how']}" : ''}" \
                                  "#{article['gaps'] ? ". Modeller's responsibility: #{article['gaps']}" : ''}",
                       inputs: inputs, article: article['article'])
          else
            audit.warn(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}" \
                                  "#{article['how'] ? ". Applied: #{article['how']}" : ''}" \
                                  "#{article['gaps'] ? ". Gaps: #{article['gaps']}" : ''}",
                       inputs: inputs, article: article['article'])
          end
        end
      end

      def single_instance(instances, audit)
        instances = instances.sort
        if instances.empty?
          yield
        else
          instances.drop(1).each do |extra|
            audit&.info(:loads, "removed duplicate load instance #{extra.nameString}")
            extra.remove
          end
          instances.first
        end
      end

      def set_fractions(definition, record, key)
        latent = record["#{key}_fraction_latent"].to_f
        radiant = record["#{key}_fraction_radiant"].to_f
        lost = record["#{key}_fraction_lost"].to_f
        definition.setFractionLatent(latent) unless latent.zero?
        definition.setFractionRadiant(radiant) unless radiant.zero?
        definition.setFractionLost(lost) unless lost.zero?
      end

      COMFORT_SCHEDULES = {
        clothing: 'Clothing Schedule', air_velocity: 'Air Velocity Schedule',
        work_efficiency: 'Work Efficiency Schedule'
      }.freeze

      def comfort_schedule(model, kind)
        name = COMFORT_SCHEDULES.fetch(kind)
        existing = model.getScheduleRulesetByName(name)
        return existing.get if existing.is_initialized

        schedule = OpenStudio::Model::ScheduleRuleset.new(model)
        schedule.setName(name)
        case kind
        when :clothing
          schedule.defaultDaySchedule.setName('Clothing Schedule Default Winter Clothes')
          schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
          rule = OpenStudio::Model::ScheduleRule.new(schedule)
          rule.daySchedule.setName('Clothing Schedule Summer Clothes')
          rule.daySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.5)
          rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(5), 1))
          rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(9), 30))
        when :air_velocity
          schedule.defaultDaySchedule.setName('Air Velocity Schedule Default')
          schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.2)
        when :work_efficiency
          schedule.defaultDaySchedule.setName('Work Efficiency Schedule Default')
          schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        end
        schedule
      end

      # ---- internals (not API) ----
      private_class_method :apply_to_space_type, :apply_ventilation,
                           :apply_infiltration, :assign_zone_thermostats,
                           :emit_article_coverage, :single_instance,
                           :set_fractions, :comfort_schedule
    end

    # Facade: apply NECB loads to every tagged space type.
    def self.apply_loads(model, vintage: '2020', audit: nil)
      Apply.apply_loads(model, vintage: vintage, audit: audit)
    end
  end
end
