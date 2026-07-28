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
  #         design_cooling_kw: 42.0|nil } ],
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

    def self.characterize(model, audit: nil)
      plants = model.getPlantLoops.sort_by(&:nameString).map { |loop| plant_facts(loop, audit) }
      plant_by_name = plants.to_h { |p| [p[:name], p] }

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

      hvac_plants = plants.reject { |p| p[:type] == :service_water }
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

      air_loop.supplyComponents.each do |comp|
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
        heat_pump: false, heat_pump_sources: [], terminal_type: :none,
        design_cooling_kw: 0.0, cooling_capacity_complete: true,
        evidence: [] }
    end

    HEATING_COILS = [
      [:to_CoilHeatingGas, ->(_c, _p) { 'NaturalGas' }, false],
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
        group[:evidence] << "heated: #{evidence}"
        return true
      end
      false
    end

    # D-37 (Note A-8.4.4.13): heat-pump SOURCE matters for the 8.4.4.13
    # reference redirect — water-LOOP (internal loop, aux boiler/tower
    # allowed) stays on Table -A; air/water/ground-SOURCE redirects.
    def self.record_heat_pump(group, hp_kind, unit)
      return unless hp_kind

      group[:heat_pump] = true
      group[:heat_pump_sources] |= [hp_kind == :water_to_air ? water_to_air_hp_source(unit) : :air]
    end

    GROUND_HX_CASTS = %i[to_GroundHeatExchangerVertical to_GroundHeatExchangerHorizontalTrench].freeze

    # Classify a water-to-air heat pump by its SOURCE loop per Note
    # A-8.4.4.13: ground HX / district / temperature-source components mean
    # the loop is fed by EXTERNAL water or ground (water-/ground-source ->
    # :external); otherwise it is an internal water loop (:water_loop —
    # an aux boiler and/or heat-rejection device is explicitly allowed).
    def self.water_to_air_hp_source(coil)
      loop = coil.respond_to?(:plantLoop) ? coil.plantLoop : nil
      return :water_loop if loop.nil? || loop.empty?

      external = loop.get.supplyComponents.any? do |c|
        GROUND_HX_CASTS.any? { |cast| c.respond_to?(cast) && c.send(cast).is_initialized } ||
          c.to_DistrictHeating.is_initialized || c.to_DistrictCooling.is_initialized ||
          defined_district_heating_water?(c) ||
          (c.respond_to?(:to_PlantComponentTemperatureSource) && c.to_PlantComponentTemperatureSource.is_initialized)
      end
      external ? :external : :water_loop
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
      [:to_ZoneHVACBaseboardConvectiveWater, { heat: :hydronic }],
      [:to_ZoneHVACBaseboardConvectiveElectric, { heat: 'Electricity' }],
      [:to_ZoneHVACPackagedTerminalAirConditioner, { cool: 'Electricity', heat: :coil }],
      [:to_ZoneHVACPackagedTerminalHeatPump, { heat: 'Electricity', cool: 'Electricity', hp: true }],
      [:to_ZoneHVACFourPipeFanCoil, { heat: :coil, cool: :coil }],
      [:to_ZoneHVACTerminalUnitVariableRefrigerantFlow, { heat: 'Electricity', cool: 'Electricity', hp: true }],
      [:to_ZoneHVACUnitHeater, { heat: :coil }],
      [:to_ZoneHVACWaterToAirHeatPump, { heat: 'Electricity', cool: 'Electricity', hp: true }],
      [:to_ZoneHVACHighTemperatureRadiant, { heat: 'Electricity' }],
      [:to_ZoneHVACLowTemperatureRadiantElectric, { heat: 'Electricity' }]
    ].freeze

    def self.merge_zonal_equipment(group, zone, plant_by_name, _audit)
      zone.equipment.each do |eq|
        next if terminal_like?(eq)

        ZONAL.each do |cast, roles|
          optional = eq.respond_to?(cast) ? eq.send(cast) : nil
          next unless optional&.is_initialized

          unit = optional.get
          evidence = "#{eq.iddObjectType.valueName} in #{zone.nameString}"
          if roles[:heat]
            group[:heated] = true
            group[:heating_energy_types] |= zonal_fuels(unit, roles[:heat], :heat, plant_by_name)
            group[:evidence] << "heated: #{evidence}"
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

  end
end
