class BTAPCosting

  # --------------------------------------------------------------------------------------------------
  # This function gets all costs associated with boilers (i.e., boilers, pumps, flues, electrical
  # lines and boxes, fuel lines and distribution piping to zonal heating units)
  # --------------------------------------------------------------------------------------------------
  def boiler_costing(model, prototype_creator)

    #Global flag to determine if a GSHP is present
    @gshp_flag = false

    #Global flag to determine if a AWHP is present
    @awhp_flag = false

    totalCost = 0.0

    # Get regional cost factors for this province and city
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s == "GasBoilers"}.first  # Get any row from spreadsheet in case of region error
    regional_material, regional_installation =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Get regional electric cost factors for this province and city
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s.upcase == "BOX" && data['Size'].to_i == 1}.first
    reg_mat_elec, reg_lab_elec =
      get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Store some geometry data for use below...
    util_dist, ht_roof, nom_flr_hght, horz_dist, numAGFlrs, mechRmInBsmt = getGeometryData(model, prototype_creator)

    template_type = prototype_creator.template

    plant_loop_info = {}
    plant_loop_info[:boilers] = []
    plant_loop_info[:boilerpumps] = []

    # Iterate through the plant loops to get boiler & pump data...
    model.getPlantLoops.each do |plant_loop|
      next unless (plant_loop.name.get.to_s.downcase == "hot water loop") || (plant_loop.name.get.to_s.downcase == "hw plantloop")
      plant_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_BoilerHotWater.is_initialized
          boiler = supply_comp.to_BoilerHotWater.get
          boiler_info = {}
          plant_loop_info[:boilers] << boiler_info
          boiler_info[:name] = boiler.name.get
          # 2020-09-01 CK Include efficiency for boiler upgrade costing
          boiler_info[:efficiency] = boiler.nominalThermalEfficiency.to_f
          if boiler.fuelType =~ /Electric/i
            boiler_info[:fueltype] = 'ElecBoilers'
          elsif boiler.fuelType =~ /NaturalGas/i
            boiler_info[:fueltype] = 'GasBoilers'
            #2020-09-01 CK Include modifications for condensing and pulse gas boilers
            if boiler_info[:efficiency] >= 0.827 && boiler_info[:efficiency] < 0.9
              boiler_info[:fueltype] = "CondensingBoilers"
            elsif boiler_info[:efficiency] >= 0.9
              boiler_info[:fueltype] = "PulseBoilers"
            end
          elsif boiler.fuelType =~ /Oil/i       # Oil, FuelOil, FuelOil#2
            boiler_info[:fueltype] = 'OilBoilers'
          end
          boiler_info[:nominal_capacity] = boiler.nominalCapacity.to_f / 1000 # kW
        elsif supply_comp.to_PumpConstantSpeed.is_initialized
          csPump = supply_comp.to_PumpConstantSpeed.get
          csPump_info = {}
          plant_loop_info[:boilerpumps] << csPump_info
          csPump_info[:name] = csPump.name.get
          if csPump.isRatedPowerConsumptionAutosized.to_bool
            csPumpSize = csPump.autosizedRatedPowerConsumption.to_f
          else
            csPumpSize = csPump.ratedPowerConsumption.to_f
          end
          csPump_info[:size] = csPumpSize.to_f # Watts
          if csPump.isRatedFlowRateAutosized.to_bool
            csPump_info[:water_flow_m3_per_s] = csPump.autosizedRatedFlowRate.to_f
          else
            csPump_info[:water_flow_m3_per_s] = csPump.ratedFlowRate.to_f
          end
        elsif supply_comp.to_PumpVariableSpeed.is_initialized
          vsPump = supply_comp.to_PumpVariableSpeed.get
          vsPump_info = {}
          plant_loop_info[:boilerpumps] << vsPump_info
          vsPump_info[:name] = vsPump.name.get
          if vsPump.isRatedPowerConsumptionAutosized.to_bool
            vsPumpSize = vsPump.autosizedRatedPowerConsumption.to_f
          else
            vsPumpSize = vsPump.ratedPowerConsumption.to_f
          end
          vsPump_info[:size] = vsPumpSize.to_f # Watts
          if vsPump.isRatedFlowRateAutosized.to_bool
            vsPump_info[:water_flow_m3_per_s] = vsPump.autosizedRatedFlowRate.to_f
          else
            vsPump_info[:water_flow_m3_per_s] = vsPump.ratedFlowRate.to_f
          end
        elsif supply_comp.to_HeatPumpWaterToWaterEquationFitHeating.is_initialized
          gshp = supply_comp.to_HeatPumpWaterToWaterEquationFitHeating.get
          gshp_info = {}
          gshp_info[:fueltype] = 'wshp'
          gshp_info[:name] = gshp.name.to_s
          if gshp.isRatedHeatingCapacityAutosized.to_bool
            gshp_info[:nominal_capacity] = gshp.autosizedRatedHeatingCapacity.to_f/1000.0
          else
            gshp_info[:nominal_capacity] = gshp.ratedHeatingCapacity.to_f/1000.0
          end
          plant_loop_info[:boilers] << gshp_info
          @gshp_flag = true
        elsif supply_comp.to_HeatPumpPlantLoopEIRHeating.is_initialized
          awhp = supply_comp.to_HeatPumpPlantLoopEIRHeating.get
          awhp_info = {}
          awhp_info[:fueltype] = 'Airtowaterhp'
          awhp_info[:name] = awhp.name.to_s
          if awhp.isReferenceCapacityAutosized.to_bool
            awhp_info[:nominal_capacity] = awhp.autosizedReferenceCapacity.to_f/1000.0
          else
            awhp_info[:nominal_capacity] = awhp.referenceCapacity.to_f/1000.0
          end
          plant_loop_info[:boilers] << awhp_info
          @awhp_flag = true
        end
      end
    end

    boilerCost = 0.0 ; thisBoilerCost = 0.0 ; flueCost = 0.0 ; utilCost = 0.0 ; fuelFittingCost = 0.0
    numBoilers = 0 ; multiplier = 1.0 ; primaryFuel = ''; primaryCap = 0 ; backupBoiler = false

    # Get costs associated with each boiler
    plant_loop_info[:boilers].each do |boiler|

      # Get primary/secondary/backup boiler cost based on fuel type and capacity for each boiler
      # 06-Sep-2019 JTB: Added check for no 'Primary' or 'Secondary' label and assume primary.
      #    This boiler prefix name seemed to disappear after the heat pump work was committed.
      numBoilers += 1
      if boiler[:name] =~ /primary/i || (boiler[:name] !~ /primary/i && boiler[:name] !~ /secondary/ && numBoilers == 1) || (boiler[:fuel_type] == 'wshp') || (boiler[:fuel_type] == 'Airtowaterhp')
        primaryFuel = boiler[:fueltype]
        primaryCap = boiler[:nominal_capacity]
        matCost, labCost = getHVACCost(boiler[:name], boiler[:fueltype], boiler[:nominal_capacity], false)

        # 2020-09-02 CK: Assume condensing oil boilers cost twice as much as non-condensing oil boilers
        if boiler[:fueltype] == 'OilBoilers' && boiler[:efficiency] >= 0.9
          thisBoilerCost = matCost * 2 * regional_material / 100.0 + labCost * regional_installation / 100.0
        else
          thisBoilerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
        end

        # Flue and utility component costs (for gas and oil boilers only)
        # 2020-09-02 CK:  Include pulse and condensing gas boilers to those with utility component costs
        if boiler[:fueltype] == 'GasBoilers' || boiler[:fueltype] == 'OilBoilers' || boiler[:fueltype] == 'CondensingBoilers' || boiler[:fueltype] == 'PulseBoilers'
          # Calculate flue costs once for all boilers since flues combined by header when multiple boilers
          # 6 inch diameter flue (#384)
          materialHash = get_cost_info(mat: 'Venting', size: '6')
          matCost, labCost = getCost('flue', materialHash, multiplier)
          flueVentCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          #6 inch elbow fitting (#386)
          materialHash = get_cost_info(mat: 'VentingElbow', size: '6')
          matCost, labCost = getCost('flue elbow', materialHash, multiplier)
          flueElbowCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # 6 inch top (#392)
          materialHash = get_cost_info(mat: 'VentingTop', size: '6')
          matCost, labCost = getCost('flue top', materialHash, multiplier)
          flueTopCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Gas/Oil line piping cost per ft (#1)
          materialHash = get_cost_info(mat: 'GasLine', unit: 'L.F.')
          matCost, labCost = getCost('fuel line', materialHash, multiplier)
          fuelLineCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Gas/Oil line fitting connection per boiler (#2)
          materialHash = get_cost_info(mat: 'GasLine', unit: 'each')
          matCost, labCost = getCost('fuel line fitting connection', materialHash, multiplier)
          fuelFittingCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Header cost only non-zero if there is a secondary/backup gas/oil boiler
          headerCost = 0.0
        else  # Electric has no flue
          flueVentCost = 0.0 ; flueElbowCost = 0.0 ; flueTopCost = 0.0 ; headerCost = 0.0
        end

        # Electric utility cost components (i.e., power lines).
        # Calculate utility cost for primary boiler only since multiple boilers use common utilities

        # elec 600V #14 wire /100 ft (#848)
        materialHash = get_cost_info(mat: 'Wiring', size: 14)
        matCost, labCost = getCost('electrical wire - 600V #14', materialHash, multiplier)
        elecWireCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

        # 1 inch metal conduit (#851)
        materialHash = get_cost_info(mat: 'Conduit', unit: 'L.F.')
        matCost, labCost = getCost('1 inch metal conduit', materialHash, multiplier)
        metalConduitCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

        # 2020-09-02 CK Adding Condensing and Pulse boilers to those that need additional connections
        if boiler[:fueltype] == 'GasBoilers' || boiler[:fueltype] == 'CondensingBoilers' || boiler[:fueltype] == 'PulseBoilers'
          # Gas boilers require fuel line+valves+connectors and electrical conduit
          utilCost += (fuelLineCost + metalConduitCost) * util_dist + fuelFittingCost +
              elecWireCost * util_dist / 100

        elsif boiler[:fueltype] == 'OilBoilers'
          # Oil boilers require fuel line+valves+connectors and electrical conduit

          # Oil filtering system (#4)
          materialHash = get_cost_info(mat: 'OilLine', unit: 'each')
          matCost, labCost = getCost('Oil filtering system', materialHash, multiplier)
          oilFilterCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # 2000 USG above ground tank (#5)
          materialHash = get_cost_info(mat: 'OilTanks', size: 2000)
          matCost, labCost = getCost('Oil tank (2000 USG)', materialHash, multiplier)
          oilTankCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          utilCost += (fuelLineCost + metalConduitCost) * util_dist + fuelFittingCost +
              elecWireCost * util_dist / 100 + oilFilterCost + oilTankCost

        elsif boiler[:fueltype].to_s.downcase == 'elecboilers' || boiler[:fueltype].to_s.downcase == 'wshp'
          # Electric boilers require only conduit
          utilCost += metalConduitCost * util_dist + elecWireCost * util_dist / 100
        elsif boiler[:fuel_type].to_s.downcase == 'airtowaterhp'
          # Add heating buffer tank for awhp
          materialHash = get_cost_info(mat: 'solartank', size: 450)
          matCost, labCost = getCost('solartank', materialHash, multiplier)
          utilCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
        end

      elsif boiler[:name] =~ /secondary/i || numBoilers > 1
        if boiler[:nominal_capacity] > 0.1
          # A secondary boiler exists so use it for costing
          matCost, labCost = getHVACCost(boiler[:name], boiler[:fueltype], boiler[:nominal_capacity], false)
          # 2020-09-02 CK: Assume condensing oil boilers cost twice as much as non-condensing oil boilers
          if boiler[:fueltype] == 'OilBoilers' && boiler[:efficiency] >= 0.9
            thisBoilerCost = matCost * 2 * regional_material / 100.0 + labCost * regional_installation / 100.0
          else
            thisBoilerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
          end
        else
          # Use existing value of thisBoilerCost to represent a backup boiler!
          # This just doubles the cost of the primary boiler.
          # 2023-04-25:  Leaving backup boiler in energy model but no longer costing.
          backupBoiler = false
          thisBoilerCost = 0.0
          numBoilers -= 1
        end

        # Flue costs set to zero if secondary boiler since already calculated in primary
        flueVentCost = 0.0; flueElbowCost = 0.0; flueTopCost = 0.0

        # Check if need a flue header (i.e., there are both primary and secondary/backup boilers)
        if thisBoilerCost > 0.0 && ( (backupBoiler && primaryFuel != 'ElecBoilers') || (boiler[:fueltype] != 'ElecBoilers') || (boiler[:fueltype] != 'wshp') || (boiler[:fueltype] != 'Airtowaterhp'))
          # 6 inch diameter header (#384)
          materialHash = get_cost_info(mat: 'Venting', size: 6)
          matCost, labCost = getCost('flue header', materialHash, multiplier)
          headerVentCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          #6 inch elbow fitting for header (#386)
          materialHash = get_cost_info(mat: 'VentingElbow', size: 6)
          matCost, labCost = getCost('flue header elbow', materialHash, multiplier)
          headerElbowCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Assume a header length of 20 ft and an elbow fitting for each boiler connected to the header
          headerCost = (headerVentCost * 20  + headerElbowCost) * numBoilers
        else
          headerCost = 0.0
        end
      end
      boilerCost += thisBoilerCost
      flueCost += flueVentCost * ht_roof + flueElbowCost + flueTopCost + headerCost
      if numBoilers > 1
        # Adjust utility cost for extra fuel line fitting cost
        utilCost += fuelFittingCost * (numBoilers - 1)
      end
    end

    # Boiler pump costs
    pumpCost = 0.0; pipingToPumpCost = 0.0; numPumps = 0; pumpName = ''; pumpSize = 0.0 ; pumpFlow = 0.0
    plant_loop_info[:boilerpumps].each do |pump|
      numPumps += 1
      # Cost variable and constant volume pumps the same (the difference is in extra cost for VFD controller)
      pumpSize = pump[:size]; pumpName = pump[:name]
      pumpFlow += pump[:water_flow_m3_per_s].to_f
      matCost, labCost = getHVACCost(pumpName, 'Pumps', pumpSize, false)
      pumpCost += matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      if pump[:name] =~ /variable/i
        # Cost the VFD controller for the variable pump
        matCost, labCost = getHVACCost(pumpName, 'VFD', pumpSize, false)
        pumpCost += matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0
      end
    end
    if numBoilers > 1 && numPumps < 2
      # Add pump costing for the backup boiler pump.
      pumpCost *= 2.0
      numPumps = 2  # reset the number of pumps for piping costs below
    end
    # Double the pump costs to accomodate the costing of a backup pumps for each boiler!
    # No longer costing backup pumps.
    # pumpCost *= 2.0

    # Boiler water piping to pumps cost: Add piping elbows, valves and insulation from the boiler(s)
    # to the pumps(s) assuming a pipe diameter of 1” and a distance of 10 ft per pump

    if numBoilers > 0
      # 1 inch Steel pipe
      matCost, labCost = getHVACCost('1 inch steel pipe', 'SteelPipe', 1)
      pipingToPumpCost += 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe insulation
      matCost, labCost = getHVACCost('1 inch pipe insulation', 'PipeInsulation', 1)
      pipingToPumpCost += 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe elbow
      matCost, labCost = getHVACCost('1 inch steel pipe elbow', 'SteelPipeElbow', 1)
      pipingToPumpCost += 2.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch gate valves
      matCost, labCost = getHVACCost('1 inch gate valves', 'ValvesGate', 1)
      pipingToPumpCost += 1.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
    end

    if numBoilers > 0
      # Double pump piping cost to account for second boiler
      pipingToPumpCost *= numBoilers

      hdrDistributionCost = getHeaderPipingDistributionCost(numAGFlrs, mechRmInBsmt, regional_material, regional_installation, reg_mat_elec, reg_lab_elec,
                                                            pumpFlow, horz_dist, nom_flr_hght)
    else
      pipingToPumpCost = 0
      hdrDistributionCost = 0
    end

    totalCost = boilerCost + flueCost + utilCost + pumpCost + pipingToPumpCost + hdrDistributionCost

        @costing_report['heating_and_cooling']['plant_equipment']  << {
        'type' => 'boilers',
        'nom_flr2flr_hght_ft' => nom_flr_hght.round(1),
        'ht_roof_ft' => ht_roof.round(1),
        'longest_distance_to_ext_ft' => horz_dist.round(1),
        'wiring_and_gas_connections_distance_ft' => util_dist.round(1),
        'equipment_cost' => boilerCost.round(0),
        'flue_cost' => flueCost.round(0),
        'wiring_and_gas_connections_cost' => utilCost.round(0),
        'pump_cost' => pumpCost.round(0),
        'piping_to_pump_cost' => pipingToPumpCost.round(0),
        'header_distribution_cost' => hdrDistributionCost.round(0),
        'total_cost' => totalCost.round(0)
    }
    puts "\nHVAC Boiler costing data successfully generated. Total boiler costs: $#{totalCost.round(0)}"

    return totalCost
  end

  # --------------------------------------------------------------------------------------------------
  # Chiller costing is similar to boiler costing above
  # --------------------------------------------------------------------------------------------------
  def chiller_costing(model, prototype_creator)

    totalCost = 0.0

    # Get regional cost factors for this province and city
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s == "GasBoilers"}.first  # Get any row from spreadsheet in case of region error
    regional_material, regional_installation =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Get regional electric cost factors for this province and city
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s.upcase == "BOX" && data['Size'].to_i == 1}.first
    reg_mat_elec, reg_lab_elec =
      get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Store some geometry data for use below...
    util_dist, ht_roof, nom_flr_hght, horz_dist, numAGFlrs, mechRmInBsmt = getGeometryData(model, prototype_creator)

    template_type = prototype_creator.template

    chillerCost = 0.0 ; thisChillerCost = 0.0 ; flueCost = 0.0 ; utilCost = 0.0
    plant_loop_info = {}
    plant_loop_info[:chillers] = []
    plant_loop_info[:chillerpumps] = []
    awhp_chiller = false

    # Iterate through the plant loops to get chiller & pump data...
    model.getPlantLoops.each do |plant_loop|
      next unless (plant_loop.name.get.to_s.downcase == "chilled water loop") || (plant_loop.name.get.to_s.downcase == "chw plantloop")
      plant_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_ChillerElectricEIR.is_initialized #|| supply_comp.to_ChillerGasEIR.is_initialized
          chiller = supply_comp.to_ChillerElectricEIR.get
          chiller_info = {}
          plant_loop_info[:chillers] << chiller_info
          chiller_info[:name] = chiller.name.get
          if chiller_info[:name] =~ /WaterCooled/i
            if chiller_info[:name] =~ /Absorption/i
              chiller_info[:type] = 'HotAbsChiller'
              chiller_info[:fuel] = 'NaturalGas'
            elsif chiller_info[:name] =~ /Direct Gas/i
              chiller_info[:type] = 'GasAbsChiller'
              chiller_info[:fuel] = 'NaturalGas'
            elsif chiller_info[:name] =~ /Centrifugal/i
              chiller_info[:type] = 'CentChillerWater'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /Reciprocating/i
              chiller_info[:type] = 'RecChillerWater'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /Scroll/i
              chiller_info[:type] = 'ScrollChillerWater'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /Screw/i
              chiller_info[:type] = 'ScrewChillerWater'
              chiller_info[:fuel] = 'Electric'
            end
          elsif chiller_info[:name] =~ /AirCooled/i
            if chiller_info[:name] =~ /Reciprocating/i
              chiller_info[:type] = 'RecChillerAir'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /Scroll/i
              chiller_info[:type] = 'ScrollChillerAir'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /Screw/i
              chiller_info[:type] = 'ScrewChillerAir'
              chiller_info[:fuel] = 'Electric'
            elsif chiller_info[:name] =~ /DX/i
              chiller_info[:type] = 'DXChiller'
              chiller_info[:fuel] = 'Electric'
            end
          end
          chiller_info[:reference_capacity] = chiller.referenceCapacity.to_f / 1000 # kW
        elsif supply_comp.to_HeatPumpPlantLoopEIRCooling.is_initialized
          chiller = supply_comp.to_HeatPumpPlantLoopEIRCooling.get
          chiller_info = {}
          chiller_info[:name] = chiller.name.get
          chiller_info[:type] = 'Airtowaterhp'
          chiller_info[:fuel] = 'Electric'
          if chiller.isReferenceCapacityAutosized
            chiller_info[:reference_capacity] = chiller.autosizedReferenceCapacity.to_f / 1000 # kW
          else
            chiller_info[:reference_capacity] = chiller.referenceCapacity.to_f / 1000 # kW
          end
          awhp_chiller = true
          plant_loop_info[:chillers] << chiller_info
        elsif supply_comp.to_PumpConstantSpeed.is_initialized
          csPump = supply_comp.to_PumpConstantSpeed.get
          csPump_info = {}
          plant_loop_info[:chillerpumps] << csPump_info
          csPump_info[:name] = csPump.name.get
          if csPump.isRatedPowerConsumptionAutosized.to_bool
            csPumpSize = csPump.autosizedRatedPowerConsumption.to_f
          else
            csPumpSize = csPump.ratedPowerConsumption.to_f
          end
          csPump_info[:size] = csPumpSize.to_f # Watts
          if csPump.isRatedFlowRateAutosized.to_bool
            csPump_info[:water_flow_m3_per_s] = csPump.autosizedRatedFlowRate.to_f
          else
            csPump_info[:water_flow_m3_per_s] = csPump.ratedFlowRate.to_f
          end
        elsif supply_comp.to_PumpVariableSpeed.is_initialized
          vsPump = supply_comp.to_PumpVariableSpeed.get
          vsPump_info = {}
          plant_loop_info[:chillerpumps] << vsPump_info
          vsPump_info[:name] = vsPump.name.get
          if vsPump.isRatedPowerConsumptionAutosized.to_bool
            vsPumpSize = vsPump.autosizedRatedPowerConsumption.to_f
          else
            vsPumpSize = vsPump.ratedPowerConsumption.to_f
          end
          vsPump_info[:size] = vsPumpSize.to_f # Watts
          if vsPump.isRatedFlowRateAutosized.to_bool
            vsPump_info[:water_flow_m3_per_s] = vsPump.autosizedRatedFlowRate.to_f
          else
            vsPump_info[:water_flow_m3_per_s] = vsPump.ratedFlowRate.to_f
          end
        end
      end
    end

    # Get costs associated with each chiller
    numChillers = 0 ; multiplier = 1.0
    primaryFuel = ''; primaryCap = 0

    plant_loop_info[:chillers].each do |chiller|

      # Get primary/secondary/backup chiller cost based on type and capacity for each chiller
      # 06-Sep-2019 JTB: Added check for no 'Primary' or 'Secondary' label and assume primary.
      #    This chiller prefix name seemed to disappear after the heat pump work was committed.
      numChillers += 1
      if chiller[:type].to_s.downcase == 'airtowaterhp'
        primaryFuel = chiller[:fuel]
        primaryCap = chiller[:reference_capacity] #kW
        # Add cooling buffer tank for awhp
        materialHash = get_cost_info(mat: 'solartank', size: 450)
        matCost, labCost = getCost('solartank', materialHash, multiplier) #Costing for AWHP only buffer tank, AWHP included in boiler cost
        thisChillerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
        # Include 2 expansion tanks for awhp
        materialHash = get_cost_info(mat: 'ExpansionTanks', size: 60)
        matCost, labCost = getCost('ExpansionTanks', materialHash, multiplier) #Costing for AWHP only buffer tank, AWHP included in boiler cost
        thisChillerCost += (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2
        # Inclide glycol cost
        materalHash = get_cost_info(mat: 'glycol')
        matCost, labCost = getCost('solartank', materialHash, multiplier) #Costing for AWHP only buffer tank, AWHP included in boiler cost
        thisChillerCost += (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2

        flueVentCost = 0.0 ; flueElbowCost = 0.0 ; flueTopCost = 0.0 ; headerCost = 0.0
      elsif ((chiller[:name].to_s.downcase =~ /primary/i || (chiller[:name] !~ /primary/i && chiller[:name] !~ /secondary/i && numChillers == 1)) || (@gshp_flag))
        primaryFuel = chiller[:fuel]
        primaryCap = chiller[:reference_capacity] #kW
        if not chiller[:name].include?("ChillerElectricEIR_VSDCentrifugalWaterChiller")
          matCost, labCost = getHVACCost(chiller[:name], chiller[:type], chiller[:reference_capacity], false)
          thisChillerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
        elsif chiller[:name].include?("ChillerElectricEIR_VSDCentrifugalWaterChiller")
          thisChillerCost = vsd_chiller_cost(primaryCap: primaryCap)
        end
        # Flue cost for gas (absorption) chillers!
        if chiller[:fuel] == 'NaturalGas'
          # Calculate flue costs once for all chillets since flues combined by header when multiple chillers
          # 6 inch diameter flue (#384)
          materialHash = get_cost_info(mat: 'Venting', size: 6)
          matCost, labCost = getCost('flue', materialHash, multiplier)
          flueVentCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          #6 inch elbow fitting (#386)
          materialHash = get_cost_info(mat: 'VentingElbow', size: 6)
          matCost, labCost = getCost('flue elbow', materialHash, multiplier)
          flueElbowCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # 6 inch top (#392)
          materialHash = get_cost_info(mat: 'VentingTop', size: 6)
          matCost, labCost = getCost('flue top', materialHash, multiplier)
          flueTopCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Gas line piping cost per ft (#1)
          materialHash = get_cost_info(mat: 'GasLine', unit: 'L.F.')
          matCost, labCost = getCost('fuel line', materialHash, multiplier)
          fuelLineCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Gas line fitting connection per boiler (#2)
          materialHash = get_cost_info(mat: 'GasLine', unit: 'each')
          matCost, labCost = getCost('fuel line fitting connection', materialHash, multiplier)
          fuelFittingCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0


          # Header cost only non-zero if there is a secondary/backup gas/oil boiler
          headerCost = 0.0
        else  # Electric
          flueVentCost = 0.0 ; flueElbowCost = 0.0 ; flueTopCost = 0.0 ; headerCost = 0.0
        end

        # Electric utility costs (i.e., power lines).
        # Calculate utility cost components for primary chiller only since multiple chillers use common utilities

        # elec 600V #14 wire /100 ft (#848)
        materialHash = get_cost_info(mat: 'Wiring', size: 14)
        matCost, labCost = getCost('electrical wire - 600V #14', materialHash, multiplier)
        elecWireCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

        # 1 inch metal conduit (#851)
        materialHash = get_cost_info(mat: 'Conduit', unit: 'L.F.')
        matCost, labCost = getCost('1 inch metal conduit', materialHash, multiplier)
        metalConduitCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

        if chiller[:fuel] == 'NaturalGas'
          # Gas chillers require fuel line+valves+connectors and electrical conduit
          utilCost += (fuelLineCost + metalConduitCost) * util_dist + fuelFittingCost + elecWireCost * util_dist / 100

        else # Electric
          # Electric chillers require only conduit
          utilCost += metalConduitCost * util_dist + elecWireCost * util_dist / 100
        end

      elsif (chiller[:name].to_s.downcase =~ /secondary/i || numChillers > 1)
        if chiller[:reference_capacity] <= 0.1
          # Chiller cost is zero!
          thisChillerCost = 0.0
          numChillers -= 1
        else
          # A secondary chiller exists so use it for costing
          if not chiller[:name].include?("ChillerElectricEIR_VSDCentrifugalWaterChiller")
            matCost, labCost = getHVACCost(chiller[:name], chiller[:type], chiller[:reference_capacity], false)
            thisChillerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
          elsif chiller[:name].include?("ChillerElectricEIR_VSDCentrifugalWaterChiller")
            thisChillerCost = vsd_chiller_cost(primaryCap: primaryCap)
          end
        end

        # Flue costs set to zero if secondary chiler since already calculated in primary (if gas absorption)
        flueVentCost = 0.0; flueElbowCost = 0.0; flueTopCost = 0.0

        # Check if need a flue header (i.e., both primary and secondary chillers are gas absorption)
        if thisChillerCost > 0.0 && primaryFuel == 'NaturalGas' && chiller[:fuel] == 'NaturalGas'
          # 6 inch diameter header (#384)
          materialHash = get_cost_info(mat: 'Venting', size: 6)
          matCost, labCost = getCost('flue header', materialHash, multiplier)
          headerVentCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          #6 inch elbow fitting for header (#386)
          materialHash = get_cost_info(mat: 'VentingElbow', size: 6)
          matCost, labCost = getCost('flue header elbow', materialHash, multiplier)
          headerElbowCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Assume a header length of 20 ft and an elbow fitting for each boiler connected to the header
          headerCost = (headerVentCost * 20 + headerElbowCost) * numChillers
        else
          headerCost = 0.0
        end
      end
      chillerCost += thisChillerCost
      flueCost += flueVentCost * ht_roof + flueElbowCost + flueTopCost + headerCost
      if numChillers > 1 && primaryFuel == 'NaturalGas'
        # Adjust utility cost for extra fuel line fitting cost
        utilCost += fuelFittingCost * (numChillers - 1)
      end
      if numChillers < 2
        # Create a cost for a backup chiller by doubling cost of primary chiller
        # 2023-04-25:  Although backup chillers may be modeled we are no longer counting them.
        #chillerCost *= 2.0
        numChillers = 1
      end
    end

    # Chiller pump costs
    pumpCost = 0.0; pipingToPumpCost = 0.0; numPumps = 0; pumpName = ''; pumpSize = 0.0 ; pumpFlow = 0.0
    plant_loop_info[:chillerpumps].each do |pump|
      numPumps += 1
      # Cost variable and constant volume pumps the same (the difference is in extra cost for VFD controller)
      pumpSize = pump[:size]; pumpName = pump[:name]
      pumpFlow += pump[:water_flow_m3_per_s].to_f
      matCost, labCost = getHVACCost(pumpName, 'Pumps', pumpSize, false)
      indpumpCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      if pump[:name] =~ /variable/i
        # Cost the VFD controller for the variable pump costed above
        matCost, labCost = getHVACCost(pumpName, 'VFD', pumpSize, false)
        indpumpCost += matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0
      end
      if awhp_chiller
        pumpCost += indpumpCost * 2
      else
        pumpCost += indpumpCost
      end
    end
    if (numChillers > 1 && numPumps < 2)
      # Add pump costing for additional chillers
      pumpCost *= 2.0
      numPumps = 2  # reset the number of pumps for piping costs below
      numChillers = 2
    end
    # Double the pump costs to accomodate the costing of backup pumps for each chiller!
    # No longer costing backup pump CK 2023-06-23
    #pumpCost *= 2.0

    # Chiller water piping cost: Add piping elbows, valves and insulation from the chiller(s)
    # to the pumps(s) assuming a pipe diameter of 1” and a distance of 10 ft per pump
    if numChillers > 0
      # 1 inch Steel pipe
      matCost, labCost = getHVACCost('1 inch steel pipe', 'SteelPipe', 1)
      pipingToPumpCost = 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe insulation
      matCost, labCost = getHVACCost('1 inch pipe insulation', 'PipeInsulation', 1)
      pipingToPumpCost += 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe elbow
      matCost, labCost = getHVACCost('1 inch steel pipe elbow', 'SteelPipeElbow', 1)
      pipingToPumpCost += 2.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch gate valves
      matCost, labCost = getHVACCost('1 inch gate valves', 'ValvesGate', 1)
      pipingToPumpCost += 1.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
    end

    if numChillers > 0
      # Double pump piping cost to account for second chiller
      pipingToPumpCost *= 2 if awhp_chiller
      pipingToPumpCost *= numChillers

      hdrDistributionCost = getHeaderPipingDistributionCost(numAGFlrs, mechRmInBsmt, regional_material, regional_installation, reg_mat_elec, reg_lab_elec,
                                                            pumpFlow, horz_dist, nom_flr_hght)
    else
      pipingToPumpCost = 0
      hdrDistributionCost = 0
    end

    totalCost = chillerCost + flueCost + utilCost + pumpCost + pipingToPumpCost + hdrDistributionCost

    @costing_report['heating_and_cooling']['plant_equipment']  << {
        'type' => 'chillers',
        'nom_flr2flr_hght_ft' => nom_flr_hght.round(1),
        'ht_roof_ft' => ht_roof.round(1),
        'longest_distance_to_ext_ft' => horz_dist.round(1),
        'wiring_and_gas_connections_distance_ft' => util_dist.round(1),
        'equipment_cost' => chillerCost.round(0),
        'flue_cost' => flueCost.round(0),
        'wiring_and_gas_connections_cost' => utilCost.round(0),
        'pump_cost' => pumpCost.round(0),
        'piping_to_pump_cost' => pipingToPumpCost.round(0),
        'header_distribution_cost' => hdrDistributionCost.round(0),
        'total_cost' => totalCost.round(0)
    }

    puts "\nHVAC Chiller costing data successfully generated. Total chiller costs: $#{totalCost.round(0)}"

    return totalCost
  end

  # ----------------------------------------------------------------------------------------------
  # Cooling tower (i.e., chiller condensor loop cooling) costing
  # ----------------------------------------------------------------------------------------------
  def coolingtower_costing(model, prototype_creator)

    totalCost = 0.0

    # Get regional cost factors for this province and city
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s == "GasBoilers"}.first  # Get any row from spreadsheet in case of region error
    regional_material, regional_installation =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Get regional electric cost factors for this province and city
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s.upcase == "BOX" && data['Size'].to_i == 1}.first
    reg_mat_elec, reg_lab_elec =
      get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Store some geometry data for use below...
    util_dist, ht_roof, nom_flr_hght, horz_dist, numAGFlrs, mechRmInBsmt = getGeometryData(model, prototype_creator)

    template_type = prototype_creator.template

    cltowerCost = 0.0
    thisClTowerCost = 0.0
    utilCost = 0.0
    plant_loop_info = {}
    plant_loop_info[:coolingtowers] = []
    plant_loop_info[:coolingtowerpumps] = []
    plant_loop_info[:groundloops] = []
    cltowertype = 'cooling_towers'

    # Iterate through the plant loops to get cooling tower & pump data...
    model.getPlantLoops.each do |plant_loop|
      next unless (plant_loop.name.get.to_s =~ /Condenser Water Loop/i) || (plant_loop.name.get.to_s =~ /Condenser PlantLoop GLHX/i)
      plant_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_CoolingTowerSingleSpeed.is_initialized
          cltower = supply_comp.to_CoolingTowerSingleSpeed.get
          cltower_info = {}
          plant_loop_info[:coolingtowers] << cltower_info
          cltower_info[:name] = cltower.name.get
          cltower_info[:type] = 'ClgTwr'  # Material lookup name
          cltower_info[:fanPoweratDesignAirFlowRate] = cltower.fanPoweratDesignAirFlowRate.to_f / 1000 # kW
          cltower_info[:capacity] = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM " +
            "TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND " +
            "TableName='Central Plant' AND ColumnName='Nominal Capacity' AND " +
            "RowName='#{cltower_info[:name].upcase}' ").to_f / 1000 # kW
        elsif supply_comp.to_PumpConstantSpeed.is_initialized
          csPump = supply_comp.to_PumpConstantSpeed.get
          csPump_info = {}
          plant_loop_info[:coolingtowerpumps] << csPump_info
          csPump_info[:name] = csPump.name.get
          if csPump.isRatedPowerConsumptionAutosized.to_bool
            csPumpSize = csPump.autosizedRatedPowerConsumption.to_f
          else
            csPumpSize = csPump.ratedPowerConsumption.to_f
          end
          csPump_info[:size] = csPumpSize.to_f # Watts
        elsif supply_comp.to_PumpVariableSpeed.is_initialized
          vsPump = supply_comp.to_PumpVariableSpeed.get
          vsPump_info = {}
          plant_loop_info[:coolingtowerpumps] << vsPump_info
          vsPump_info[:name] = vsPump.name.get
          if vsPump.isRatedPowerConsumptionAutosized.to_bool
            vsPumpSize = vsPump.autosizedRatedPowerConsumption.to_f
          else
            vsPumpSize = vsPump.ratedPowerConsumption.to_f
          end
          vsPump_info[:size] = vsPumpSize.to_f # Watts
        elsif supply_comp.to_DistrictHeating.is_initialized
          groundLoop = supply_comp.to_DistrictHeating.get
          groundLoop_info = {}
          groundLoop_info[:name] = groundLoop.name.to_s
          if groundLoop.isNominalCapacityAutosized.to_bool
            groundLoop_info[:nominal_capacity] = groundLoop.autosizedNominalCapacity.to_f/1000.0
          else
            groundLoop_info[:nominal_capacity] = groundLoop.nominalCapacity.to_f/1000.0
          end
          # Get flow rate to ground loop
          if plant_loop.isMaximumLoopFlowRateAutosized.to_bool
            groundLoop_info[:plant_loop_flow_rate_m3ps] = plant_loop.autosizedMaximumLoopFlowRate.to_f
          else
            groundLoop_info[:plant_loop_flow_rate_m3ps] = plant_loop.maximumLoopFlowRate.to_f
          end
          plant_loop_info[:groundloops] << groundLoop_info
        elsif supply_comp.to_DistrictCooling.is_initialized
          groundLoop = supply_comp.to_DistrictCooling.get
          groundLoop_info = {}
          groundLoop_info[:name] = groundLoop.name.to_s
          if groundLoop.isNominalCapacityAutosized.to_bool
            groundLoop_info[:nominal_capacity] = groundLoop.autosizedNominalCapacity.to_f/1000.0
          else
            groundLoop_info[:nominal_capacity] = groundLoop.nominalCapacity.to_f/1000.0
          end
          # Get flow rate to ground loop
          if plant_loop.isMaximumLoopFlowRateAutosized.to_bool
            groundLoop_info[:plant_loop_flow_rate_m3ps] = plant_loop.autosizedMaximumLoopFlowRate.to_f
          else
            groundLoop_info[:plant_loop_flow_rate_m3ps] = plant_loop.maximumLoopFlowRate.to_f
          end
          plant_loop_info[:groundloops] << groundLoop_info
        end
      end
    end

    # Get costs associated with each cooling tower
    numTowers = 0 ; multiplier = 1.0

    plant_loop_info[:coolingtowers].each do |cltower|
      # Get cooling tower cost based on capacity
      numTowers += 1
      if numTowers == 1
        matCost, labCost = getHVACCost(cltower[:name], cltower[:type], cltower[:capacity], false)
        thisClTowerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      else  # Multiple cooling towers
        if cltower[:capacity] <= 0.1
          # Cooling tower cost is zero!
          thisClTowerCost = 0.0
        else
          # A second cooling tower exists so use it for costing
          matCost, labCost = getHVACCost(cltower[:name], cltower[:type], cltower[:capacity], false)
          thisClTowerCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
        end
      end
      cltowerCost += thisClTowerCost

      # Electric utility costs (i.e., power lines) for cooling tower(s).

      # elec 600V #14 wire /100 ft (#848)
      materialHash = get_cost_info(mat: 'Wiring', size: 14)
      matCost, labCost = getCost('electrical wire - 600V #14', materialHash, multiplier)
      elecWireCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

      # 1 inch metal conduit (#851)
      materialHash = get_cost_info(mat: 'Conduit', unit: 'L.F.')
      matCost, labCost = getCost('1 inch metal conduit', materialHash, multiplier)
      metalConduitCost = matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0

      utilCost += metalConduitCost * (ht_roof + 20) + elecWireCost * (ht_roof + 20) / 100
    end

    # Cooling Tower (condensor) pump costs
    pumpCost = 0.0; pipingCost = 0.0; numPumps = 0; pumpName = ''; pumpSize = 0.0
    plant_loop_info[:coolingtowerpumps].each do |pump|
      numPumps += 1
      # Cost variable and constant volume pumps the same (VFD controller added if variable)
      pumpSize = pump[:size]; pumpName = pump[:name]
      matCost, labCost = getHVACCost(pumpName, 'Pumps', pumpSize, false)
      pumpCost += matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      if pump[:name] =~ /variable/i
        # Cost the VFD controller for the variable pump costed above
        pumpSize = pump[:size]; pumpName = pump[:name]
        matCost, labCost = getHVACCost(pumpName, 'VFD', pumpSize, false)
        pumpCost += matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0
      end
    end
    if numTowers > 1 && numPumps < 2
      # Add pump costing for the backup pump.
      # 2023-04-25:  Not including backup tower or pump costs
      # pumpCost *= 2.0
    end
    # Double the pump costs to accomodate the costing of a backup pump(s)!
    # 2023-04-25 No longer including backup pumps
    #pumpCost *= 2.0
    #numPumps = 2  # reset the number of pumps for piping costs below


    # Chiller water piping cost: Add piping elbows, valves and insulation from the chiller(s)
    # to the pumps(s) assuming a pipe diameter of 1” and a distance of 10 ft per pump
    if numTowers > 0
      # 4 inch Steel pipe (vertical + horizontal)
      matCost, labCost = getHVACCost('4 inch steel pipe', 'SteelPipe', 4)
      pipingCost += (ht_roof * 2 + 10 * numPumps) * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 4 inch Steel pipe insulation (vertical + horizontal)
      matCost, labCost = getHVACCost('1 inch pipe insulation', 'PipeInsulation', 4)
      pipingCost += (ht_roof * 2 + 10 * numPumps) * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 4 inch Steel pipe elbow
      matCost, labCost = getHVACCost('4 inch steel pipe tee', 'SteelPipeTee', 4)
      pipingCost += 1.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 4 inch valves
      matCost, labCost = getHVACCost('4 inch BFly valves', 'ValvesBFly', 4)
      pipingCost += 1.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
    end

    # Note: No extra costs for piping for backup condenser pump or multiple cooling towers.

    # Calculate GSHP ground loop cost and interior piping
    unless plant_loop_info[:groundloops].empty?
      # GSHP ground loop cost
      # Not applying localization because costs are currently national estimates only (2023-06-19)
      cltowertype = 'ground_loop'
      largest_loop = plant_loop_info[:groundloops].max_by { |groundloop| groundloop[:nominal_capacity] }
      nominal_capacity = largest_loop[:nominal_capacity].to_f
      matCost, labCost = getHVACCost('GSHP ground loop', 'gshp_ground_loop', '')
      cltowerCost = matCost * nominal_capacity

      # GSHP piping from building to bore field cost
      # Not applying localization because costs are currently national estimates only (2023-06-19)
      gshp_dist = 50
      loop_flow = largest_loop[:plant_loop_flow_rate_m3ps]
      pipe_dia_mm = d = Math.sqrt(1.273*loop_flow/2.0)*1000
      matCost, labCost = getHVACCost('GSHP outdoor piping cost', 'gshp_buried_pipe', pipe_dia_mm, false)
      pipingCost = matCost * gshp_dist

      # Interior piping cost
      # Get mechanical room lacotion (assume this is where the GSHP is)
      mech_room, cond_spaces = prototype_creator.find_mech_room(model)
      mech_centroid = mech_room["space_centroid"]
      # Determine the length to the largest exterior wall
      ground_spaces = []
      pipe_dists = []
      # Determine the exterior ground walls touching the ground
      # Get the spaces
      model.getSpaces.sort.each do |space|
        ground_surf = false
        # Get the surfaces for the space and determine if any are contacting the ground.  If one is add it to the arroy
        # of spaces
        space.surfaces.sort.each do |surface|
          if surface.isGroundSurface
            ground_surf = true
          end
        end
        ground_spaces << space if ground_surf == true
      end
      # Go through all of the spaces contacting the ground
      ground_spaces.sort.each do |ground_space|
        # Go through all of the surfaces for the space and determine which are exterior or foundation walls
        ext_walls = ground_space.surfaces.select{ |surf| surf.surfaceType == 'Wall' && (surf.outsideBoundaryCondition == 'Outdoors' || surf.outsideBoundaryCondition == 'Foundation')}
        # Get the largest exterior wall and the distance to its centroid to the mech room centroid
        unless ext_walls.empty?
          ext_wall = ext_walls.max_by { |ext_wall| ext_wall.grossArea.to_f }
          pipe_dists << {
            wall: ext_wall,
            pipe_dist: ((ext_wall.centroid.x.to_f + ground_space.xOrigin.to_f - mech_centroid[0].to_f).abs + (ext_wall.centroid.y.to_f + ground_space.yOrigin.to_f - mech_centroid[1].to_f).abs + (ext_wall.centroid.z.to_f + ground_space.zOrigin.to_f - mech_centroid[2].to_f).abs)
          }
        end
      end
      # Find the shortest distance to the 3 largest walls and pick the shortest one
      largest_walls = pipe_dists.max_by(3) { |wall| wall[:wall].grossArea.to_f }
      pipe_dist = largest_walls.min_by { |wall| wall[:pipe_dist].to_f }
      pipe_dist_ft = (OpenStudio.convert(pipe_dist[:pipe_dist], 'm', 'ft').get)
      pipe_dia_mm = d = Math.sqrt(1.273*loop_flow/2.0)*1000
      pipe_dia_inch = (OpenStudio.convert(pipe_dia_mm/1000, 'm', 'ft').get)*12.0
      pipe_dia_inch = 8.0 if pipe_dia_inch >= 8.0

      # Include localization foctors in interior piping and fixtures
      # Cost the interior pipe
      matCost, labCost = getHVACCost('GSHP indoor piping cost', 'SteelPipe', pipe_dia_inch, false)
      pipingCost += (matCost*regional_material + labCost*regional_installation)*pipe_dist_ft*2.0/100.0

      # Cost the pipe insulation
      pipe_dia_inch = 4.0 if pipe_dia_inch > 4.0
      matCost, labCost = getHVACCost('GSHP indoor pipe insulation', 'PipeInsulation', pipe_dia_inch, false)
      pipingCost += (matCost*regional_material + labCost*regional_installation)*pipe_dist_ft*2.0/100.0

      # Cost 1 valve
      matCost, labCost = getHVACCost('GSHP indoor pipe valve', 'ValvesBig', 4.0)
      pipingCost += (matCost*regional_material + labCost*regional_installation)/100.0

      # Cost 2 pipe tees
      matCost, labCost = getHVACCost('GSHP indoor pipe tees', 'SteelPipeTee', 4.0)
      pipingCost += (matCost*regional_material + labCost*regional_installation)*2.0/100.0

      # Cost 8 pipe tees
      matCost, labCost = getHVACCost('GSHP indoor pipe elbows', 'SteelPipeElbow', 4.0)
      pipingCost += (matCost*regional_material + labCost*regional_installation)*8.0/100.0
    end
    totalCost = cltowerCost + utilCost + pumpCost + pipingCost

    @costing_report['heating_and_cooling']['plant_equipment']  << {
        'type' => cltowertype,
        'nom_flr2flr_hght_ft' => nom_flr_hght.round(1),
        'ht_roof_ft' => ht_roof.round(1),
        'longest_distance_to_ext_ft' => horz_dist.round(1),
        'wiring_and_gas_connections_distance_ft' => util_dist.round(1),
        'equipment_cost' => cltowerCost.round(0),
        'wiring_and_gas_connections_cost' => utilCost.round(0),
        'pump_cost' => pumpCost.round(0),
        'piping_cost' => pipingCost.round(0),
        'total_cost' => totalCost.round(0)
    }

    puts "\nHVAC Cooling Tower costing data successfully generated. Total cooling tower costs: $#{totalCost.round(0)}"

    return totalCost
  end


  # This method determines how many pieces of equipment are required to satisfy the required size if 1 piece is not
  # enough.  It takes in:
  # materialLookup(String):  The name to search for in the 'Material' column of the materials_hvac sheet of the costing
  #                           spreadsheet.
  # materialSize(Float):  The size to search for in the 'Size' column of teh materials_hvac sheet of the costing
  #                       spreadsheet.
  # It returns:
  # multiplier(Float):  Number of materialLookup with the largest size required to meet the materialSize.
  def get_HVAC_multiplier(materialLookup, materialSize)
    multiplier = 1.0
    materials_hvac = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == materialLookup.to_s.upcase
    }
    if materials_hvac.nil?
      puts("Error: no hvac information available for equipment #{materialLookup}!")
      raise
    elsif materials_hvac.empty?
      puts("Error: no hvac information available for equipment #{materialLookup}!")
      raise
    end
    materials_hvac.length == 1 ? max_size = materials_hvac[0] : max_size = materials_hvac.max_by {|d| d['Size'].to_f}
    if max_size['Size'].to_f <= 0
      puts("Error: #{materialLookup} has a size of 0 or less.  Please check that the correct costing_database.json file is being used or check the costing spreadsheet!")
      raise
    end
    mult = materialSize.to_f / (max_size['Size'].to_f)
    multiplier = (mult.to_i).to_f.round(0) + 1  # Use next largest integer for multiplier
    return multiplier.to_f
  end

  # This method provides the material and labour cost for a required piece of equimpment.  It takes in:
  # name(String):  The name of a piece of equipment.  Is only used for error reporting and is not linked to anything
  #                else.
  # materialLookup(String):  The material type used to search hte 'Material' column of the materials_hvac sheet of the
  #                          costing spreadsheet.
  # materialSize(float):  The size of the equipment in whichever units are required when searching the 'Size' column of
  #                       the costing spreadsheet.
  # exactMatch(true/false):  A flag to indicate if the hvac equipment must match the size provided exactly or if the
  #                          size is a minimum equipment size.
  # It returns the material cost ond labor cost for the equipment including any multipliers.
  def getHVACCost(name, materialLookup, materialSize, exactMatch=true)
    eqCostInfo = getHVACDBInfo(name: name, materialLookup: materialLookup, materialSize: materialSize, exactMatch: exactMatch)
    return getCost(eqCostInfo[:name], eqCostInfo[:hvac_material], eqCostInfo[:multiplier])
  end

  # This method was originally part of getHVACCOST but was split out because in some cases the information from the
  # materials_hvac sheet of the costing spreadsheet was required but not tho cost.
  # The method takes in:
  # name(String):  The name of a piece of equipment.  Is only used for error reporting and is not linked to anything
  #                else.
  # materialLookup(String):  The material type used to search hte 'Material' column of the materials_hvac sheet of the
  #                          costing spreadsheet.
  # materialSize(float):  The size of the equipment in whichever units are required when searching the 'Size' column of
  #                       the costing spreadsheet.
  # exactMatch(true/false):  A flag to indicate if the hvac equipment must match the size provided exactly or if the
  #                          size is a minimum equipment size.
  #
  # The method returns a hash with the following composition:
  # {
  # name(string):  Same as above.
  # hvac_material(hash):  The costing spreadsheet information for the hvac equipment being searched for.
  # multiplier(float):  Default is 1.  Will be higher if exactMatch is false, and no materialLookup could be found with
  #                     a large enough materialSize in the costing spreadsheet. In this case, it is assumed that several
  #                     pieced of equipment defined by hvact_material are used to satisfy the required materialSize.
  #                     The multiplier defines the number of hvac_material required to meet the materialSize
  # }
  def getHVACDBInfo(name:, materialLookup:, materialSize:, exactMatch: true)
    multiplier = 1.0
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    if materialSize == 'nil' || materialSize == '' || materialSize == nil
      # When materialSize is blank because there is only one row in the data sheet, the value is nil
      hvac_material = materials_hvac.select { |data| data['Material'].to_s.upcase == materialLookup.to_s.upcase }.first
    else
      if exactMatch
        hvac_material = materials_hvac.select {|data|
          data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Size'].to_f == materialSize
        }.first
      else
        hvac_material_info = materials_hvac.select {|data|
          data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Size'].to_f >= materialSize
        }
        if hvac_material_info.empty?
          hvac_material = nil
        elsif hvac_material_info.size == 1
          hvac_material = hvac_material_info[0]
        else
          hvac_material = hvac_material_info.min_by{|data| data['Size'].to_f}
        end
      end
    end
    if hvac_material.nil?
      if exactMatch
        puts "HVAC material error! Could not find #{name} in materials_hvac!"
        raise
      else
        # There is no exact match in the costing spreadsheet so redo search for next largest size
        hvac_material = materials_hvac.select {|data|
          data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Size'].to_f >= materialSize.to_f
        }.min_by{|mat_info| mat_info['Size'].to_f}
        if hvac_material.nil?
          # The nominal capacity is greater than the maximum value in the API data for this boiler!
          # Lookup cost for a capacity divided by the multiple of req'd size/max size.
          multiplier = get_HVAC_multiplier( materialLookup, materialSize )
          hvac_materials = materials_hvac.select {|data|
            data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Size'].to_f >= materialSize.to_f / multiplier.to_f
          }
          if hvac_materials.size == 0
            puts "HVAC material error! Could not find next largest size for #{name} in #{materials_hvac}"
            raise
          elsif hvac_materials.size == 1
            hvac_material = hvac_materials[0]
          else
            hvac_material = hvac_materials.min_by{|data| data['Size'].to_f}
          end
        end
      end
    end
    # Create the return hash.
    costDBInfo = {
      name: name,
      hvac_material: hvac_material,
      multiplier: multiplier
    }
    return costDBInfo
  end


  def getCost(materialType, materialHash, multiplier)
    material_cost = 0.0 ; labour_cost = 0.0
    costing_data = @costing_database['costs'].detect do |data|
      data['id'].to_s.upcase == materialHash['id'].to_s.upcase
    end
    if costing_data.nil?
      puts "HVAC #{materialType} with id #{materialHash['id']} not found in the costing database. Skipping."
      raise
    else
      # Get cost information from lookup.
      # Adjust for material and labour multiplier in costing spreadsheet 'materials_hvac' sheet 'material_mult' and
      # 'labour_mult' columns.
      (materialHash['material_mult'].nil?) || (materialHash['material_mult'].empty?) ? mat_mult = 1.0 : mat_mult = materialHash['material_mult'].to_f
      (materialHash['labour_mult'].nil?) || (materialHash['labour_mult'].empty?) ? lab_mult = 1.0 : lab_mult = materialHash['labour_mult'].to_f
      material_cost = costing_data['baseCosts']['materialOpCost'].to_f * multiplier * mat_mult
      labour_cost = costing_data['baseCosts']['laborOpCost'].to_f * multiplier * lab_mult
    end
    return material_cost, labour_cost
  end

  def getGeometryData(model, prototype_creator)
    num_of_above_ground_stories = model.getBuilding.standardsNumberOfAboveGroundStories.to_i
    space_mod = OpenstudioStandards::Space
    if model.building.get.nominalFloortoFloorHeight().empty?
      volume = model.building.get.airVolume()
      flrArea = 0.0
      if model.building.get.conditionedFloorArea.empty?
        model.getThermalZonesSorted.each do |tz|
          tz.spaces.sort.each do |tz_space|
            flrArea += tz_space.floorArea.to_f if ( (space_mod.space_cooled?(tz_space)) || (space_mod.space_heated?(tz_space)) )
          end
          flrArea += tz.floorArea
        end
      else
        flrArea = model.building.get.conditionedFloorArea().get
      end
      nominal_flr2flr_height = 0.0
      nominal_flr2flr_height = volume / flrArea unless flrArea <= 0.01
    else
      nominal_flr2flr_height = model.building.get.nominalFloortoFloorHeight.get
    end

    # Location of mechanical room and utility distances for use below (space_centroid is an array
    # in mech_room hash containing the x,y and z coordinates of space centroid). Utility distance
    # uses the distance from the mech room centroid to the perimeter of the building.
    mech_room, cond_spaces = prototype_creator.find_mech_room(model)
    mech_room_story = nil
    target_cent = [mech_room['space_centroid'][0], mech_room['space_centroid'][1]]
    found = false
    model.getBuildingStorys.sort.each do |story|
      story.spaces.sort.each do |space|
        if space.nameString == mech_room['space_name']
          mech_room_story = story
          found = true
          break
        end
      end
      break if found
    end
    distance_info_hash = get_story_cent_to_edge( building_story: mech_room_story, prototype_creator: prototype_creator,
                                                 target_cent: target_cent, full_length: false )
    horizontal_dist = distance_info_hash[:start_point][:line][:dist]  # in metres

    ht_roof = 0.0
    util_dist = 0.0
    mechRmInBsmt = false
    if mech_room['space_centroid'][2] < 0
      # Mechanical room is in the basement (z dimension is negative).
      mechRmInBsmt = true
      ht_roof = (num_of_above_ground_stories + 1) * nominal_flr2flr_height
      util_dist = nominal_flr2flr_height + horizontal_dist
    elsif mech_room['space_centroid'][2] == 0
      # Mech room on ground floor
      ht_roof = num_of_above_ground_stories * nominal_flr2flr_height
      util_dist = horizontal_dist
    else
      # Mech room on some other floor
      ht_roof = (num_of_above_ground_stories - (mech_room['space_centroid'][2]/nominal_flr2flr_height).round(0)) * nominal_flr2flr_height
      util_dist = ht_roof + horizontal_dist
    end

    util_dist = OpenStudio.convert(util_dist,"m","ft").get
    nominal_flr2flr_height = OpenStudio.convert(nominal_flr2flr_height,"m","ft").get
    ht_roof = OpenStudio.convert(ht_roof,"m","ft").get
    horizontal_dist = OpenStudio.convert(horizontal_dist,"m","ft").get

    return util_dist, ht_roof, nominal_flr2flr_height, horizontal_dist, num_of_above_ground_stories, mechRmInBsmt
  end

  # --------------------------------------------------------------------------------------------------
  # This function gets all costs associated zonal heating and cooling systems
  # (i.e., zonal units, pumps, flues & utility costs)
  # --------------------------------------------------------------------------------------------------
  def zonalsys_costing(model, prototype_creator, mech_room, cond_spaces)

    totalCost = 0.0

    # Get regional cost factors for this province and city
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s == "GasBoilers"}.first  # Get any row from spreadsheet in case of region error
    regional_material, regional_installation =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Get regional electric cost factors for this province and city
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s.upcase == "BOX" && data['Size'].to_i == 1}.first
    reg_mat_elec, reg_lab_elec =
      get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)

    # Store some geometry data for use below...
    util_dist, ht_roof, nom_flr_hght, horz_dist, numAGFlrs, mechRmInBsmt = getGeometryData(model, prototype_creator)

    template_type = prototype_creator.template

    zone_loop_info = {}
    zone_loop_info[:zonesys] = []
    numZones = 0; floorNumber = 0
    vrfSystemFloors = {
      maxCeil: -9999999999999,
      lowCeil: 9999999999999,
      vrfFloors: []
    }

    model.getThermalZonesSorted.each do |zone|
      numZones += 1
      zone.equipment.each do |equipment|
        obj_type = equipment.iddObjectType.valueName.to_s
        if equipment.to_ZoneHVACComponent.is_initialized
          # This is a zonal HVAC component
          zone_info = {}
          zone_loop_info[:zonesys] << zone_info

          # Get floor number from zone name string using regexp (Flr-N, where N is the storey number)
          zone_info[:zonename] = zone.name.get
          zone_info[:zonename].scan(/.*Flr-(\d+).*/) {|num| zone_info[:flrnum] = num[0].to_i}

          unless zone.isConditioned.empty?
            zone_info[:is_conditioned] = zone.isConditioned.get
          else
            zone_info[:is_conditioned] = 'N/A'
            puts "Warning: zone.isConditioned is empty for #{zone.name.get}!"
          end

          zone_info[:multiplier] = zone.multiplier

          # Get the zone ceiling height value from the sql file...
          query = "SELECT CeilingHeight FROM Zones WHERE ZoneName='#{zone_info[:zonename].upcase}'"
          ceilHeight = model.sqlFile().get().execAndReturnFirstDouble(query)
          zone_info[:ceilingheight] = OpenStudio.convert(ceilHeight.to_f,"m","ft").get  # feet

          zone_info[:heatcost] = 0.0
          zone_info[:coolcost] = 0.0
          zone_info[:heatcoolcost] = 0.0
          zone_info[:pipingcost] = 0.0
          zone_info[:wiringcost] = 0.0
          zone_info[:multiplier] = zone.multiplier
          zone_info[:sysname] = equipment.name.get

          # Get the heat capacity values from the sql file - ZoneSizes table...
          query = "SELECT UserDesLoad FROM ZoneSizes WHERE ZoneName='#{zone_info[:zonename].upcase}' AND LoadType='Heating'"
          heatCapVal = model.sqlFile().get().execAndReturnFirstDouble(query)
          zone_info[:heatcapacity] = heatCapVal.to_f / 1000.0 # Watts -> kW

          component = equipment.to_ZoneHVACComponent.get
          if component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
            heating_coil_name = component.to_ZoneHVACPackagedTerminalAirConditioner.get.heatingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{heating_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:heatcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
            cooling_coil_name = component.to_ZoneHVACPackagedTerminalAirConditioner.get.coolingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{cooling_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:coolcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
          elsif component.to_ZoneHVACFourPipeFanCoil.is_initialized # 2PFC & 4PFC
            heating_coil_name = component.to_ZoneHVACFourPipeFanCoil.get.heatingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{heating_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:heatcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
            cooling_coil_name = component.to_ZoneHVACFourPipeFanCoil.get.coolingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{cooling_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:coolcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
          elsif component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
            heating_coil_name = component.to_ZoneHVACPackagedTerminalHeatPump.get.heatingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{heating_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:heatcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
            cooling_coil_name = component.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil.name.to_s
            query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' AND RowName='#{cooling_coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
            zone_info[:coolcapacity] = model.sqlFile.get.execAndReturnFirstDouble(query).to_f/1000.0
          elsif component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
            # Use separate method to get zonal VRF system info
            zonalSys = component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
            vrfSystemFloors = getZonalVRFInfo(zone: zone, model: model, prototype_creator: prototype_creator, zonalSys: zonalSys, vrfSystemFloors: vrfSystemFloors, regMat: regional_material, regLab: regional_installation, numZones: numZones)
            # When done, go to the next piece of equipment.  Will do VRF costing once all thermal zones are
            # investigated.
            next
          else
            cooling_coil_name = 'nil'
          end

          unless (obj_type.to_s == 'OS_ZoneHVAC_FourPipeFanCoil') || (obj_type.to_s == 'OS_ZoneHVAC_PackagedTerminalHeatPump') || (obj_type.to_s == 'OS_ZoneHVAC_PackagedTerminalAirConditioner')
            # Get the cooling total capacity (sen+lat) value from the sql file - ComponentSizes table
            query = "SELECT Value FROM ComponentSizes WHERE CompName='#{cooling_coil_name.upcase}' AND Units='W'"
            coolCapVal = model.sqlFile().get().execAndReturnFirstDouble(query)
            zone_info[:coolcapacity] = coolCapVal.to_f / 1000.0 # Watts -> kW
          end

          if (zone_info[:sysname] =~ /Baseboard Convective Water/i) or (zone_info[:sysname] =~ /BaseboardConvectiveWater/i)
            zone_info[:systype] = 'HW'
            # HW convector length based on 0.425 kW/foot
            if zone_info[:heatcapacity] > 0
              heatCapacity = zone_info[:heatcapacity] / zone.multiplier
              convLength = (heatCapacity / 0.425).round(0)
              # HW convector 1" copper core pipe cost
              matCost, labCost = getHVACCost(zone_info[:sysname], 'ConvectCopper', 1.25, true)
              convPipeCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * convLength
              # For each convector there will be a shut-off valve, 2 Tee connections and 2 elbows to
              # isolate the convector from the hot water loop distribution for servicing and balancing.
              # Hot water convectors are manufactured in maximum 8 ft lengths, therefore the number of
              # convectors per thermal zone is (rounded up to nearest integer):
              ratio = (convLength.to_f / 8.0).to_f
              numConvectors = (ratio - ratio.to_i) > 0.10 ? (ratio + 0.5).round(0) : ratio
              # Cost of valves:
              matCost, labCost = getHVACCost('1.25 inch gate valve', 'ValvesGate', 1.25, true)
              convValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * numConvectors
              # Cost of tees:
              matCost, labCost = getHVACCost('1.25 inch copper tees', 'CopperPipeTee', 1.25, true)
              convTeesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numConvectors
              # Cost of elbows:
              matCost, labCost = getHVACCost('1.25 inch copper elbows', 'CopperPipeElbow', 1.25, true)
              convElbowsCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numConvectors
              # Total convector cost for this zone (excluding distribution piping):
              convCost = (convPipeCost + convValvesCost + convTeesCost + convElbowsCost) * zone.multiplier
              zone_info[:heatcost] = convCost
              zone_info[:num_units] = numConvectors

              # Single pipe supply and return
              perimPipingCost = getPerimDistPipingCost(zone, nom_flr_hght, regional_material, regional_installation)
              zone_info[:pipingcost] = perimPipingCost

              totalCost += convCost + perimPipingCost
            end

          elsif (zone_info[:sysname]=~ /Baseboard Convective Electric/i) or (zone_info[:sysname]=~ /BaseboardConvectiveElectric/i)
            zone_info[:systype] = 'BB'
            # BB number based on 0.935 kW/unit
            if zone_info[:heatcapacity] > 0
              heatCapacity = zone_info[:heatcapacity] / zone.multiplier
              ratio = (heatCapacity / 0.935).to_f
              numConvectors = (ratio - ratio.to_i) > 0.10 ? (ratio + 0.5).round(0) : ratio
              # BB electric convector unit cost (Just one in sheet)
              matCost, labCost = getHVACCost(zone_info[:sysname], 'ElectricBaseboard', 'nil', true)
              elecBBCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * numConvectors
              # For each baseboard there will be an electrical junction box
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numConvectors
              # Total electric basbeboard cost for this zone:
              elecConvCost = (elecBBCost + elecBoxCost) * zone.multiplier
              zone_info[:heatcost] = elecConvCost
              zone_info[:num_units] = numConvectors

              perimWiringCost = getPerimDistWiringCost(zone, nom_flr_hght, reg_mat_elec, reg_lab_elec)
              zone_info[:wiringcost] = perimWiringCost

              totalCost += elecConvCost + perimWiringCost
            end

          elsif (zone_info[:sysname] =~ /PTAC/i) || (obj_type.to_s == 'OS_ZoneHVAC_PackagedTerminalAirConditioner')
            zone_info[:systype] = 'PTAC'
            # Heating cost of PTAC is handled by Baseboard Convective Electric Heater entry in Equipment list!
            # Cooling cost of PTAC ...
            if zone_info[:coolcapacity] > 0
              # DX cooling unit
              coolCapacity = zone_info[:coolcapacity] / zone.multiplier
              numUnits = get_HVAC_multiplier('PTAC', coolCapacity)
              # PTAC unit cost (Note that same numUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'PTAC', coolCapacity, false)
              thePTACUnitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each PTAC unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
              # Total PTAC cost for this zone (excluding distribution piping):
              thePTACCost = (thePTACUnitCost + elecBoxCost) * zone.multiplier
              zone_info[:coolcost] = thePTACCost
              zone_info[:num_units] = numUnits

              perimWiringCost = getPerimDistWiringCost(zone, nom_flr_hght, reg_mat_elec, reg_lab_elec)
              zone_info[:wiringcost] = perimWiringCost

              totalCost += thePTACCost + perimWiringCost
            end

          elsif (zone_info[:sysname] =~ /PTHP/i) || (obj_type.to_s =~ /OS_ZoneHVAC_PackagedTerminalHeatPump/)
            zone_info[:systype] = 'HP'
            # Cost of PTAC based on heating capacity...
            if zone_info[:heatcapacity] > 0
              # DX heat pump unit
              capacityHPUnit = zone_info[:coolcapacity] > zone_info[:heatcapacity] ?
                                 zone_info[:coolcapacity] / zone.multiplier : zone_info[:heatcapacity] / zone.multiplier
              numUnits = get_HVAC_multiplier('ashp', capacityHPUnit)
              # HP unit cost (Note that same numUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'ashp', capacityHPUnit, false)
              theHPUnitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each HP unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
              # Total HP cost for this zone (excluding distribution piping):
              theHPCost = (theHPUnitCost + elecBoxCost) * zone.multiplier
              zone_info[:heatcoolcost] = theHPUnitCost
              zone_info[:num_units] = numUnits

              perimWiringCost = getPerimDistWiringCost(zone, nom_flr_hght, reg_mat_elec, reg_lab_elec)
              zone_info[:wiringcost] = perimWiringCost

              totalCost += theHPCost + perimWiringCost
            end

          elsif zone_info[:sysname] =~ /2-pipe Fan Coil/i
            zone_info[:sfurnaceystype] = '2FC'
            if zone_info[:heatcapacity] > 0 || zone_info[:coolcapacity] > 0
              # Hot water heating and chilled water cooling type fan coil unit
              capacityFCUnit = zone_info[:coolcapacity] > zone_info[:heatcapacity] ?
                               zone_info[:coolcapacity] / zone.multiplier : zone_info[:heatcapacity] / zone.multiplier
              numFCUnits = get_HVAC_multiplier('FanCoilHtgClgVent', capacityFCUnit)
              # 2PFC unit cost (Note that same numFCUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'FanCoilHtgClgVent', capacityFCUnit, false)
              fcUnitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each 2PFC unit there will be a shut-off valve, 2 Tee connections and 2 elbows to
              # isolate the convector from the hot water loop distribution for servicing and balancing.
              # Assumed unit piping is 1.25 inches in diameter.
              # Cost of valves:
              matCost, labCost = getHVACCost('1.25 inch gate valve', 'ValvesGate', 1.25, true)
              fcValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * numFCUnits
              # Cost of tees:
              matCost, labCost = getHVACCost('1.25 inch copper tees', 'CopperPipeTee', 1.25, true)
              fcTeesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numFCUnits
              # Cost of elbows:
              matCost, labCost = getHVACCost('1.25 inch copper elbows', 'CopperPipeElbow', 1.25, true)
              fcElbowsCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numFCUnits
              # For each 2PFC unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numFCUnits
              # Total 2PFC cost for this zone (excluding distribution piping):
              fcCost = (fcUnitCost + fcValvesCost + fcTeesCost + fcElbowsCost + elecBoxCost) * zone.multiplier
              zone_info[:heatcoolcost] = fcCost
              zone_info[:num_units] = numFCUnits

              # Cost for one set supply/return piping
              perimPipingCost = getPerimDistPipingCost(zone, nom_flr_hght, regional_material, regional_installation)
              zone_info[:pipingcost] = perimPipingCost

              perimWiringCost = getPerimDistWiringCost(zone, nom_flr_hght, reg_mat_elec, reg_lab_elec)
              zone_info[:wiringcost] = perimWiringCost

              totalCost += fcCost + perimPipingCost + perimWiringCost
            end

          elsif (zone_info[:sysname] =~ /4-pipe Fan Coil/i) || (obj_type =~ /OS_ZoneHVAC_FourPipeFanCoil/)
            zone_info[:systype] = '4FC'
            if (zone_info[:heatcapacity] > 0) || (zone_info[:coolcapacity] > 0)
              # Hot water heating and chilled water cooling type fan coil unit
              capacityFCUnit = zone_info[:coolcapacity] > zone_info[:heatcapacity] ?
                                   zone_info[:coolcapacity] / zone.multiplier : zone_info[:heatcapacity] / zone.multiplier
              numFCUnits = get_HVAC_multiplier('FanCoilHtgClgVent', capacityFCUnit)
              # 4PFC unit cost (Note that same numFCUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'FanCoilHtgClgVent', capacityFCUnit, false)
              fcUnitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each 4PFC unit there will be 2 shut-off valves, 4 Tee connections and 4 elbows to
              # isolate the convector from the hot water loop distribution for servicing and balancing.
              # Assumed unit piping is 1.25 inches in diameter.
              # Cost of valves:
              matCost, labCost = getHVACCost('1.25 inch gate valve', 'ValvesGate', 1.25, true)
              fcValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numFCUnits
              # Cost of tees:
              matCost, labCost = getHVACCost('1.25 inch copper tees', 'CopperPipeTee', 1.25, true)
              fcTeesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 4 * numFCUnits
              # Cost of elbows:
              matCost, labCost = getHVACCost('1.25 inch copper elbows', 'CopperPipeElbow', 1.25, true)
              fcElbowsCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 4 * numFCUnits
              # For each 4PFC unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numFCUnits
              # Total 4PFC cost for this zone (excluding distribution piping):
              fcCost = (fcUnitCost + fcValvesCost + fcTeesCost + fcElbowsCost + elecBoxCost) * zone.multiplier
              zone_info[:heatcoolcost] = fcCost
              zone_info[:num_units] = numFCUnits

              # Cost for two sets supply/return piping
              perimPipingCost = 2 * getPerimDistPipingCost(zone, nom_flr_hght, regional_material, regional_installation)
              zone_info[:pipingcost] = perimPipingCost

              perimWiringCost = getPerimDistWiringCost(zone, nom_flr_hght, reg_mat_elec, reg_lab_elec)
              zone_info[:wiringcost] = perimWiringCost

              totalCost += fcCost + perimPipingCost + perimWiringCost
            end

          elsif zone_info[:sysname] =~ /Unit Heater/i || zone_info[:sysname] =~ /Unitary/i
            zone_info[:systype] = 'FUR'
            # Two types of unit heaters: electric and gas
            unitHeater = component.to_ZoneHVACUnitHeater.get
            heatCoil = unitHeater.heatingCoil
            if heatCoil.to_CoilHeatingGas.is_initialized   # TODO: Need to test this!
              # The gas unit heaters are cabinet type with a burner and blower rather than the radiant type
              gasCoil = heatCoil.to_CoilHeatingGas.get
              if heatCoil.isNominalCapacityAutosized.to_bool
                zone_info[:heatcapacity] = gasCoil.autosizedNominalCapacity.to_f/1000.0
              else
                zone_info[:heatcapacity] = gasCoil.nominalCapacity.to_f/1000.0
              end
              if zone_info[:heatcapacity] > 0
                heatCapacity = zone_info[:heatcapacity] / zone.multiplier
                numUnits = get_HVAC_multiplier('gasheater', heatCapacity)
                # Unit cost (Note that same unit multiple applied within getHVACCost())
                matCost, labCost = getHVACCost(zone_info[:sysname], 'gasheater', heatCapacity, false)
                unitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
                # For each unit heater there will be an electrical junction box (wiring costed with distribution - not here)
                matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
                elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
                # It is assumed that the gas unit heater(s) are located in the centre of this zone. An 8 in exhaust duct
                # must be costed from the unit heater to the exterior via the roof. The centroid of this zone:
                if zone_info[:flrnum] > 1
                  zoneCentroidToRoof_Ft = 10 + nom_flr_hght * zone_info[:flrnum]
                else
                  zoneCentroidToRoof_Ft = 10
                end
                matCost, labCost = getHVACCost('Unit heater exhaust duct', 'Ductwork-S', 8, true)
                exhaustductCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * zoneCentroidToRoof_Ft
                zone_info[:heatcost] = (unitCost + elecBoxCost + exhaustductCost) * zone.multiplier
                zone_info[:num_units] = numUnits

                # Cost of gas line header for zone. Header is located in the centre of this zone's floor
                mechRmInBsmt ? numFlrs = numAGFlrs + 1 : numFlrs = numAGFlrs
                hdrGasLen = numFlrs * nom_flr_hght
                # Gas line - first one in spreadsheet
                matCost, labCost = getHVACCost('Central header gas line', 'GasLine', '')
                hdrGasLineCost = hdrGasLen * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

                # Cost of gas line from header (centre of flr) to unit heater (centre of zone)
                #centreOfFloor = get_story_cent_to_edge( building_story: zone_info[:flrnum], prototype_creator: prototype_creator, target_cent: target_cent, full_length: false )
                #centreOfSpace = get_space_floor_centroid(space:)
                #gasLineLen = ABS(centreOfFloor - centreOfSpace)

                # Cost of wiring header for zone

                # Cost of wiring from header to unit heater


                totalCost += zone_info[:heatcost] + hdrGasLineCost
              end
            elsif heatCoil.to_CoilHeatingElectric.is_initialized # Electric Unit Heater
              elecCoil = heatCoil.to_CoilHeatingElectric.get
              if elecCoil.isNominalCapacityAutosized.to_bool
                zone_info[:heatcapacity] = elecCoil.autosizedNominalCapacity.to_f/1000.0
              else
                zone_info[:heatcapacity] = elecCoil.nominalCapacity.to_f/1000.0
              end
              if zone_info[:heatcapacity] > 0
                heatCapacity = zone_info[:heatcapacity] / zone.multiplier
                numUnits = get_HVAC_multiplier('elecheat', heatCapacity)
                # Unit cost (Note that same unit multiple applied within getHVACCost())
                matCost, labCost = getHVACCost(zone_info[:sysname], 'elecheat', heatCapacity, false)
                unitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
                # For each unit heater there will be an electrical junction box (wiring costed with distribution - not here)
                matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
                elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
                zone_info[:heatcost] = (unitCost + elecBoxCost) * zone.multiplier
                zone_info[:num_units] = numUnits
                # Cost of wiring to electric unit heater


                totalCost += zone_info[:heatcost]
              end
            elsif heatCoil.to_CoilHeatingWater.is_initialized  # Hot water unit heater
              waterCoil = heatCoil.to_CoilHeatingWater.get
              if waterCoil.isRatedCapacityAutosized.to_bool
                zone_info[:heatcapacity] = waterCoil.autosizedRatedCapacity.to_f/1000.0
              else
                zone_info[:heatcapacity] = waterCoil.ratedCapacity.to_f/1000.0
              end
              if zone_info[:heatcapacity] > 0
                heatCapacity = zone_info[:heatcapacity] / zone.multiplier
                # Max capacity for hot water heater is 75300 Watts
                numUnits = get_HVAC_multiplier('hotwateruh', heatCapacity)
                matCost, labCost = getHVACCost(zone_info[:sysname], 'hotwateruh', heatCapacity, false)
                unitHtrCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
                # For each unit heater there will be a shut-off valve, 2 Tee connections and 2 elbows to
                # isolate the convector from the hot water loop distribution for servicing and balancing.
                # Cost of valves:
                matCost, labCost = getHVACCost('1.25 inch gate valve', 'ValvesGate', 1.25, true)
                unitHtrValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * numUnits
                # Cost of tees:
                matCost, labCost = getHVACCost('1.25 inch copper tees', 'CopperPipeTee', 1.25, true)
                unitHtrTeesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numUnits
                # Cost of elbows:
                matCost, labCost = getHVACCost('1.25 inch copper elbows', 'CopperPipeElbow', 1.25, true)
                unitHtrElbowsCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * 2 * numUnits
                # For each unit heater there will be an electrical junction box (wiring costed with distribution - not here)
                matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
                elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
                # Total convector cost for this zone (excluding distribution piping):
                unitHeaterCost = (unitHtrCost + unitHtrValvesCost + unitHtrTeesCost + unitHtrElbowsCost + elecBoxCost) * zone.multiplier
                zone_info[:heatcost] = unitHeaterCost
                zone_info[:num_units] = numUnits
                # Cost of distribution piping from header to unit heater


                totalCost += unitHeaterCost
              end
            end
          elsif zone_info[:sysname] =~ /WindowAC/i
            zone_info[:systype] = 'WinAC'
            # Cooling cost of WindowAC ...
            if cooling_coil_name == 'nil'
              # The cooling coil name doesn't exist so must use a different method to determine cooling
              # capacity for window AC units!
              query = "SELECT Value FROM ComponentSizes WHERE CompName='WindowAC' AND Units='W'"
              coolCapVal = model.sqlFile().get().execAndReturnFirstDouble(query)
              zone_info[:coolcapacity] = coolCapVal.to_f / 1000.0 # Watts -> kW
            end
            if zone_info[:coolcapacity] > 0
              # DX cooling unit
              coolCapacity = zone_info[:coolcapacity] / zone.multiplier
              numUnits = get_HVAC_multiplier('WINAC', coolCapacity)
              # Window AC unit cost (Note that same numUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'WINAC', coolCapacity, false)
              unitWinACCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each WinAC unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
              # Total WinAC cost for this zone:
              theWinACCost = (unitWinACCost + elecBoxCost) * zone.multiplier
              zone_info[:coolcost] = theWinACCost
              zone_info[:num_units] = numUnits
              totalCost += theWinACCost
            end
          elsif zone_info[:sysname] =~ /Split/i
            zone_info[:systype] = 'MiniSplit'
            # Cooling cost of Mini-split AC ...
            if cooling_coil_name == 'nil'
              # The cooling coil name doesn't exist so must use a different method to determine cooling
              # capacity for mini-spli units!
              query = "SELECT Value FROM ComponentSizes WHERE CompName='WindowAC' AND Units='W'"
              coolCapVal = model.sqlFile().get().execAndReturnFirstDouble(query)
              zone_info[:coolcapacity] = coolCapVal.to_f / 1000.0 # Watts -> kW
            end
            if zone_info[:coolcapacity] > 0
              # Mini-splt cooling unit
              coolCapacity = zone_info[:coolcapacity] / zone.multiplier
              numUnits = get_HVAC_multiplier('SplitSZWall', coolCapacity)
              # PTAC unit cost (Note that same numUnits multiple applied within getHVACCost())
              matCost, labCost = getHVACCost(zone_info[:sysname], 'PTAC', coolCapacity, false)
              theMiniSplitUnitCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
              # For each PTAC unit there will be an electrical junction box (wiring costed with distribution - not here)
              matCost, labCost = getHVACCost('Electrical Outlet Box', 'Box', 1, true)
              elecBoxCost = (matCost * reg_mat_elec / 100.0 + labCost * reg_lab_elec / 100.0) * numUnits
              # Total PTAC cost for this zone (excluding distribution piping):
              theMiniSplitCost = (theMiniSplitUnitCost + elecBoxCost) * zone.multiplier
              zone_info[:coolcost] = theMiniSplitCost
              zone_info[:num_units] = numUnits
              totalCost += theMiniSplitCost
            end

          end
          # Add information to zonal costing report.
          @costing_report['heating_and_cooling']['zonal_systems'] << {
            'systype' => zone_info[:systype],
            'zone_number' => numZones,
            'zone_name' => zone_info[:zonename],
            'zone_multiple' => zone_info[:multiplier],
            'heat_capacity(kW)' => zone_info[:heatcapacity].round(1),
            'cool_capacity(kW)' => zone_info[:coolcapacity].round(1),
            'heat_cost' => zone_info[:heatcost].round(0),
            'cool_cost' => zone_info[:coolcost].round(0),
            'heatcool_cost' => zone_info[:heatcoolcost].round(0),
            'piping_cost' => zone_info[:pipingcost].round(0),
            'wiring_cost' => zone_info[:wiringcost].round(0),
            'num_units' => zone_info[:num_units],
            'cummultive_zonal_cost' => totalCost.round(0)
          }
        end # End of check of check of if zonal equipment exists
      end # End of equipment loop
    end # End of zone loop

    # Get cost of zonal vrf systems
    unless vrfSystemFloors[:vrfFloors].empty?
      totalCost += getZonalVRFCosting(vrfSystemFloors: vrfSystemFloors, model: model, prototype_creator: prototype_creator, regMat: regional_material, regLab: regional_installation, cumulCost: totalCost)
    end
    puts "\nZonal systems costing data successfully generated. Total zonal systems costs: $#{totalCost.round(0)}"

    return totalCost
  end

  def getHeaderPipingDistributionCost(numAGFlrs, mechRmInBsmt, regional_material, regional_installation, reg_elec_mat, reg_elec_inst, pumpFlow, horz_dist, nom_flr_hght)
    # Hot water central header piping distribution costs. Note that the piping distribution cost
    # of zone piping is done in the zonalsys_costing function

    # Central header piping Cost
    supHdrCost = 0; retHdrCost = 0
    mechRmInBsmt ? numFlrs = numAGFlrs + 1 : numFlrs = numAGFlrs
    if numFlrs < 3
      # Header pipe is same diameter as distribution pipes to zone floors
      supHdrLen = numFlrs * nom_flr_hght

      # 1.25 inch Steel pipe
      matCost, labCost = getHVACCost('Header 1.25 inch steel pipe', 'SteelPipe', 1.25)
      supHdrpipingCost = supHdrLen * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1.25 inch Steel pipe insulation
      matCost, labCost = getHVACCost('Header 1.25 inch pipe insulation', 'PipeInsulation', 1.25)
      supHdrInsulCost = supHdrLen * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1.25 inch gate valves
      matCost, labCost = getHVACCost('Header 1.25 inch gate valves', 'ValvesGate', 1.25)
      supHdrValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1.25 inch tee
      matCost, labCost = getHVACCost('Header 1.25 inch steel tee', 'SteelPipeTee', 1.25)
      supHdrTeeCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      supHdrCost = supHdrpipingCost + supHdrInsulCost + supHdrValvesCost + supHdrTeeCost
      retHdrCost = supHdrCost
    else  # Greater than 3 floors (including basement)
      # Use pumpFlow to determine pipe size
      if pumpFlow <= 0.0001262
        hdrPipeSize = 0.5
      elsif pumpFlow > 0.0001262 && pumpFlow <= 0.0002524
        hdrPipeSize = 0.75
      elsif pumpFlow > 0.0002524 && pumpFlow <= 0.0005047
        hdrPipeSize = 1.0
      elsif pumpFlow > 0.0005047 && pumpFlow <= 0.0010090
        hdrPipeSize = 1.25
      elsif pumpFlow > 0.0010090 && pumpFlow <= 0.0015773
        hdrPipeSize = 1.5
      elsif pumpFlow > 0.0015773 && pumpFlow <= 0.0031545
        hdrPipeSize = 2.0
      elsif pumpFlow > 0.0031545
        hdrPipeSize = 2.5
      end

      hdrPipeLen = horz_dist + nom_flr_hght * numFlrs

      # Steel pipe
      matCost, labCost = getHVACCost("Header Steel Pipe - #{hdrPipeSize} inch", 'SteelPipe', hdrPipeSize)
      supHdrpipingCost = hdrPipeLen * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # Steel pipe insulation
      matCost, labCost = getHVACCost("Header Pipe Insulation - #{hdrPipeSize} inch", 'PipeInsulation', hdrPipeSize)
      supHdrInsulCost = hdrPipeLen * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # Gate valves
      matCost, labCost = getHVACCost("Header Gate Valves - #{hdrPipeSize} inch", 'ValvesGate', hdrPipeSize)
      supHdrValvesCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # Tee
      matCost, labCost = getHVACCost("Header Steel Tee - #{hdrPipeSize} inch", 'SteelPipeTee', hdrPipeSize)
      supHdrTeeCost = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      supHdrCost = supHdrpipingCost + supHdrInsulCost + supHdrValvesCost + supHdrTeeCost
      retHdrCost = supHdrCost
    end

    hdrPipeCost = supHdrCost + retHdrCost

    # Electrical header costs. Central electric header cost for zonal heatingunits
    hdrLen = numFlrs * nom_flr_hght

    # Conduit - only one spreadsheet entry
    matCost, labCost = getHVACCost('Header Metal conduit', 'Conduit', '')
    hdrConduitCost = hdrLen * (matCost * reg_elec_mat / 100.0 + labCost * reg_elec_inst / 100.0)

    # Wiring - size 10
    matCost, labCost = getHVACCost('Header No 10 Wiring', 'Wiring', 10)
    hdrWireCost = hdrLen / 100 * (matCost * reg_elec_mat / 100.0 + labCost * reg_elec_inst / 100.0)

    # Box - size 4
    matCost, labCost = getHVACCost('Header 4 inch deep Box', 'Box', 4)
    hdrBoxCost = numFlrs * (matCost * reg_elec_mat / 100.0 + labCost * reg_elec_inst / 100.0)

    elecHdrCost = hdrConduitCost + hdrWireCost + hdrBoxCost

    # Central gas header cost will be determined in zonalsys_costing function since
    # this cost depends on existence of at least one gas-fired unit heater in building.

    hdrDistributionCost = hdrPipeCost + elecHdrCost

    return hdrDistributionCost
  end

  def getPerimDistPipingCost(zone, nom_flr_hght, regional_material, regional_installation)
    # Get perimeter distribution piping cost
    extWallArea = 0.0
    perimPipingCost = 0.0
    zone.getSpacesSorted.each do |space|
      if space.spaceType.empty? or space.spaceType.get.standardsSpaceType.empty? or space.spaceType.get.standardsBuildingType.empty?
        raise ("standards Space type and building type is not defined for space:#{space.name.get}. Skipping this space for costing.")
      end
      extWallArea += OpenStudio.convert(space.exteriorWallArea.to_f,"m^2","ft^2").get  # sq.ft.
    end
    perimTotal = ( extWallArea / nom_flr_hght ) * zone.multiplier

    # 1.25 inch Steel pipe
    matCost, labCost = getHVACCost('Perimeter Distribution - 1.25 inch steel pipe', 'SteelPipe', 1.25)
    perimPipingCost = perimTotal * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

    # 1.25 inch Steel pipe insulation
    matCost, labCost = getHVACCost('Perimeter Distribution - 1.25 inch pipe insulation', 'PipeInsulation', 1.25)
    perimPipingCost += perimTotal * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

    return perimPipingCost
  end

  def getPerimDistWiringCost(zone, nom_flr_hght, regional_material, regional_installation)
    # Get perimeter distribution wiring cost
    extWallArea = 0.0
    perimWiringCost = 0.0
    zone.getSpacesSorted.each do |space|
      if space.spaceType.empty? or space.spaceType.get.standardsSpaceType.empty? or space.spaceType.get.standardsBuildingType.empty?
        raise ("standards Space type and building type is not defined for space:#{space.name.get}. Skipping this space for costing.")
      end
      extWallArea += OpenStudio.convert(space.exteriorWallArea.to_f,"m^2","ft^2").get  # sq.ft.
    end
    perimTotal = ( extWallArea / nom_flr_hght ) * zone.multiplier

    # Conduit - only one spreadsheet entry
    matCost, labCost = getHVACCost('Perimeter Distribution - Metal conduit', 'Conduit', '')
    perimWiringCost = perimTotal * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

    # Wiring - size 10
    matCost, labCost = getHVACCost('Perimeter Distribution - No 10 Wiring', 'Wiring', 10)
    perimWiringCost += perimTotal / 100 * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

    return perimWiringCost
  end

  # Get information on Zonal VRF System in a Thermal Zone
  def getZonalVRFInfo(zone:, model:, prototype_creator:, zonalSys:, vrfSystemFloors:, regMat:, regLab:, numZones:)
    #Get heating and cooling coil objects
    heatingCoil = zonalSys.heatingCoil.get.to_CoilHeatingDXVariableRefrigerantFlow.get
    coolingCoil = zonalSys.coolingCoil.get.to_CoilCoolingDXVariableRefrigerantFlow.get

    # Get heating capacity
    if heatingCoil.isRatedTotalHeatingCapacityAutosized.to_bool
      heatingCapkW = heatingCoil.autosizedRatedTotalHeatingCapacity.to_f/1000.0
    else
      heatingCapkW = (heatingCoil.ratedTotalHeatingCapacity).to_f/1000.0
    end

    # Get cooling capacity
    if coolingCoil.isRatedTotalCoolingCapacityAutosized.to_bool
      coolingCapkW = coolingCoil.autosizedRatedTotalCoolingCapacity.to_f/1000.0
    else
      coolingCapkW = coolingCoil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f/1000.0
    end

    # Get the multiplier for the thermal zone
    zoneMult = zone.multiplier

    # Set capacity to the highest of the heating or cooling capacity and adjust for the thermal zone multiplier
    heatingCapkW >= coolingCapkW ? totalCapkW = heatingCapkW/zoneMult : totalCapkW = coolingCapkW/zoneMult

    # Get the thermal zone (TZ) and collect information on:
    # The TZ name.
    # The TZ capacity.
    # The spaces associated with the TZ.
    # The floors the spaces occupy.
    # The total ceiling area and floor area for each floor the spaces occupy.
    # The centroid of all of the spaces on a given floor (this may be outside of the spaces for some geometries)
    # The building story names and objects associated with a thermal zone.
    # the ceiling and floor area of the spaces associated with it for each floor they occupy
    # The capacity of the TZ on a given floor (calculated at total capacity * floor area of TZ spaces on floor/total TZ floor area)
    # The VRF ceiling mounts required and associated cost
    # The VRF system controllers cost
    tzFloorsInfo = prototype_creator.thermal_zone_get_centroid_per_floor(zone)
    tzFloorsInfo.each do |tzFloor|
      tzStoryFloorArea_m2 = 0
      tzSpaceMults = []
      tzFloor[:spaces].each do |tz_space|
        tzStoryFloorArea_m2 += tz_space.floorArea.to_f
        tzSpaceMults << tz_space.multiplier.to_f
      end
      tzFloorCapkW = totalCapkW * tzStoryFloorArea_m2 / zone.floorArea.to_f
      # Get the VRF Ceiling mount information and cost
      vrfCeilMountInfo = getHVACDBInfo(name: "VRF Ceiling Mount", materialLookup: "VRF-CeilingMount", materialSize: tzFloorCapkW, exactMatch: false)
      # Get VRF Ceiling mount cost.
      material, labour = getCost(vrfCeilMountInfo[:name], vrfCeilMountInfo[:hvac_material], vrfCeilMountInfo[:multiplier])
      # The multiplier (number of units required to meet the demand) is already included in the material and labour cost.
      vrfCeilMountCost = (material*regMat + labour*regLab) / 100.0
      # Get the VRF System Controller Cost (for 1 controller)
      material, labour = getHVACCost("VRF System Controller", 'VRF-Sys-Controller', nil, true)
      # Since material and labour are for 1 controller the multiplier is added here.
      vrfSysContCost = (material * regMat + labour * regLab) * vrfCeilMountInfo[:multiplier] / 100.0

      # Put the thermal zone information for the floor into a hash.
      tzFloorInfo = {
        tzName: zone.name.to_s,
        tzNum: numZones,
        tzFloorName: tzFloor[:story_name],
        tzFloorCeilingAream2: tzFloor[:ceiling_area],
        tzMult: zoneMult,
        tzSpaces: tzFloor[:spaces],
        tzSpaceMults: tzSpaceMults,
        tzFloorArea_m2: tzStoryFloorArea_m2,
        tzFloorCapkW: tzFloorCapkW,
        tzCentroid: tzFloor[:centroid],
        vrfCeilMountInfo: vrfCeilMountInfo,
        vrfCeilMountCost: vrfCeilMountCost,
        vrfSysContCost: vrfSysContCost
      }

      # Add the TZ information for the floor to a hash containing all of the thermal zones.
      vrfSystemFloors = compileZonalVRFFloors(vrfSystemFloors: vrfSystemFloors, tzFloor: tzFloorInfo)
    end
    return vrfSystemFloors
  end

  # Cost zonal VRF systems including zone equipment (ceiling units and associated tubing and wiring), floor equipment (
  # branch distributor on each floor), VRF system condenser (assumed one on rooftop and another every 50m), and piping
  # and wiring linking the branch distributors to one another and to the condensers.
  #
  # Takes in:
  # vrfSystemFloors = {
  #         maxCeil(float):  The height of the thermal zone served by a VRF system with the highest ceiling in the
  #                          building.  This is referenced to the global origin for the building.  The units are m.
  #         lowCeil(float):  The height of the thermal zone served by a VRF system with the lowest ceiling in the
  #                          building.  This is referenced to the global origin for the building.  The units are m.
  #         vrfFloors(array):  [
  #           storyName(string):  Name of the current floor (story).
  #           buildStoryObj(Obj):  The OpenStudio object associated with the current floor (story).
  #           floorAream2:  Total floor area (m2) of thermal zones on the current floor served by VRF systems.  Does not
  #                         include multipliers.
  #           floorCeillingAream2:  The Total ceiling area (m2) of thermal zones on the current floor served by VRF
  #                                 systems.  Does not include multipliers.
  #           floorTZs(array):  An array containing each tzFloor hash described above for the current floor.
  #
  #         ]
  #       }
  # model(hash):  OpenStudio building model.
  # prototype_creator(object):  OpenStudio-Standards object for whichever version of NECB was used to create the model.
  # regMat(float):  HVAC regional cost factor for materiel.
  # regLab(float):  HVAC regional cost factor for labour.
  # cumulCost(float):  Cumulative zonal system cost.
  #
  # Output(float):  Total cost for VRF system.  Also adds information to @costing_report for condenser(s), VRF zonal
  #                 systems, and branch distributors.
  def getZonalVRFCosting(vrfSystemFloors:, model:, prototype_creator:, regMat:, regLab:, cumulCost:)
    # Include empty array in costing report for branch distributor costs on each floor
    @costing_report['heating_and_cooling']['floor_systems'] = []
    total_cost = 0
    vrfWireInfo = getHVACDBInfo(name: "VRF Wiring", materialLookup: "wiring", materialSize: 10, exactMatch: true)
    regMatElec, regLabElec = get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], vrfWireInfo[:hvac_material])

    # Find the center of the highest roof
    roof_cent_info = prototype_creator.find_highest_roof_centre(model)
    roof_cent = roof_cent_info[:roof_centroid]
    # Find the distance between the highest roof and the ceiling of the lowest space served by a VRF system
    maxHeightDiff = (roof_cent[2] - vrfSystemFloors[:lowCeil]).to_f.round(8)
    # Find the roof height for the condenensate line cost.  If the maxHeightDiff includes basement spaces use it,
    # otherwise use the height of the roof.
    maxHeightDiff > roof_cent[2].to_f.round(8) ? roofHeight = maxHeightDiff : roofHeight = roof_cent[2].to_f.round(8)
    # Get the condenser cost
    vrfCondenserCost = costVRFCondenser(model: model, maxHeightDiff: maxHeightDiff, regMat: regMat, regLab: regLab, regMatElec: regMatElec, regLabElec:regLabElec, roofHeight: roofHeight)
    total_cost += vrfCondenserCost
    vrfSystemFloors[:vrfFloors].each do |currFloor|
      vrfDistWallInfo = getWallWithLargestArea(currFloor: currFloor)
      vrfDistWallCent = vrfDistWallInfo[:wallCent]
      totalFloorCapkW = 0
      totalFloorCeilUnits = 0
      floorMults = []
      currFloor[:floorTZs].each do |floorTZ|
        zoneWallLengthm = (vrfDistWallCent[0] - floorTZ[:tzCentroid][0]).abs + (vrfDistWallCent[1] - floorTZ[:tzCentroid][1]).abs
        zoneWallLengthft = (OpenStudio.convert(zoneWallLengthm, 'm', 'ft').get)
        elecLength = zoneWallLengthft + 10.0 * (floorTZ[:vrfCeilMountInfo][:multiplier] - 1)

        # Get the zone refrigerant tubing cost (tubing running from the ceiling units to the brancd distributers).  A
        # Size of 50 is used for interior refrigerant tubing while 10 is used for the exterior tubing used between the
        # branch distributors and the condensers.
        zoneRefrigTubingMat, zoneRefrigTubingLab = getHVACCost("VRF Zone Refrigerant Tubing", 'Refrig-tubing', 50, true)
        # Refrigerant tubing comes in 50 ft rolls
        zoneRefrigTubingCost = ((zoneRefrigTubingMat * regMat + zoneRefrigTubingLab * regLab) / 100) * elecLength / 50.0

        # Include condensate line tubing cost
        zoneCondTubingMat, zoneCondTubingLab = getHVACCost('VRF Zone Condensate Line Tubing', 'PEX_tubing', 0.5, true)
        zoneCondTubingCost = ((zoneCondTubingMat * regMat + zoneCondTubingLab * regLab) / 100) * elecLength

        # Include coupler cost for condensate line
        zoneCondCouplingMat, zoneCondCouplingLab = getHVACCost('VRF Zone Condensate Line Couplers', 'PVC_coupling', 0.5, true)
        zoneCondCouplingCost = ((zoneCondCouplingMat * regMat + zoneCondCouplingLab * regLab) / 100) * floorTZ[:vrfCeilMountInfo][:multiplier]

        # Include tee cost for condensate line
        zoneCondTeeMat, zoneCondTeeLab = getHVACCost('VRF Zone Condensate Line Tees', 'PVC_tee', 0.5, true)
        zoneCondTeeCost = ((zoneCondTeeMat * regMat + zoneCondTeeLab * regLab) / 100) * floorTZ[:vrfCeilMountInfo][:multiplier]

        # Total condensate line cost
        zoneCondLineCost = zoneCondTubingCost + zoneCondCouplingCost + zoneCondTeeCost

        # Get the wiring cost
        zoneWiringMat, zoneWiringLab = getCost(vrfWireInfo[:name], vrfWireInfo[:hvac_material], vrfWireInfo[:multiplier])
        zoneWiringCost = ((zoneWiringMat*regMatElec + zoneWiringLab*regLabElec)/100)*elecLength/100

        # Get the conduit cost
        zoneConduitMat, zoneConduitLab = getHVACCost("VRF Zone Conduit", 'Conduit', nil, true)
        zoneConduitCost = ((zoneConduitMat*regMatElec + zoneConduitLab*regLabElec)/100)*elecLength

        # Get the total cost
        totalZoneCost = (zoneRefrigTubingCost + zoneCondLineCost + zoneWiringCost + zoneConduitCost + floorTZ[:vrfCeilMountCost] + floorTZ[:vrfSysContCost])*floorTZ[:tzMult]

        total_cost += totalZoneCost

        cumulCost += total_cost
        # Add zonal cost to report
        @costing_report['heating_and_cooling']['zonal_systems'] << {
          'systype' => 'zonalVRF',
          'zone_number' => floorTZ[:tzNum],
          'zone_name' => floorTZ[:tzName],
          'zone_multiple' => floorTZ[:tzMult],
          'heat_capacity(kW)' => floorTZ[:tzFloorCapkW].round(1),
          'cool_capacity(kW)' => floorTZ[:tzFloorCapkW].round(1),
          'heat_cost' => 0.00,
          'cool_cost' => 0.00,
          'heatcool_cost' => ((floorTZ[:vrfCeilMountCost] + floorTZ[:vrfSysContCost]) * floorTZ[:tzMult]).round(0),
          'piping_cost' => ((zoneRefrigTubingCost + zoneCondLineCost) * floorTZ[:tzMult]).round(0),
          'wiring_cost' => ((zoneWiringCost + zoneConduitCost) * floorTZ[:tzMult]).round(0),
          'num_units' => floorTZ[:vrfCeilMountInfo][:multiplier],
          'cummultive_zonal_cost' => cumulCost.round(0)
        }
        totalFloorCapkW += floorTZ[:tzFloorCapkW]
        totalFloorCeilUnits += floorTZ[:vrfCeilMountInfo][:multiplier]
        # Determine the distribution of thermal zone multipliers on the floor.  For each thermal zone on the floor get
        # the multiplier.  If the same multiplier is already in the arry then add 1 to the number of occurrences of that
        # multiplier.  If the multiplier is not in the array then add the multiplier to the array with an occurrence of
        # one.
        if floorMults.empty?
          floorMults << {
            zoneMult: floorTZ[:tzMult],
            numMults: 1
          }
        else
          numFloorMult = floorMults.select{|data| data[:zoneMult] == floorTZ[:tzMult]}
          if numFloorMult.empty?
            floorMults << {
              zoneMult: floorTZ[:tzMult],
              numMults: 1
            }
          else
            numFloorMult[0][:numMults] += 1
          end
        end
      end
      # Find the number of and type of branch distributors which meet the number of ceiling unit criteria and capacity
      # criteria.  Costing for a separate, smaller, branch distributor may be returned if multiple branch distributors
      # are required to meet the connection or load requirements.  In this case this smaller branch distributor will
      # meet any connection or capacity remaining from the main equipment*(multiplier - 1).  In some cases most of the
      # requirements may be met by the (multiplier - 1)*equipment and a much smaller piece of equipment can be used for
      # the remaining requipments.
      vrfBranchDistInfo, vrfBranchDistInfoRed= getHVACMultiSizeDBInfo(name: 'VRF Branch Distributors', materialLookup: 'VRF-Solenoid', materialCap: totalFloorCapkW, materialCon: totalFloorCeilUnits)
      # Get the branch distributor cost
      vrfBranchDistMat, vrfBranchDistLab = getCost(vrfBranchDistInfo[:name], vrfBranchDistInfo[:hvac_material], vrfBranchDistInfo[:multiplier])
      vrfBranchDistCost = (vrfBranchDistMat*regMat + vrfBranchDistLab*regLab)/100
      # Using the distribution of zone multipliers on the floor find which appears most often.
      initMaxMult = floorMults.max_by{|data| data[:numMults]}
      # If several different zone multipliers appear the same number of times then choose the largest zone multiplier
      floorMultsMatch = floorMults.select{|data| data[:numMults] == initMaxMult[:numMults]}
      if floorMultsMatch.size > 1
        maxMult = floorMultsMatch.max_by{|data| data[:zoneMult]}[:zoneMult]
      else
        maxMult = initMaxMult[:zoneMult]
      end
      # multiply the branch distributer cost by the floor multiplier
      totalVRFBranchDistCost = vrfBranchDistCost*maxMult

      # Add branch distributor cost to report
      @costing_report['heating_and_cooling']['floor_systems'] << {
        'systype' => 'VRFBranchDistributor',
        'floor_name' => currFloor[:storyName],
        'floor_multiple' => maxMult,
        'heat_capacity(kW)' => totalFloorCapkW.round(1),
        'cool_capacity(kW)' => totalFloorCapkW.round(1),
        'num_ceiling_units' => totalFloorCeilUnits,
        'heatcool_cost' => totalVRFBranchDistCost.round(0),
        'num_units' => vrfBranchDistInfo[:multiplier],
        'total_floor_cost' => totalVRFBranchDistCost.round(0)
      }

      total_cost += totalVRFBranchDistCost

      # Check if a smaller piece of equipment was found to meet the requirements remaining after removing the
      # (multiplier-1) requirements.
      unless vrfBranchDistInfoRed.nil?
        # Get the branch distributor cost
        vrfBranchDistRedMat, vrfBranchDistRedLab = getCost(vrfBranchDistInfo[:name], vrfBranchDistInfoRed[:red_ret_hash], 1.0)
        vrfBranchDistRedCost = (vrfBranchDistRedMat*regMat + vrfBranchDistRedLab*regLab)/100

        # multiply the branch distributer cost by the floor multiplier
        totalVRFBranchDistRedCost = vrfBranchDistRedCost*maxMult

        # Add branch distributor cost to report
        @costing_report['heating_and_cooling']['floor_systems'] << {
          'systype' => 'VRFBranchDistributor',
          'floor_name' => currFloor[:storyName],
          'floor_multiple' => maxMult,
          'heat_capacity(kW)' => vrfBranchDistInfoRed[:numCap].to_f.round(1),
          'cool_capacity(kW)' => vrfBranchDistInfoRed[:numCap].to_f.round(1),
          'num_ceiling_units' => vrfBranchDistInfoRed[:numCon].to_f.round(1),
          'heatcool_cost' => totalVRFBranchDistRedCost.round(0),
          'num_units' => 1.0,
          'total_floor_cost' => totalVRFBranchDistRedCost.round(0)
        }
        total_cost += totalVRFBranchDistRedCost
      end
    end
    return total_cost
  end

  # This method takes information about a thermal zone served by a VRF system (tzFloor) and adds it to the collection of
  # thermal zones also served by VRF systems on the same floor.  The ultimate output (once all thermal zones are read)
  # is an array of hashes.  Each entry in the array represents a floor of the building.  Each floor entry contains
  # information about thermal zones served by VRF systems on that floor.
  #
  # The information on the thermal zone served by a VRF system on a given floor is contained in tzFloor.  The overall
  # collection of thermal zone information by floors is contained in vrfSystemFloors.  This method modifies
  # vrfSystemFloors which is why that is an input and output for the method.  Both tzFloor and vrfSystemFloors are
  # described below:
  # Input:
  #       tzFloor = {
  #         tzName(string): Name of the thermal zone.
  #         tzFloorName(string): Name of the floor the thermal zone is on (or if the TZ is on multiple floors the
  #                              name of the current floor being looked at for the thermal zone).
  #         tzFloorCeilingAream2(float): The ceiling area (m2) of the thermal zone on the given floor (this is for the
  #                                      current thermal zone only and does not include multiples).
  #         tzMult(float): The multiplier for the thermal zone (that is the thermal zone is modeled as tzMult number
  #                        of identical thermal zones).
  #         tzSpaces(array): An array containing all of the space objects contained by the thermal zone on the given
  #                          floor.
  #         tzSpaceMults(array): An array containing all of the multipliers for the spaces in tzSpaces (probably all the
  #                              same as tzMult but I added it anyway).
  #         tzFloorArea_m2(float): The floor area (m2) of all of the spaces in the thermal zone on the given floor (this
  #                                is for the current thermal zone only and does not include multiples).
  #         tzFloorCapkW(float): The capacity (kW) of the thermal zone VRF system for the current floor.  It is the
  #                              highest of the heating and cooling capacities for the VRF system.  It dose not include
  #                              multipliers and is only for the current floor.  If the same thermal zone spans multiple
  #                              floors then this is the total copacity for the thermal zone times tzFloorArea_m2
  #                              divided by the total floor area for the thermal zone.
  #         tzCentroid(array):  This is an array containing three items.  These items ore x, y and z coordinates of the
  #                             centroid of the current thermal zone on the current floor referenced to the global
  #                             origin for the building.  The units are in m.  Note that, depending on the shape of the
  #                             thermal zone on the current floor, the centroid may not actually lie in the thermal
  #                             zone (e.g. for an L shaped thermal zone the centroid may be outside the L).
  #         vrfCeilMountInfo(hash): This is a hash containing the costing information, from the costing spreadsheet, for
  #                                 the VRF ceiling mounts serving the thermal zone on the current floor.  It is only
  #                                 for the current floor and does not include tz multipliers.
  #         vrfCeilMountCost(float): The cost of the VRF ceiling mounts serving the thermal zone on the current floor.
  #                                  It is only for the current floor and does not include tz multipliers.
  #         vrfSysContCost: The cost of the VRF system controllers that are associated with each VRF ceiling mount.  It
  #                         is only for the current floor and does not include tz multipliers.
  #       }
  #
  #       vrfSystemFloors = {
  #         maxCeil(float):  The height of the thermal zone served by a VRF system with the highest ceiling in the
  #                          building.  This is referenced to the global origin for the building.  The units are m.
  #         lowCeil(float):  The height of the thermal zone served by a VRF system with the lowest ceiling in the
  #                          building.  This is referenced to the global origin for the building.  The units are m.
  #         vrfFloors(array):  [
  #           storyName(string):  Name of the current floor (story).
  #           buildStoryObj(Obj):  The OpenStudio object associated with the current floor (story).
  #           floorAream2:  Total floor area (m2) of thermal zones on the current floor served by VRF systems.  Does not
  #                         include multipliers.
  #           floorCeillingAream2:  The Total ceiling area (m2) of thermal zones on the current floor served by VRF
  #                                 systems.  Does not include multipliers.
  #           floorTZs(array):  An array containing each tzFloor hash described above for the current floor.
  #
  #         ]
  #       }
  #
  def compileZonalVRFFloors(vrfSystemFloors:, tzFloor:)
    # Check for the highest ceiling and lowest ceiling.
    vrfSystemFloors[:maxCeil] = tzFloor[:tzCentroid][2].to_f if tzFloor[:tzCentroid][2].to_f >= vrfSystemFloors[:maxCeil].to_f
    vrfSystemFloors[:lowCeil] = tzFloor[:tzCentroid][2].to_f if tzFloor[:tzCentroid][2].to_f <= vrfSystemFloors[:lowCeil].to_f
    # If this is the first time vrfSystemFloors has been used add a new floor and enter the information for tzFloor in
    # it.
    if vrfSystemFloors[:vrfFloors].empty?
      vrfSystemFloors[:vrfFloors] << {
        storyName: tzFloor[:tzFloorName],
        buildStoryObj: tzFloor[:tzSpaces][0].buildingStory.get,
        floorAream2: tzFloor[:tzFloorArea_m2],
        floorCeilingAream2: tzFloor[:tzFloorCeilingAream2],
        floorTZs: [tzFloor]
      }
    else
      # If vrfSystemFloors has been used check if the the floor that tzFloor is on has an entry already.
      vrfFloor = vrfSystemFloors[:vrfFloors].select{|sysFloor| sysFloor[:storyName].to_s.upcase == tzFloor[:tzFloorName].to_s.upcase}
      # If no entry has been made for the floor tzFloor is on then add a new floor and include the tzFloor info.
      if vrfFloor.empty?
        vrfSystemFloors[:vrfFloors] << {
          storyName: tzFloor[:tzFloorName],
          buildStoryObj: tzFloor[:tzSpaces][0].buildingStory.get,
          floorAream2: tzFloor[:tzFloorArea_m2],
          floorCeilingAream2: tzFloor[:tzFloorCeilingAream2],
          floorTZs: [tzFloor]
        }
      else
        # If the floor that tzFloor is on has already been made then adjust the floor information to include tzFloor.
        vrfFloor[0][:floorAream2] += tzFloor[:tzFloorArea_m2]
        vrfFloor[0][:floorCeilingAream2] += tzFloor[:tzFloorCeilingAream2]
        vrfFloor[0][:floorTZs] << tzFloor
      end
    end
    return vrfSystemFloors
  end

  # This method finds and returns the outside wall with the largest area on a given building story.  It takes in:
  #         currFloor = {
  #           storyName(string):  Name of the current floor (story).
  #           buildStoryObj(Obj):  The OpenStudio object associated with the current floor (story).
  #           floorAream2:  Total floor area (m2) of thermal zones on the current floor served by VRF systems.  Does not
  #                         include multipliers.
  #           floorCeillingAream2:  The Total ceiling area (m2) of thermal zones on the current floor served by VRF
  #                                 systems.  Does not include multipliers.
  #           floorTZs(array):  An array containing each tzFloor hash described above for the current floor.
  #
  #         }
  # It returns a hash containing the following:
  # wallRetHash = {
  #         largestOutsideWallObj(OS Object):  OpenStudio surface object with the largest gross area that has a 'wall'
  #                                            surface type and an 'Outdoors' outside boundary condition.
  #         wallCentObj(array of floats):  OpenStudio point3d object containing the x, y, z coordinates of the wall above
  #                                  wall's centroid.  In local coordinate system.
  #         wallCentOrigin(array of OS Objects):  Coordinates of the local wall origin in the absolute building
  #                                               coordinate system.
  #         wallCent(array of floats):  Coordinates of the wall's centroid in floats referenced to the building
  #                                     coordinate system.
  # }
  def getWallWithLargestArea(currFloor:)
    outsideWalls = []
    # Get all the spaces associated with the building story
    floorSpaces = currFloor[:buildStoryObj].spaces
    # Cycle through each space associated with the building story.
    floorSpaces.each do |floorSpace|
      # Get the surfaces in the spcae which have a 'Wall' Surface Type and an 'Outdoors' outside boundary condition.
      spaceOutWalls = floorSpace.surfaces.select{|surf| surf.surfaceType.to_s.upcase == 'WALL' && ((surf.outsideBoundaryCondition.to_s.upcase == 'OUTDOORS') || (surf.outsideBoundaryCondition.to_s.upcase == 'GROUND') || (surf.outsideBoundaryCondition.to_s.upcase == 'FOUNDATION'))}
      # Add these surfaces to the array containing outdoor walls.
      spaceOutWalls.each{|outWall| outsideWalls << outWall}
    end
    # Find and return the outside wall object with the largest gross area.
    largestWall = outsideWalls.sort.max_by{|outWall| outWall.grossArea.to_f}
    largestWallSpace = largestWall.space.get
    largestWallSpaceOrigin = [
      largestWallSpace.xOrigin,
      largestWallSpace.yOrigin,
      largestWallSpace.zOrigin
    ]
    wallCentObj = largestWall.centroid
    wallCent = [
      wallCentObj.x.to_f + largestWallSpaceOrigin[0].to_f,
      wallCentObj.y.to_f + largestWallSpaceOrigin[1].to_f,
      wallCentObj.z.to_f + largestWallSpaceOrigin[2].to_f
    ]
    wallRetHash = {
      largestOutsideWallObj: largestWall,
      wallCentObj: wallCentObj,
      wallCentOrigin: largestWallSpaceOrigin,
      wallCent: wallCent
    }
    return wallRetHash
  end

  # Costing for the VRF Condenser(s) and the wiring and piping conecting the Condenser(s) to the branch distributors
  # on each floor of the building with thermal zones served by a VRF system.
  #
  # Taking in:
  # model(hash): OpenStudio building model
  # maxHeightDiff(float, m):  Difference between height of highest ceiling and ceiling of lowest space served by a VRF
  #                           system.
  # regMat(float):  HVAC regional cost factor for material.
  # regLab(float):  HVAC regional cost factor for labour.
  # RegMatElec(float):  Electrical regional cost factor for material.
  # RegLabElec(float):  Electrical regional cost factor for labour.
  #
  # Returns:
  # Total VRF condensor cost (also adds information to @costing_report).
  def costVRFCondenser(model:, maxHeightDiff:, regMat:, regLab:, regMatElec:, regLabElec:, roofHeight:)
    # VRF systems have a maximum height difference of 50m.  If the height difference calculated above is greater than
    # 50m then determine how many VRF condensers are required (one every 50m)
    numVRFheight = 1.0
    if maxHeightDiff > 50.0
      (maxHeightDiff % 50.0).round(1) > 0.0 ? numVRFheight = (maxHeightDiff / 50.0).to_i.to_f + 1.0 : numVRFheight = (maxHeightDiff / 50.0).to_f.round(0)
    end
    # Get the VRF condenser and calculate the overall capacity as the largest of the heating or cooling capacities.
    vrfCond = model.getAirConditionerVariableRefrigerantFlows[0]
    if vrfCond.isGrossRatedHeatingCapacityAutosized.to_bool
      heatingCapkW = vrfCond.autosizedGrossRatedHeatingCapacity.to_f/1000.0
    else
      heatingCapkW = vrfCond.grossRatedHeatingCapacity.to_f/1000.0
    end
    if vrfCond.isGrossRatedTotalCoolingCapacityAutosized.to_bool
      coolingCapkW = vrfCond.autosizedGrossRatedTotalCoolingCapacity.to_f/1000.0
    else
      coolingCapkW = vrfCond.grossRatedTotalCoolingCapacity.to_f/1000.0
    end
    heatingCapkW >= coolingCapkW ? vrfCondCapkW = heatingCapkW : vrfCondCapkW = coolingCapkW
    # If more than one VRF condenser is present because of a large height difference then assume each VRF condenser will
    # serve the same fraction of the load.  Divide the revised capacity as the original capacity divided by the number
    # of VRF condensers required to compensate for a height difference (the default is 1).
    modVRFCondCapkW = vrfCondCapkW / numVRFheight
    vrfCondInfo = getHVACDBInfo(name: "VRF Condenser Unit", materialLookup: "VRF-HP-HRV-Outdoor", materialSize: modVRFCondCapkW, exactMatch: false)
    vrfSizeMult = vrfCondInfo[:multiplier]
    vrfMat, vrfLab = getCost(vrfCondInfo[:name], vrfCondInfo[:hvac_material], vrfCondInfo[:multiplier])
    vrfCondCost = (vrfMat * regMat + vrfLab * regLab) / 100

    # Cost the refrigerant tubing (assume 20' of 0.5" supply and 1.0833" return tubing)
    # vrfCondSizeTon = (OpenStudio.convert(modVRFCondCapkW.to_f, 'kW', 'kBtu/hr').get)/12.0
    refrigPipeMat, refrigPipeLab = getHVACCost("Refrigerant Piping", 'refrig-tubing-large', 20, true)
    refrigPipingCost = (refrigPipeMat * regMat + refrigPipeLab * regLab) / 100

    # Cost insulation for tubing (assume 20' of 1.25" pipe insulation for both the supply and return refrigerant tubing)
    refrigInsMat, refrigInsLab = getHVACCost('Refrigerant Insulation', 'pipeinsulation', 1.25, true)
    refrigInsulationCost = (refrigInsMat * regMat + refrigInsLab * regLab) * 2 * 20 / 100

    # Cost the wiring
    vrfWireMat, vrfWireLab = getHVACCost('VRF Wiring', 'wiring', 10, true)
    vrfWireLength = 20
    vrfWiringCost = ((vrfWireMat*regMatElec + vrfWireLab*regLabElec)/100)*vrfWireLength/100

    # Cost the Conduit
    vrfConduitMat, vrfConduitLab = getHVACCost('VRF Wiring Conduit', 'Conduit', nil, true)
    vrfConduitCost = ((vrfConduitMat*regMatElec + vrfConduitLab*regLabElec)/100)*vrfWireLength

    # Cost the disconnect
    vrfDiscMat, vrfDiscLab = getHVACCost('VRF Wiring Disconnect', 'Safety_switch', 60, true)
    vrfDiscCost = (vrfDiscMat*regMatElec + vrfDiscLab*regLabElec)/100

    # Determine the Tubing and wiring between the branch distributors and the condenser unit on the roof.  This cost is
    # included with the condenser cost since this is for the entire building and only depends on the distance between
    # the height difference between the lowest space served by a VRF system and the roof center height.  It will be the
    # same cost even if there are several condensers because of height restrictions).
    #
    # Get the refrigerant tubing cost.  Exterior refrigerant tubing is given in 10' lengths of 0.5" supply and 1-1/8"
    # return tubing.  The tubing is assumed to run inside the building so no insulation or all-weather protection is
    # provided.
    buildRefrigTubingMat, buildRefrigTubingLab = getHVACCost("VRF Building Refrigerant Tubing", 'refrig-tubing-large', 10, true)
    # Get distance between lowest floor served by the VRF system and the roof in feet
    maxHeightDiffFt = OpenStudio.convert(maxHeightDiff, 'm', 'ft').get
    # Tubing cost divided by ten because tubing costing is provided in 10 ft rolls
    buildRefrigCost = ((buildRefrigTubingMat * regMat + buildRefrigTubingLab * regLab) / 100) * maxHeightDiffFt / 10.0

    # Get the cost of condensate tubing for the whole building.  A different height is used than the that for
    # refrigerant tubing since the condensate line must extend from the height of the roof (where the condenser is) to
    # the ground floor (if maxHeightDiff does not extend the entire building height) or basement ()if maxHeightDiff
    # includes a basement).
    buildCondMat, buildCondLab = getHVACCost('Building Condensate pipe', 'PEX_tubing', 0.5, true)
    buildCondCost = ((buildCondMat * regMat + buildCondLab * regLab) / 100) * maxHeightDiffFt

    # Get the wiring cost (note wiring comes in 100 ft lengths)
    buildWiringMat, buildWiringLab = getHVACCost('VRF Wiring', 'wiring', 10, true)
    buildWiringCost = ((buildWiringMat * regMatElec + buildWiringLab * regLabElec) / 100) * maxHeightDiffFt / 100.0

    # Get the conduit cost
    buildConduitMat, buildConduitLab = getHVACCost("VRF Building Conduit", 'Conduit', nil, true)
    buildConduitCost = ((buildConduitMat * regMatElec + buildConduitLab * regLabElec) / 100) * maxHeightDiffFt

    # Find totals
    totalVRFCondCost = vrfCondCost * numVRFheight
    totalVRFPipingCost = (refrigPipingCost + refrigInsulationCost) * numVRFheight * vrfSizeMult + buildRefrigCost + buildCondCost
    totalVRFWiringCost = (vrfWiringCost + vrfConduitCost + vrfDiscCost) * numVRFheight * vrfSizeMult + buildWiringCost + buildConduitCost
    totalVRFEquipCost = totalVRFCondCost + totalVRFPipingCost + totalVRFWiringCost


    # Add to VRF Condenser cost report.  I was not sure where to put this since it was really neither a plant unit or a
    # zonal unit.  I guess it supplies several zones so that makes it plant equipment.
    @costing_report['heating_and_cooling']['plant_equipment']  << {
      'type' => 'VRF Zonal System Condenser',
      'nom_flr2flr_hght_ft' => 0.0,
      'ht_roof_ft' => maxHeightDiffFt.round(1),
      'longest_distance_to_ext_ft' => 0.0,
      'wiring_and_gas_connections_distance_ft' => (vrfWireLength*numVRFheight*vrfSizeMult + maxHeightDiffFt).round(1),
      'equipment_cost' => totalVRFCondCost.round(0),
      'wiring_and_gas_connections_cost' => totalVRFWiringCost.round(0),
      'pump_cost' => 0.00,
      'piping_cost' => totalVRFPipingCost.round(0),
      'total_cost' => totalVRFEquipCost.round(0)
    }

    return totalVRFEquipCost
  end

  # This method was originally part of getHVACCOST but was split out because in some cases the information from the
  # materials_hvac sheet of the costing spreadsheet was required but not tho cost.
  # The method takes in:
  # name(String):  The name of a piece of equipment.  Is only used for error reporting and is not linked to anything
  #                else.
  # materialLookup(String):  The material type used to search hte 'Material' column of the materials_hvac sheet of the
  #                          costing spreadsheet.
  # materialSize(float):  The size of the equipment in whichever units are required when searching the 'Size' column of
  #                       the costing spreadsheet.
  # exactMatch(true/false):  A flag to indicate if the hvac equipment must match the size provided exactly or if the
  #                          size is a minimum equipment size.
  #
  # The method returns a hash with the following composition:
  # {
  # name(string):  Same as above.
  # hvac_material(hash):  The costing spreadsheet information for the hvac equipment being searched for.
  # multiplier(float):  Default is 1.  Will be higher if exactMatch is false, and no materialLookup could be found with
  #                     a large enough materialSize in the costing spreadsheet. In this case, it is assumed that several
  #                     pieced of equipment defined by hvact_material are used to satisfy the required materialSize.
  #                     The multiplier defines the number of hvac_material required to meet the materialSize
  # }
  def getHVACMultiSizeDBInfo(name:, materialLookup:, materialCap:, materialCon:)
    multiplier = 1.0
    numConLoops = 1.0
    # Get the materials_hvac sheet info from the costing spreadsheet
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    # Find material that meet the materialCon requirement
    hvac_material_con_info = materials_hvac.select {|data|
      data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Fuel'].to_f >= materialCon
    }
    hvac_material = []
    unless hvac_material_con_info.empty?
      # If the materialCon criteria check if any of the selected material meet the mateterialCap criteria
      hvac_material_cap_info = hvac_material_con_info.select {|data| data['Size'].to_f >= materialCap}
      if hvac_material_cap_info.nil? || hvac_material_cap_info.empty?
        # If none do then select the material with the largest capacity that met the materialCon criteria
        hvac_material << hvac_material_con_info.max_by {|data| data['Size'].to_f}
        con_per_loop = hvac_material[0]['Fuel'].to_f
      else
        # If something met both the materialCon and materialCap then return a hash containing the material and other
        # information and we are done.
        hvac_material = hvac_material_cap_info.min_by {|data| data['Size'].to_f}
        ret_hash = {
          name: name,
          hvac_material: hvac_material,
          multiplier: 1
        }
        return ret_hash
      end
    end
    if hvac_material.empty?
      # If no equipment met the materialCon criteria then find all with the material type we want
      hvac_material_info = materials_hvac.select {|data| data['Material'].to_s.upcase == materialLookup.to_s.upcase}
      # If you cannot find even the material type then something has gone very wrong.  Stop everything and tell the user.
      raise "HVAC material error! Could not find next largest size for #{name} in the materials_hvac sheet of the costing spreadsheet of #{materialLookup} type." if hvac_material_info.empty?
      # Find the equipment with the largest 'Fuel' (this is what defines the materialCon options for this material type)
      hvac_material = hvac_material_info.max_by{|data| data['Fuel'].to_f}
      # Find the number of pieces of equipment will be needed to meet the materialCon requirement
      (((materialCon.to_f) % (hvac_material['Fuel'].to_f)).round(3) > 0.0) ? numConLoops = ((materialCon.to_f/(hvac_material['Fuel'].to_f)).to_i + 1).to_f.round(0) : numConLoops = (materialCon.to_f/(hvac_material['Fuel'].to_f)).round(0)
      # Revise the materialCon requirement now that several pieces of equipment are being used
      con_per_loop = materialCon / numConLoops
      # Find all the appropriate equipment in the costing spreadsheet that meet the revised materialCon requirement
      hvac_material = hvac_material_info.select{|data| data['Fuel'].to_f >= con_per_loop}
    end

    # Now that we have some equipment that meet the required materialCon requirement revise the materialCap requirement
    # in case multiple pieces of equipment were to meet the materialCon requirement.
    reqMatSize = materialCap/numConLoops
    # Of the equipment that met the (modified or original) materialCan requirement select the equipment the meets the
    # (modified or original) capacity requirement.
    material_cap = hvac_material.select{|data| data['Size'].to_f >= reqMatSize}
    if material_cap.empty?
      # If none of the selected materials meet the materialCap requirement find the one with the largest capacity
      largestMat = hvac_material.max_by{|data| data['Size'].to_f}
      maxAvailCap = largestMat['Size'].to_f
      # Find out how many are required to meet the materialCap requirement
      (reqMatSize%maxAvailCap).to_f.round(3) > 0 ? numCapLoops = (((reqMatSize/maxAvailCap).to_i) + 1).to_f.round(0) : numCapLoops = (reqMatSize/maxAvailCap).to_f.round(0)
      # Calculate how many pieces of equipment are now required to meet both the materialCon and materialCap
      # requirements
      totLoops = numConLoops*numCapLoops
      # Revise the materialCap and materialCon requirements to reflect that even more pieces of equipment will be used
      # to meet both requirements
      modMatCap = (materialCap / totLoops).to_f
      modMatCon = (materialCon / totLoops).to_f
      # Search for equipment that meet both the modMatCap and modMatCon criteria
      hvac_material_info = materials_hvac.select {|data| data['Material'].to_s.upcase == materialLookup.to_s.upcase}
      material_cap = hvac_material_info.select{|data| (data['Size'].to_f >= modMatCap) && (data['Fuel'].to_f >= modMatCon)}
      if material_cap.empty?
        # It should have gotten something.  If it didn't then select the one with largest capacity and use that.
        ret_mat = largestMat
      else
        # Find the equipment with the smallest capacity that meets the requirement
        ret_mat = material_cap.min_by{|data| data['Size'].to_f}
      end
    else
      # If something now meets the materialCon and materialCap requirement select the one with the smallest capacity.
      totLoops = numConLoops
      ret_mat = material_cap.min_by{|data| data['Size'].to_f}
    end
    # If multiple branch distributors are required check if the last one can be smaller than the others and return that
    # in addition to the other branch distributors.
    if totLoops.round(0) > 1.0
      # Check check the remaining size requirements for the last branch distributor
      (materialCon - (totLoops - 1.0)*(ret_mat['Fuel'].to_f)) > 0 ? redCon = (materialCon - (totLoops - 1.0)*(ret_mat['Fuel'].to_f)) : redCon = 0.0
      (materialCap - (totLoops - 1.0)*(ret_mat['Size'].to_f)) > 0 ? redCap = (materialCap - (totLoops - 1.0)*(ret_mat['Size'].to_f)) : redCap = 0.0
      # If either are greater than zero (as should be the case) then look for equipment that can meet the remaining
      # connection or capacity requipments.
      if (redCon > 0) || (redCap > 0)
        # Find material that meet the remaining connection and capacity requirements.
        hvac_material_red = materials_hvac.select {|data|
          data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Fuel'].to_f >= redCon && data['Size'].to_f >= redCap
        }
        if hvac_material_red.size == 0
          # If no equipment could be found which meet the remaining connection and capacity requirements then return
          # the the number and type of equipment without adjust for a smaller final piece of equipment.
          red_ret_hash = nil
        else
          # If equipment could be found then select the one with the minimum number of connections.
          red_ret = hvac_material_red.min_by{|data| data['Fuel'].to_f}
          min_hvac_sel = hvac_material_red.select{|data| data['Fuel'].to_f == red_ret['Fuel'].to_f}
          # If more than one piece of equipment can meet the minimum connection requirement then select the one with the
          # minimum capacity requirement.
          if min_hvac_sel.size > 1
            red_ret = min_hvac_sel.min_by{|data| data['Size'].to_f}
          end
          red_ret_hash = {
            red_ret_hash: red_ret,
            numCon: redCon,
            numCap: redCap
          }
        end
      end
    end
    # If multiple pieces of equipment are required to meet the connection and capacity requirements check if a smaller
    # piece of equipment was found to get the final remaining requirements.  If one is found then adjust the multiplier
    # for the main equipment to be reduced by one and return the smaller remaining piece of equipment.
    red_ret_hash.nil? ? retLoops = totLoops : retLoops = totLoops - 1.0
    # Create a hash with the results and return it.
    ret_hash = {
      name: name,
      hvac_material: ret_mat,
      multiplier: retLoops
    }
    return ret_hash, red_ret_hash
  end

  # This method is for the calculation of VSD chiller cost
  def vsd_chiller_cost(primaryCap:)
    # Gather a list of VSD chillers that exist in the costing spreadsheet
    vsd_chiller_sizes = []
    vsd_chiller_options = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == 'ChillerElectricEIR_VSDCentrifugalWaterChiller'.upcase
    }
    vsd_chiller_options[0..-1].each do |a,b|
      a.each do |key,value|
        vsd_chiller_sizes << value.to_f if key=='Size'
      end
    end

    # Look for a VSD in the list of VSDs that has the closest size, and calculate its cost
    vsd_chiller_closet_to_current_kw = vsd_chiller_sizes.sort_by { |item| (primaryCap-item).abs }.first(1)
    quantity_chiller_electric_eir = 1.0
    search_chiller_electric_eir = {
        row_id_1: 'ChillerElectricEIR_VSDCentrifugalWaterChiller',
        row_id_2: vsd_chiller_closet_to_current_kw[0].to_s
    }
    sheet_name = 'materials_hvac'
    column_1 = 'Material'
    column_2 = 'Size'
    tags = ['heating_and_cooling','plant_equipment','chiller']
    thisChillerCost = assembly_cost(cost_info:search_chiller_electric_eir,
                                    sheet_name:sheet_name,
                                    column_1:column_1,
                                    column_2:column_2,
                                    quantity:quantity_chiller_electric_eir,
                                    tags: tags)
    # puts "thisVSDChillerCost is #{thisChillerCost}"
    return thisChillerCost
  end
end
