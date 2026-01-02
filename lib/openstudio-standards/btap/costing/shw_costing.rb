class BTAPCosting

  # --------------------------------------------------------------------------------------------------
  # This function gets all costs associated with SHW/DHW (i.e., tanks, pumps, flues, piping  and
  # utility costs)
  # --------------------------------------------------------------------------------------------------
  def shw_costing(model, prototype_creator)

    @costing_report['shw'] = {}
    totalCost = 0.0

    # Get regional cost factors for this province and city
    materials_hvac = @costing_database["raw"]["materials_hvac"]
    hvac_material = materials_hvac.select {|data|
      data['Material'].to_s == "WaterGas"}.first  # Get any row from spreadsheet in case of region error
    regional_material, regional_installation =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material)
    # Use wiring to get regional cost factors for electrical equipment such as conduit and VFDs
    hvac_material_elec = get_cost_info(mat: 'Wiring', size: 14, unit: nil)
    regional_material_elec, regional_installation_elec =
        get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], hvac_material_elec)

    # Store some geometry data for use below...
    util_dist, ht_roof, nominal_flr2flr_height, horizontal_dist = getGeometryData(model, prototype_creator)

    template_type = prototype_creator.template

    plant_loop_info = {}
    plant_loop_info[:shwtanks] = []
    plant_loop_info[:shwpumps] = []
    hphw_tank_names = []

    num_reg_gas_tanks = 0
    num_reg_oil_tanks = 0
    num_elec_tanks = 0
    num_hphw_tanks = 0
    num_high_eff_gas_tanks = 0
    num_high_eff_oil_tanks = 0

    # HPHW heaters are stored outside of the plant loop
    # Iterate through these first to determine if their are HPHW heaters
    model.getWaterHeaterHeatPumps.each do |hphw|
      if hphw.to_WaterHeaterHeatPump.is_initialized
        hphw_tank_name = hphw.tank.name.get
        hphw_tank_names << hphw_tank_name
      end
    end
    # Iterate through the plant loops to get shw tank & pump data...
    model.getPlantLoops.each do |plant_loop|
      next unless plant_loop.name.get.to_s =~ /Main Service Water Loop/i
      plant_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_WaterHeaterMixed.is_initialized
          tank = supply_comp.to_WaterHeaterMixed.get
          tank_info = {}
          plant_loop_info[:shwtanks] << tank_info
          tank_info[:name] = tank.name.get
          tank_info[:type] = "WaterHeater:Mixed"
          tank_info[:heater_thermal_efficiency] = tank.heaterThermalEfficiency.get unless tank.heaterThermalEfficiency.empty?
          tank_info[:heater_fuel_type] = tank.heaterFuelType
          tank_info[:nominal_capacity] = tank.heaterMaximumCapacity.to_f / 1000 # kW
          tank_info[:heater_volume_gal] = (OpenStudio.convert(tank.tankVolume.to_f, 'm^3', 'gal').get)
          tank_info[:eff_mult] = 1.0
          if tank.heaterFuelType =~ /Electric/i
            # Check if the tank is associated with a HPHW heater
            if hphw_tank_names.include?(tank.name.get)
              tank_info[:heater_fuel_type] = 'HPHW_Heater'
              tank_info[:tank_mult] = get_HVAC_multiplier(tank_info[:heater_fuel_type], tank_info[:nominal_capacity])
              tank_info[:nominal_capacity] /= tank_info[:tank_mult]
              tank_info[:heater_volume_gal] /= tank_info[:tank_mult]
              num_hphw_tanks += tank_info[:tank_mult]
            elsif !hphw_tank_names.include?(tank.name.get)
              tank_info[:heater_fuel_type] = 'WaterElec'
              tank_info[:tank_mult] = get_HVAC_multiplier(tank_info[:heater_fuel_type], tank_info[:nominal_capacity])
              tank_info[:nominal_capacity] /= tank_info[:tank_mult]
              tank_info[:heater_volume_gal] /= tank_info[:tank_mult]
              num_elec_tanks += tank_info[:tank_mult]
            end
          elsif tank.heaterFuelType =~ /NaturalGas/i
            tank_info[:heater_fuel_type] = 'WaterGas'
            tank_info[:tank_mult] = get_HVAC_multiplier(tank_info[:heater_fuel_type], tank_info[:nominal_capacity])
            tank_info[:nominal_capacity] /= tank_info[:tank_mult]
            tank_info[:heater_volume_gal] /= tank_info[:tank_mult]
            if tank_info[:heater_thermal_efficiency] >= 0.85
              tank_info[:heater_fuel_type] = 'WaterGas_HE'
              tank_info[:eff_mult] = 1.3
              num_high_eff_gas_tanks += tank_info[:tank_mult]
            else
              num_reg_gas_tanks += tank_info[:tank_mult]
            end
          elsif tank.heaterFuelType =~ /Oil/i       # Oil, FuelOil, FuelOil#2
            tank_info[:heater_fuel_type] = 'WaterOil'
            tank_info[:tank_mult] = get_HVAC_multiplier(tank_info[:heater_fuel_type], tank_info[:nominal_capacity])
            tank_info[:nominal_capacity] /= tank_info[:tank_mult]
            tank_info[:heater_volume_gal] /= tank_info[:tank_mult]
            if tank_info[:heater_thermal_efficiency] >= 0.85
              tank_info[:heater_fuel_type] = 'WaterOil_HE'
              tank_info[:eff_mult] = 1.3
              num_high_eff_oil_tanks += tank_info[:tank_mult]
            else
              num_reg_oil_tanks += tank_info[:tank_mult]
            end
          end
        elsif supply_comp.to_PumpConstantSpeed.is_initialized
          csPump = supply_comp.to_PumpConstantSpeed.get
          csPump_info = {}
          plant_loop_info[:shwpumps] << csPump_info
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
          plant_loop_info[:shwpumps] << vsPump_info
          vsPump_info[:name] = vsPump.name.get
          if vsPump.isRatedPowerConsumptionAutosized.to_bool
            vsPumpSize = vsPump.autosizedRatedPowerConsumption.to_f
          else
            vsPumpSize = vsPump.ratedPowerConsumption.to_f
          end
          vsPump_info[:size] = vsPumpSize.to_f # Watts
        end
      end
    end

    # Get costs associated with each shw tank
    tankCost = 0.0 ; flueCost = 0.0 ; utilCost = 0.0 ; fuelFittingCost = 0.0; fuelLineCost = 0.0
    multiplier = 1.0 ; primaryFuel = ''; primaryCap = 0

    plant_loop_info[:shwtanks].each do |tank|
      # Get primary/secondary/backup tank cost based on fuel type and capacity for each tank
      #set to local variables.
      primaryFuel = tank[:heater_fuel_type]
      primaryCap = tank[:nominal_capacity].to_f
      heaterVolGal = tank[:heater_volume_gal].to_f

      #Get tank cost.
      if primaryFuel.include?("WaterGas")
        # For gas fired shw tanks we don't have to bother with volume.  However, we have to accept a revised tank volume
        # which is there for electric and oil tanks even though we won't use it.
        shwTankCostInfo = getSHWTankCost(name: tank[:name], materialLookup: primaryFuel, materialSize: primaryCap, tankVol: nil)
        tank[:nominal_cacacity] = shwTankCostInfo[:Cap_kW]
      else
        # If the SHW tank is electric or oil need to find the cost for one with a large enough capacity and volume. If
        # no tanks have a large enough volume then get_SHWTankCost will find the tank with the largest volume and find
        # how many tanks of that size are needed (multiplier).  Below, if this multiplier is larger than one then
        # the tank volume is adjusted to be the largest one that was found (by revVol) and the tank required capacity is
        # reduced by dividing by the multiplier.
        shwTankCostInfo  = getSHWTankCost(name: tank[:name], materialLookup: primaryFuel, materialSize: primaryCap, tankVol: heaterVolGal)
        tank[:heater_volume_gal] = shwTankCostInfo[:Vol_USGal]
        tank[:nominal_capacity] = shwTankCostInfo[:Cap_kW]
        if shwTankCostInfo[:multiplier] > 1.0
          if primaryFuel.include?("WaterElec")
            num_elec_tanks -= tank[:tank_mult]
            tank[:tank_mult] *= shwTankCostInfo[:multiplier]
            num_elec_tanks += tank[:tank_mult]
          elsif primaryFuel.include?("HPHW_Heater")
            num_hphw_tanks -= tank[:tank_mult]
            tank[:tank_mult] *= shwTankCostInfo[:multiplier]
            num_hphw_tanks += tank[:tank_mult]
          else
            if tank[:heater_thermal_efficiency] >= 0.85
              num_high_eff_oil_tanks -= tank[:tank_mult]
              tank[:tank_mult] *= shwTankCostInfo[:multiplier]
              num_high_eff_oil_tanks += tank[:tank_mult]
            else
              num_reg_oil_tanks -= tank[:tank_mult]
              tank[:tank_mult] *= shwTankCostInfo[:multiplier]
              num_reg_oil_tanks += tank[:tank_mult]
            end
          end
        end
      end
      matCost = shwTankCostInfo[:matCost]*tank[:tank_mult].to_f
      labCost = shwTankCostInfo[:labCost]*tank[:tank_mult].to_f

      thisTankCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      tankCost += thisTankCost

      # Determine power venting costs for high efficiency tanks.  Doing this here because tank multiplier and capacity
      # may have changed.
      if tank[:eff_mult] > 1.1
        if shwTankCostInfo[:Cap_kW] < 200
          # 1/8 hp power vent
          materialHash = materials_hvac.find {|data|
            data['Material'].to_s == 'Waterheater_power_vent' && data['Size'].to_s == '0.125'}
          matCost, labCost = getCost('1/8 hp power vent', materialHash, multiplier)
          flueCost += (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * tank[:tank_mult]
        else
          # 1/2 hp power vent
          materialHash = materials_hvac.find {|data|
            data['Material'].to_s == 'Waterheater_power_vent' && data['Size'].to_s == '0.5'}
          matCost, labCost = getCost('1/2 hp power vent', materialHash, multiplier)
          flueCost += (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0) * tank[:tank_mult]
        end
      end
    end

    numTanks = num_elec_tanks + num_hphw_tanks + num_reg_gas_tanks + num_high_eff_gas_tanks + num_reg_oil_tanks + num_high_eff_oil_tanks
    numFuelTanks = num_reg_gas_tanks + num_high_eff_gas_tanks + num_reg_oil_tanks + num_high_eff_oil_tanks

    if numTanks > 0
      # Electric utility cost components (i.e., power lines).

      # elec 600V #14 wire /100 ft (#848)
      materialHash = get_cost_info(mat: 'Wiring', size: 14)
      matCost, labCost = getCost('electrical wire - 600V #14', materialHash, multiplier)
      elecWireCost = matCost * regional_material_elec / 100.0 + labCost * regional_installation_elec / 100.0

      # 1 inch metal conduit (#851)
      materialHash = get_cost_info(mat: 'Conduit', unit: 'L.F.')
      matCost, labCost = getCost('1 inch metal conduit', materialHash, multiplier)
      metalConduitCost = matCost * regional_material_elec / 100.0 + labCost * regional_installation_elec / 100.0

      # Electric utility wire and conduit cost used by all tanks except HPHW
      utilCost += (metalConduitCost * util_dist + elecWireCost * util_dist / 100) * (numTanks - num_hphw_tanks)

      # Get costs condition on fuel types.
      if numFuelTanks> 0
        numRegFuelTanks = num_reg_gas_tanks + num_reg_oil_tanks
        numHighEffFuelTanks = num_high_eff_gas_tanks + num_high_eff_oil_tanks

        # Gas/Oil line piping cost per ft (#1)
        materialHash = get_cost_info(mat: 'GasLine', unit: 'L.F.')
        matCost, labCost = getCost('fuel line', materialHash, multiplier)
        fuelLineCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

        # Gas/Oil line fitting connection per tank (#2)
        materialHash = get_cost_info(mat: 'GasLine', unit: 'each')
        matCost, labCost = getCost('fuel line fitting connection', materialHash, multiplier)
        fuelFittingCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

        if numRegFuelTanks > 0
          # Flue and utility component costs (for gas and oil tanks only)
          # Calculate flue costs once for all tanks since flues combined by header when multiple tanks
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

          # Adding one regular flue if any regular efficiency shw tanks are present
          flueCost += flueVentCost * ht_roof + flueElbowCost + flueTopCost

          # Header cost only non-zero if there is a secondary/backup gas/oil tank
          if numRegFuelTanks > 1
            # Check if need a flue header (i.e., there are both primary and secondary/backup tanks)
            # 6 inch diameter header (#384)
            materialHash = get_cost_info(mat: 'Venting', size: 6)
            matCost, labCost = getCost('flue header', materialHash, multiplier)
            headerVentCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

            #6 inch elbow fitting for header (#386)
            materialHash = get_cost_info(mat: 'VentingElbow', size: 6)
            matCost, labCost = getCost('flue header elbow', materialHash, multiplier)
            headerElbowCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

            # Adding a regular tank header for every additional regular efficiency SHW tank present
            # Assume a header length of 20 ft and an elbow fitting for each tank connected to the header
            flueCost += (headerVentCost * 20  + headerElbowCost) * (numRegFuelTanks - 1)
          end
        end

        # If high efficiency fuel fired shw tanks are present add flues (1 per tank)
        if numHighEffFuelTanks > 0
          #6 inch PVC pipe (#1327)
          materialHash = get_cost_info(mat: 'Vent_pvc', size: 6)
          matCost, labCost = getCost('flue', materialHash, multiplier)
          pvcFluePipe = (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

          #6 inch PVC Coupling (#1319)
          materialHash = get_cost_info(mat: 'Vent_pvc_coupling', size: 6)
          matCost, labCost = getCost('flue elbow', materialHash, multiplier)
          pvcFlueCoupling = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # 6 inch PVC elbow (#1329)
          materialHash = get_cost_info(mat: 'Vent_pvc_elbow', size: 6)
          matCost, labCost = getCost('flue top', materialHash, multiplier)
          pvcFlueElbow = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # Adding PVC flue costs for all high efficiency fuel fired SHW tanks
          flueCost += (pvcFluePipe * 20.0 + pvcFlueCoupling + pvcFlueElbow) * numHighEffFuelTanks
        end

        # If natural gas tanks are present include fuel line and connectors
        if (num_reg_gas_tanks + num_reg_gas_tanks) > 0
          # Gas tanks require fuel line+valves+connectors
          utilCost += (fuelLineCost * util_dist + fuelFittingCost) * (num_reg_gas_tanks + num_high_eff_gas_tanks)

        elsif (num_reg_oil_tanks + num_high_eff_oil_tanks) > 0
          # Oil tanks require fuel line+valves+connectors and electrical conduit

          # Oil filtering system (#4)
          materialHash = get_cost_info(mat: 'OilLine', unit: 'each')
          matCost, labCost = getCost('Oil filtering system', materialHash, multiplier)
          oilFilterCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          # 2000 USG above ground tank (#5)
          materialHash = get_cost_info(mat: 'OilTanks', size: 2000)
          matCost, labCost = getCost('Oil tank (2000 USG)', materialHash, multiplier)
          oilTankCost = matCost * regional_material / 100.0 + labCost * regional_installation / 100.0

          utilCost += (fuelLineCost * util_dist + fuelFittingCost) * (num_reg_oil_tanks + num_high_eff_oil_tanks) + oilFilterCost + oilTankCost
        end
      end
    end

    # Tank pump costs
    pumpCost = 0.0; pipingCost = 0.0; numPumps = 0; pumpName = ''; pumpSize = 0.0
    plant_loop_info[:shwpumps].each do |pump|
      numPumps += 1
      # Cost variable and constant volume pumps the same (the difference is in extra cost for VFD controller)
      pumpSize = pump[:size]; pumpName = pump[:name]
      matCost, labCost = getHVACCost(pumpName, 'Pumps', pumpSize, false)
      pumpCost += matCost * regional_material / 100.0 + labCost * regional_installation / 100.0
      if pump[:name] =~ /variable/i
        # Cost the VFD controller for the variable pump costed above
        pumpSize = pump[:size]; pumpName = pump[:name]
        matCost, labCost = getHVACCost(pumpName, 'VFD', pumpSize, false)
        pumpCost += matCost * regional_material_elec / 100.0 + labCost * regional_installation_elec / 100.0
      end
    end
    #if numTanks > 1 && numPumps < 2
      # Add pump costing for the backup tank pump.
      # 2024-04-25:  No longer including redundant costs.
      #pumpCost *= 2.0
      #numPumps = 2  # reset the number of pumps for piping costs below
    #end
    # Double the pump costs to accomodate the costing of a backup pumps for each tank!
    # 2024-04-25:  No longer including redundant casts.
    # pumpCost *= 2.0

    # Tank water piping cost: Add piping elbows, valves and insulation from the tank(s)
    # to the pumps(s) assuming a pipe diameter of 1” and a distance of 10 ft per pump
    if numTanks > 0
      # 1 inch Steel pipe
      matCost, labCost = getHVACCost('1 inch steel pipe', 'SteelPipe', 1)
      pipingCost += 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe insulation
      matCost, labCost = getHVACCost('1 inch pipe insulation', 'PipeInsulation', 1)
      pipingCost += 10.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch Steel pipe elbow
      matCost, labCost = getHVACCost('1 inch steel pipe elbow', 'SteelPipeElbow', 1)
      pipingCost += 2.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)

      # 1 inch gate valves
      matCost, labCost = getHVACCost('1 inch gate valves', 'ValvesGate', 1)
      pipingCost += 1.0 * numPumps * (matCost * regional_material / 100.0 + labCost * regional_installation / 100.0)
    end

    # 2023-04-25:  Removing costing for redundant equipment and piping.
    #if numTanks > 1
      # Double pump piping cost to account for second tank
    #  pipingCost *= 2
    #end

    # ckirney, 2019-04-12:  shw_distribution_costing mostly completed however priorities have changed for now so
    # completion and testing will be delayed.  Adding code to master for now but it will not be called until it is
    # ready.
    # distCost = shw_distribution_costing(model: model, prototype_creator: prototype_creator)

    totalCost = tankCost + flueCost + utilCost + pumpCost + pipingCost

    @costing_report['shw'] = {
        'shw_nom_flr2flr_hght_ft' => nominal_flr2flr_height.round(1),
        'shw_ht_roof' => ht_roof.round(1),
        'shw_longest_distance_to_ext_ft' => horizontal_dist.round(1),
        'shw_utility_distance_ft' => util_dist.round(1),
        'shw_tanks' => tankCost.round(2),
        'shw_num_of_modeled_tanks' => plant_loop_info[:shwtanks].size,
        'num_elec_tanks' => num_elec_tanks,
        'num_hphw_tanks' => num_hphw_tanks,
        'shw_num_reg_eff_gas_tanks' => num_reg_gas_tanks,
        'shw_num_high_eff_gas_tanks' => num_high_eff_gas_tanks,
        'shw_num_reg_eff_oil_tanks' => num_reg_oil_tanks,
        'shw_num_high_eff_oil_tanks' => num_high_eff_oil_tanks,
        'shw_num_of_costed_tanks' => numTanks,
        'shw_flues' => flueCost.round(2),
        'shw_utilties' => utilCost.round(2),
        'shw_pumps' => pumpCost.round(2),
        'shw_num_of_pumps' => plant_loop_info[:shwpumps].size,
        'shw_piping' => pipingCost.round(2),
        'shw_total' => totalCost.round(2)
    }
    puts "\nHVAC SHW costing data successfully generated. Total shw costs: $#{totalCost.round(2)}"

    return totalCost
  end

  def shw_distribution_costing(model:, prototype_creator:)
    total_shw_dist_cost = 0
    roof_cent = prototype_creator.find_highest_roof_centre(model)
    mech_room, cond_spaces = prototype_creator.find_mech_room(model)
    min_space = get_lowest_space(spaces: cond_spaces)
    mech_sizing_info = read_mech_sizing()
    shw_sp_types = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'shw_space_types')
    excl_sp_types = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'exclusive_shw_space_types')
    shw_main_cost = cost_shw_main(mech_room: mech_room, roof_cent: roof_cent, min_space: min_space)
    total_shw_dist_cost += shw_main_cost[:cost]
    #determine if space is wet:  prototype_creator.is_an_necb_wet_space?(space)
    #Sort spaces by floor and conditioned spaces
    space_mod = OpenstudioStandards::Space
    model.getBuildingStorys.sort.each do |build_story|
      public_wash = false
      other_public_wash = false
      build_story.spaces.sort.each do |space|
        next unless (space_mod.space_heated?(space) || space_mod.space_cooled?(space)) && !space_mod.space_plenum?(space)
        sp_type_name = space.spaceType.get.nameString
        shw_neccesary = shw_sp_types.select {|table_sp_type|
          !/#{table_sp_type.upcase}/.match(sp_type_name.upcase).nil?
        }
        if shw_neccesary.empty?
          public_wash = true
        else
          shw_dist_cost = get_shw_dist_cost(space: space, roof_cent: roof_cent)
          total_shw_dist_cost += shw_dist_cost[:cost]
          public_shw = excl_sp_types.select {|ex_table_sp_type|
            !/#{ex_table_sp_type.upcase}/.match(sp_type_name.upcase).nil?
          }
          other_public_wash = true
        end
      end
      if public_wash == true && other_public_wash == false
        #Cost two shw piping to two washrooms in the center of the story.  Assume each has 20 feet of supply and return
        #shw piping to the story center (10 feet supply, 10 feet return).
        dist_ft = 40
        shw_dist_search = []
        shw_dist_search << {
            mat: 'CopperPipe',
            unit: 'L.F.',
            size: 0.75,
            mult: dist_ft
        }
        washroom_shw_cost = get_comp_cost(cost_info: shw_dist_search)
        total_shw_dist_cost += washroom_shw_cost
      end
    end
    return total_shw_dist_cost
  end

  def get_space_floor_centroid(space:)
    # Determine the bottom surface of the space and calculate it's centroid.
    # Get the coordinates of the origin for the space (the coordinates of points in the space are relative to this).
    xOrigin = space.xOrigin
    yOrigin = space.yOrigin
    zOrigin = space.zOrigin
    # Get the surfaces for the space.
    space_surfaces = space.surfaces
    # Find the floor (aka the surface with the lowest centroid).
    min_surf = space_surfaces.min_by{|sp_surface| (sp_surface.centroid.z.to_f)}
    # The following is added to determine the overall floor centroid because some spaces have floors composed of more than one surface.
    floor_centroid = [0, 0, 0]
    space_surfaces.each do |sp_surface|
      if min_surf.centroid.z.to_f.round(8) == sp_surface.centroid.z.to_f.round(8)
        floor_centroid[0] = floor_centroid[0] + sp_surface.centroid.x.to_f*sp_surface.grossArea.to_f
        floor_centroid[1] = floor_centroid[1] + sp_surface.centroid.y.to_f*sp_surface.grossArea.to_f
        floor_centroid[2] = floor_centroid[2] + sp_surface.grossArea
      end
    end

    # Determine the floor centroid
    floor_centroid[0] = floor_centroid[0]/floor_centroid[2]
    floor_centroid[1] = floor_centroid[1]/floor_centroid[2]

    return {
        centroid: [floor_centroid[0] + xOrigin, floor_centroid[1] + yOrigin, min_surf.centroid.z.to_f + zOrigin],
        floor_area_m2: floor_centroid[2]
    }
  end

  def get_shw_dist_cost(space:, roof_cent:)
    shw_dist_search = []
    space_cent = get_space_floor_centroid(space: space)
    dist_m = (roof_cent[:roof_centroid][0] - space_cent[:centroid][0]).abs + (roof_cent[:roof_centroid][1] - space_cent[:centroid][1]).abs
    dist_ft = OpenStudio.convert(dist_m, 'm', 'ft').get
    shw_dist_search << {
        mat: 'CopperPipe',
        unit: 'L.F.',
        size: 0.75,
        mult: dist_ft
    }
    total_comp_cost = get_comp_cost(cost_info: shw_dist_search)
    return {
        length_m: dist_m,
        cost: total_comp_cost
    }
  end

  def cost_shw_main(mech_room:, roof_cent:, min_space:)
    shw_dist_search = []
    building_height_m = (roof_cent[:roof_centroid][2] - min_space[:roof_cent][2]).abs
    mech_to_cent_dist_m = (roof_cent[:roof_centroid][0] - mech_room['space_centroid'][0]).abs + (roof_cent[:roof_centroid][1] - mech_room['space_centroid'][1]).abs
    #Twice the distance to account for supply and return shw piping.
    total_dist_m = 2*(building_height_m + mech_to_cent_dist_m)
    total_dist_ft = OpenStudio.convert(total_dist_m, 'm', 'ft').get
    shw_dist_search << {
        mat: 'CopperPipe',
        unit: 'L.F.',
        size: 0.75,
        mult: total_dist_ft
    }
    total_comp_cost = get_comp_cost(cost_info: shw_dist_search)
    return {
        length_m: total_dist_m,
        cost: total_comp_cost
    }
  end

  # Getting cost for SHW Tanks.  This method is different from the getHVACCost method used everywhere else in that it
  # accepts a tank volume argument in addition to the tank capacity (materialSize in this case).  This additional
  # argument means that the method must search for a SHW tank heated with the right fuel that has a large enough
  # capacity and volume.
  #
  # IMPORTANT:  This method assumes that when SHW tanks are retrieved from the model their capacity is checked against
  # the capacities of costed tanks.  If the modeled capacity is too large then it is costed as though multiple smaller
  # tanks are present.  Thus, this method assumes that anything passed to it will be small enough to be costed.  This is
  # another difference from the getHVACCost method which includes a call to get_HVAC_multiplier that checks if a costed
  # item is too big and should be replaced by several smaller items.
  #
  # Note that the multiplier is always set to 1.0 when claculating the cost.  That is because the multiplier is applied
  # to the cost in the main shw_costing method.
  def getSHWTankCost(name:, materialLookup:, materialSize:, tankVol:)
    multiplier = 1.0
    materials_hvac = @costing_database['raw']['materials_hvac']
    # Get costing spreadsheet data for gas and oil fired mixed shw tanks
    if tankVol.nil?
      # If no tank volume is provided then only look at capacity.
      # Get all capacities hor that type of tank.
      hvac_materials = materials_hvac.select {|data|
        data['Material'].to_s == materialLookup.to_s && data['Size'].to_f >= materialSize.to_f
      }
      if hvac_materials.empty?
        # If no tanks have a big enough capacity then something is amiss and return an error (this should never happen
        # because tanks capacity should be checked before this method is called).
        puts "HVAC material error! Could not find next largest size for #{name} in #{materials_hvac}"
        raise
      elsif hvac_materials.size == 1
        # Only one tank has an appropriate capacity find it's cost and return it.
        matCost, labCost = getCost(name, hvac_materials[0], 1.0)
        ret_hash = {
            matCost: matCost,
            labCost: labCost,
            multiplier: multiplier,
            Vol_USGal: tankVol,
            Cap_kW: hvac_materials[0]['Size'].to_f

        }
        return ret_hash
      else
        # More than one tank has a big enough capacity.  Find the cost of the one with teh smallest capacity and return
        # it.
        hvac_material = hvac_materials.min_by {|data| data['Size'].to_f}
        matCost, labCost = getCost(name, hvac_material, 1.0)
        ret_hash = {
            matCost: matCost,
            labCost: labCost,
            multiplier: multiplier,
            Vol_USGal: tankVol,
            Cap_kW: hvac_material['Size'].to_f
        }
        return ret_hash
      end
    else
      # We need to find a tank with a big enough capacity and volume.
      # First see if a unique tank with a large enough capacity and volume exists
      hvac_materials = materials_hvac.select {|data|
        data['Material'].to_s == materialLookup.to_s && data['Size'].to_f >= materialSize.to_f && data['Fuel'].to_f >= tankVol
      }
      if hvac_materials.empty?
        # If none exists see if the tank volume is big enough.  Note that tank capacity was checked earlier so capacity
        # should not be an issue.  However, volume was not checked.  It is possible that tanks with a big enough
        # capacity are in the costing database but not a big enough volume.
        #
        # Find the largest volume tank with a big enough capacity.  Find out how many of those tanks are needed to
        # satisfy the volume requirement.
        multiplier, revVol = get_SHW_vol_multiplier(materialLookup: materialLookup, materialSize: materialSize, materialVol: tankVol)
        materialSize /= multiplier
        tankVol = revVol
        # Try again to get tanks with a large enough size and capacity
        hvac_materials = materials_hvac.select {|data|
          data['Material'].to_s == materialLookup.to_s && data['Size'].to_f >= materialSize.to_f && data['Fuel'].to_f >= tankVol
        }
        # You may notice that there is no handling for cases where there is more than one tank with a large enough
        # capacity and volume.  There actually is, it is just a little further below.
        if hvac_materials.empty?
          puts "HVAC material error! Could not find a #{name} tank with a capacity >= #{materialSize} kW and a volume >= #{tankVol} US Gal in #{materials_hvac}"
        elsif hvac_materials.size == 1
          matCost, labCost = getCost(name, hvac_materials[0], 1.0)
          ret_hash = {
              matCost: matCost,
              labCost: labCost,
              multiplier: multiplier,
              Vol_USGal: hvac_materials[0]['Fuel'].to_f,
              Cap_kW: hvac_materials[0]['Size'].to_f
          }
          return ret_hash
        end
      elsif hvac_materials.size == 1
        matCost, labCost = getCost(name, hvac_materials[0], 1.0)
        ret_hash = {
            matCost: matCost,
            labCost: labCost,
            multiplier: multiplier,
            Vol_USGal: hvac_materials[0]['Fuel'].to_f,
            Cap_kW: hvac_materials[0]['Size'].to_f
        }
        return ret_hash
      end
      # If mare than one tank has a lorge enough capacity and volume then find the one with the smallest volume.
      hvac_materials_min_vol = hvac_materials.min_by {|data| data['Fuel'].to_f}
      if hvac_materials_min_vol.nil?
        # Well, something went horribly wrong.  You should have gotten this far only if there were several tanks that
        # had a large enough capacity and volume.  Now we can't find the smallest one.  Not sure what happened but
        # whatever it was it is not good.
        puts "HVAC material error! Could not find a #{name} tank with a capacity >= #{materialSize} kW and a volume >= #{materialVol} US Gal in costing database."
        raise
      else
        # Find how many tanks have the lowest volume.
        hvac_materials_vol = hvac_materials.select {|data| data['Fuel'].to_f == hvac_materials_min_vol['Fuel'].to_f}
        if hvac_materials_vol.size == 1
          hvac_material = hvac_materials_vol[0]
        else
          # If more than one tank as a small enough volume choose the one with the smallest capacity.
          hvac_material = hvac_materials_vol.min_by {|data| data['Size'].to_f}
        end
        matCost, labCost = getCost(name, hvac_material, 1.0)
        ret_hash = {
            matCost: matCost,
            labCost: labCost,
            multiplier: multiplier,
            Vol_USGal: hvac_material['Fuel'].to_f,
            Cap_kW: hvac_material['Size'].to_f
        }
        return ret_hash
      end
    end
  end

  # This method is a copy of get_HVAC_multiplier but searches for volume in the 'Fuel' column of the materials_hvac
  # sheet.  The 'Fuel' column is where tank volume information is kept for electric and oil SHW tanks.
  def get_SHW_vol_multiplier(materialLookup:, materialSize:, materialVol:)
    multiplier = 1.0
    materials_hvac = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == materialLookup.to_s.upcase && data['Size'].to_f >= materialSize
    }
    if materials_hvac.nil? || materials_hvac.empty?
      puts("Error: no hvac information available for equipment #{materialLookup}!")
      raise
    end
    materials_hvac.length == 1 ? max_size = materials_hvac[0] : max_size = materials_hvac.max_by {|d| d['Fuel'].to_f}
    if max_size['Fuel'].to_f <= 0
      puts("Error: #{materialLookup} has a volume of 0 or less.  Please check that the correct costing_database.json file is being used or check the costing spreadsheet!")
      raise
    end
    mult = materialVol.to_f / (max_size['Fuel'].to_f)

    multiplier = (mult.to_i).to_f + 1.0  # Use next largest integer for multiplier
    return multiplier.to_f, max_size['Fuel'].to_f
  end

  def get_cost_info(mat:, size: nil, unit: nil)
    comp_info = nil
    if unit.nil?
      comp_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == mat.to_s.upcase and
          data['Size'].to_f.round(2) == size.to_f.round(2)
      }.first
    elsif size.nil?
      comp_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == mat.to_s.upcase and
          data['unit'].to_s.upcase == unit.to_s.upcase
      }.first
    elsif size.nil? && unit.nil?
      comp_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == mat.to_s.upcase
      }.first
    else
      comp_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == mat.to_s.upcase and
          data['Size'].to_f.round(2) == size.to_f.round(2) and
          data['unit'].to_s.upcase == unit.to_s.upcase
      }.first
    end
    if comp_info.nil?
      puts("No data found for material: #{mat}, size: #{size}, with unit: #{unit}")
      raise
    end
    return comp_info
  end

end
