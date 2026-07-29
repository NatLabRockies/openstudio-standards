require 'json'
require_relative 'catalog_icons'

module OpenStudioHVAC
  # Self-contained HTML catalog of EVERY system this gem can build. For each
  # catalog row the system is actually BUILT on the bundled 5-zone fixture and
  # its real topology is extracted, so the diagrams cannot drift from what the
  # builders assemble ("build-and-extract", never hand-drawn schematics).
  #
  # UX: a master-detail single page. A sticky, searchable left sidebar lists all
  # systems grouped by family; the right pane shows ONLY the selected system,
  # with one TAB per loop (plus a zone-equipment tab). Every system's full detail
  # is embedded but hidden — selection/tab switching is plain inline JS, so the
  # file stays one self-contained document.
  #
  # Loops are drawn as a VERTICAL CASCADE matching the OpenStudio Application's
  # own GridItem.cpp layout: the SUPPLY equipment as a horizontal row on TOP, a
  # labelled center connector band ("Supply Equipment" / "Demand Equipment"),
  # then the DEMAND side on the BOTTOM as a splitter -> parallel branches stacked
  # vertically -> mixer, closed by left/right risers with flow arrows so it reads
  # as circulation. Every component + demand cell carries a native SVG <title>
  # for a hover tooltip.
  #
  # The whole report is one self-contained document: inline CSS, inline SVG and
  # inline JS, no external requests of any kind (no CDN, no <link>, no remote
  # src/href/@import/url(), no web fonts) — a test asserts this. Inline <script>
  # and <style> make no network requests and are the mechanism here.
  #
  # This file deliberately mirrors the approach of openstudio-necb's
  # report/{model_query,svg,diagrams,html}.rb but is REIMPLEMENTED self-contained
  # here: openstudio-hvac sits BELOW openstudio-necb in the dependency graph and
  # must not depend on it.
  module CatalogReport
    module_function

    FIXTURE = File.expand_path('../../test/fixtures/5ZoneNoHVAC.osm', __dir__)

    # ---- component classification (mirrors necb ModelQuery::COMPONENT_KINDS) ----
    # Order matters: the FIRST matching regex wins, so specific rules precede
    # broad ones. In particular :heat_pump (plant/water-source heat pumps) MUST
    # precede :pump — every "HeatPump_*" idd contains the substring "Pump", so a
    # bare /Pump/ rule would otherwise swallow the heat pump and hide it. The
    # :pump rule is anchored to real pump classes (^OS_Pump / ^OS_HeaderedPumps)
    # so it never catches a HeatPump.
    COMPONENT_KINDS = [
      [:oa,           /AirLoopHVAC_OutdoorAirSystem/],
      [:hx,           /HeatExchanger/],
      [:cooling_coil, /Coil_Cooling|CoilSystem_Cooling|EvaporativeCooler/],
      [:heating_coil, /Coil_Heating|Humidifier/],
      [:fan,          /^OS_Fan/],
      [:boiler,       /Boiler/],
      [:water_heater, /WaterHeater/],
      [:chiller,      /Chiller/],
      [:tower,        /CoolingTower|FluidCooler/],
      [:heat_pump,    /HeatPump_WaterToWater|HeatPump_PlantLoop_EIR|HeatPump_WaterToAir/],
      [:district,     /DistrictHeating|DistrictCooling/],
      [:pump,         /^OS_Pump|^OS_HeaderedPumps/]
    ].freeze

    KIND_LABELS = {
      oa: 'Outdoor air', hx: 'Heat recovery', cooling_coil: 'Cooling coil',
      heating_coil: 'Heating coil', fan: 'Fan', boiler: 'Boiler',
      water_heater: 'Water heater', chiller: 'Chiller', tower: 'Cooling tower',
      pump: 'Pump', heat_pump: 'Heat pump', district: 'District energy',
      zone: 'Thermal zone', other: 'Component',
      # Plant-demand load groups + air-loop zone-level rows.
      baseboard: 'Baseboard (hydronic)', fan_coil: 'Fan-coil coil',
      heat_pump_coil: 'Heat-pump coil', water_use: 'Water use',
      terminal: 'Air terminal'
    }.freeze

    # Per-kind fill colors for component glyphs.
    KIND_COLORS = {
      oa: '#7fb3d5', hx: '#a569bd', cooling_coil: '#5dade2', heating_coil: '#e59866',
      fan: '#82e0aa', boiler: '#e57373', water_heater: '#e59866', chiller: '#5dade2',
      tower: '#76d7c4', pump: '#f7dc6f', heat_pump: '#48c9b0', district: '#bb8fce',
      zone: '#d6dbdf', other: '#d5d8dc',
      baseboard: '#e59866', fan_coil: '#82e0aa', heat_pump_coil: '#76d7c4',
      water_use: '#7fb3d5', terminal: '#aeb6bf'
    }.freeze

    # Loop track accent colors, keyed by loop kind (spec-mandated hues).
    LOOP_COLORS = {
      air: '#2874a6', hot_water: '#c0392b', chilled_water: '#17a2b8',
      condenser: '#16a085', shw: '#8e44ad'
    }.freeze

    LOOP_LABELS = {
      air: 'Air loop', hot_water: 'Hot water loop', chilled_water: 'Chilled water loop',
      condenser: 'Condenser loop', shw: 'Service water loop'
    }.freeze

    # Zone-equipment idd type -> human label. Ordered most-specific first so the
    # first matching regex wins.
    ZONE_EQUIPMENT = [
      [/ZoneHVAC_Baseboard.*Water/,                       'hot water baseboard'],
      [/ZoneHVAC_Baseboard.*Electric/,                    'electric baseboard'],
      [/ZoneHVAC_Baseboard/,                              'baseboard'],
      [/ZoneHVAC_PackagedTerminalHeatPump/,               'PTHP'],
      [/ZoneHVAC_PackagedTerminalAirConditioner/,         'PTAC'],
      [/ZoneHVAC_TerminalUnit_VariableRefrigerantFlow/,   'VRF terminal'],
      [/ZoneHVAC_WaterToAirHeatPump/,                     'water-source heat pump'],
      [/ZoneHVAC_UnitHeater/,                             'unit heater'],
      [/ZoneHVAC_FourPipeFanCoil/,                        'fan coil'],
      [/ZoneHVAC_EnergyRecoveryVentilator/,               'ERV'],
      [/ZoneHVAC_LowTemp/,                                'radiant panel'],
      [/ZoneHVAC/,                                        'zone unit']
    ].freeze

    # Air-terminal idd type -> human label (most-specific first).
    TERMINAL_KINDS = [
      [/VAV_HeatAndCool_Reheat/,        'VAV heat/cool reheat terminal'],
      [/VAV_HeatAndCool_NoReheat/,      'VAV heat/cool terminal'],
      [/VAV_Reheat/,                    'VAV reheat terminal'],
      [/VAV_NoReheat/,                  'VAV terminal'],
      [/ConstantVolume_Reheat/,         'CV reheat terminal'],
      [/ConstantVolume_NoReheat/,       'Diffuser (uncontrolled)'],
      [/ConstantVolume_FourPipeInduction/, 'Induction terminal'],
      [/SeriesPIU/,                     'Series PIU terminal'],
      [/ParallelPIU/,                   'Parallel PIU terminal'],
      [/InletSideMixer/,                'Inlet-side mixer terminal'],
      [/CooledBeam/,                    'Cooled-beam terminal'],
      [/Uncontrolled/,                  'Diffuser (uncontrolled)'],
      [/AirTerminal/,                   'Air terminal']
    ].freeze

    # Per-FAMILY description blurb (verbatim from spec). Shown as the card
    # description; the canonical name is displayed separately (no duplication).
    FAMILY_BLURB = {
      'baseboards' => 'Perimeter baseboard heating only, no central air system.',
      'composite' => 'A dedicated ventilation unit paired with separate zone conditioning (fan coils, water/ground-source heat pumps, or residential AC).',
      'doas' => 'Dedicated outdoor air system providing ventilation only; zone conditioning is separate.',
      'doas_pthp' => 'Dedicated outdoor air with packaged terminal heat pumps at each zone (NECB ECM hs11).',
      'ecm_ashp_baseboard' => 'Air-source (or cold-climate) heat pump for primary heating and cooling with baseboard backup (NECB ECMs hs09/hs12).',
      'ecm_doas_vrf' => 'Dedicated outdoor air with variable refrigerant flow zone terminals on an air-source heat pump (NECB ECMs hs08/hs13).',
      'ecm_hp_fancoils' => 'Central heat-pump plant (ground-, water-, or air-source) serving hydronic fan coils (NECB ECMs hs14-16).',
      'evap_cooler' => 'Direct evaporative cooling, with or without supplementary heat.',
      'fan_coils' => 'Two-pipe (TPFC) or four-pipe (FPFC) fan coils per zone on a central chiller and boiler, with a make-up air unit for ventilation (NECB systems 2 and 5).',
      'furnace' => 'Forced-air furnace providing central heating.',
      'mau_ptac' => 'Make-up air unit for ventilation plus packaged terminal air conditioners at each zone (NECB system 1 variants).',
      'psz' => 'Packaged single-zone rooftop unit — one air handler per zone with DX or heat-pump cooling and a gas/electric heating coil, optionally with perimeter baseboards (NECB systems 3 and 4, and PSZ-AC).',
      'unit_heaters' => 'Standalone gas or electric unit heaters.',
      'vav_reheat' => 'Multi-zone variable-air-volume — a central built-up air handler with chilled-water or DX cooling and zone reheat terminals, plus baseboards (NECB system 6 and packaged VAV).',
      'vrf' => 'Variable refrigerant flow heat-recovery system serving zone terminals.',
      'wshp' => 'Water-source heat pumps at each zone on a common condenser-water loop.',
      'zone_ervs' => 'Zone-level energy recovery ventilators providing ventilation with heat recovery.',
      'zone_terminal' => 'Zone terminal units — packaged terminal AC/heat pump or window AC — with baseboard heating.'
    }.freeze

    FAMILY_TITLES = {
      'baseboards' => 'Baseboard heating', 'composite' => 'Composite (DOAS + zone conditioning)',
      'doas' => 'Dedicated outdoor air', 'doas_pthp' => 'DOAS + PTHP (ECM hs11)',
      'ecm_ashp_baseboard' => 'ASHP + baseboard (ECM hs09/hs12)',
      'ecm_doas_vrf' => 'DOAS + VRF (ECM hs08/hs13)',
      'ecm_hp_fancoils' => 'Heat-pump plant fan coils (ECM hs14-16)',
      'evap_cooler' => 'Evaporative cooling', 'fan_coils' => 'Fan coils (NECB sys 2 / 5)',
      'furnace' => 'Furnace', 'mau_ptac' => 'MAU + PTAC (NECB sys 1)',
      'psz' => 'Packaged single-zone (NECB sys 3 / 4, PSZ-AC)',
      'unit_heaters' => 'Unit heaters', 'vav_reheat' => 'VAV with reheat (NECB sys 6, PVAV)',
      'vrf' => 'Variable refrigerant flow', 'wshp' => 'Water-source heat pumps',
      'zone_ervs' => 'Zone ERVs', 'zone_terminal' => 'Zone terminal units'
    }.freeze

    # ------------------------------------------------------------------ public

    # Build every catalog system on the fixture, extract its topology, and render
    # the whole catalog as one self-contained HTML string.
    #
    # @param path [String, nil] if given, the HTML is also written here
    # @param fixture [String] the seed .osm (default: bundled 5ZoneNoHVAC)
    # @return [String] the self-contained HTML document
    # Families whose systems are packaged/per-zone (one unit or air loop PER
    # zone): building them across all fixture zones just replicates identical
    # loops, so a single zone is the succinct, representative diagram. Every
    # other family has a central air handler or plant genuinely serving many
    # zones, so it keeps the full zone set to show that.
    SINGLE_ZONE_FAMILIES = %w[psz zone_terminal baseboards unit_heaters furnace evap_cooler vrf].freeze

    def to_html(path = nil, fixture: FIXTURE)
      rows = Catalog.rows
      # Load + thermostat the fixture ONCE, then clone it per system. Reloading
      # the .osm from disk costs ~2.4 s each (OSM deserialization); an in-memory
      # clone costs ~6 ms — the difference between a ~4 min and a ~6 s run.
      base = prepared_base(fixture)
      cards = rows.map { |row| build_card(row, base) }
      html = assemble(cards)
      File.write(path, html) if path
      html
    end

    # ------------------------------------------------- reusable diagram API
    # A REUSABLE, host-agnostic diagram bundle for ANY model. A consuming report
    # (e.g. openstudio-necb's AHJ compliance report) drives its own proposed and
    # reference models through this to get the SAME OpenStudio-App-style loop
    # diagrams the catalog draws, without depending on catalog internals. Returns
    # PLAIN hashes (inline-SVG strings + labels) and NEVER raises — on any failure
    # it returns an empty bundle carrying the error message, so a host render can
    # degrade gracefully. To resolve the diagrams' <use href="#icon-…"> refs the
    # host must embed `icon_defs` ONCE per document and add `DIAGRAM_CSS` to its
    # stylesheet.
    #
    # @param model [OpenStudio::Model::Model]
    # @return [Hash] { loops: [{ kind:, label:, svg: }...],
    #                  zone_equipment_svg: <svg String or nil>, empty: <bool>,
    #                  error: <String, only on failure> }
    def model_diagrams(model)
      zones = model.getThermalZones.sort_by(&:nameString)
      topo = extract(model, zones)
      loops = (topo[:air_loops] + topo[:plant_loops]).map do |loop|
        { kind: loop[:kind], label: loop_display_label(loop),
          svg: loop_diagram_svg(loop) }
      end
      zeq = topo[:zone_equipment]
      { loops: loops,
        zone_equipment_svg: zeq.empty? ? nil : zone_equipment_svg(zeq),
        empty: loops.empty? && zeq.empty? }
    rescue StandardError => e
      { loops: [], zone_equipment_svg: nil, empty: true, error: e.message }
    end

    # A DESCRIPTIVE label for a loop, so a host's dropdown chooser can tell
    # loops apart. Plant loops keep their kind label ("Hot water loop",
    # "Chilled water loop", "Condenser loop"). An AIR loop instead names the
    # zone(s) it serves — "Air loop — Thermal Zone 1" for a single-zone (PSZ)
    # air handler, "Air loop (N zones)" for a multi-zone air handler — which
    # resolves the ambiguous "Air loop / Air loop 2…" problem when several
    # packaged single-zone units are listed together.
    def loop_display_label(loop)
      base = LOOP_LABELS.fetch(loop[:kind], 'Loop')
      return base unless loop[:kind] == :air

      zones = (loop[:demand] || []).map { |d| d[:zone_name] }.compact.reject { |n| n.to_s.empty? }
      case zones.size
      when 1 then "#{base} — #{zones.first}"
      when 0 then base
      else "#{base} (#{zones.size} zones)"
      end
    end

    # The self-contained CSS subset a HOST document needs so the reused loop/zone
    # diagrams render correctly outside the catalog page: the scroll container, the
    # intrinsic-size svg override (so a host's own responsive `svg { width:100% }`
    # rule does not stretch a diagram), and print break-avoidance. The catalog page
    # keeps its own full CSS; this is only the diagram-relevant subset. Fully
    # self-contained — no url()/@import/external references (a host's
    # no-external-references test must still pass).
    DIAGRAM_CSS = <<~CSS.freeze
      .diagram { overflow-x: auto; break-inside: avoid; margin: .4rem 0 1rem; }
      /* Render diagram SVGs at their intrinsic size (fixed box/gap constants) so a
         component box is the same physical size in every diagram and wide loops
         scroll horizontally instead of shrinking; this MUST win over any generic
         `svg { width: 100% }` rule in the host stylesheet. */
      .diagram svg { width: auto; height: auto; max-width: none; display: block; }
      .diagram .note { font-size: .82rem; color: #555; font-style: italic; margin: .3rem 0; }
    CSS

    # -------------------------------------------------------- build & extract

    def prepared_base(fixture)
      model = load_model(fixture)
      model.getThermalZones.each do |z|
        next if z.thermostatSetpointDualSetpoint.is_initialized

        z.setThermostatSetpointDualSetpoint(OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model))
      end
      model
    end

    # @param base [OpenStudio::Model::Model] the prepared fixture to clone
    # @return [Hash] card data: row, canonical, description, topology or diagram_error
    def build_card(row, base)
      canonical = Canonical.name(row)
      # Description = the per-family blurb only; the canonical name is shown on
      # its own element, so appending it here would just duplicate it.
      description = FAMILY_BLURB.fetch(row['family'], '')
      card = { row: row, canonical: canonical, description: description }
      begin
        model = base.clone(true).to_Model
        zones = model.getThermalZones.sort_by(&:nameString)
        # Packaged/per-zone families replicate identical loops per zone, so one
        # zone is the representative diagram. Every other family has a central
        # handler/plant genuinely serving many zones — TWO zones is enough to show
        # that (and to render two demand branches) without a busy 5-zone diagram.
        zones = SINGLE_ZONE_FAMILIES.include?(row['family']) ? zones.first(1) : zones.first(2)
        OpenStudioHVAC.build_system(model, row['name'], zones)
        card[:topology] = extract(model, zones)
      rescue StandardError => e
        # Never crash the whole report over one odd build — render the card
        # without a diagram plus a small "diagram unavailable" note.
        card[:diagram_error] = e.message
      end
      card
    end

    def load_model(fixture)
      OpenStudio::Model::Model.load(OpenStudio::Path.new(fixture)).get
    end

    # Extract a plain-hash topology snapshot (mirrors necb ModelQuery, extended
    # with supply/demand split, per-component tooltip attributes, and zone
    # equipment). Never raises.
    def extract(model, zones)
      {
        air_loops: air_loops(model),
        plant_loops: plant_loops(model),
        zone_equipment: zone_equipment(zones)
      }
    end

    def air_loops(model)
      model.getAirLoopHVACs.sort_by(&:nameString).map do |loop|
        # Air loops have a single supply air-handler path (typically no supply
        # splitter) — every real component becomes a series cell in flow order.
        { kind: :air, name: loop.nameString,
          supply: supply_columns(decompose_air_supply(loop)),
          demand: air_demand(loop) }
      end
    end

    def plant_loops(model)
      model.getPlantLoops.sort_by(&:nameString).map do |loop|
        supply = decompose_supply_plant(loop)
        { kind: plant_kind(supply), name: loop.nameString,
          supply: supply_columns(supply),
          demand: demand_branch_lists(decompose_demand_plant(loop)) }
      end
    end

    # Classify a plant loop by the equipment on its (decomposed) supply side.
    def plant_kind(decomp)
      kinds = decomp_cells(decomp).map { |cell| cell[:kind] }
      return :shw if kinds.include?(:water_heater)
      return :condenser if kinds.include?(:tower)
      return :chilled_water if kinds.include?(:chiller)
      return :hot_water if kinds.include?(:boiler)

      :condenser # heat-pump / WSHP condenser loops have neither boiler nor chiller
    end

    # Every cell of a decomposed side (pre-series + parallel branches + post-series).
    def decomp_cells(decomp)
      decomp[:pre] + decomp[:branches].flatten + decomp[:post]
    end

    # An air loop serves thermal zones. Consistent with the "don't collapse"
    # principle, its demand is drawn as ONE branch PER served zone (the diagram is
    # built on 1 or 2 zones), each branch showing that zone's air terminal plus
    # its ZoneHVAC* equipment. Returns one hash per zone:
    # { kind: :zone, zone_name:, terminal:, equipment: [...], tooltip: }.
    def air_demand(loop)
      zones = begin
        loop.thermalZones.sort_by(&:nameString)
      rescue StandardError
        []
      end
      zones.map do |zone|
        name = begin
          zone.nameString
        rescue StandardError
          ''
        end
        terminal = zone_terminal(zone)
        equipment = zone_hvac_equipment(zone)
        tip = ['Served thermal zone', "Zone: #{truncate(name, 40)}"]
        tip << "Terminal: #{terminal[:label]}" if terminal
        equipment.each { |e| tip << "Zone equipment: #{e[:label]}" }
        { kind: :zone, zone_name: name, terminal: terminal, equipment: equipment,
          tooltip: tip.join("\n") }
      end
    end

    # The air terminal serving a zone (from airLoopHVACTerminal, or the terminal
    # object among the zone's equipment). Guarded — returns nil if none.
    def zone_terminal(zone)
      obj = nil
      if zone.respond_to?(:airLoopHVACTerminal)
        opt = zone.airLoopHVACTerminal
        obj = opt.get if opt.respond_to?(:is_initialized) && opt.is_initialized
      end
      obj ||= zone.equipment.find { |e| e.iddObjectType.valueName =~ /AirTerminal/ }
      return nil unless obj

      idd = obj.iddObjectType.valueName
      name = begin
        obj.nameString
      rescue StandardError
        ''
      end
      tip = ["Air terminal: #{terminal_label(idd)}", "Type: #{clean_idd(idd)}"]
      tip << "Name: #{truncate(name, 48)}" unless name.to_s.empty?
      { label: terminal_label(idd), idd: idd, name: name, tooltip: tip.join("\n") }
    rescue StandardError
      nil
    end

    def terminal_label(idd_name)
      TERMINAL_KINDS.each { |regex, label| return label if idd_name =~ regex }
      'Air terminal'
    end

    # Deduped labels + counts of the ZoneHVAC* units in one zone (its container rows).
    def zone_hvac_equipment(zone)
      counts = Hash.new(0)
      order = []
      rep = {}
      zone.equipment.each do |equip|
        idd = equip.iddObjectType.valueName
        label = zone_equipment_label(idd)
        next unless label

        order << label unless counts.key?(label)
        counts[label] += 1
        rep[label] ||= idd
      end
      order.map do |label|
        tip = ["Zone equipment: #{label}", "Type: #{clean_idd(rep[label])}",
               "#{counts[label]} in this zone"].join("\n")
        { label: label, count: counts[label], tooltip: tip, idd: rep[label] }
      end
    rescue StandardError
      []
    end

    # Build one drawable DEMAND cell for a served component, or nil for anything
    # not drawn (nodes, connectors, pipes, unclassified — so a bypass branch of
    # bare pipe yields no cell and its branch is dropped). On a DEMAND side a
    # chiller means its CONDENSER is the load (a condenser-water loop cooling the
    # chillers) and a water-to-water heat pump means its SOURCE side — so these
    # surface as loads, suffixed "(condenser)"/"(source)". Zone-contained coils
    # (four-pipe fan coil, water-source heat pump, hydronic baseboard) carry a
    # "— <Zone>" suffix tracing where the coil lives. Same cell shape as a supply
    # cell so the two sides share the renderer.
    def demand_cell(component)
      return nil unless real?(component)

      idd = component.iddObjectType.valueName
      name = component_name(component)
      spec = demand_spec(component, idd, name)
      return classify_component(component) unless spec # air-handler coils, HX, ... (nil for pipes)

      tip = ["#{spec[:label]} (served load)", "Type: #{clean_idd(idd)}"]
      tip << "Served: #{truncate(name, 48)}" unless name.empty?
      { kind: spec[:kind], name: name, idd: idd, label: spec[:label], tooltip: tip.join("\n") }
    rescue StandardError
      nil
    end

    # The kind + specific label for a served demand component, or nil to defer to
    # the generic supply classifier (air-handler water coils, heat exchangers).
    def demand_spec(component, idd, name)
      # A chiller on a demand side = its condenser being cooled by this loop;
      # reuse the supply-side compressor-type parse, suffixed "(condenser)".
      return { kind: :chiller, label: "#{chiller_label(name)} (condenser)" } if idd =~ /Chiller/
      # A water-to-water / plant-loop heat pump on a demand side = its source side.
      return { kind: :heat_pump, label: 'Heat pump (source)' } if idd =~ /HeatPump_WaterToWater|HeatPump_PlantLoop_EIR/

      return zone_or_group(component, :baseboard, 'Baseboard (hydronic)') if idd =~ /Coil_Heating_Water_Baseboard/
      return { kind: :water_use, label: 'Water use' } if idd =~ /WaterUse_Connections/
      return zone_or_group(component, :heat_pump_coil, 'Heat-pump coil') if idd =~ /WaterToAirHeatPump|WaterToWaterHeatPump/

      if idd =~ /Coil_(Heating|Cooling)_Water/
        z = zone_of(component)
        return { kind: :fan_coil, label: "Fan-coil coil — #{z}" } if z
        return { kind: :cooling_coil, label: 'Cooling coil (air handler)' } if idd =~ /Cooling/

        return { kind: :heating_coil, label: 'Heating coil (air handler)' }
      end

      nil
    end

    # A zone-contained coil is labelled with its zone ("Fan-coil coil — Thermal
    # Zone 1"), so the diagram shows WHERE each coil is; a coil not in a zone
    # keeps the bare label.
    def zone_or_group(component, kind, base)
      zone = zone_of(component)
      { kind: kind, label: zone ? "#{base} — #{zone}" : base }
    end

    # The thermal-zone name a demand coil lives in, traced through its container
    # ZoneHVAC unit (four-pipe fan coil, water-source heat pump, baseboard), or
    # nil for an air-handler coil (whose container is an HVACComponent, not a
    # zone). demandComponents yields bare ModelObjects, so cast up first. Guarded.
    def zone_of(component)
      return nil unless component.respond_to?(:to_HVACComponent)

      hvac = component.to_HVACComponent
      return nil unless hvac.is_initialized

      cz = hvac.get.containingZoneHVACComponent
      return nil unless cz.is_initialized

      tz = cz.get.thermalZone
      tz.is_initialized ? tz.get.nameString : nil
    rescue StandardError
      nil
    end

    def component_name(component)
      component.nameString
    rescue StandardError
      ''
    end

    # ---- loop decomposition (faithful to OpenStudio App GridItem.cpp) ----
    # Each loop side is decomposed by walking its ACTUAL branch structure through
    # the OpenStudio Model API (never by classifying a flat component list): a
    # PRE-series run before the splitter, one PARALLEL branch per non-empty
    # splitter outlet, and a POST-series run after the mixer. This mirrors the
    # OpenStudio Application's SupplySideItem/DemandSideItem + HorizontalBranchGroup
    # decomposition, so two boilers/chillers are two branches, a condenser demand's
    # two chillers are two branches, and zone coils are one branch each — with NO
    # counting, grouping, or collapse anywhere.

    # `real?`: mirrors GridItem.cpp `isNotSplitterMixerNodesPred` — a component is
    # part of the drawn topology iff its iddObjectType is NOT a Node, Splitter,
    # Mixer, or Connector. (Pipes pass this test but yield no drawable CELL — the
    # cell builders return nil for them — so a bare-pipe bypass branch is empty
    # and dropped.)
    def real?(component)
      component.iddObjectType.valueName !~ /Node|Connector_Splitter|Connector_Mixer|ZoneSplitter|ZoneMixer/
    rescue StandardError
      false
    end

    # Decompose one loop side into { pre:, branches:, post: }. `branch_walk` walks
    # the series of one branch (splitter outlet -> mixer); `whole/pre/post` are the
    # ordered component lists for the single-path, before-splitter, and after-mixer
    # runs; `cell_fn` maps a component to a drawable cell (nil = not drawn). If the
    # splitter/mixer yield <= 1 non-empty branch, the side is a single series path
    # (pre = the whole side); otherwise it is genuinely parallel equipment.
    def decompose_side(splitter, mixer, whole, pre, post, branch_walk, cell_fn)
      branches = splitter.outletModelObjects.filter_map do |outlet|
        hvac = outlet.to_HVACComponent
        next nil unless hvac.is_initialized

        cells = branch_walk.call(hvac.get, mixer).select { |c| real?(c) }.filter_map { |c| cell_fn.call(c) }
        cells.empty? ? nil : cells
      end
      return { pre: real_cells(whole, cell_fn), branches: [], post: [] } if branches.size <= 1

      { pre: real_cells(pre, cell_fn), branches: branches, post: real_cells(post, cell_fn) }
    end

    # The drawable cells of an ordered component list (real? components mapped
    # through the cell builder, dropping nodes/connectors/pipes/unclassified).
    def real_cells(components, cell_fn)
      components.select { |c| real?(c) }.filter_map { |c| cell_fn.call(c) }
    end

    # A plant loop's SUPPLY side: pump(s) before the splitter, parallel equipment
    # branches (two chillers/boilers, or a single heat pump / district source),
    # equipment after the mixer.
    def decompose_supply_plant(loop)
      splitter = loop.supplySplitter
      mixer = loop.supplyMixer
      decompose_side(splitter, mixer,
                     loop.supplyComponents,
                     loop.supplyComponents(loop.supplyInletNode, splitter),
                     loop.supplyComponents(mixer, loop.supplyOutletNode),
                     ->(start, mix) { loop.supplyComponents(start, mix) },
                     method(:classify_component))
    rescue StandardError
      { pre: real_cells(loop.supplyComponents, method(:classify_component)), branches: [], post: [] }
    end

    # A plant loop's DEMAND side: each served load (an air-handler coil, or a
    # zone-level fan-coil / baseboard coil, or a cooled chiller condenser / heat
    # pump source) is its OWN parallel branch — straight from the demand splitter's
    # outlets, never counted or collapsed.
    def decompose_demand_plant(loop)
      splitter = loop.demandSplitter
      mixer = loop.demandMixer
      decompose_side(splitter, mixer,
                     loop.demandComponents,
                     loop.demandComponents(loop.demandInletNode, splitter),
                     loop.demandComponents(mixer, loop.demandOutletNode),
                     ->(start, mix) { loop.demandComponents(start, mix) },
                     method(:demand_cell))
    rescue StandardError
      { pre: real_cells(loop.demandComponents, method(:demand_cell)), branches: [], post: [] }
    end

    # An air loop's supply is a single air-handler path (no supply splitter): every
    # real component is a series cell in flow order. AirLoopHVACUnitarySystem
    # containers (staged NECB reference systems) are expanded to the fan and
    # coils they hold — the container itself draws nothing.
    def decompose_air_supply(loop)
      { pre: real_cells(Coils.supply_components(loop), method(:classify_component)), branches: [], post: [] }
    end

    # Flatten a decomposition into ordered supply COLUMNS for the renderer: the
    # pre-series cells and post-series cells are single-cell columns; the parallel
    # branches (if any) are one stacked column of branch series.
    def supply_columns(decomp)
      cols = decomp[:pre].map { |cell| { cells: [cell] } }
      cols << { parallel: true, branches: decomp[:branches] } unless decomp[:branches].empty?
      cols.concat(decomp[:post].map { |cell| { cells: [cell] } })
      cols
    end

    # Flatten a demand decomposition into a list of demand BRANCHES (each a series
    # of cells) for the demand stack: the parallel branches when present, else the
    # single series path as one branch (empty => "No loads").
    def demand_branch_lists(decomp)
      return decomp[:branches] unless decomp[:branches].empty?

      decomp[:pre].empty? ? [] : [decomp[:pre]]
    end

    # Classify + label one supply component, or nil for unclassified nodes/pipes.
    def classify_component(component)
      idd = component.iddObjectType.valueName
      kind = classify(idd)
      return nil unless kind

      name = begin
        component.nameString
      rescue StandardError
        ''
      end
      { kind: kind, name: name, idd: idd, label: component_label(idd, name),
        tooltip: component_tooltip(component, kind, idd, name) }
    end

    def classify(idd_name)
      COMPONENT_KINDS.each { |kind, regex| return kind if idd_name =~ regex }
      nil
    end

    # The SPECIFIC human label for a component, reflecting its exact type rather
    # than the coarse kind — the whole point of the extraction fix. Coils split by
    # DX/electric/gas/water/heat-pump; fans and pumps by control type; chillers by
    # compressor type parsed from the object NAME (the fan-coil and VAV systems
    # differ ONLY by chiller type); boilers by Primary/Secondary; heat pumps vs
    # pumps; district heating vs cooling. Falls back to the coarse kind label.
    def component_label(idd, name = '')
      case idd
      when /Coil_Heating_DX/ then 'DX heating coil'
      when /Coil_Heating_WaterToAirHeatPump/ then 'Heat-pump heating coil'
      when /Coil_Heating_Water/ then 'Hot-water heating coil'
      when /Coil_Heating_Electric/ then 'Electric heating coil'
      when /Coil_Heating_Gas/ then 'Gas heating coil'
      when /Coil_Cooling_DX/ then 'DX cooling coil'
      when /Coil_Cooling_WaterToAirHeatPump/ then 'Heat-pump cooling coil'
      when /Coil_Cooling_Water/ then 'Chilled-water cooling coil'
      when /HeatPump.*Cooling/ then 'Heat pump (cooling)'
      when /HeatPump.*Heating/ then 'Heat pump (heating)'
      when /HeatPump/ then 'Heat pump'
      when /DistrictHeating/ then 'District heating'
      when /DistrictCooling/ then 'District cooling'
      when /Boiler/ then boiler_label(name)
      when /Chiller/ then chiller_label(name)
      when /Fan_ConstantVolume/ then 'Constant-volume fan'
      when /Fan_VariableVolume/ then 'Variable-volume fan'
      when /Fan_OnOff/ then 'On/off fan'
      when /Fan_SystemModel/ then 'Fan (system model)'
      when /HeaderedPumps/ then 'Headered pumps'
      when /Pump_VariableSpeed/ then 'Variable-speed pump'
      when /Pump_ConstantSpeed/ then 'Constant-speed pump'
      else KIND_LABELS.fetch(classify(idd), 'Component')
      end
    end

    # Boiler label from the object name: NECB builds a lead/lag pair named
    # "Primary Boiler" / "Secondary Boiler".
    def boiler_label(name)
      return 'Primary boiler' if name =~ /primary/i
      return 'Secondary boiler' if name =~ /secondary/i

      'Boiler'
    end

    # Chiller label from the compressor type encoded in the object name — the only
    # thing that distinguishes the 16 fan-coil and 18 VAV chiller variants.
    def chiller_label(name)
      return 'Centrifugal chiller' if name =~ /centrifugal/i
      return 'Reciprocating chiller' if name =~ /reciprocat/i
      return 'Rotary-screw chiller' if name =~ /screw/i
      return 'Scroll chiller' if name =~ /scroll/i

      'Chiller'
    end

    # --------------------------------------------------------- tooltip attrs
    # Cheap, sizing-free attribute reads for the hover tooltip. Every getter is
    # guarded — extraction must never raise.

    def clean_idd(idd)
      idd.to_s.sub(/\AOS[_:]/, '').tr('_', ' ').strip
    end

    def component_tooltip(component, kind, idd, name = nil)
      name ||= begin
        component.nameString
      rescue StandardError
        ''
      end
      # First line = the SPECIFIC label; the full iddObjectType + object name are
      # kept below so the hover tooltip always carries the raw truth.
      lines = [component_label(idd, name), "Type: #{clean_idd(idd)}"]
      lines << "Name: #{truncate(name, 48)}" unless name.to_s.empty?
      component_attrs(component, kind, name).each { |k, v| lines << "#{k}: #{v}" }
      lines.join("\n")
    end

    def component_attrs(component, kind, name)
      attrs = {}
      add_opt_attr(attrs, 'Fuel', component, :to_BoilerHotWater, :fuelType)
      add_opt_attr(attrs, 'Fuel', component, :to_CoilHeatingGas, :fuelType)
      add_opt_attr(attrs, 'Fuel', component, :to_WaterHeaterMixed, :heaterFuelType)
      add_flag_attr(attrs, 'Fuel', 'Electricity', component, :to_CoilHeatingElectric)
      if kind == :fan
        type = fan_type(component)
        attrs['Control'] = type if type
      end
      if kind == :chiller
        attrs['Condenser'] = 'air-cooled' if name =~ /air.?cool/i
        attrs['Condenser'] = 'water-cooled' if name =~ /water.?cool/i
      end
      attrs
    end

    def add_opt_attr(attrs, key, component, caster, getter)
      return if attrs.key?(key)
      return unless component.respond_to?(caster)

      opt = component.public_send(caster)
      return unless opt.respond_to?(:is_initialized) && opt.is_initialized

      obj = opt.get
      return unless obj.respond_to?(getter)

      val = obj.public_send(getter).to_s
      attrs[key] = val unless val.empty?
    rescue StandardError
      nil
    end

    def add_flag_attr(attrs, key, value, component, caster)
      return if attrs.key?(key)
      return unless component.respond_to?(caster)

      opt = component.public_send(caster)
      attrs[key] = value if opt.respond_to?(:is_initialized) && opt.is_initialized
    rescue StandardError
      nil
    end

    def fan_type(component)
      %w[VariableVolume ConstantVolume OnOff SystemModel].each do |type|
        caster = "to_Fan#{type}"
        next unless component.respond_to?(caster)

        opt = component.public_send(caster)
        return type.gsub(/([a-z])([A-Z])/, '\1 \2') if opt.respond_to?(:is_initialized) && opt.is_initialized
      end
      nil
    rescue StandardError
      nil
    end

    # Deduped human labels + counts of the ZoneHVAC* equipment on the served zones.
    # @return [Array<Hash>] [{ label:, count: }] ordered as encountered
    # Per-zone equipment — NOT collapsed across zones. Each built zone keeps its
    # own ZoneHVAC* units (same shape as an air-demand zone), so the Zone
    # equipment tab shows one container per zone instead of one aggregated count.
    def zone_equipment(zones)
      zones.filter_map do |zone|
        name = begin
          zone.nameString
        rescue StandardError
          ''
        end
        equipment = zone_hvac_equipment(zone)
        next if equipment.empty?

        tip = ["Zone: #{truncate(name, 40)}"]
        equipment.each { |e| tip << "Zone equipment: #{e[:label]}" }
        { zone_name: name, equipment: equipment, tooltip: tip.join("\n") }
      end
    end

    def zone_equipment_label(idd_name)
      ZONE_EQUIPMENT.each { |regex, label| return label if idd_name =~ regex }
      nil
    end

    # -------------------------------------------------------------- SVG utils
    # Minimal inline-SVG primitives (mirrors necb Report::SVG). No external assets.

    def esc(value)
      value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    # Emit the svg at its NATURAL pixel size: explicit width/height ATTRIBUTES
    # equal to the viewBox dimensions so it renders 1:1 (no stretch-to-fit). Box
    # size and spacing are fixed constants (see CELL_W/CELL_H/CELL_HGAP), so a
    # component box is the same physical size in every diagram; wide loops scroll.
    def open_svg(width, height, label)
      %(<svg width="#{r(width)}" height="#{r(height)}" viewBox="0 0 #{r(width)} #{r(height)}" ) +
        %(role="img" aria-label="#{esc(label)}" ) +
        %(xmlns="http://www.w3.org/2000/svg" font-family="sans-serif" font-size="11">)
    end

    def svg_rect(x, y, w, h, fill, opts = {})
      extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{esc(v)}") }.join
      %(<rect x="#{r(x)}" y="#{r(y)}" width="#{r([w, 0].max)}" height="#{r(h)}" fill="#{fill}"#{extra}/>)
    end

    def svg_line(x1, y1, x2, y2, stroke, opts = {})
      extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{esc(v)}") }.join
      %(<line x1="#{r(x1)}" y1="#{r(y1)}" x2="#{r(x2)}" y2="#{r(y2)}" stroke="#{stroke}"#{extra}/>)
    end

    def svg_text(x, y, string, opts = {})
      extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{esc(v)}") }.join
      %(<text x="#{r(x)}" y="#{r(y)}"#{extra}>#{esc(string)}</text>)
    end

    def r(value)
      value.round(1)
    end

    # ------------------------------------------------------------- OS icons
    # Real OpenStudio Application component icons (BSD-3-Clause), extracted into
    # ICON_DATA/ICON_FOR_IDD by scripts/build_icons.rb. Each icon's base64 PNG is
    # embedded EXACTLY ONCE in a hidden master <svg><defs> as a <symbol>; every
    # component cell references it by id via <use href="#icon-…">, so ~1000 cells
    # add ~40 tiny <use> tags, not ~40 fat data-URIs. See THIRD_PARTY_NOTICES.md.

    # The hidden master defs: one <symbol> per icon, the data-URI embedded once.
    def icon_defs
      syms = ICON_DATA.map do |stem, info|
        %(<symbol id="icon-#{stem}" viewBox="0 0 #{info[:w]} #{info[:h]}" ) +
          %(preserveAspectRatio="xMidYMid meet">) +
          %(<image width="#{info[:w]}" height="#{info[:h]}" href="#{info[:data]}"/></symbol>)
      end.join
      %(<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" aria-hidden="true" ) +
        %(style="position:absolute;width:0;height:0;overflow:hidden"><defs>#{syms}</defs></svg>)
    end

    # A <use> reference to the embedded icon for this idd, or nil if none is
    # mapped (caller then falls back to the hand-drawn glyph).
    def icon_use(idd, x, y, size)
      stem = ICON_FOR_IDD[idd]
      return nil unless stem && ICON_DATA.key?(stem)

      %(<use href="#icon-#{stem}" x="#{r(x)}" y="#{r(y)}" width="#{r(size)}" height="#{r(size)}"/>)
    end

    # The mark drawn on the left of a component cell: the real OS App icon when
    # one is mapped for the idd, else the hand-drawn glyph fallback. Centered in a
    # `size`-wide box whose left edge is at `x`, vertically centered on `cy`.
    def component_mark(kind, idd, x, cy, size)
      icon_use(idd, x, cy - size / 2.0, size) || glyph(kind, x + size / 2.0, cy)
    end

    # ---------------------------------------------------------------- glyphs
    # Tiny hand-drawn component glyphs, centered in a box of the given width.
    # Pure inline SVG paths/shapes — no icon fonts, no external images. Kept as the
    # FALLBACK for any idd without an OS App icon (and used by the legend).
    def glyph(kind, cx, cy)
      case kind
      when :oa # arrow pointing in
        %(<path d="M#{r(cx - 8)} #{r(cy)} H#{r(cx + 5)} M#{r(cx + 1)} #{r(cy - 4)} L#{r(cx + 6)} #{r(cy)} L#{r(cx + 1)} #{r(cy + 4)}" fill="none" stroke="#1b4f72" stroke-width="1.6"/>)
      when :cooling_coil, :heating_coil # zigzag coil
        pts = (0..6).map { |i| "#{r(cx - 9 + i * 3)},#{r(cy + (i.even? ? -4 : 4))}" }.join(' ')
        stroke = kind == :heating_coil ? '#a04000' : '#1b4f72'
        %(<polyline points="#{pts}" fill="none" stroke="#{stroke}" stroke-width="1.6"/>)
      when :fan, :pump # circle with a blade tick
        %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="7" fill="none" stroke="#145a32" stroke-width="1.6"/>) +
          %(<line x1="#{r(cx)}" y1="#{r(cy)}" x2="#{r(cx + 5)}" y2="#{r(cy - 3)}" stroke="#145a32" stroke-width="1.6"/>)
      when :boiler # flame / up-triangle
        %(<path d="M#{r(cx)} #{r(cy - 7)} L#{r(cx + 6)} #{r(cy + 6)} L#{r(cx - 6)} #{r(cy + 6)} Z" fill="#922b21"/>)
      when :chiller # snowflake
        s = 7
        %(<g stroke="#154360" stroke-width="1.5">) +
          %(<line x1="#{r(cx - s)}" y1="#{r(cy)}" x2="#{r(cx + s)}" y2="#{r(cy)}"/>) +
          %(<line x1="#{r(cx)}" y1="#{r(cy - s)}" x2="#{r(cx)}" y2="#{r(cy + s)}"/>) +
          %(<line x1="#{r(cx - 5)}" y1="#{r(cy - 5)}" x2="#{r(cx + 5)}" y2="#{r(cy + 5)}"/>) +
          %(<line x1="#{r(cx - 5)}" y1="#{r(cy + 5)}" x2="#{r(cx + 5)}" y2="#{r(cy - 5)}"/></g>)
      when :tower # down chevrons (heat rejection)
        %(<path d="M#{r(cx - 7)} #{r(cy - 4)} L#{r(cx)} #{r(cy + 1)} L#{r(cx + 7)} #{r(cy - 4)} M#{r(cx - 7)} #{r(cy + 1)} L#{r(cx)} #{r(cy + 6)} L#{r(cx + 7)} #{r(cy + 1)}" fill="none" stroke="#0e6251" stroke-width="1.6"/>)
      when :heat_pump # circle with up + down arrows (bidirectional heat transfer)
        %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="7.5" fill="none" stroke="#0b5345" stroke-width="1.5"/>) +
          %(<path d="M#{r(cx - 3)} #{r(cy + 4)} V#{r(cy - 4)} M#{r(cx - 5)} #{r(cy - 1)} L#{r(cx - 3)} #{r(cy - 4)} L#{r(cx - 1)} #{r(cy - 1)}" fill="none" stroke="#0b5345" stroke-width="1.3"/>) +
          %(<path d="M#{r(cx + 3)} #{r(cy - 4)} V#{r(cy + 4)} M#{r(cx + 1)} #{r(cy + 1)} L#{r(cx + 3)} #{r(cy + 4)} L#{r(cx + 5)} #{r(cy + 1)}" fill="none" stroke="#0b5345" stroke-width="1.3"/>)
      when :district # external plant: little building with a roof
        %(<rect x="#{r(cx - 7)}" y="#{r(cy - 1)}" width="14" height="7" fill="none" stroke="#6c3483" stroke-width="1.4"/>) +
          %(<path d="M#{r(cx - 8)} #{r(cy - 1)} L#{r(cx)} #{r(cy - 7)} L#{r(cx + 8)} #{r(cy - 1)}" fill="none" stroke="#6c3483" stroke-width="1.4"/>)
      when :hx # diamond
        %(<path d="M#{r(cx)} #{r(cy - 7)} L#{r(cx + 7)} #{r(cy)} L#{r(cx)} #{r(cy + 7)} L#{r(cx - 7)} #{r(cy)} Z" fill="none" stroke="#6c3483" stroke-width="1.6"/>)
      when :water_heater
        %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="7" fill="none" stroke="#6c3483" stroke-width="1.6"/><line x1="#{r(cx)}" y1="#{r(cy - 4)}" x2="#{r(cx)}" y2="#{r(cy + 4)}" stroke="#6c3483" stroke-width="1.6"/>)
      when :zone # served-zone box with a divider
        %(<rect x="#{r(cx - 7)}" y="#{r(cy - 6)}" width="14" height="12" fill="none" stroke="#566573" stroke-width="1.4"/>) +
          %(<line x1="#{r(cx)}" y1="#{r(cy - 6)}" x2="#{r(cx)}" y2="#{r(cy + 6)}" stroke="#566573" stroke-width="1"/>)
      when :terminal, :fan_coil # diffuser / terminal: down-pointing wedge
        %(<path d="M#{r(cx - 7)} #{r(cy - 5)} H#{r(cx + 7)} L#{r(cx)} #{r(cy + 6)} Z" fill="none" stroke="#5d6d7e" stroke-width="1.5"/>)
      when :baseboard # low finned box
        %(<rect x="#{r(cx - 8)}" y="#{r(cy - 2)}" width="16" height="7" fill="none" stroke="#a04000" stroke-width="1.4"/>) +
          %(<path d="M#{r(cx - 6)} #{r(cy - 2)} V#{r(cy - 6)} M#{r(cx)} #{r(cy - 2)} V#{r(cy - 6)} M#{r(cx + 6)} #{r(cy - 2)} V#{r(cy - 6)}" stroke="#a04000" stroke-width="1.2"/>)
      when :water_use # tap / droplet
        %(<path d="M#{r(cx)} #{r(cy - 7)} C#{r(cx + 6)} #{r(cy)} #{r(cx + 4)} #{r(cy + 6)} #{r(cx)} #{r(cy + 6)} C#{r(cx - 4)} #{r(cy + 6)} #{r(cx - 6)} #{r(cy)} #{r(cx)} #{r(cy - 7)} Z" fill="none" stroke="#1b4f72" stroke-width="1.4"/>)
      else
        %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="5" fill="none" stroke="#555" stroke-width="1.4"/>)
      end
    end

    # ------------------------------------------------------------- diagrams
    # Each loop is drawn as a VERTICAL CASCADE matching the OpenStudio App's
    # GridItem.cpp layout: the SUPPLY equipment as a horizontal row on TOP, a
    # labelled center connector band, then the DEMAND side on the BOTTOM as a
    # splitter -> parallel branches (stacked vertically) -> mixer, closed by
    # left/right risers with flow arrows so it reads as circulation.

    # Fixed pixel geometry mirroring the OS App's ~90px GridItem grid. Every
    # constant is FIXED (never derived from component count or container width) so
    # a cell is the same physical size in every diagram and wide/tall loops SCROLL
    # in .diagram (overflow-x:auto) instead of rescaling.
    GRID      = 90    # OS App grid cell (setGridPos*100 there; scaled here)
    CELL_W    = 130   # component cell width
    CELL_H    = 44    # component cell height
    CELL_HGAP = 30    # gap between series cells (left -> right)
    CELL_VGAP = 16    # gap between vertically-stacked parallel branches
    NODE_R    = 6     # splitter / mixer / connection node radius (~15px in OS App)
    BUS_TAP   = 24    # splitter/mixer bus stand-off from the branch content
    BAND_H    = 58    # center connector band height (Supply/Demand labels + nodes)
    ZONE_W    = 156   # air-demand zone cell width
    ZHEAD_H   = 24    # zone cell header height
    ZROW_H    = 18    # one zone-level row (equipment) inside the zone cell
    ZONE_PAD  = 10    # zone cell bottom padding
    PBR_W     = 202   # plant-demand branch cell width (fits zone-labelled coils on two lines)
    EDGE      = 24    # closing-riser inset from the svg edge
    EDGE_GAP  = 22    # gap between a closing riser and the content
    PAD_TOP   = 14    # top padding above the supply row
    PAD_BOT   = 16    # bottom padding below the demand block

    # Dispatch: air loops draw a zone branch on demand; plant loops draw the
    # served loads as parallel demand branches. Both share the vertical cascade.
    def loop_diagram_svg(loop)
      loop[:kind] == :air ? air_loop_diagram(loop) : plant_loop_diagram(loop)
    end

    # AIR loop cascade: SUPPLY row on top (OA + coils/fan/hx), then ONE demand
    # branch PER served zone (splitter -> stacked zone branches -> mixer); each
    # zone branch = [air terminal cell] -> [zone cell listing the zone's ZoneHVAC*
    # equipment]. Single-zone systems show 1 branch, multi-zone show 2.
    def air_loop_diagram(loop)
      accent = LOOP_COLORS.fetch(:air, '#555')
      supply = loop[:supply].empty? ? nil : loop[:supply]
      render_cascade('Air loop diagram', accent, supply, air_demand_branches(loop[:demand], accent))
    end

    # PLANT loop cascade: SUPPLY row on top (pump -> boiler/chiller/tower/...,
    # setpoint tick at the outlet), DEMAND on the bottom as splitter -> PARALLEL
    # branch cells (one per served-load group, incl. zone-level baseboard /
    # fan-coil coils) stacked vertically -> mixer.
    def plant_loop_diagram(loop)
      accent = LOOP_COLORS.fetch(loop[:kind], '#555')
      supply = loop[:supply].empty? ? nil : loop[:supply]
      label = "#{LOOP_LABELS.fetch(loop[:kind], 'Loop')} diagram"
      render_cascade(label, accent, supply, plant_demand_branches(loop[:demand], accent), setpoint: true)
    end

    # Assemble a full cascade: measure the supply row and the demand stack, place
    # supply on TOP and demand on the BOTTOM (padded to a shared content width and
    # centered), then draw the center band and the closing risers between them.
    def render_cascade(title, accent, supply, demand_specs, setpoint: false)
      sup = measure_supply(supply)
      dem = measure_demand(demand_specs)
      content_w = [sup[:w], dem[:w]].max

      content_x0 = EDGE + EDGE_GAP
      left_riser_x = EDGE
      right_riser_x = content_x0 + content_w + EDGE_GAP
      svg_w = right_riser_x + EDGE
      center_x = content_x0 + content_w / 2.0

      supply_top = PAD_TOP
      supply_cy = supply_top + sup[:h] / 2.0
      band_top = supply_top + sup[:h]
      demand_top = band_top + BAND_H
      svg_h = demand_top + dem[:h] + PAD_BOT

      supply_x0 = content_x0 + (content_w - sup[:w]) / 2.0
      demand_x0 = content_x0 + (content_w - dem[:w]) / 2.0

      s = draw_supply(sup, accent, supply_x0, supply_cy, setpoint: setpoint)
      d = draw_demand(dem, accent, demand_x0, demand_top)

      out = [open_svg(svg_w, svg_h, title)]
      out.concat(closing_risers(accent, left_riser_x, right_riser_x, s, d))
      out.concat(center_band(accent, center_x, band_top, demand_top))
      out.concat(s[:parts])
      out.concat(d[:parts])
      out << '</svg>'
      out.join
    end

    # ---- supply row (TOP) ----

    # Measure the supply row: a mix of single-cell SERIES columns and a stacked
    # PARALLEL column (genuinely parallel equipment, each branch itself a short
    # left->right series). Columns may differ in width, so widths are summed; row
    # height grows to fit the tallest parallel column.
    def measure_supply(cols)
      cols = [{ cells: [nil] }] if cols.nil? || cols.empty?
      dims = cols.map { |col| supply_col_dims(col) }
      { cols: cols, dims: dims,
        w: dims.sum { |d| d[0] } + (cols.size - 1) * CELL_HGAP,
        h: dims.map { |d| d[1] }.max }
    end

    # [width, height] of one supply column: a series cell is one CELL_W box; a
    # parallel column is as wide as its longest branch series and as tall as its
    # stacked branches.
    def supply_col_dims(col)
      return [CELL_W, CELL_H] unless col[:parallel]

      n = col[:branches].size
      max_len = col[:branches].map(&:size).max
      [max_len * CELL_W + (max_len - 1) * CELL_HGAP, n * CELL_H + (n - 1) * CELL_VGAP]
    end

    # Draw the supply row left->right in flow order. Series columns (one cell) are
    # joined by horizontal pipes with flow arrows; a parallel column is drawn as
    # its branch series stacked vertically between a splitter (left) and mixer
    # (right) node — straight from the loop's real splitter, never from a count.
    # Returns the row's inlet/outlet points for the closing risers.
    def draw_supply(sup, accent, x0, cy, setpoint: false)
      parts = []
      inlet = nil
      outlet = nil
      prev_right = nil
      col_x = x0
      sup[:cols].each_with_index do |col, i|
        col_w = sup[:dims][i][0]
        if col[:parallel]
          left_pt, right_pt = draw_supply_parallel(parts, col, accent, col_x, col_w, cy)
        else
          parts << supply_cell(col_x, cy - CELL_H / 2.0, col[:cells].first, accent)
          left_pt = [col_x, cy]
          right_pt = [col_x + CELL_W, cy]
        end
        if prev_right
          parts << svg_line(prev_right[0], cy, left_pt[0], cy, accent, stroke_width: 2)
          parts << flow_arrow((prev_right[0] + left_pt[0]) / 2.0, cy, :right, accent)
        end
        inlet ||= left_pt
        outlet = right_pt
        prev_right = right_pt
        col_x += col_w + CELL_HGAP
      end
      parts << setpoint_tick(outlet[0] + 9, cy, accent) if setpoint && outlet
      { parts: parts, inlet: inlet, outlet: outlet }
    end

    # Draw a parallel supply column: N branches (each a left->right series of
    # cells) stacked vertically between a splitter dot (left) and mixer dot
    # (right). Returns the column's [left, right] connection points.
    def draw_supply_parallel(parts, col, accent, col_x, col_w, cy)
      branches = col[:branches]
      n = branches.size
      col_h = n * CELL_H + (n - 1) * CELL_VGAP
      top = cy - col_h / 2.0
      sx = col_x - CELL_HGAP * 0.45
      mx = col_x + col_w + CELL_HGAP * 0.45
      branches.each_with_index do |cells, j|
        cyj = top + j * (CELL_H + CELL_VGAP) + CELL_H / 2.0
        bx = col_x
        cells.each_with_index do |branch_cell, k|
          if k.positive?
            parts << svg_line(bx - CELL_HGAP, cyj, bx, cyj, accent, stroke_width: 1.4)
            parts << flow_arrow(bx - CELL_HGAP / 2.0, cyj, :right, accent)
          end
          parts << supply_cell(bx, cyj - CELL_H / 2.0, branch_cell, accent)
          bx += CELL_W + CELL_HGAP
        end
        branch_right = col_x + cells.size * CELL_W + (cells.size - 1) * CELL_HGAP
        parts << svg_line(sx, cy, col_x, cyj, accent, stroke_width: 1.2)
        parts << svg_line(branch_right, cyj, mx, cy, accent, stroke_width: 1.2)
      end
      parts << node_dot(sx, cy, accent, 'Supply splitter (parallel equipment)')
      parts << node_dot(mx, cy, accent, 'Supply mixer (parallel equipment)')
      [[sx, cy], [mx, cy]]
    end

    # One supply cell for a classified component. The visible line is the SPECIFIC
    # label (e.g. "DX heating coil" vs "Electric heating coil", "Centrifugal
    # chiller", "Constant-volume fan"), truncated to the fixed cell width; the
    # full label + raw iddObjectType + object name live in the <title> tooltip.
    def supply_cell(x, y, data, accent)
      return cell(x, y, CELL_W, CELL_H, :other, 'No components', '',
                  'No classified supply components on this loop', accent) if data.nil?

      cell(x, y, CELL_W, CELL_H, data[:kind], data[:label], nil,
           data[:tooltip], accent, idd: data[:idd])
    end

    # A single component cell: the real OS App icon (or the hand-drawn glyph
    # fallback) on the left, one or two text lines, and a native <title> tooltip.
    # Fixed geometry; used by supply and plant demand. The loop-kind color remains
    # the box fill/border.
    # The type label is word-wrapped to fit the cell so specific types are never
    # truncated; the object name is intentionally omitted (it is noise here and
    # already lives in the <title> tooltip). `_line2` is retained for signature
    # compatibility but ignored.
    def cell(x, y, w, h, kind, line1, _line2, tooltip, accent, idd: nil)
      fill = KIND_COLORS.fetch(kind, '#d5d8dc')
      tx = x + 32
      budget = [((w - 40) / 5.7).floor, 8].max
      lines = wrap_label(line1, budget, 2)
      parts = ['<g class="cell">', %(<title>#{esc(tooltip)}</title>)]
      parts << svg_rect(x, y, w, h, fill, stroke: accent, rx: 6, stroke_width: 1.4)
      parts << component_mark(kind, idd, x + 4, y + h / 2.0, 24)
      if lines.size <= 1
        parts << svg_text(tx, y + h / 2.0 + 3.5, lines.first.to_s, font_weight: 'bold', font_size: 10)
      else
        parts << svg_text(tx, y + h / 2.0 - 2.5, lines[0], font_weight: 'bold', font_size: 10)
        parts << svg_text(tx, y + h / 2.0 + 9.5, lines[1], font_weight: 'bold', font_size: 10)
      end
      parts << '</g>'
      parts.join
    end

    # ---- demand stack (BOTTOM) ----

    # Measure the demand block: a shared content width (branches padded to match)
    # and the total stacked height. Width includes the splitter/mixer bus taps.
    def measure_demand(branch_specs)
      content_w = branch_specs.map { |b| b[:content_w] }.max
      stack_h = branch_specs.sum { |b| b[:content_h] } + (branch_specs.size - 1) * CELL_VGAP
      { branches: branch_specs, content_w: content_w,
        w: 2 * NODE_R + 2 * BUS_TAP + content_w, h: stack_h }
    end

    # Draw the demand block: a splitter node + vertical bus on the LEFT, N branches
    # stacked vertically (each its own horizontal row rendered by its spec), and a
    # mixer node + vertical bus on the RIGHT. Small tap dots where branches meet
    # the buses. Returns the splitter/mixer points for the closing risers.
    def draw_demand(dem, accent, x0, top)
      split_x = x0 + NODE_R
      content_x = split_x + BUS_TAP
      mixer_x = content_x + dem[:content_w] + BUS_TAP
      dcy = top + dem[:h] / 2.0

      centers = []
      y = top
      dem[:branches].each do |b|
        centers << y + b[:content_h] / 2.0
        y += b[:content_h] + CELL_VGAP
      end

      parts = []
      parts << svg_line(split_x, centers.first, split_x, centers.last, accent, stroke_width: 2)
      parts << svg_line(mixer_x, centers.first, mixer_x, centers.last, accent, stroke_width: 2)
      dem[:branches].each_with_index do |b, i|
        bcy = centers[i]
        parts << svg_line(split_x, bcy, content_x, bcy, accent, stroke_width: 1.4)
        parts << svg_line(content_x + b[:content_w], bcy, mixer_x, bcy, accent, stroke_width: 1.4)
        parts << flow_arrow(content_x - 8, bcy, :right, accent)
        parts << tap_dot(split_x, bcy, accent)
        parts << tap_dot(mixer_x, bcy, accent)
        parts << %(<g class="demand-branch">#{b[:render].call(content_x, bcy)}</g>)
      end
      parts << node_dot(split_x, dcy, accent, 'Demand splitter (inlet)', css: 'demand-splitter')
      parts << node_dot(mixer_x, dcy, accent, 'Demand mixer (outlet)', css: 'demand-mixer')
      { parts: parts, splitter: [split_x, dcy], mixer: [mixer_x, dcy] }
    end

    # The air-loop demand: one branch PER served zone = [air terminal cell] ->
    # [zone cell listing that zone's ZoneHVAC* equipment], stacked vertically
    # between the demand splitter and mixer. One branch for single-zone systems,
    # two for multi-zone (the diagram is built on at most 2 zones).
    def air_demand_branches(zones, accent)
      list = zones.nil? || zones.empty? ? [nil] : zones
      list.map do |zone|
        rows = zone_container_rows(zone)
        zone_h = ZHEAD_H + rows.size * ZROW_H + ZONE_PAD
        content_h = [CELL_H, zone_h].max
        render = lambda do |cx, cy|
          term = zone && zone[:terminal]
          tk = term ? :terminal : :other
          t_label = term ? term[:label] : 'No terminal'
          t_tip = term ? term[:tooltip] : 'No air terminal on this zone'
          t_idd = term ? term[:idd] : nil
          zx = cx + CELL_W + CELL_HGAP
          parts = [cell(cx, cy - CELL_H / 2.0, CELL_W, CELL_H, tk, t_label, nil, t_tip, accent, idd: t_idd)]
          parts << svg_line(cx + CELL_W, cy, zx, cy, accent, stroke_width: 1.4)
          parts << flow_arrow((cx + CELL_W + zx) / 2.0, cy, :right, accent)
          parts << zone_cell(zx, cy - zone_h / 2.0, zone_h, zone, rows, accent)
          parts.join
        end
        { content_w: CELL_W + CELL_HGAP + ZONE_W, content_h: content_h, render: render }
      end
    end

    # The plant-loop demand: one stacked branch per PARALLEL demand branch, drawn
    # straight from the demand splitter's outlets (never a count). Each branch is a
    # left->right series of served-load cells (a fan-coil / baseboard coil, an
    # air-handler coil, a cooled chiller condenser, a heat-pump source, water use);
    # in practice a served branch is a single cell, but a multi-cell series draws
    # faithfully. An empty demand shows a single "No loads" note.
    def plant_demand_branches(branch_lists, accent)
      list = branch_lists.nil? || branch_lists.empty? ? [nil] : branch_lists
      list.map do |cells|
        n = cells.nil? ? 1 : cells.size
        content_w = n * PBR_W + (n - 1) * CELL_HGAP
        render = lambda do |cx, cy|
          next plant_branch_cell(cx, cy - CELL_H / 2.0, nil, accent) if cells.nil?

          bx = cx
          parts = []
          cells.each_with_index do |c, k|
            if k.positive?
              parts << svg_line(bx - CELL_HGAP, cy, bx, cy, accent, stroke_width: 1.4)
              parts << flow_arrow(bx - CELL_HGAP / 2.0, cy, :right, accent)
            end
            parts << plant_branch_cell(bx, cy - CELL_H / 2.0, c, accent)
            bx += PBR_W + CELL_HGAP
          end
          parts.join
        end
        { content_w: content_w, content_h: CELL_H, render: render }
      end
    end

    def plant_branch_cell(x, y, branch, accent)
      branch ||= { kind: :other, label: 'No loads',
                   tooltip: 'No demand-side loads on this loop' }
      cell(x, y, PBR_W, CELL_H, branch[:kind] || :other, branch[:label].to_s, nil,
           branch[:tooltip], accent, idd: branch[:idd])
    end

    # The zone-equipment rows listed inside an air-loop zone cell: each ZoneHVAC*
    # unit (baseboard, PTAC, fan coil, unit heater). The air TERMINAL is drawn as
    # its own upstream cell, so it is NOT repeated here. Never empty.
    def zone_container_rows(zone)
      rows = (zone && zone[:equipment] || []).map do |eq|
        kind = eq[:label] =~ /baseboard/i ? :baseboard : :other
        { kind: kind, text: eq[:label], count: eq[:count], tooltip: eq[:tooltip], idd: eq[:idd] }
      end
      rows << { kind: :zone, text: 'no zone equipment', count: nil } if rows.empty?
      rows
    end

    # The air-loop demand zone cell: header = the served zone's name, with the
    # zone-equipment rows stacked inside it. One cell per served zone.
    def zone_cell(x, y, h, zone, rows, accent)
      name = zone ? zone[:zone_name].to_s : ''
      head = name.empty? ? 'Served zone' : "Zone: #{truncate(name, 18)}"
      tip = zone ? zone[:tooltip] : 'Served zone'
      parts = ['<g class="cell zone-cell">', %(<title>#{esc(tip)}</title>)]
      parts << svg_rect(x, y, ZONE_W, h, '#eef2f5', stroke: accent, rx: 6, stroke_width: 1.6)
      parts << (icon_use('OS_ThermalZone', x + 5, y + 4, 16) || glyph(:zone, x + 14, y + 13))
      parts << svg_text(x + 26, y + 16, head, font_weight: 'bold', font_size: 9, fill: accent)
      parts << svg_line(x + 6, y + ZHEAD_H - 3, x + ZONE_W - 6, y + ZHEAD_H - 3, '#c9d3da', stroke_width: 1)
      rows.each_with_index do |row, i|
        ry = y + ZHEAD_H + i * ZROW_H + ZROW_H / 2.0
        parts << '<g>'
        parts << %(<title>#{esc(row[:tooltip])}</title>) if row[:tooltip]
        parts << (icon_use(row[:idd], x + 7, ry - 8, 16) || row_glyph(row[:kind], x + 15, ry))
        text = row[:count].to_i > 1 ? "#{row[:text]} ×#{row[:count]}" : row[:text]
        parts << svg_text(x + 28, ry + 3.5, truncate(text, 22), font_size: 9)
        parts << '</g>'
      end
      parts << '</g>'
      parts.join
    end

    # ---- center band + closing risers ----

    # The center connector band between supply and demand: the "Supply Equipment"
    # / "Demand Equipment" labels, the supply-outlet and demand-inlet nodes, and a
    # central feed pipe carrying flow down from the supply block into the demand.
    def center_band(accent, center_x, band_top, band_bot)
      mid = (band_top + band_bot) / 2.0
      [
        svg_line(center_x, band_top, center_x, band_bot, accent, stroke_width: 1.6, stroke_dasharray: '4 3'),
        flow_arrow(center_x, mid + 4, :down, accent),
        band_label('Supply Equipment', center_x, band_top + 18, accent),
        band_label('Demand Equipment', center_x, band_bot - 7, accent),
        node_dot(center_x, band_top, accent, 'Supply outlet node'),
        node_dot(center_x, band_bot, accent, 'Demand inlet node')
      ]
    end

    # A band label with a white halo so the central feed pipe does not strike
    # through the text.
    def band_label(text, cx, y, accent)
      w = text.length * 5.7 + 8
      svg_rect(cx - w / 2.0, y - 10, w, 14, '#ffffff') +
        svg_text(cx, y, text, text_anchor: 'middle', font_weight: 'bold', font_size: 10, fill: accent)
    end

    # The closing risers that make it read as a closed loop: the supply OUTLET
    # runs out to the right edge and DOWN to the demand mixer (arrow down); the
    # demand splitter runs to the left edge and UP to the supply INLET (arrow up).
    def closing_risers(accent, lx, rx, s, d)
      w = 2
      s_in = s[:inlet]
      s_out = s[:outlet]
      d_split = d[:splitter]
      d_mix = d[:mixer]
      [
        svg_line(lx, s_in[1], s_in[0], s_in[1], accent, stroke_width: w),
        svg_line(lx, d_split[1], d_split[0], d_split[1], accent, stroke_width: w),
        svg_line(lx, s_in[1], lx, d_split[1], accent, stroke_width: w),
        flow_arrow(lx, (s_in[1] + d_split[1]) / 2.0, :up, accent),
        svg_line(s_out[0], s_out[1], rx, s_out[1], accent, stroke_width: w),
        svg_line(d_mix[0], d_mix[1], rx, d_mix[1], accent, stroke_width: w),
        svg_line(rx, s_out[1], rx, d_mix[1], accent, stroke_width: w),
        flow_arrow(rx, (s_out[1] + d_mix[1]) / 2.0, :down, accent)
      ]
    end

    # A small filled node where a branch taps a splitter/mixer bus.
    def tap_dot(x, y, accent)
      %(<circle cx="#{r(x)}" cy="#{r(y)}" r="2.6" fill="#{accent}"/>)
    end

    # Small in-container row glyph (terminal wedge, baseboard fins, or generic dot).
    def row_glyph(kind, cx, cy)
      case kind
      when :terminal
        %(<path d="M#{r(cx - 6)} #{r(cy - 4)} H#{r(cx + 6)} L#{r(cx)} #{r(cy + 5)} Z" fill="none" stroke="#1a5276" stroke-width="1.3"/>)
      when :baseboard
        %(<rect x="#{r(cx - 6)}" y="#{r(cy - 2)}" width="12" height="5" fill="none" stroke="#a04000" stroke-width="1.2"/>)
      else
        %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="3.4" fill="none" stroke="#555" stroke-width="1.3"/>)
      end
    end

    # A loop node (splitter / mixer / connection point) — a hollow dot with a
    # tooltip and an optional CSS class for the demand splitter/mixer markers.
    def node_dot(x, y, accent, label, css: nil)
      cls = css ? %( class="#{css}") : ''
      %(<g#{cls}><title>#{esc(label)}</title>) +
        %(<circle cx="#{r(x)}" cy="#{r(y)}" r="#{NODE_R}" fill="#fff" stroke="#{accent}" stroke-width="1.8"/></g>)
    end

    # A setpoint-manager tick at a supply outlet node.
    def setpoint_tick(x, y, accent)
      %(<g><title>Setpoint node (supply outlet)</title>) +
        %(<line x1="#{r(x)}" y1="#{r(y - 7)}" x2="#{r(x)}" y2="#{r(y + 7)}" stroke="#{accent}" stroke-width="1.6"/>) +
        %(<circle cx="#{r(x)}" cy="#{r(y - 9)}" r="2.4" fill="#{accent}"/></g>)
    end

    def flow_arrow(x, y, dir, color)
      case dir
      when :down  then %(<path d="M#{r(x - 5)} #{r(y - 4)} L#{r(x + 5)} #{r(y - 4)} L#{r(x)} #{r(y + 5)} Z" fill="#{color}"/>)
      when :up    then %(<path d="M#{r(x - 5)} #{r(y + 4)} L#{r(x + 5)} #{r(y + 4)} L#{r(x)} #{r(y - 5)} Z" fill="#{color}"/>)
      when :right then %(<path d="M#{r(x - 4)} #{r(y - 5)} L#{r(x - 4)} #{r(y + 5)} L#{r(x + 5)} #{r(y)} Z" fill="#{color}"/>)
      when :left  then %(<path d="M#{r(x + 4)} #{r(y - 5)} L#{r(x + 4)} #{r(y + 5)} L#{r(x - 5)} #{r(y)} Z" fill="#{color}"/>)
      end
    end

    # The Zone equipment tab: one zone container per built zone (reusing the
    # air-demand zone_cell), stacked vertically — NOT collapsed into counts.
    def zone_equipment_svg(zones_data)
      return %(<p class="note">No zone equipment on this system.</p>) if zones_data.empty?

      accent = '#5d6d7e'
      gap = 14
      metrics = zones_data.map do |z|
        rows = zone_container_rows(z)
        [z, rows, ZHEAD_H + rows.size * ZROW_H + 8]
      end
      total_h = metrics.sum { |m| m[2] } + (metrics.size - 1) * gap + 16
      parts = [open_svg(ZONE_W + 20, total_h, 'Zone equipment')]
      y = 8
      metrics.each do |z, rows, h|
        parts << zone_cell(10, y, h, z, rows, accent)
        y += h + gap
      end
      parts << '</svg>'
      parts.join
    end

    def truncate(string, max)
      string.to_s.length > max ? "#{string[0, max - 1]}…" : string.to_s
    end

    # Word-wrap a label into at most `max_lines` lines of ~`max_chars` each so the
    # full specific type (e.g. "Chilled-water cooling coil") shows instead of
    # being truncated. Overflowing words hard-truncate as a last resort.
    def wrap_label(string, max_chars, max_lines = 2)
      lines = ['']
      string.to_s.split(/\s+/).each do |word|
        if lines.last.empty?
          lines[-1] = word
        elsif lines.last.length + 1 + word.length <= max_chars
          lines[-1] = "#{lines.last} #{word}"
        elsif lines.size < max_lines
          lines << word
        else
          lines[-1] = "#{lines.last} #{word}"
        end
      end
      lines.map { |l| l.length > max_chars ? "#{l[0, max_chars - 1]}…" : l }
    end

    # ---------------------------------------------------------------- HTML

    def assemble(cards)
      by_family = cards.group_by { |c| c[:row]['family'] }
      families = by_family.keys.sort_by { |f| FAMILY_TITLES.fetch(f, f).downcase }

      idx = 0
      ordered = {}
      families.each do |family|
        ordered[family] = by_family[family].sort_by { |c| c[:row]['name'] }
        ordered[family].each { |c| c[:id] = "sys-#{idx}"; idx += 1 }
      end
      total = cards.size
      display_cards = families.flat_map { |f| ordered[f] }

      out = [+'<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">']
      out << '<meta name="viewport" content="width=device-width, initial-scale=1">'
      out << '<title>OpenStudio-HVAC System Catalog</title>'
      out << "<style>#{CSS}</style></head><body>"
      # The embedded OS App icons: every data-URI lives ONCE in this hidden master
      # defs; component cells reference them by id via <use>.
      out << icon_defs
      out << topbar(total, families.size)
      out << '<div class="app">'
      out << sidebar(families, ordered, total)
      out << '<main class="detail-pane">'
      out << display_cards.each_with_index.map { |c, i| detail_html(c, i.zero?) }.join
      out << '</main></div>'
      out << footer
      out << "<script>#{script(total)}</script>"
      out << '</body></html>'
      out.join
    end

    def topbar(total, family_count)
      %(<header class="topbar"><h1>OpenStudio-HVAC System Catalog</h1>) +
        %(<p class="meta">#{total} buildable HVAC systems across #{family_count} families. ) +
        %(Every diagram is extracted from a system actually built on the bundled 5-zone fixture — ) +
        %(the topology cannot drift from what the gem assembles. Select a system on the left; hover ) +
        %(any component for details.</p>#{legend}</header>)
    end

    # Only the loop-colour key is shown: component symbols are the real
    # OpenStudio App icons (self-labelled, with tooltips), so a glyph legend
    # would just list marks the diagram no longer draws.
    def legend
      loop_keys = LOOP_COLORS.map do |kind, color|
        %(<span class="lk"><span class="sw" style="background:#{color}"></span>#{esc(LOOP_LABELS[kind])}</span>)
      end.join
      %(<div class="legend"><strong>Loops</strong>#{loop_keys}) +
        %(<span class="lk-note">Component symbols are OpenStudio Application icons; hover any for details.</span></div>)
    end

    def sidebar(families, ordered, total)
      groups = families.map do |family|
        items = ordered[family].map do |card|
          row = card[:row]
          search = [row['name'], card[:canonical], family, row['sys_abbr']].compact.join(' ').downcase
          active = card[:id] == 'sys-0' ? ' active' : ''
          # Always show the canonical (human-readable) name in the nav for
          # consistency; the exact argument name stays searchable + as a tooltip.
          %(<button type="button" class="nav-item#{active}" data-target="#{card[:id]}" ) +
            %(data-search="#{esc(search)}" title="#{esc(row['name'])}">#{esc(card[:canonical])}</button>)
        end.join
        %(<div class="nav-family collapsed"><button type="button" class="nav-family-title">) +
          %(<span class="caret">&#9656;</span>#{esc(FAMILY_TITLES.fetch(family, family))}</button>#{items}</div>)
      end.join
      %(<aside class="sidebar">) +
        %(<div class="search-wrap"><input type="search" id="system-search" placeholder="Search systems…" ) +
        %(autocomplete="off" aria-label="Search systems"><span id="search-count">#{total} of #{total}</span></div>) +
        %(<nav class="nav-list">#{groups}</nav></aside>)
    end

    def detail_html(card, first)
      row = card[:row]
      badges = [%(<span class="badge badge-family">#{esc(row['family'])}</span>)]
      badges << %(<span class="badge badge-sys">#{esc(row['sys_abbr'])}</span>) if row['sys_abbr']
      active = first ? ' active' : ''
      %(<article class="system-detail#{active}" id="#{card[:id]}">) +
        %(<div class="detail-head"><code>#{esc(row['name'])}</code>#{badges.join}</div>) +
        %(<div class="canonical">#{esc(card[:canonical])}</div>) +
        %(<p class="desc">#{esc(card[:description])}</p>) +
        %(#{tabs_html(card)}</article>)
    end

    # Render the system's loops as TABS (one per loop present), plus a
    # zone-equipment tab if there is any. Tab switching is scoped per system by
    # the inline JS, so switching tabs on the shown system can't affect others.
    def tabs_html(card)
      unless card[:topology]
        note = card[:diagram_error] ? ": #{esc(card[:diagram_error])}" : ''
        return %(<p class="note note-err">Diagram unavailable — this system did not build on the fixture#{note}.</p>)
      end

      topology = card[:topology]
      loops = topology[:air_loops] + topology[:plant_loops]
      tabs = []
      seen = Hash.new(0)
      loops.each do |loop|
        base = LOOP_LABELS.fetch(loop[:kind], 'Loop')
        seen[base] += 1
        label = seen[base] > 1 ? "#{base} #{seen[base]}" : base
        tabs << { label: label, body: loop_diagram_svg(loop) }
      end
      tabs << { label: 'Zone equipment', body: zone_equipment_svg(topology[:zone_equipment]) } unless topology[:zone_equipment].empty?

      if tabs.empty?
        return %(<p class="note">No central loops or zone equipment were assembled for this system.</p>)
      end

      sys = card[:id]
      bar = tabs.each_with_index.map do |t, i|
        %(<button type="button" class="tab#{i.zero? ? ' active' : ''}" data-tab="#{sys}-t#{i}">#{esc(t[:label])}</button>)
      end.join
      panels = tabs.each_with_index.map do |t, i|
        %(<div class="tab-panel#{i.zero? ? ' active' : ''}" id="#{sys}-t#{i}"><div class="diagram">#{t[:body]}</div></div>)
      end.join
      %(<div class="tabs"><div class="tab-bar">#{bar}</div>#{panels}</div>)
    end

    def footer
      %(<footer><p>Generated by OpenStudioHVAC::CatalogReport — self-contained, no external requests. ) +
        %(OpenStudio #{begin; OpenStudio.openStudioVersion; rescue StandardError; '?'; end}.</p>) +
        %(<p>Component icons &copy; the OpenStudio Coalition, from the OpenStudio Application ) +
        %((BSD-3-Clause). See THIRD_PARTY_NOTICES.md.</p></footer>)
    end

    # Plain inline JS — no libraries. Handles search filtering, master-detail
    # selection, and per-system tab switching via one delegated click handler.
    def script(total)
      <<~JS
        (function(){
          var TOTAL = #{total};
          function selectSystem(id){
            var d = document.querySelectorAll('.system-detail');
            for (var i = 0; i < d.length; i++){ d[i].classList.remove('active'); }
            var el = document.getElementById(id);
            if (el){ el.classList.add('active'); }
            var n = document.querySelectorAll('.nav-item');
            for (var j = 0; j < n.length; j++){
              n[j].classList.toggle('active', n[j].getAttribute('data-target') === id);
            }
            window.scrollTo(0, 0);
          }
          document.addEventListener('click', function(e){
            var tab = e.target.closest ? e.target.closest('.tab') : null;
            if (tab){
              var bar = tab.parentNode, box = bar.parentNode;
              var tabs = bar.querySelectorAll('.tab');
              for (var i = 0; i < tabs.length; i++){ tabs[i].classList.remove('active'); }
              tab.classList.add('active');
              var panels = box.querySelectorAll('.tab-panel');
              for (var k = 0; k < panels.length; k++){ panels[k].classList.remove('active'); }
              var target = document.getElementById(tab.getAttribute('data-tab'));
              if (target){ target.classList.add('active'); }
              return;
            }
            var famTitle = e.target.closest ? e.target.closest('.nav-family-title') : null;
            if (famTitle){ famTitle.parentNode.classList.toggle('collapsed'); return; }
            var nav = e.target.closest ? e.target.closest('.nav-item') : null;
            if (nav){ selectSystem(nav.getAttribute('data-target')); }
          });
          var search = document.getElementById('system-search');
          if (search){
            search.addEventListener('input', function(){
              var q = this.value.trim().toLowerCase(), visible = 0;
              var fams = document.querySelectorAll('.nav-family');
              for (var f = 0; f < fams.length; f++){
                var any = false, items = fams[f].querySelectorAll('.nav-item');
                for (var i = 0; i < items.length; i++){
                  var match = items[i].getAttribute('data-search').indexOf(q) >= 0;
                  // Clearing the inline style (match/empty-query) lets the
                  // .collapsed CSS rule hide items again when search is empty.
                  items[i].style.display = match ? '' : 'none';
                  if (match){ any = true; visible++; }
                }
                fams[f].style.display = any ? '' : 'none';
                // While searching, auto-expand families with a match and collapse
                // those without; when the box is cleared, re-collapse everything.
                if (q){ fams[f].classList.toggle('collapsed', !any); }
                else { fams[f].classList.add('collapsed'); }
              }
              var c = document.getElementById('search-count');
              if (c){ c.textContent = visible + ' of ' + TOTAL; }
            });
          }
        })();
      JS
    end

    CSS = <<~CSS
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
             color: #111; background: #f4f6f8; line-height: 1.45; font-size: 14px; }
      .topbar { background: #fff; border-bottom: 1px solid #d0d7de; padding: 1rem 1.5rem; }
      h1 { font-size: 1.45rem; margin-bottom: .2rem; }
      p.meta { color: #444; font-size: .85rem; max-width: 60rem; margin-bottom: .5rem; }
      .legend { font-size: .78rem; margin: .25rem 0; display: flex; flex-wrap: wrap; gap: .7rem; align-items: center; }
      .legend strong { margin-right: .2rem; }
      .lk-note { color: #667; font-style: italic; }
      .lk, .gk { display: inline-flex; align-items: center; gap: .3rem; white-space: nowrap; }
      .sw { display: inline-block; width: .9rem; height: .9rem; border-radius: .2rem; }
      .gk-svg { width: 20px; height: 20px; }

      .app { display: flex; align-items: flex-start; gap: 1rem; padding: 1rem 1.5rem; }
      .sidebar { flex: 0 0 300px; width: 300px; position: sticky; top: 1rem;
                 max-height: calc(100vh - 2rem); overflow-y: auto; background: #fff;
                 border: 1px solid #d0d7de; border-radius: .5rem; padding: .6rem; }
      .search-wrap { position: sticky; top: 0; background: #fff; padding-bottom: .5rem;
                     display: flex; flex-direction: column; gap: .25rem; }
      #system-search { width: 100%; padding: .45rem .6rem; font-size: .9rem; border: 1px solid #b8c0c8;
                       border-radius: .4rem; }
      #search-count { font-size: .72rem; color: #667; padding-left: .1rem; }
      .nav-family { margin-top: .5rem; }
      .nav-family-title { display: flex; align-items: center; gap: .3rem; width: 100%; border: none;
                          background: none; font: inherit; font-size: .68rem; text-transform: uppercase;
                          letter-spacing: .04em; color: #667; font-weight: 700; cursor: pointer;
                          text-align: left; padding: .3rem .3rem .15rem; }
      .nav-family-title:hover { color: #1a5276; }
      .caret { display: inline-block; font-size: .8em; transition: transform .12s ease; }
      .nav-family:not(.collapsed) .caret { transform: rotate(90deg); }
      .nav-family.collapsed .nav-item { display: none; }
      .nav-item { display: block; width: 100%; text-align: left; border: none; background: none;
                  font: inherit; font-size: .8rem; color: #24313c; padding: .3rem .5rem; border-radius: .35rem;
                  cursor: pointer; word-break: break-word; }
      .nav-item:hover { background: #eef2f5; }
      .nav-item.active { background: #1a5276; color: #fff; font-weight: 600; }

      .detail-pane { flex: 1; min-width: 0; background: #fff; border: 1px solid #d0d7de;
                     border-radius: .5rem; padding: 1rem 1.2rem; }
      .system-detail { display: none; }
      .system-detail.active { display: block; }
      .detail-head { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
      .detail-head code { font-size: 1rem; font-weight: 700; background: #eef2f5; padding: .2rem .5rem;
                          border-radius: .3rem; word-break: break-word; }
      .badge { display: inline-block; padding: .1rem .5rem; border-radius: .3rem; font-weight: 700;
               font-size: .72rem; color: #fff; }
      .badge-family { background: #34495e; } .badge-sys { background: #1a5276; }
      .canonical { font-size: 1rem; font-weight: 600; color: #1a5276; margin: .5rem 0 .15rem; }
      .desc { font-size: .85rem; color: #444; margin-bottom: .8rem; }

      .tabs { margin-top: .4rem; }
      .tab-bar { display: flex; flex-wrap: wrap; gap: .2rem; border-bottom: 2px solid #d0d7de; margin-bottom: .6rem; }
      .tab { border: none; background: none; font: inherit; font-size: .82rem; font-weight: 600; color: #555;
             padding: .4rem .8rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -2px; }
      .tab:hover { color: #1a5276; }
      .tab.active { color: #1a5276; border-bottom-color: #1a5276; }
      .tab-panel { display: none; }
      .tab-panel.active { display: block; }
      .diagram { overflow-x: auto; }
      /* Render SVGs at their intrinsic size (fixed box/gap constants) so a
         component box is the same physical size in every system; wide loops
         scroll horizontally in .diagram instead of shrinking to fit. */
      .diagram svg { width: auto; height: auto; max-width: none; display: block; }

      .chips { display: flex; flex-wrap: wrap; gap: .4rem; }
      .chip-eq { display: inline-block; background: #e8f0f3; border: 1px solid #aebfc9; border-radius: 1rem;
                 padding: .15rem .7rem; font-size: .8rem; font-weight: 600; color: #21618c; }
      .note { font-size: .82rem; color: #555; font-style: italic; margin: .3rem 0; }
      .note-err { color: #9a6700; font-style: normal; font-weight: 600; }
      footer { margin: 1.5rem; font-size: .75rem; color: #555; }

      @media (max-width: 760px) {
        .app { flex-direction: column; }
        .sidebar { position: static; width: 100%; flex-basis: auto; max-height: 40vh; }
      }
      @media print {
        .sidebar, .topbar .legend { display: none; }
        .system-detail { display: block; break-inside: avoid; }
        .tab-panel { display: block; }
        * { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
      }
    CSS
  end
end
