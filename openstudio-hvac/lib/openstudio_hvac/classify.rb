module OpenStudioHVAC
  # Characterize ANY model's HVAC into a neutral facts hash — the inverse of the builder.
  #
  # Works on arbitrary OSMs (structural loop-composition walk); gem-built systems are
  # recognized exactly via their air-loop names (default namer stamps the catalog name,
  # legacy NECB models are recognized by their sys_N pipe names).
  #
  # The facts schema is a serializable contract consumed by NECB reference selection
  # (Table 8.4.4.7.-A needs heated/cooled, energy types, heat pumps, purchased energy,
  # cooling capacity) and by costing of foreign models.
  #
  #   {
  #     built_by_gem: true|false,
  #     zone_groups: [
  #       { zones: ['Zone 1', ...], air_loop: 'name'|nil,
  #         family: 'psz'|nil, catalog_name: 'PSZ RTU ...'|nil, family_guess: :multizone_vav|...,
  #         heated: true, cooled: false,
  #         heating_energy_types: ['NaturalGas'], cooling_energy_types: ['Electricity'],
  #         heat_pump: false, heat_pump_sources: [:air|:water_loop|:external],
  #         terminal_type: :vav_reheat|:cv_reheat|:cv|:none,
  #         design_cooling_kw: 42.0|nil,
  #         dcv: false, system_outdoor_air_method: 'ZoneSum'|nil } ],
  #     plants: [ { name:, type: :hot_water|:chilled_water|:condenser|:service_water|:other,
  #                 fuels: ['NaturalGas'], purchased: false, heat_pump: false } ],
  #     purchased_energy: { heating: false, cooling: false }
  #   }
  module Classify
    # Legacy NECB pipe-name prefix -> gem family (sys_2/5 are fan-coil systems, sys_1/4 MAU-based).
    PIPE_NAME_FAMILIES = {
      'sys_1' => 'mau_ptac', 'sys_2' => 'fan_coils', 'sys_3' => 'psz',
      'sys_4' => 'psz', 'sys_5' => 'fan_coils', 'sys_6' => 'vav_reheat'
    }.freeze

    # Characterize a model's HVAC into the neutral facts hash (schema above).
    # @param model [OpenStudio::Model::Model] any model (gem-built or foreign)
    # @param audit [AuditLog, nil]
    # @return [Hash] facts — { built_by_gem:, zone_groups: [...], plants: [...],
    #   purchased_energy: { heating:, cooling: } } (see the module docstring)
    def self.characterize(model, audit: nil)
      plants = model.getPlantLoops.sort_by(&:nameString).map { |loop| plant_facts(loop, audit) }
      plant_by_name = plants.to_h { |p| [p[:name], p] }
      annotate_heat_pump_plants(model, plant_by_name)

      groups = []
      served = {}
      model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        group = air_loop_group(air_loop, plant_by_name, audit)
        air_loop.thermalZones.each { |z| served[z.nameString] = group }
        groups << group
      end

      # zones without an air loop: zonal-equipment-only (or unconditioned) singleton groups
      model.getThermalZones.sort_by(&:nameString).each do |zone|
        if (group = served[zone.nameString])
          merge_zonal_equipment(group, zone, plant_by_name, audit)
        else
          groups << zonal_group(zone, plant_by_name, audit)
        end
      end

      groups.each do |group|
        if !group[:cooled]
          group[:design_cooling_kw] = 0.0
        elsif !group.delete(:cooling_capacity_complete)
          group[:design_cooling_kw] = nil
          audit&.warn(:characterize, 'cooling capacity unsized — design_cooling_kw unavailable (run a sizing run for kW-threshold rules)',
                      target: group[:air_loop] || group[:zones].first)
        end
        group.delete(:cooling_capacity_complete)
      end

      # HP SOURCE loops are excluded from purchased-energy detection: a district
      # object standing in for a ground field / condenser water (the legacy
      # GLHX pattern) is not purchased heating for the building (D-58).
      hvac_plants = plants.reject { |p| p[:type] == :service_water || p[:hp_source_loop] }
      facts = {
        built_by_gem: groups.any? && groups.all? { |g| g[:air_loop].nil? || g[:catalog_name] },
        zone_groups: groups,
        plants: plants,
        purchased_energy: {
          heating: hvac_plants.any? { |p| p[:purchased] && p[:type] == :hot_water },
          cooling: hvac_plants.any? { |p| p[:purchased] && p[:type] == :chilled_water }
        }
      }
      audit&.info(:characterize, 'model characterized',
                  inputs: { zone_groups: groups.size, plants: plants.size,
                            built_by_gem: facts[:built_by_gem] })
      facts
    end

    # ---------------- plants ----------------

    def self.plant_facts(loop, audit)
      fuels = []
      purchased = false
      heat_pump = false
      has_boiler = has_chiller = has_rejection = false

      loop.supplyComponents.each do |comp|
        if comp.to_BoilerHotWater.is_initialized
          has_boiler = true
          fuels << comp.to_BoilerHotWater.get.fuelType
        elsif comp.to_ChillerElectricEIR.is_initialized
          has_chiller = true
          fuels << 'Electricity'
        elsif comp.to_DistrictHeating.is_initialized || defined_district_heating_water?(comp)
          purchased = true
          fuels << 'Purchased'
        elsif comp.to_DistrictCooling.is_initialized
          purchased = true
          fuels << 'Purchased'
        elsif comp.to_HeatPumpPlantLoopEIRHeating.is_initialized ||
              comp.to_HeatPumpWaterToWaterEquationFitHeating.is_initialized
          heat_pump = true
          fuels << 'Electricity'
        elsif comp.to_HeatPumpPlantLoopEIRCooling.is_initialized
          heat_pump = true
          fuels << 'Electricity'
        elsif comp.to_CoolingTowerSingleSpeed.is_initialized ||
              comp.to_EvaporativeFluidCoolerSingleSpeed.is_initialized ||
              comp.to_GroundHeatExchangerVertical.is_initialized
          has_rejection = true
        elsif comp.to_WaterHeaterMixed.is_initialized
          fuels << comp.to_WaterHeaterMixed.get.heaterFuelType
        end
      end

      swh = loop.demandComponents.any? { |c| c.to_WaterUseConnections.is_initialized }
      type = if swh then :service_water
             elsif has_boiler || (purchased && heating_loop?(loop)) || (heat_pump && heating_loop?(loop)) then :hot_water
             elsif has_chiller || (purchased && !heating_loop?(loop)) then :chilled_water
             elsif has_rejection then :condenser
             elsif heat_pump then :hot_water
             else :other
             end

      facts = { name: loop.nameString, type: type, fuels: fuels.uniq,
                purchased: purchased, heat_pump: heat_pump }
      audit&.info(:characterize, 'plant loop classified', target: loop.nameString,
                  value: type, inputs: { fuels: facts[:fuels], purchased: purchased })
      facts
    end

    # DistrictHeatingWater replaced DistrictHeating at OS 3.7; handle both SDKs.
    def self.defined_district_heating_water?(comp)
      comp.respond_to?(:to_DistrictHeatingWater) && comp.to_DistrictHeatingWater.is_initialized
    end

    def self.heating_loop?(loop)
      exit_c = loop.sizingPlant.designLoopExitTemperature
      exit_c > 30.0 # hot loops design well above chilled/condenser temperatures
    end

    # ---------------- air-loop groups ----------------

    def self.air_loop_group(air_loop, plant_by_name, audit)
      group = base_group(air_loop.thermalZones.map(&:nameString), air_loop.nameString)
      recognize_gem_name(group, air_loop, audit)
      outdoor_air_facts(group, air_loop, audit)

      # Coils.supply_components descends into AirLoopHVACUnitarySystem containers
      # (staged NECB reference systems) — otherwise a staged sys 3/4 reads as an
      # air loop with no coils at all.
      Coils.supply_components(air_loop).each do |comp|
        scan_heating_component(group, comp, plant_by_name, "#{comp.iddObjectType.valueName} on #{air_loop.nameString}")
        scan_cooling_component(group, comp, plant_by_name, "#{comp.iddObjectType.valueName} on #{air_loop.nameString}")
      end

      air_loop.thermalZones.sort_by(&:nameString).each do |zone|
        zone.equipment.each do |eq|
          terminal_facts(group, eq, plant_by_name)
        end
      end

      group[:family_guess] ||= structural_family_guess(group)
      audit&.decision(:characterize, 'zone group characterized', target: air_loop.nameString,
                      inputs: { zones: group[:zones].size, terminal: group[:terminal_type] },
                      value: group[:family] || group[:family_guess],
                      evidence: group[:evidence].join('; '))
      group
    end

    def self.recognize_gem_name(group, air_loop, audit)
      name = air_loop.nameString
      candidate = name.split(' | ').first
      begin
        row = Catalog.resolve(candidate)
        group[:catalog_name] = row['name']
        group[:family] = row['family']
        group[:evidence] << "air loop name resolves to catalog entry '#{row['name']}'"
        return
      rescue ArgumentError
        # not a gem catalog name
      end
      if (m = name.match(/\A(sys_\d)\|/))
        group[:family_guess] = PIPE_NAME_FAMILIES[m[1]]
        group[:evidence] << "legacy NECB pipe name (#{m[1]})"
        audit&.info(:characterize, 'legacy NECB pipe-named loop recognized',
                    target: name, value: group[:family_guess])
      end
    end

    def self.base_group(zone_names, air_loop_name)
      { zones: zone_names, air_loop: air_loop_name,
        family: nil, catalog_name: nil, family_guess: nil,
        heated: false, cooled: false,
        heating_energy_types: [], cooling_energy_types: [],
        heat_pump: false, heat_pump_sources: [], heat_pump_source_loops: [], terminal_type: :none,
        zonal_units: [], loop_dx_cooling: false,
        design_cooling_kw: 0.0, cooling_capacity_complete: true,
        dcv: false, system_outdoor_air_method: nil,
        evidence: [] }
    end

    # 8.4.4.15.(2) (2025: 8.4.5.15.(2)): the demand-control-ventilation strategy of
    # the PROPOSED air loop has to be reproduced in the reference building, so the
    # facts hash has to carry it across the teardown that replaces the loop.
    # EnergyPlus expresses the strategy on Controller:MechanicalVentilation as the
    # DCV flag plus the system outdoor-air method (ZoneSum = occupancy-based,
    # IndoorAirQualityProcedure = CO2-based) — both are recorded.
    def self.outdoor_air_facts(group, air_loop, audit)
      oa_system = air_loop.airLoopHVACOutdoorAirSystem
      return if oa_system.empty?

      mech = oa_system.get.getControllerOutdoorAir.controllerMechanicalVentilation
      group[:dcv] = mech.demandControlledVentilation
      group[:system_outdoor_air_method] = mech.systemOutdoorAirMethod
      return unless group[:dcv]

      group[:evidence] << "demand-controlled ventilation enabled (#{group[:system_outdoor_air_method]})"
      audit&.info(:characterize, 'proposed air loop carries demand-controlled ventilation',
                  target: air_loop.nameString, value: group[:system_outdoor_air_method],
                  inputs: { demand_controlled_ventilation: true })
    end

    HEATING_COILS = [
      [:to_CoilHeatingGas, ->(_c, _p) { 'NaturalGas' }, false],
      [:to_CoilHeatingGasMultiStage, ->(_c, _p) { 'NaturalGas' }, false],
      [:to_CoilHeatingDXMultiSpeed, ->(_c, _p) { 'Electricity' }, :air],
      [:to_CoilHeatingElectric, ->(_c, _p) { 'Electricity' }, nil],
      [:to_CoilHeatingWater, ->(c, p) { hydronic_fuels(c, p) }, nil],
      [:to_CoilHeatingDXSingleSpeed, ->(_c, _p) { 'Electricity' }, :air],
      [:to_CoilHeatingDXVariableSpeed, ->(_c, _p) { 'Electricity' }, :air],
      [:to_CoilHeatingWaterBaseboard, ->(c, p) { hydronic_fuels(c, p) }, nil],
      [:to_CoilHeatingWaterToAirHeatPumpEquationFit, ->(_c, _p) { 'Electricity' }, :water_to_air],
      [:to_CoilHeatingDXVariableRefrigerantFlow, ->(_c, _p) { 'Electricity' }, :air]
    ].freeze

    def self.scan_heating_component(group, comp, plant_by_name, evidence)
      HEATING_COILS.each do |cast, fuel_of, hp_kind|
        optional = comp.respond_to?(cast) ? comp.send(cast) : nil
        next unless optional&.is_initialized

        coil = optional.get
        group[:heated] = true
        group[:heating_energy_types] |= Array(fuel_of.call(coil, plant_by_name))
        record_heat_pump(group, hp_kind, coil)
        record_plant_heat_pump(group, coil, plant_by_name) if hp_kind.nil? # hydronic coils: plant may BE a heat pump
        group[:evidence] << "heated: #{evidence}"
        return true
      end
      false
    end

    # 8.4.4.13.(2) reaches a heat pump that "supplies ... conditioned water to a
    # hydronic loop" — a PLANT heat pump serving coils/baseboards/fan coils, not
    # just a coil-level unit. When the plant a hydronic coil draws from carries
    # a heat pump, the group is a heat-pump group and the plant's annotated
    # source kind (:air / :external / :water_loop) governs the D-37 redirect
    # split (D-58).
    def self.record_plant_heat_pump(group, coil, plant_by_name)
      return if coil.nil?

      loop = coil.respond_to?(:plantLoop) ? coil.plantLoop : nil
      return if loop.nil? || loop.empty?

      plant = plant_by_name[loop.get.nameString]
      return unless plant && plant[:heat_pump]

      group[:heat_pump] = true
      group[:heat_pump_sources] |= [plant[:hp_source] || :water_loop]
      group[:heat_pump_source_loops] |= [plant[:hp_source_loop_name]].compact
      group[:evidence] << "plant heat pump on '#{plant[:name]}' (source #{plant[:hp_source] || :water_loop})"
    end

    # The water heating coil a zonal unit draws from its plant, if any.
    def self.zonal_water_heating_coil(unit)
      coil = unit.respond_to?(:heatingCoil) ? unit.heatingCoil : nil
      coil = coil.get if coil.respond_to?(:is_initialized) && coil.is_initialized
      return nil if coil.nil? || !coil.respond_to?(:to_CoilHeatingWater)

      return coil.to_CoilHeatingWater.get if coil.to_CoilHeatingWater.is_initialized
      return coil.to_CoilHeatingWaterBaseboard.get if coil.respond_to?(:to_CoilHeatingWaterBaseboard) &&
                                                      coil.to_CoilHeatingWaterBaseboard.is_initialized

      nil
    end

    # D-37 (Note A-8.4.4.13): heat-pump SOURCE matters for the 8.4.4.13
    # reference redirect — water-LOOP (internal loop, aux boiler/tower
    # allowed) stays on Table -A; air/water/ground-SOURCE redirects.
    def self.record_heat_pump(group, hp_kind, unit)
      return unless hp_kind

      group[:heat_pump] = true
      group[:heat_pump_sources] |= [hp_kind == :water_to_air ? water_to_air_hp_source(unit) : :air]
      # 8.4.4.13.(2)(g)(ii) needs "all the heat pumps connected to the same
      # water loop" — record the source-loop NAME so the aux-fuel election can
      # aggregate across zone groups sharing it (D-52).
      return unless hp_kind == :water_to_air && unit.respond_to?(:plantLoop)

      loop = unit.plantLoop
      group[:heat_pump_source_loops] |= [loop.get.nameString] if loop.is_initialized
    end

    GROUND_HX_CASTS = %i[to_GroundHeatExchangerVertical to_GroundHeatExchangerHorizontalTrench].freeze

    # Note A-8.4.4.13's boundary evidence: ground HX / district / temperature-
    # source components mean the loop is fed by EXTERNAL water or ground
    # (water-/ground-source); otherwise it is an internal water loop (aux
    # boiler and/or heat-rejection device explicitly allowed).
    def self.external_source_loop?(loop)
      loop.supplyComponents.any? do |c|
        GROUND_HX_CASTS.any? { |cast| c.respond_to?(cast) && c.send(cast).is_initialized } ||
          c.to_DistrictHeating.is_initialized || c.to_DistrictCooling.is_initialized ||
          defined_district_heating_water?(c) ||
          (c.respond_to?(:to_PlantComponentTemperatureSource) && c.to_PlantComponentTemperatureSource.is_initialized)
      end
    end

    # Classify a water-to-air heat pump by its SOURCE loop per Note
    # A-8.4.4.13 (see external_source_loop?).
    def self.water_to_air_hp_source(coil)
      loop = coil.respond_to?(:plantLoop) ? coil.plantLoop : nil
      return :water_loop if loop.nil? || loop.empty?

      external_source_loop?(loop.get) ? :external : :water_loop
    end

    PLANT_HP_CASTS = %i[to_HeatPumpPlantLoopEIRHeating to_HeatPumpWaterToWaterEquationFitHeating
                        to_HeatPumpPlantLoopEIRCooling to_HeatPumpWaterToWaterEquationFitCooling].freeze

    # Classify each heat-pump PLANT's source per Note A-8.4.4.13 (D-58): the HP
    # object's source-side loop carries the evidence — external components =>
    # :external (water/ground source); a plain internal loop => :water_loop;
    # no source loop at all (air-source condenser) => :air. The source loop is
    # flagged (`hp_source_loop`) so purchased-energy detection skips it: a
    # district object standing in for a ground field (the legacy GLHX pattern)
    # is not purchased heating for the building.
    def self.annotate_heat_pump_plants(model, plant_by_name)
      model.getPlantLoops.each do |loop|
        plant = plant_by_name[loop.nameString]
        next unless plant && plant[:heat_pump]

        source = nil
        loop.supplyComponents.each do |comp|
          PLANT_HP_CASTS.each do |cast|
            optional = comp.respond_to?(cast) ? comp.send(cast) : nil
            next unless optional&.is_initialized

            hp = optional.get
            secondary = hp.respond_to?(:secondaryPlantLoop) ? hp.secondaryPlantLoop : nil
            if secondary.nil? || secondary.empty?
              source ||= :air
            else
              src_loop = secondary.get
              src_plant = plant_by_name[src_loop.nameString]
              src_plant[:hp_source_loop] = true if src_plant
              plant[:hp_source_loop_name] = src_loop.nameString
              source = external_source_loop?(src_loop) ? :external : (source || :water_loop)
            end
          end
        end
        plant[:hp_source] = source || :water_loop
      end
    end

    def self.scan_cooling_component(group, comp, plant_by_name, evidence)
      kw = nil
      fuels = nil
      hp = nil
      hp_unit = nil
      if comp.to_CoilCoolingDXSingleSpeed.is_initialized
        c = comp.to_CoilCoolingDXSingleSpeed.get
        fuels = 'Electricity'
        kw = optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
      elsif comp.to_CoilCoolingDXMultiSpeed.is_initialized
        # a staged coil's TOTAL capacity is its TOP stage (E+ stages are cumulative)
        top = comp.to_CoilCoolingDXMultiSpeed.get.stages.last
        fuels = 'Electricity'
        kw = top && optional_kw(top.grossRatedTotalCoolingCapacity, top.autosizedGrossRatedTotalCoolingCapacity)
      elsif comp.to_CoilCoolingDXTwoSpeed.is_initialized
        c = comp.to_CoilCoolingDXTwoSpeed.get
        fuels = 'Electricity'
        kw = optional_kw(c.ratedHighSpeedTotalCoolingCapacity, c.autosizedRatedHighSpeedTotalCoolingCapacity)
      elsif comp.to_CoilCoolingDXVariableSpeed.is_initialized
        c = comp.to_CoilCoolingDXVariableSpeed.get
        fuels = 'Electricity'
        kw = optional_kw(c.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel,
                         c.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel)
      elsif comp.to_CoilCoolingWater.is_initialized
        c = comp.to_CoilCoolingWater.get
        fuels = hydronic_fuels(c, plant_by_name)
        kw = optional_kw(nil, c.autosizedDesignCoilLoad)
      elsif comp.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
        c = comp.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
        fuels = 'Electricity'
        hp = :water_to_air
        hp_unit = c
        kw = optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
      elsif comp.to_CoilCoolingDXVariableRefrigerantFlow.is_initialized
        c = comp.to_CoilCoolingDXVariableRefrigerantFlow.get
        fuels = 'Electricity'
        hp = :air
        kw = optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
      elsif comp.to_EvaporativeCoolerDirectResearchSpecial.is_initialized
        fuels = 'Electricity'
        kw = 0.0
      else
        return false
      end

      group[:cooled] = true
      group[:cooling_energy_types] |= Array(fuels)
      record_heat_pump(group, hp, hp_unit)
      # The Table 8.4.4.7.-A residential parenthetical needs to know whether the
      # LOOP's own DX cools the zones (an air-cooled unitary/packaged shape) —
      # a fact, where the family string is only a name (D-58).
      group[:loop_dx_cooling] = true if comp.iddObjectType.valueName =~ /Coil_Cooling_DX/
      group[:evidence] << "cooled: #{evidence}"
      if kw.nil?
        group[:cooling_capacity_complete] = false
      else
        group[:design_cooling_kw] += kw
      end
      true
    end

    def self.hydronic_fuels(coil, plant_by_name)
      loop = coil.plantLoop
      return 'Unknown' unless loop.is_initialized

      plant = plant_by_name[loop.get.nameString]
      return 'Unknown' if plant.nil? || plant[:fuels].empty?

      plant[:fuels]
    end

    def self.optional_kw(hard, autosized)
      [hard, autosized].each do |value|
        next if value.nil?
        return value.to_f / 1000.0 unless value.respond_to?(:is_initialized)
        return value.get.to_f / 1000.0 if value.is_initialized
      end
      nil
    end

    # ---------------- 8.4.4.13.(2)(g) heating-election inventory (D-52) ----------------

    BASEBOARD_VARIABLE = 'Baseboard Total Heating Energy'
    COIL_VARIABLE = 'Heating Coil Heating Energy'

    DX_HEATING_CASTS = %i[to_CoilHeatingDXSingleSpeed to_CoilHeatingDXMultiSpeed
                          to_CoilHeatingDXVariableSpeed to_CoilHeatingWaterToAirHeatPumpEquationFit
                          to_CoilHeatingDXVariableRefrigerantFlow].freeze
    AUX_COIL_FUELS = {
      to_CoilHeatingGas: 'NaturalGas',
      to_CoilHeatingGasMultiStage: 'NaturalGas',
      to_CoilHeatingElectric: 'Electricity',
      to_CoilHeatingWater: :hydronic
    }.freeze

    # The SDK-side half of the 8.4.4.13.(2)(g) auxiliary-fuel election: which
    # equipment on the PROPOSED delivers space heating, under which EnergyPlus
    # output variable, and on which energy type. The umbrella joins these names
    # with the proposed annual run's SQL sums (this gem never simulates) and
    # hands the joined data back to reference_hvac as `proposed_annual:`.
    #
    # @param model [OpenStudio::Model::Model] the PROPOSED model
    # @return [Hash]
    #   :loops — { air loop name => { hp: [coil names], aux: [{name:, fuel:}] } }
    #   :zones — { zone name => [{name:, fuel:, variable:, role: :aux | :hp}] }
    #   All heating quantities the election compares are DELIVERED heat
    #   (Heating Coil Heating Energy / Baseboard Total Heating Energy), one
    #   consistent basis across fuels.
    def self.heating_election_inventory(model)
      plants = model.getPlantLoops.sort_by(&:nameString).map { |loop| plant_facts(loop, nil) }
      plant_by_name = plants.to_h { |p| [p[:name], p] }

      loops = {}
      model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        entry = { hp: [], aux: [] }
        Coils.supply_components(air_loop).each do |comp|
          if DX_HEATING_CASTS.any? { |cast| comp.respond_to?(cast) && comp.send(cast).is_initialized }
            entry[:hp] << comp.nameString
          elsif (aux = aux_coil_entry(comp, plant_by_name))
            entry[:aux] << aux
          end
        end
        loops[air_loop.nameString] = entry if entry[:hp].any? || entry[:aux].any?
      end

      zones = {}
      model.getThermalZones.sort_by(&:nameString).each do |zone|
        list = zone.equipment.flat_map { |eq| zonal_heating_entries(eq, plant_by_name) }
        zones[zone.nameString] = list if list.any?
      end
      { loops: loops, zones: zones }
    end

    def self.aux_coil_entry(comp, plant_by_name)
      AUX_COIL_FUELS.each do |cast, fuel|
        optional = comp.respond_to?(cast) ? comp.send(cast) : nil
        next unless optional&.is_initialized

        coil = optional.get
        resolved = fuel == :hydronic ? Array(hydronic_fuels(coil, plant_by_name)).join('+') : fuel
        return { name: coil.nameString, fuel: resolved }
      end
      nil
    end

    def self.zonal_heating_entries(eq, plant_by_name)
      if eq.to_ZoneHVACBaseboardConvectiveElectric.is_initialized ||
         (eq.respond_to?(:to_ZoneHVACBaseboardRadiantConvectiveElectric) &&
          eq.to_ZoneHVACBaseboardRadiantConvectiveElectric.is_initialized)
        return [{ name: eq.nameString, fuel: 'Electricity', variable: BASEBOARD_VARIABLE, role: :aux }]
      end

      water_baseboard = %i[to_ZoneHVACBaseboardConvectiveWater to_ZoneHVACBaseboardRadiantConvectiveWater]
                        .filter_map { |cast| eq.respond_to?(cast) ? eq.send(cast) : nil }
                        .find(&:is_initialized)
      if water_baseboard
        coil = water_baseboard.get.heatingCoil
        fuel = Array(hydronic_fuels(coil, plant_by_name)).join('+')
        return [{ name: eq.nameString, fuel: fuel, variable: BASEBOARD_VARIABLE, role: :aux }]
      end

      coils = zonal_heating_coils(eq)
      coils.filter_map do |coil, role|
        if role == :hp
          { name: coil.nameString, fuel: 'Electricity', variable: COIL_VARIABLE, role: :hp }
        elsif (aux = aux_coil_entry(coil, plant_by_name))
          aux.merge(variable: COIL_VARIABLE, role: :aux)
        end
      end
    end

    # [coil, :hp | :aux] pairs for a zonal unit or terminal. The unit's DX
    # heating coil is the heat pump itself; its supplemental coil and every
    # non-DX heating coil are terminal/auxiliary heating.
    def self.zonal_heating_coils(eq)
      pairs = []
      { to_ZoneHVACPackagedTerminalAirConditioner: [:heatingCoil],
        to_ZoneHVACPackagedTerminalHeatPump: %i[heatingCoil supplementalHeatingCoil],
        to_ZoneHVACWaterToAirHeatPump: %i[heatingCoil supplementalHeatingCoil],
        to_ZoneHVACFourPipeFanCoil: [:heatingCoil],
        to_ZoneHVACUnitHeater: [:heatingCoil],
        to_AirTerminalSingleDuctVAVReheat: [:reheatCoil],
        to_AirTerminalSingleDuctConstantVolumeReheat: [:reheatCoil] }.each do |cast, accessors|
        optional = eq.respond_to?(cast) ? eq.send(cast) : nil
        next unless optional&.is_initialized

        unit = optional.get
        accessors.each do |accessor|
          next unless unit.respond_to?(accessor)

          coil = unit.send(accessor)
          coil = coil.get if coil.respond_to?(:is_initialized) && coil.is_initialized
          next unless coil.respond_to?(:nameString)

          hp = DX_HEATING_CASTS.any? { |c| coil.respond_to?(c) && coil.send(c).is_initialized }
          pairs << [coil, hp ? :hp : :aux]
        end
        break
      end
      pairs
    end

    TERMINALS = {
      to_AirTerminalSingleDuctVAVReheat: :vav_reheat,
      to_AirTerminalSingleDuctVAVNoReheat: :vav,
      to_AirTerminalSingleDuctConstantVolumeReheat: :cv_reheat,
      to_AirTerminalSingleDuctConstantVolumeNoReheat: :cv
    }.freeze

    def self.terminal_facts(group, eq, plant_by_name)
      TERMINALS.each do |cast, kind|
        optional = eq.send(cast)
        next unless optional.is_initialized

        group[:terminal_type] = kind
        if %i[vav_reheat cv_reheat].include?(kind)
          coil = optional.get.reheatCoil
          scan_heating_component(group, coil, plant_by_name,
                                 "reheat coil on terminal #{eq.nameString}")
        end
        return true
      end
      false
    end

    # ---------------- zonal equipment ----------------

    ZONAL = [
      [:to_ZoneHVACBaseboardConvectiveWater, { heat: :hydronic, kind: :baseboard }],
      [:to_ZoneHVACBaseboardConvectiveElectric, { heat: 'Electricity', kind: :baseboard }],
      [:to_ZoneHVACPackagedTerminalAirConditioner, { cool: 'Electricity', heat: :coil, kind: :ptac }],
      [:to_ZoneHVACPackagedTerminalHeatPump, { heat: 'Electricity', cool: 'Electricity', hp: true, kind: :pthp }],
      [:to_ZoneHVACFourPipeFanCoil, { heat: :coil, cool: :coil, kind: :fan_coil }],
      [:to_ZoneHVACTerminalUnitVariableRefrigerantFlow, { heat: 'Electricity', cool: 'Electricity', hp: true, kind: :vrf_terminal }],
      [:to_ZoneHVACUnitHeater, { heat: :coil, kind: :unit_heater }],
      [:to_ZoneHVACWaterToAirHeatPump, { heat: 'Electricity', cool: 'Electricity', hp: true, kind: :wshp }],
      [:to_ZoneHVACHighTemperatureRadiant, { heat: 'Electricity', kind: :radiant }],
      [:to_ZoneHVACLowTemperatureRadiantElectric, { heat: 'Electricity', kind: :radiant }]
    ].freeze

    def self.merge_zonal_equipment(group, zone, plant_by_name, _audit)
      zone.equipment.each do |eq|
        next if terminal_like?(eq)

        ZONAL.each do |cast, roles|
          optional = eq.respond_to?(cast) ? eq.send(cast) : nil
          next unless optional&.is_initialized

          unit = optional.get
          evidence = "#{eq.iddObjectType.valueName} in #{zone.nameString}"
          group[:zonal_units] |= [roles[:kind]] if roles[:kind]
          if roles[:heat]
            group[:heated] = true
            group[:heating_energy_types] |= zonal_fuels(unit, roles[:heat], :heat, plant_by_name)
            group[:evidence] << "heated: #{evidence}"
            record_plant_heat_pump(group, zonal_water_heating_coil(unit), plant_by_name)
          end
          if roles[:cool]
            group[:cooled] = true
            group[:cooling_energy_types] |= zonal_fuels(unit, roles[:cool], :cool, plant_by_name)
            group[:evidence] << "cooled: #{evidence}"
            add_zonal_cooling_capacity(group, unit)
          end
          record_heat_pump(group, roles[:hp] && zonal_hp_kind(unit), zonal_hp_coil(unit))
          break
        end
      end
      group
    end

    def self.terminal_like?(eq)
      TERMINALS.keys.any? { |cast| eq.respond_to?(cast) && eq.send(cast).is_initialized }
    end

    # PTHP/VRF terminals are air-source; ZoneHVAC WSHP units are water-to-air
    # (their SOURCE loop decides :water_loop vs :external — see
    # water_to_air_hp_source).
    def self.zonal_hp_kind(unit)
      unit.to_ZoneHVACWaterToAirHeatPump.is_initialized ? :water_to_air : :air
    end

    WTA_COIL_CASTS = %i[to_CoilCoolingWaterToAirHeatPumpEquationFit
                        to_CoilHeatingWaterToAirHeatPumpEquationFit
                        to_CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit
                        to_CoilHeatingWaterToAirHeatPumpVariableSpeedEquationFit].freeze

    def self.zonal_hp_coil(unit)
      wshp = unit.to_ZoneHVACWaterToAirHeatPump
      return nil if wshp.empty?

      [wshp.get.coolingCoil, wshp.get.heatingCoil].each do |coil|
        WTA_COIL_CASTS.each do |cast|
          optional = coil.respond_to?(cast) ? coil.send(cast) : nil
          return optional.get if optional&.is_initialized
        end
      end
      nil
    end

    def self.zonal_fuels(unit, role, side, plant_by_name)
      case role
      when String then [role]
      when :hydronic
        coil = unit.heatingCoil
        coil.to_CoilHeatingWaterBaseboard.is_initialized ? Array(hydronic_fuels(coil.to_CoilHeatingWaterBaseboard.get, plant_by_name)) : ['Unknown']
      when :coil
        coil = side == :heat ? unit.heatingCoil : unit.coolingCoil
        coil = coil.get if coil.respond_to?(:is_initialized) && coil.is_initialized
        return ['Unknown'] if coil.nil?
        return ['NaturalGas'] if coil.to_CoilHeatingGas.is_initialized
        return ['Electricity'] if coil.to_CoilHeatingElectric.is_initialized || coil.to_CoilCoolingDXSingleSpeed.is_initialized
        return Array(hydronic_fuels(coil.to_CoilHeatingWater.get, plant_by_name)) if coil.to_CoilHeatingWater.is_initialized
        return Array(hydronic_fuels(coil.to_CoilCoolingWater.get, plant_by_name)) if coil.to_CoilCoolingWater.is_initialized

        ['Unknown']
      else
        ['Unknown']
      end
    end

    def self.add_zonal_cooling_capacity(group, unit)
      coil = unit.respond_to?(:coolingCoil) ? unit.coolingCoil : nil
      coil = coil.get if coil.respond_to?(:is_initialized) && coil.is_initialized
      return if coil.nil?

      kw =
        if coil.to_CoilCoolingDXSingleSpeed.is_initialized
          c = coil.to_CoilCoolingDXSingleSpeed.get
          optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
        elsif coil.to_CoilCoolingWater.is_initialized
          optional_kw(nil, coil.to_CoilCoolingWater.get.autosizedDesignCoilLoad)
        elsif coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
          c = coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
          optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
        elsif coil.to_CoilCoolingDXVariableRefrigerantFlow.is_initialized
          c = coil.to_CoilCoolingDXVariableRefrigerantFlow.get
          optional_kw(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity)
        end
      kw.nil? ? group[:cooling_capacity_complete] = false : group[:design_cooling_kw] += kw
    end

    def self.zonal_group(zone, plant_by_name, audit)
      group = base_group([zone.nameString], nil)
      merge_zonal_equipment(group, zone, plant_by_name, audit)
      group[:family_guess] = structural_family_guess(group)
      audit&.decision(:characterize, 'zonal-only group characterized', target: zone.nameString,
                      inputs: { heated: group[:heated], cooled: group[:cooled] },
                      value: group[:family_guess],
                      evidence: group[:evidence].join('; '))
      group
    end

    # Coarse structural guess for foreign systems (gem-built groups carry exact :family).
    def self.structural_family_guess(group)
      if group[:air_loop]
        case group[:terminal_type]
        when :vav_reheat, :vav then :multizone_vav
        when :cv_reheat then :multizone_cv
        else group[:zones].size > 1 ? :central_doas_or_cv : :packaged_single_zone
        end
      elsif group[:heated] && group[:cooled] then :zonal_heat_cool
      elsif group[:heated] then :zonal_heating_only
      elsif group[:cooled] then :zonal_cooling_only
      else :unconditioned
      end
    end

    # ---- internals (not API) ----
    private_class_method :plant_facts, :defined_district_heating_water?, :heating_loop?,
                         :air_loop_group, :recognize_gem_name, :base_group,
                         :outdoor_air_facts, :scan_heating_component,
                         :record_plant_heat_pump, :zonal_water_heating_coil,
                         :record_heat_pump, :external_source_loop?,
                         :water_to_air_hp_source, :annotate_heat_pump_plants,
                         :scan_cooling_component, :hydronic_fuels, :optional_kw,
                         :aux_coil_entry, :zonal_heating_entries, :zonal_heating_coils,
                         :terminal_facts, :merge_zonal_equipment, :terminal_like?,
                         :zonal_hp_kind, :zonal_hp_coil, :zonal_fuels,
                         :add_zonal_cooling_capacity, :zonal_group,
                         :structural_family_guess
  end
end
