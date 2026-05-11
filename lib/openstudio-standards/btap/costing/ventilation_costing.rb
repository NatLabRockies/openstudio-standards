class BTAPCosting
  def ventilation_costing(model, prototype_creator, template_type, mech_room, cond_spaces)
    # Set up reporting hash
    @costing_report['ventilation'] = {system_1: [], system_2: [], system_3: [], system_4: [], system_5: [], system_6: [], system_7: [], mech_to_roof: [], trunk_duct: [], floor_trunk_ducts: [], tz_distribution: [], hrv_return_ducting: [], natural_ventilation: [], demand_controlled_ventilation: []}
    # Get mechanical sizing for costing information from mech_sizing.json
    mech_sizing_info = read_mech_sizing()
    # Find the mechanical room in the model and conditioned spaces - moved to btap_costing.rb
    # mech_room, cond_spaces = prototype_creator.find_mech_room(model)
    # Find the center of the highest roof in the model (this will be surrounded by roof top mechancial equipment and is where utility lines will be sent)
    roof_cent = prototype_creator.find_highest_roof_centre(model)
    # Find the lowest space in the building (trunk duct runs from here to the highest space).
    min_space = get_lowest_space(spaces: cond_spaces)
    vent_cost = 0
    # Start ventilation costing
    vent_cost += ahu_costing(model: model, prototype_creator: prototype_creator, template_type: template_type, mech_room: mech_room, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info, min_space: min_space)
    #  natural ventilation costing
    nv_total_cost = cost_audit_nv(model: model, prototype_creator: prototype_creator)
    # demand-controlled ventilation costing
    dcv_cost_total = cost_audit_dcv(model: model, prototype_creator: prototype_creator)
    # total ventilation cost
    vent_cost += nv_total_cost + dcv_cost_total
    return vent_cost
  end

  def ahu_costing(model:, prototype_creator:, template_type:, mech_room:, roof_cent:, mech_sizing_info:, min_space:)
    ahu_cost = 0
    hrv_total_cost = 0
    heat_type = {
        'HP' => 0,
        'elec' => 0,
        'Gas' => 0,
        'HW' => 0,
    }
    cool_type = {
        'DX' => 0,
        'CHW' => 0,
    }

    rt_unit_num = 0
    total_vent_flow_m3_per_s = 0
    sys_1_4 = true
    hvac_floors = []
    # Go through each air loop in the model and cost it
    model.getAirLoopHVACs.sort.each do |airloop|
      @airloop_info = nil
      airloop_name = airloop.nameString
      # Look for the system type from the name of the air loop
      sys_name_loc = airloop_name.to_s.upcase.index("SYS_")
      if sys_name_loc.nil?
        puts "The name of airloop #{airloop_name} does not start with a valid NECB system type described as \"Sys_\" and then an NECB system number."
        puts "Please rename the airloop appropriately or do not cost the ventilation system until ventilation costing can handle non-NECB ventilation systems."
        next
      else
        sys_type = airloop_name[(sys_name_loc+4)].to_i
        sys_type_real = sys_type
        # For costing, treat system types 1 and 4 the same (treat both as system 1)
        sys_type = 1 if sys_type == 4
        next if sys_type == 2
      end
      ahu_tags = [
        "ventilation",
        airloop_name,
        "system #{sys_type_real}"
      ]
      rt_unit_num += 1

      @airloop_info = {sys_type: sys_type}
      @airloop_info[:name] = airloop_name

      # Get the air loop supply airflow rate (used for sizing the ahu for costing)
      if airloop.isDesignSupplyAirFlowRateAutosized
        airloop_flow_m3_per_s = airloop.autosizedDesignSupplyAirFlowRate.to_f
      else
        airloop_flow_m3_per_s = airloop.designSupplyAirFlowRate.to_f
      end
      airloop_flow_cfm = (OpenStudio.convert(airloop_flow_m3_per_s, 'm^3/s', 'cfm').get)
      airloop_flow_lps = (OpenStudio.convert(airloop_flow_m3_per_s, 'm^3/s', 'L/s').get)
      total_vent_flow_m3_per_s += airloop_flow_m3_per_s
      # Set up hash to record heating and cooling capacities.  If more than one heating or cooling source is present this will be used to determine which is predominant one since ahu costing is done based on one heating fuel and cooling type
      heat_cap = {
          'HP' => 0,
          'elec' => 0,
          'Gas' => 0,
          'HW' => 0,
          'CCASHP' => 0
      }
      cool_cap = {
          'DX' => 0,
          'CHW' => 0,
      }
      @airloop_info[:airloop_flow_m3_per_s] = airloop_flow_m3_per_s.round(3)
      total_heat_cool_cost = 0
      airloop_equipment = []
      #@airloop_info[:equipment_info] = []
      # Find HRVs in the air loop so they can be costed if present
      hrv_info = get_hrv_info(airloop: airloop, model: model)
      # Sort through all of the supply components in the air loop and collect heating and cooling equipment
      airloop.supplyComponents.sort.each do |supplycomp|
        # Get the OS object type of the supply component
        obj_type = supplycomp.iddObjectType.valueName.to_s
        mech_capacity = 0
        heating_fuel = 'none'
        cooling_type = 'none'
        adv_dx_clg_eqpt = false
        cat_search = nil
        # Based on the object type determine how to handle it.
        case obj_type
          # Determine what to do (if anything) with a piece of air loop heating/cooling equipment.  Note the comment for the first type applies to the rest.
        when /OS_Coil_Heating_DX_VariableSpeed/
          # Get the object and make sure it is cast correctly
          suppcomp = supplycomp.to_CoilHeatingDXVariableSpeed.get
          # Determine the size of the object if either autosized or manualy sized
          if suppcomp.isRatedHeatingCapacityAtSelectedNominalSpeedLevelAutosized
            mech_capacity = suppcomp.autosizedRatedHeatingCapacityAtSelectedNominalSpeedLevel.to_f/1000.0
          else
            mech_capacity = suppcomp.ratedHeatingCapacityAtSelectedNominalSpeedLevel.to_f/1000.0
          end
          # Determine from the name if it is a CCASHP
          if suppcomp.name.to_s.upcase.include?("CCASHP")
            # Set the heating equipment type (used to determine how to cost the equipment)
            heating_fuel = 'CCASHP'
            # Set the term used to search the 'hvac_costing' sheet in the costing spreadsheet to get costing information
            cat_search = 'coils'
            # Set the heating capacity (used to determine the predominant heating type for the air loop)
            heat_cap['CCASHP'] += mech_capacity
          else
            heating_fuel = 'HP'
            cat_search = 'ashp'
            heat_cap['HP'] += mech_capacity
          end
        when /OS_Coil_Heating_DX_SingleSpeed/
          suppcomp = supplycomp.to_CoilHeatingDXSingleSpeed.get
          if suppcomp.isRatedTotalHeatingCapacityAutosized
            mech_capacity = suppcomp.autosizedRatedTotalHeatingCapacity.to_f/1000.0
          else
            mech_capacity = suppcomp.ratedTotalHeatingCapacity.to_f/1000.0
          end
          if suppcomp.name.to_s.upcase.include?("CCASHP")
            heating_fuel = 'CCASHP'
            # There is a separate method which costs additional CCASHP cost information.  The 'coils' category is only
            # one of the pieces of equipment that goes into CCASHP costing.
            cat_search = 'coils'
            heat_cap['CCASHP'] += mech_capacity
          else
            heating_fuel = 'HP'
            cat_search = 'ashp'
            heat_cap['HP'] += mech_capacity
          end
        when 'OS_Coil_Heating_Electric'
          heating_fuel = 'elec'
          suppcomp = supplycomp.to_CoilHeatingElectric.get
          if suppcomp.isNominalCapacityAutosized
            mech_capacity = suppcomp.autosizedNominalCapacity.to_f/1000.0
          else
            mech_capacity = suppcomp.nominalCapacity.to_f/1000.0
          end
          cat_search = 'elecheat'
          heat_cap['elec'] += mech_capacity
        when /OS_Coil_Heating_Gas/
          heating_fuel = 'Gas'
          suppcomp = supplycomp.to_CoilHeatingGas.get
          if suppcomp.isNominalCapacityAutosized
            mech_capacity = suppcomp.autosizedNominalCapacity.to_f/1000.0
          else
            mech_capacity = suppcomp.nominalCapacity.to_f/1000.0
          end
          cat_search = 'FurnaceGas'
          heat_cap['Gas'] += mech_capacity
        when /OS_Coil_Heating_Water/
          heating_fuel = 'HW'
          suppcomp = supplycomp.to_CoilHeatingWater.get
          if suppcomp.isRatedCapacityAutosized
            mech_capacity = suppcomp.autosizedRatedCapacity.to_f/1000.0
          else
            suppcomp.ratedCapacity.to_f/1000.0
          end
          cat_search = 'coils'
          heat_cap['HW'] += mech_capacity
        when /OS_Coil_Cooling_DX_SingleSpeed/
          suppcomp = supplycomp.to_CoilCoolingDXSingleSpeed.get
          if suppcomp.isRatedTotalCoolingCapacityAutosized
            mech_capacity = suppcomp.autosizedRatedTotalCoolingCapacity.to_f/1000.0
          else
            mech_capacity = suppcomp.ratedTotalCoolingCapacity.to_f/1000.0
          end
          if suppcomp.name.to_s.upcase.include?('DX-ADV')
            cooling_type = 'DX-adv'
            cat_search = 'coils'
            cool_cap['DX'] += mech_capacity
          else
            cooling_type = 'DX'
            cat_search = 'coils'
            cool_cap['DX'] += mech_capacity
          end
        when /OS_Coil_Cooling_DX_VariableSpeed/
          suppcomp = supplycomp.to_CoilCoolingDXVariableSpeed.get
          if suppcomp.isGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevelAutosized
            mech_capacity = suppcomp.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f/1000.0
          else
            mech_capacity = suppcomp.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f/1000.0
          end
          if suppcomp.name.to_s.upcase.include?('DX-ADV')
            cooling_type = 'DX-adv'
            cat_search = 'coils'
            cool_cap['DX'] += mech_capacity
          else
            cooling_type = 'DX'
            cat_search = 'coils'
            cool_cap['DX'] += mech_capacity
          end
        when /Coil_Cooling_Water/
          cooling_type = 'CHW'
          suppcomp = supplycomp.to_CoilCoolingWater.get
          mech_capacity = suppcomp.autosizedDesignCoilLoad.to_f/1000.0
          cat_search = 'coils'
          cool_cap['CHW'] += mech_capacity
        when /OS_AirLoopHVAC_UnitaryHeatPump_AirToAir/
          suppcomp = supplycomp.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
          htg_coil = suppcomp.heatingCoil
          if htg_coil.to_CoilHeatingDXSingleSpeed.is_initialized
            htg_coil = htg_coil.to_CoilHeatingDXSingleSpeed.get
            if htg_coil.isRatedTotalHeatingCapacityAutosized
              mech_capacity = htg_coil.autosizedRatedTotalHeatingCapacity.to_f/1000.0
            else
              mech_capacity = htg_coil.ratedTotalHeatingCapacity.to_f/1000.0
            end
            heating_fuel = 'HP'
            cat_search = 'ashp'
            heat_cap['HP'] += mech_capacity
          end
          clg_coil = suppcomp.coolingCoil
          if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
            clg_coil = clg_coil.to_CoilCoolingDXSingleSpeed.get
            if clg_coil.isRatedTotalCoolingCapacityAutosized
              mech_capacity = clg_coil.autosizedRatedTotalCoolingCapacity.to_f/1000.0
            else
              mech_capacity = clg_coil.ratedTotalCoolingCapacity.to_f/1000.0
            end
            cooling_type = 'DX'
            cat_search = 'coils'
            cool_cap['DX'] += mech_capacity
          end
          supp_htg_coil = suppcomp.supplementalHeatingCoil
          if supp_htg_coil.to_CoilHeatingElectric.is_initialized
            supp_htg_coil = supp_htg_coil.to_CoilHeatingElectric.get
          elsif supp_htg_coil.to_CoilHeatingGas.is_initialized
            supp_htg_coil = supp_htg_coil.to_CoilHeatingGas.get
          end
          if supp_htg_coil.isNominalCapacityAutosized
            mech_capacity = supp_htg_coil.autosizedNominalCapacity.to_f/1000.0
          else
            mech_capacity = supp_htg_coil.nominalCapacity.to_f/1000.0
          end
          if supp_htg_coil.class.name.include? 'CoilHeatingElectric'
            cat_search = 'elecheat'
            heat_cap['elec'] += mech_capacity
          elsif supp_htg_coil.class.name.include? 'CoilHeatingGas'
            cat_search = 'FurnaceGas'
            heat_cap['Gas'] += mech_capacity
          end
        end
        # This hash contains all of the pertinent information required for costing a piece of air loop heating/cooling equipment
        equipment_info = {
          sys_type: sys_type,
          obj_type: obj_type,
          supply_comp: supplycomp,
          heating_fuel: heating_fuel,
          cooling_type: cooling_type,
          adv_dx_clg_eqpt: adv_dx_clg_eqpt,
          mech_capacity_kw: mech_capacity,
          cat_search: cat_search
        }
        unless equipment_info[:mech_capacity_kw].to_f <= 0
          # Add the piece of air loop equipment to an array for costing if the equipment does something (that is has a size larger than 0)
          airloop_equipment << equipment_info
        end
      end

      # Determine the predominant heating and cooling fuel type.
      ahu_heat_cool_info = determine_ahu_htg_clg_fuel(heat_cap: heat_cap, cool_cap: cool_cap, heat_type: heat_type, cool_type: cool_type)
      heat_type = ahu_heat_cool_info[:heat_type]
      cool_type = ahu_heat_cool_info[:cool_type]
      # Cost rooftop ventilation unit.
      costed_ahu_info = cost_ahu(sys_type: sys_type, airloop_flow_lps: airloop_flow_lps, airloop_flow_cfm: airloop_flow_cfm, mech_sizing_info: mech_sizing_info, heating_fuel: ahu_heat_cool_info[:heating_fuel], cooling_type: ahu_heat_cool_info[:cooling_type], airloop_name: airloop_name, vent_tags: ahu_tags)
      # Get ventilation heating and cooling equipment costs.
      air_loop_equip_return_info = airloop_equipment_costing(airloop_equipment: airloop_equipment, ahu_mult: costed_ahu_info[:mult].to_f, vent_tags: ahu_tags)
      # Get the air loop equipment reporting information from the air loop equipment costing method return hash
      al_eq_reporting_info = air_loop_equip_return_info[:al_eq_reporting_info]
      # Add the air loop equipment costing to the total air loop cost
      total_heat_cool_cost += air_loop_equip_return_info[:heat_cool_cost]

      # Determine information about thermal zones supplied by this air loop and sort it by building floor
      hvac_floors = gen_hvac_info_by_floor(hvac_floors: hvac_floors, model: model, prototype_creator: prototype_creator, airloop: airloop, sys_type: sys_type, hrv_info: hrv_info)
      sys_1_4 = false unless (sys_type == 1 || sys_type == 4)

      reheat_cost, reheat_array = reheat_recool_cost(airloop: airloop, prototype_creator: prototype_creator, model: model, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info, vent_tags: ahu_tags, report_mult: 1.0)

      if hrv_info[:hrv_present]
        hrv_rep = hrv_cost(hrv_info: hrv_info, airloop: airloop, vent_tags: ahu_tags, report_mult: 1.0)
        hrv_total_cost += hrv_rep[:revised_hrv_cost].to_f
      else
        hrv_rep = {}
      end

      @airloop_info[:hrv] = hrv_rep
      ahu_cost +=  costed_ahu_info[:adjusted_base_ahu_cost] + reheat_cost + total_heat_cool_cost
      @airloop_info[:equipment_info] = al_eq_reporting_info
      @airloop_info[:reheat_recool] = reheat_array
      @costing_report['ventilation'].each {|key, value| value << @airloop_info if key.to_s == ('system_' + sys_type.to_s)}
    end
    if total_vent_flow_m3_per_s == 0 || total_vent_flow_m3_per_s.nil?
      puts "No ventilation system is present which can currently be costed."
      @costing_report['ventilation'] = {
          error: "No ventilation system is present which can currently be costed."
      }
      return 0
    end
    @costing_report['ventilation'][:hrv_total_cost] = hrv_total_cost.round(2)
    mech_roof_cost, mech_roof_rep = mech_to_roof_cost(heat_type: heat_type, cool_type: cool_type, mech_room: mech_room, roof_cent: roof_cent, rt_unit_num: rt_unit_num)
    @costing_report['ventilation'][:mech_to_roof] = mech_roof_rep
    trunk_duct_cost, trunk_duct_info = vent_trunk_duct_cost(tot_air_m3pers: total_vent_flow_m3_per_s, min_space: min_space, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info, sys_1_4: sys_1_4)
    @costing_report['ventilation'][:trunk_duct] << trunk_duct_info
    floor_dist_cost, build_floor_trunk_info = floor_vent_dist_cost(hvac_floors: hvac_floors, prototype_creator: prototype_creator, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info)
    @costing_report['ventilation'][:floor_trunk_ducts] << build_floor_trunk_info
    tz_dist_cost, duct_dist_rep = tz_vent_dist_cost(hvac_floors: hvac_floors, mech_sizing_info: mech_sizing_info)
    @costing_report['ventilation'][:tz_distribution] << duct_dist_rep
    hrv_ducting_cost, hrv_ret_duct_report = hrv_duct_cost(prototype_creator: prototype_creator, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info, hvac_floors: hvac_floors)
    @costing_report['ventilation'][:hrv_return_ducting] = hrv_ret_duct_report
    ahu_cost += tz_dist_cost  + trunk_duct_cost + floor_dist_cost  + hrv_ducting_cost + hrv_total_cost + mech_roof_cost
    return ahu_cost.round(2)
  end

  # This method determines the main heating fuel and cooling type used by an air handling unit (a given model's air
  # loop). The method also determines the ahu's supplementary heating type (if any) if the primary heater is a heat
  # pump.  All capacities are in KW.
  #
  # Inputs:
  #
  # heat_cap: The capacity of heaters in the supply side of the air loop.  This is used to determine the main heating
  #          type used by the ahu.  They can be the following types:
  #           HP (Heat Pump)
  #           elec (Electricity)
  #           Gas
  #           HW (Hot Water)
  #           CCASHP (Cold Climate Air Source Heat Pump)
  # cool_cap:  The capacity of cooling units in the supply side of the air loop.  This is used to determine the main
  #           cooling type used by the ahu.  They can be the following types:
  #           DX (Direct Expansion)
  #           CHW (Chilled Water)
  #           Note that HP and CCASHP are not inculded.  If the the main heating type is a HP or CCASHP and the main
  #           cooling type is DX then the the main cooling type will be reported as being the same as the main heating
  #           type.
  # heat_type: This is a hash of counters used to determine what services (electrical lines, hot water pipes, chilled
  #            water pipes, etc.) need to be run from the main mechanical room (where they are assumed to originate) to
  #            the roof of the building (where the ahu's are located).  The following tpes are used:
  #            HP:  Heat pump (also used for CCASHP, esentially just an electircal line is needed which is always
  #            inculded anyway)
  #            elec: Electricity (an electrical line is needed which is always inculded anyway)
  #            Gas: Gas (a gas line is needed)
  #            HW: Hot water (a hot water line is needed)
  # cool_type: This is the same as heat_type only for cooling.  This is really just used to determine if a chilled water
  #            line is needed since an electrical line is always inculded.
  #            DX:  Direct Exchange (also used for HP and CCASHP since only the defaul electrical line is needed)
  #            CHW:  Chilled water (a chilled water pipe is required)
  #
  # Outputs:
  # heat_cool_info:  This is a hash that contains the return information which inculdes:
  #             heating_fuel:  The primary heating fuel used by the ahu (and supplemental heating fuel if used by a HP
  #                            or CCASHP).  This is used when searching the 'hvac_vent_ahu' sheet in the costing
  #                            spreasheet when costing the ahu.
  #             cooling_type:  The primary cooling type used by the ahu.  This is used when searching the
  #                            'hvac_vent_ahu' sheet in the costing spreadsheet when costing the ahu.
  #             heat_type:  See above (only counters adjusted)
  #             cool_type:  See above (only counters adjusted)
  #
  def determine_ahu_htg_clg_fuel(heat_cap:, cool_cap:, heat_type:, cool_type:)
    # Determine the predominant heating and cooling type by looking for the key associated with the largest value in the
    # heat_cap and cool_cap hashes.  For heating it returns HP, elec, Gas, HW or CCASHP and for cooling it returns CHW
    # or DX.
    heating_fuel = heat_cap.max_by{|key, value| value}[0]
    cooling_type = cool_cap.max_by{|key, value| value}[0]

    # Increase the counter of the associated cooling type by 1
    cool_type[cooling_type] += 1


    # If a variety of heat pump (regular HP or CCASHP) is present then, for costing, it is assumed to be the primary
    # heating type for the ahu.
    if heat_cap['HP'] > 0 || heat_cap['CCASHP'] > 0
      # Increase the heat_type counter for heat pump by 1.
      heat_type['HP'] += 1

      # Get the capacities of just the HP and CCASHP.
      pri_hp_type = {
        'HP' => heat_cap['HP'],
        'CCASHP' => heat_cap['CCASHP']
      }
      # Use the same technique for heating_fuel and cooling_type to determine which type of heat pump has the largest
      # capacity.  This is used in the off chance that more than one heat pump type is present (I'm not even sure that
      # is possible in OpenStudio air loops but I include this little bit of edge case handling anyway).
      hp_type = pri_hp_type.max_by{|key, value| value}[0].to_s
      heating_fuel = hp_type
      # It is possible to heat your building with an ASHP and use chilled water to cool your building.  I don't know why
      # you would do that but we can cost the ahu if you do.  If the main cooling type is DX (which is highly likely
      # if you are heating your air loop with an ASHP) then the main cooling type is set to be the main heating type
      # of the air loop (either regular HP or fancy CCAHP).
      if cooling_type == 'DX'
        cooling_type = hp_type
      end
      # This determines if supplemental heating is used with your heat pump (very likely in most of Canada if you heat
      # with a HP).
      unless (heat_cap['elec'] == 0) && (heat_cap['Gas'] == 0) && (heat_cap['HW'] == 0)
        # Create a hash of just the fuel heating in the air loop and change the hash key to match what we will look for
        # in the hvac_vent_ahu sheet in the costing speadsheet
        hp_supp_cap = {
          '-e' => heat_cap['elec'],
          '-g' => heat_cap['Gas'],
          '-hw' => heat_cap['HW'],
        }
        # Look for the key (which is the fuel type) with the largest associated value (which is the capacity).
        hp_supp = hp_supp_cap.max_by{|key, value| value}[0].to_s
        # Increase the heat_type count for the associated supplement heat type.  This is necessary since if gas heating
        # is used as supplemental heatnig for a heat pump then a gas line will be required between the mechanical room
        # and the roof.
        case hp_supp
        when '-e'
          heat_type['elec'] += 1
        when '-g'
          heat_type['Gas'] += 1
        when 'hw'
          heat_type['HW'] += 1
        end
      end
      # Get the heating fuel by appending the supplementary heating type just determined (if any) to the heat pump type
      heating_fuel = hp_type
      heating_fuel += hp_supp  unless hp_supp.nil?
    else
      # If you do not use a heat pump then increase the heat_type counter for whatever fuel you use to heat the air loop
      # by 1.
      heat_type[heating_fuel] += 1
    end
    # Create the hash with the results and return it (I use a hash to return a bunch of results because it seems
    # cleaner).
    heat_cool_info = {
      heating_fuel: heating_fuel,
      cooling_type: cooling_type,
      heat_type: heat_type,
      cool_type: cool_type,
    }
    return heat_cool_info
  end
  # This method tokes in:
  # ids:  The list of material ids to look for in the 'material_id' column of the materials_hvac sheet.
  # The number of ids should match the number of id_quants (this is checked earlier).
  # id_quants:  The number of the piece of equipment defined by the ids above required.  Like ids this should be an
  # array taken from the 'id_layers_quantity_multipliers' column of the 'hvac_vent_ahu' sheet for the air handler that
  # matches the required criteria.  The number of ids should match the number of id_quants (this is checked earlier).
  # overall_mult:  An multiplier to apply to all ids and id_quants (I'm not sure if this is used anymore).
  # This method cycles through each of the ids and searches for it in the 'material_id' column of the 'material_hvac'
  # sheet in the costing spreadsheet.  The equipment information found in the 'materials_hvac' is then costed.  The cost
  # is then multiplied by the associated id_quants.  For example, if the ids contains 5 elements the method searches for
  # each one.  In our example, when we get ot the 4th element of the ids we multiply its associated cost by the 4th
  # element of the id_quants array.  The total cost is then summed and multiplied by the 'overall_mult' and returned.
  def vent_assembly_cost(ids:, id_quants:, overall_mult: 1.0, vent_tags: [], report_mult: 1.0)
    assembly_tags = vent_tags.clone
    total_cost = 0
    # Cycle through each of the ids.  The index is used to select the correct element of the id_quants array.
    ids.each_with_index do |id, index|
      # Get the equipment information from the costing spreadsheet's 'material_hvac' sheet whose 'material_id' matches
      # the id.
      mat_cost_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['material_id'].to_f.round(0) == id.to_f.round(0)
      }.first
      # If it cannot find it there is an issue with either the 'materials_hvac' sheet or the 'hvac_vent_ahu' sheet which
      # the user has to deal with.
      if mat_cost_info.nil?
        raise "Error: no assembly information available for material id #{id}!"
      end
      # Get the cost for the piece of equipment, multiply it by the associated id_quants element and add to the total
      total_cost += get_vent_mat_cost(mat_cost_info: mat_cost_info, report_mult: (overall_mult*id_quants[index].to_f*report_mult), vent_tags: assembly_tags)*id_quants[index].to_f
    end
    # multiply the total by the overal_mult (which is probably always 1.0 now but I'm not sure) and return the cost.
    return (total_cost*overall_mult)
  end

  # This method finds how many pieces of costed equipment are required to meet a given load if no one piece of costed
  # equipment can do it.  It takes in two hashes:
  # mult_floor:  This should probably be mult_ceiling.  It is the maximum size of mechanical equipment that should be
  # selected.  This is used if you really want to make sure that a given piece of mechanical equipment does not exceed
  # this size.  It is normally not used.
  # loop_equip:  This hash must have the following information in it:
  # cat_search:  The category or type of the mechanical equipment that is being searched for in the 'Material' column
  # of the 'materials_hvac' sheet in the costing spreadsheet.
  # supply_comp:  This is the oir loop supply component from the OpenStudio model.  It is really just used to give a
  # name in any error messages.
  # mech_capacity:  This is the capacity of the piece of the supply component being costed.
  #
  # The method first looks for all of the items in the 'materials_hvac' sheet whose 'Material' match the 'cat_search'
  # criteria.  If none are found then something has gone wrong so an error is generated telling the user what happened.
  # Assuming it found some items it then finds the largest one (or the largest one that does not exceed the mult_floor
  # category).  It then divides the mech_capacity by the size of the costed equipment it found to determine the minimum
  # number of pieces of costed equipment meets the model equipment capacity (the multiplier).  With this information it
  # then rounds the multiplier to the next largest whole number and divides the modeled equipment capacity by this size
  # to determine the revised size of equipment (this may be smaller than the largest piece of equipment).  It then looks
  # for the smallest piece of costed equipment that meets this requirement and returns the result.
  def get_vent_system_mult(loop_equip:, mult_floor: nil)
    # Look for all of the equipment in the materials_hvac sheet that has a 'Material' that matches the cat_search
    # criteria.
    heat_cool_cost = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == loop_equip[:cat_search].to_s.upcase
    }

    # In some cases loop_equip[:supply_comp] may not be an object but a string.  If this is the case then the string
    # should be given rather than a message that nameString does not exist.
    equip_name = loop_equip[:supply_comp].nameString rescue equip_name = loop_equip[:supply_comp].to_s

    # If it cannot find any then return an error telling the user what happened.  This is likely the result of a
    # spelling mistake somewhere but it is something the user will have to deal with.
    if heat_cool_cost.nil? || heat_cool_cost.empty?
      raise "Error: no equipment could be found whose type matches the name #{loop_equip[:cat_search]} for the #{equip_name} air loop supply component!"
    end
    # Set the maximum size to be a really large number if it is not defined.
    mult_floor.nil? ? max_eq_size = 99999999999999999999.0 : max_eq_size = mult_floor.to_f
    # Find the largest piece of equipment that is smaller than the size ceiling.
    max_size = heat_cool_cost.select {|element| element['Size'].to_f <= max_eq_size}.max_by{|data| data['Size'].to_f}
    # If you cannot find any then the size ceiling is too small.  Raise an error telling the user
    if max_size.nil? || max_size.empty?
      raise "Error no equipment of the type #{loop_equip[:cat_search]} could be found with a size less than #{max_eq_size} for the #{equip_name} air loop supply component!"
    end
    # Make sure the piece of equipment has a capacity larger than 0.
    if max_size['Size'].to_f <= 0
      raise "Error: #{loop_equip[:cat_search]} has a size of 0 or less.  Please check that the correct costing_database.json file is being used or check the costing spreadsheet!"
    end
    # Find the revised number of pieces of equipment and round to the next largest whole number.
    mult = (loop_equip[:mech_capacity_kw].to_f) / (max_size['Size'].to_f)
    # This is to handle the small possibility that the revised capacity is a whole number.
    mult > (mult.to_i).to_f.round(0) ? multiplier = (mult.to_i).to_f.round(0) + 1 : multiplier = mult.round(0)
    # Find the new capacity of the pieces of equipment
    new_cap = loop_equip[:mech_capacity_kw].to_f/multiplier.to_f
    # Find the smallest piece of costed equimpent that meets the new size requirement.
    return_equip = heat_cool_cost.select{|data| data['Size'].to_f >= new_cap}.min_by{|element| element['Size'.to_f]}
    # If no costed equipment can be found that matches this new size then something is wrong and use the largest piece
    # you found before.
    return_equip = max_size if (return_equip.nil? || return_equip.empty?)
    return return_equip, multiplier.to_f
  end

  # This method finds ahu with the largest supply air capacity based on the heating and cooling characteristics defined
  # by loop_equip.  Loop_equip is a hash which includes:
  # sys_type: the NECB HVAC system type (one of 1, 3, 4, or 6)
  # heating_fuel: The predominant heating fuel
  # cooling_type: The predominant cooling type
  # airloop_flow_lps: The air loop flow rate (L/s)
  # airloop_name: The name of the air loop (used in an error message)
  #
  # If no air handler is found that meets the above requirements raise an error telling the user that something is
  # wrong.  If one or more air handlers are found choose the one with the larges 'Supply_air'.  This defines the largest
  # air handler of the given type.  Then divide the air loop air flow by the maximum air flow available.  Round up and
  # this number defines how many air handlers are required to meet the load.
  #
  # In some cases, the air loop flow rate is only a little larger than that available by the largest air handler.  For
  # example, an air loop may have a flow rate of 16000 L/s but the largest available air handler is 15000 L/s.  Rather
  # than costing two 15000 L/s air handlers it would be cheaper to cost two 8000 L/s air handlers.  To do this, the
  # method divides the air_loop_flow_lps by the number of required air handlers.  It then looks for air handlers which
  # meet the required characteristics and revised air flow rate.  If more than one are found it selects the smallest one
  # available.  It then returns this new air handler along with the raw number of air handlens (which may be a fraction)
  # and the maximum number (which will be an integer).
  def get_ahu_mult(loop_equip:)
    # Look for the largest air handler that matches the system type, heating fuel, and cooling type requirements
    ahu = @costing_database['raw']['hvac_vent_ahu'].select {|data|
      data['Sys_type'].to_f.round(0) == loop_equip[:sys_type].to_f.round(0) and
          data['Htg'].to_s.upcase == loop_equip[:heating_fuel].to_s.upcase and
          data['Clg'].to_s.upcase == loop_equip[:cooling_type].to_s.upcase
    }.max_by {|element| element['Supply_air'].to_f}
    # If none are found something has gone wrong.  Tell the user.
    if ahu.nil? || ahu.empty?
      raise "Error: no ahu information available for equipment #{loop_equip[:airloop_name]}!"
    end
    # I probably don't need to check this but make sure that the air handler has a size larger than 0.
    if ahu['Supply_air'].to_f <= 0
      raise "Error: #{loop_equip[:airloop_name]} has a size of 0 or less.  Please check that the correct costing_database.json file is being used or check the costing spreadsheet!"
    end
    # Determine the number of air handlers to be the air loop flow rate divided by the maximum air handler size.  This
    # will likely not be a whole number.
    mult = (loop_equip[:airloop_flow_lps].to_f) / (ahu['Supply_air'].to_f)
    # Since air handlers only come in integer numbers (half and air handler would not be too useful) round up to the
    # next whole number (the if statement is for the off chance that the required number ended up being an integer).
    mult > (mult.to_i).to_f.round(0) ? multiplier = (mult.to_i).to_f.round(0) + 1 : multiplier = mult.round(0)
    # Get the revised required air flow rate by dividing the air loop air flow by the number of air handlers
    rev_air_flow = loop_equip[:airloop_flow_lps].to_f / multiplier
    # Find air handlers that can meet that air flow and choose the smallest one that meets the requirement.
    rev_ahu = @costing_database['raw']['hvac_vent_ahu'].select {|data|
      data['Sys_type'].to_f.round(0) == loop_equip[:sys_type].to_f.round(0) and
        data['Htg'].to_s.upcase == loop_equip[:heating_fuel].to_s.upcase and
        data['Clg'].to_s.upcase == loop_equip[:cooling_type].to_s.upcase and
        data['Supply_air'].to_f >= rev_air_flow
    }.min_by{|info| info['Supply_air'].to_f}
    # If none are found something weird is happening so keep the one you already found.
    if rev_ahu.nil? || rev_ahu.empty?
      # Something weird happened, keep the ahu you found before.
    else
      ahu = rev_ahu
    end
    return ahu, multiplier, rev_air_flow
  end

  # This method costs a piece of mechanical equipment.  The mat_cost_info is a hash that contains the information for the
  # piece of equipment from the 'materials_hvac' sheet of the costing spreadsheet.  It contains:
  # material_id:  An index sometimes used to refer to find a specific piece of equipment
  # material:  The type of equipment.
  # description:  A description of the piece of equipment.
  # Size:  The size of the piece of equipment (see units for the unit this is in).
  # Fuel:  Sometimes this is indicates the fuel type, sometimes it is an additional size criteria.
  # source:  The source to look for the costing information. This can be placeholder or custom.
  # id:  The unique id of the costing information associated with this piece of equipment.
  # unit:  The units of the given Size (can be one of many units).
  # province_state:  For custom costing data, this is the province or state that the costing data is given for (used to
  # adjust the costing data so it can be used nationally).
  # city:  For custom costing data, this is the city that the costing data is given for (used to adjust the costing so
  # it can be used nationally).
  # year:  The year the costing information is provided for (it should be the same for everything but some costs are
  # only available in some years and not others).
  # material_cost:  The custom cost for material (e.g. the cost of a pipe).  Not used for placeholder costs.
  # labour_cost:  The custom cost for labour (e.g. the labour to install the pipe).  Not used for placeholder costs.
  # equipment_cost:  The custom cost of equipment required (e.g. the cost of any machinery required to install the pipe,
  # often this is 0).  This is not used for placeholder costs.
  # material_op_factor:  Ask Mike or Phylroy.  Probably not for placeholder costs.
  # labour_op_factor:  Ask Mike or Phylroy.  Probably not for placeholder costs.
  # equipment_op_factor:  Ask Mike or Phylroy.  Probably not for placeholder costs.
  # comments:  comments.
  # material_mult:  A fixed multiplier to multiply the material cost by.
  # labour_mult:  A fixed multiplier to multiply the labour costs by.
  # The method uses the id from 'mat_cost_info' to find costing information for the piece of equipment in the costing
  # database.  It then adjusts the material and equipment cost by the regional cost factor for the location the model
  # is supposed to be in.  The resulting adjusted equipment and material costs are then multiplied by any associated
  # multipliers and the total amount is returned.
  def get_vent_mat_cost(mat_cost_info:, vent_tags: [], report_mult: 1.0)
    cost_tags =vent_tags.clone
    if mat_cost_info.nil?
      raise("Error: no assembly information available for material!")
    end
    # Look for the costing information for the piece of equipment in the costing database.
    costing_data = @costing_database['costs'].detect {|data| data['id'].to_s.upcase == mat_cost_info['id'].to_s.upcase}
    # If no costing information is found then return an error.
    if costing_data.nil?
      raise "Error: no costing information available for material id #{mat_cost_info['id']}!"
    elsif costing_data['baseCosts']['materialOpCost'].nil? || costing_data['baseCosts']['laborOpCost'].nil?
      #This is a stub for some work that needs to be done to account for equipment costing. For now this is zeroed out.
      # A similar test is done on reading the data from the database and collected in the error file when the
      # costing database is generated.
      puts("Error: costing information for material id #{mat_cost_info['id']} is nil.  Please check costing data.")
      return 0.0
    end
    # The costs from the costing database are US national average costs (for placeholder costs) or whatever is in the
    # 'province_state' and 'city' fieleds (for custom costs).  These costs need to be adjusted to reflect the costs
    # expected in the location of interest.  The 'get_regional_cost_factors' method finds the appropriate cost
    # adjustment factors.
    mat_mult, inst_mult = get_regional_cost_factors(@costing_report['province_state'], @costing_report['city'], mat_cost_info)
    if mat_mult.nil? || inst_mult.nil?
      raise("Error: no localization information available for material id #{id}!")
    end
    # Get any associated material or labour multiplier for the equipment present in the 'materials_hvac' sheet in the
    # costing spreadsheet.
    mat_cost_info['material_mult'].to_f == 0 ? mat_quant = 1.0 : mat_quant = mat_cost_info['material_mult'].to_f
    mat_cost_info['labour_mult'].to_f == 0 ? lab_quant = 1.0 : lab_quant = mat_cost_info['labour_mult'].to_f
    # Calculate the adjusted material and labour costs.
    mat_cost = costing_data['baseCosts']['materialOpCost']*(mat_mult/100.0)*mat_quant
    lab_cost = costing_data['baseCosts']['laborOpCost']*(inst_mult/100.0)*lab_quant
    # Add information to report output if tags provided.
    unless cost_tags.empty?
      cost_tags << mat_cost_info['Material'].to_s
      cost_tags << mat_cost_info['description'].to_s
      # Add support for equipment_multiplier (if used in the future).
      mat_cost_info['equipment_mult'].nil? || mat_cost_info['equipment_mult'].to_f == 0 ? equip_quant = 1.0 : equip_quant = mat_cost_info['equipment_mult'].to_f
      add_costed_item(material_id: mat_cost_info['id'], quantity: report_mult.to_f, material_mult: mat_quant, labour_mult: lab_quant, equip_mult: equip_quant, tags: cost_tags)
    end
    # Return the total.
    return (mat_cost+lab_cost)
  end

  def cost_heat_cool_equip(equipment_info:, vent_tags: [], report_mult: 1.0)
    equip_tags = vent_tags.clone
    total_cost = 0
    multiplier, heat_cool_cost_info = get_vent_cost_data(equipment_info: equipment_info)
    total_cost += (get_vent_mat_cost(mat_cost_info: heat_cool_cost_info, vent_tags: equip_tags, report_mult: (report_mult*multiplier)))*multiplier
    if equipment_info[:cooling_type] == 'DX' || equipment_info[:cooling_type] == 'DX-adv'
      equipment_info[:cooling_type].include?("-adv") ? search_suff = "-adv" : search_suff = ""
      equipment_info[:cat_search] = "CondensingUnit" + search_suff
      equip_tags << equipment_info[:cat_search] unless equip_tags.empty?
      multiplier, heat_cool_cost_info = get_vent_cost_data(equipment_info: equipment_info)
      total_cost += get_vent_mat_cost(mat_cost_info: heat_cool_cost_info, vent_tags: equip_tags, report_mult: (report_mult*multiplier))*multiplier
      equip_tags << "piping" unless equip_tags.empty?
      piping_search = []

      piping_search << {
        mat: 'SteelPipe',
        unit: 'L.F.',
        size: 1.25,
        mult: 32.8
      }
      piping_search << {
        mat: 'PipeInsulationsilica',
        unit: 'L.F.',
        size: 1.25,
        mult: 32.8
      }
      piping_search << {
        mat: 'SteelPipeElbow',
        unit: 'each',
        size: 1.25,
        mult: 8
      }
      total_cost += get_comp_cost(cost_info: piping_search, vent_tags: equip_tags, report_mult: (report_mult*multiplier))*multiplier
      return total_cost
    end
    # This needs to be revised as currently the costing spreadsheet may not inculde heating and cooling coil costs in
    # the ahu definition sheet.  This is commented out for now but will need to be revisited.  See btap_tasks issue 156.
=begin
    if equipment_info[:heating_fuel] == 'HP'
      if sys_type == 3 || sys_type == 6
        # Remove the DX cooling unit for ashp in type 3 and 6 systems
        heat_cool_cost = @costing_database['raw']['materials_hvac'].select {|data|
          data['Material'].to_s.upcase == 'DX' and
              data['Size'].to_f.round(8) >= equipment_info[:mech_capacity_kw].to_f
        }.first
        if heat_cool_cost.nil?
          heat_cool_cost, multiplier = get_vent_system_mult(loop_equip: equipment_info)
        end
        total_cost -= (get_vent_mat_cost(mat_cost_info: heat_cool_cost))*multiplier

        # Remove the heating coil for ashp in type 3 and 6 systems
        heat_cool_cost = @costing_database['raw']['materials_hvac'].select {|data|
          data['Material'].to_s.upcase == 'COILS' and
              data['Size'].to_f.round(8) >= equipment_info[:mech_capacity_kw].to_f
        }.first
        if heat_cool_cost.nil?
          heat_cool_cost, multiplier = get_vent_system_mult(loop_equip: equipment_info)
        end
        total_cost -= (get_vent_mat_cost(mat_cost_info: heat_cool_cost))*multiplier
        puts 'hello'
      end
      # Add pre-heat for ashp in all cases
      # This needs to be refined as well.  Only add the cost of an electric heat if a heater (presumably of any type) if
      # one is not already explicitly modeled in the air loop (and thus costed already as part of this method).  This is
      # also part of btap_tasks issue 156.
      heat_cool_cost = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == 'ELECHEAT' and
            data['Size'].to_f.round(8) >= equipment_info[:mech_capacity_kw].to_f
      }.first
      if heat_cool_cost.nil?
        heat_cool_cost, multiplier = get_vent_system_mult(loop_equip: equipment_info)
      end
      total_cost += (get_vent_mat_cost(mat_cost_info: heat_cool_cost))*multiplier
    end
=end
    return total_cost
  end

  # This method collects information related a piece of equipment from the 'materials_hvac' sheet in the costing
  # spreadsheet.  This information is then used to determine the cost of a piece of equipment.  It takes in the
  # equipment_info hash.  This hash contains the following information:
  # equipment_info = {
  # cat_search: This is the category or type of mechanical equipment that is being costed.  It is used to match items in
  # the 'Material' column of the 'materials_hvac' sheet.
  # mech_capacity_kw:  This is the capacity of the piece of mechanical equipment being costed.  Although it has kw in
  # the name this is not always the case.  It is compared against information in the 'Size' column of the
  # 'materials_hvac' sheet.
  # supply_comp:  This is the OpenStudio object being costed.  If there is an error this is used to tell which piece
  # of the model had the issue.
  #
  # The method tries to find the smallest piece of equipment that matches the equipment type and that can satisfy the
  # capacity requirements.  If it cannot find one then it then it assumes that the largest matching piece of equipment
  # cannot meet the required capacity and tries to determine how many would be need to meet the required capacity.  It
  # then returns the information it found in the costing spreadsheet and the number of piece of equipment would be
  # required (if applicable)
  def get_vent_cost_data(equipment_info:)
    # Assume one piece of equipment is enough.
    multiplier = 1.0
    # Find the smallest piece of equipment in 'materials_hvac' sheet that matches the equipment type and meets the
    # capacity requirement.
    heat_cool_cost_data = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == equipment_info[:cat_search].to_s.upcase and
        data['Size'].to_f.round(8) >= equipment_info[:mech_capacity_kw].to_f
    }.min_by{|heat_cool| heat_cool[:mech_capcity_kw].to_f}
    # If it cannot find any then assume the largest piece of equipment in the costing spreadsheet is too small and
    # figure out how many of a smaller piece of equipment are required and what the smaller piece of equipment would be.
    if heat_cool_cost_data.nil? || heat_cool_cost_data.empty?
      heat_cool_cost_data, multiplier = get_vent_system_mult(loop_equip: equipment_info)
    end
    # Return the number of equipment necessary and the informatino required to find the piece of equipment in the
    # costing database.
    return multiplier, heat_cool_cost_data
  end

  def gas_burner_cost(heating_fuel:, sys_type:, airloop_flow_cfm:, mech_sizing_info:, costed_ahu_info:, vent_tags: [], report_mult: 1.0)
    ahu_airflow_lps = costed_ahu_info[:ahu]["Supply_air"].to_f
    report_mult_mod = report_mult*(-1.0)
    burner_tags = vent_tags.clone
    if (sys_type == 3 || sys_type == 6)
      return 0
      mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'ahu_airflow')
      coil_sizing_info = mech_table.select{|data| (data['ahu_airflow_range_lps'][0].to_f <= ahu_airflow_lps) && (data['ahu_airflow_range_lps'][1].to_f > ahu_airflow_lps) }
      if coil_sizing_info.empty?
        coil_sizing_kW = mech_table.max_by{|data| data['ahu_airflow_range_lps'][1]}
      else
        coil_sizing_kW = coil_sizing_info[0]
      end
      heating_kw = coil_sizing_kW['htg_coil_sizing_kW'].to_f
      cooling_kw = coil_sizing_kW['DX_coil_sizing_kW'].to_f
      heat_mech_eq_mult, heat_cost_info = get_vent_cost_data(equipment_info: {cat_search: 'coils', mech_capacity_kw: heating_kw})
      cool_mech_eq_mult, cool_cost_info = get_vent_cost_data(equipment_info: {cat_search: 'coils', mech_capacity_kw: cooling_kw})
      heating_coil_cost = heat_mech_eq_mult*get_vent_mat_cost(mat_cost_info: heat_cost_info, vent_tags: burner_tags, report_mult: (report_mult_mod*heat_mech_eq_mult))
      dx_coil_cost = cool_mech_eq_mult*get_vent_mat_cost(mat_cost_info: cool_cost_info, vent_tags: burner_tags, report_mult: (report_mult_mod*cool_mech_eq_mult))
      return heating_coil_cost + dx_coil_cost
    else
      if airloop_flow_cfm >= 1000 && airloop_flow_cfm <= 1500
        mult, mech_info = get_vent_cost_data(equipment_info: {cat_search: 'DuctFurGasExt', mech_capacity_kw: 88})
        return get_vent_mat_cost(mat_cost_info: mech_info, vent_tags: burner_tags, report_mult: (report_mult_mod*mult))*mult
      elsif airloop_flow_cfm > 1500
        mult, mech_info = get_vent_cost_data(equipment_info: {cat_search: 'DuctFurGasExt', mech_capacity_kw: 132})
        return get_vent_mat_cost(mat_cost_info: mech_info, vent_tags: burner_tags, report_mult: (report_mult_mod*mult))*mult
      end
    end
    return 0.0
  end

  # This method looks for an air handler in the 'hvac_vent_ahu' sheet of the costing spreadsheet.  The inputs it uses
  # to find the air handler are:
  # sys_type:  HVAC system type (can handle NECB systems 1, 3, 4 or 6)
  # airloop_flow_lps:  Air loop design air flow rate (L/s)
  # heating_fuel:  The predominant heating fuel used by the air loop (HP, CCASHP, HW, Gas, Propane, Oil)
  # cooling_type:  The predominant cooling type used by the air loop (DX, HP, CCASHP, CHW)
  # airloop_name:  The name of the air loop (only used for error messages)
  #
  # If no air handler with matching characteristics are found it assumes that all of the ones in the 'hvac_vent_ahu' ore
  # too small.  I then calls get_ahu_mult to find the largest air handler with the appropriate characteristics and finds
  # how many of those are required to meet the load (see get_ahu_mult for more information).  Once the appropriate air
  # handler is selected from the 'hvac_vent_ahu' the method then reads the numbers in column K (id_layers) and column N
  # (id_layers_quantity_multipliers).  The numbers in 'id_layers' are indexes that match column A (material_id) in the
  # 'material_hvac' costing spreadsheet sheet.  The numbers in 'id_layers_quantity_multipliers' define how many pieces
  # of equipment defined in the id_layer.  The method then calls the 'vent_assembly_cost' method which takes the set of
  # id_layers, the 'id_layers_quantity_multipliers' and the overall_mult.  This costs each item in 'id_layers',
  # multiplies the cost by the number in 'id_layers_quantity_multipliers' and multiplies everything by 'overall_mult'.
  # The returned cast is then multiplied by the number of air handlers present (mult) and returns the cost.
  #
  # The method now also also includes the call to the 'gas_burner_cost' method to adjust for burner costs.  It also
  # includes the ahu size adjustement previously done in the main 'ahu_costing' method.
  def cost_ahu(sys_type:, airloop_flow_lps:, airloop_flow_cfm:, mech_sizing_info:, heating_fuel:, cooling_type:, airloop_name:, vent_tags: [])
    # Assmue one air handler to start
    mult = 1.0
    # Find an air handler in the 'hvac_vent_ahu' sheet that matches the system_type, air flow rate, heating type and
    # cooling type.
    ahu = @costing_database['raw']['hvac_vent_ahu'].select {|data|
      data['Sys_type'].to_f.round(0) == sys_type.to_f.round(0) and
          data['Supply_air'].to_f >= airloop_flow_lps and
          data['Htg'].to_s == heating_fuel and
          data['Clg'].to_s == cooling_type
    }.min_by{|info| info['Supply_air'].to_f}
    # If none are there assume that none had a big enough air flow rate.  Create a data structure with the pertinent
    # air handler information.
    if ahu.nil? || ahu.empty?
      loop_equip = {
          sys_type: sys_type,
          heating_fuel: heating_fuel,
          cooling_type: cooling_type,
          airloop_flow_lps: airloop_flow_lps,
          airloop_name: airloop_name
      }
      # Find send the air handler information to the 'get_ahu_mult' method which returns the air handler information and
      # the number which will meet the supply air rate.
      ahu, mult, rev_airloop_flow_lps = get_ahu_mult(loop_equip: loop_equip)
      # If one air handler which meets the requirements is found then use that one.
    else
      rev_airloop_flow_lps = airloop_flow_lps
    end
    # set the number of air hondlers in @airloop_info which is included in the ventilation costing report.
    @airloop_info[:num_rooftop_units] = mult.to_i
    # Calculate the ahu cost modifier for systems other than the largest (recreation of modifier originally applied in
    # the 'ahu_costing' method).
    ahu['Supply_air'].to_f.round(0) == 15000 ? ahu_cost_mod = 1.0 : ahu_cost_mod = (rev_airloop_flow_lps/(ahu['Supply_air'].to_f))
    # Get the 'id_layers' from the 'hvac_vent_ahu' sheet and put them into an array
    ids = ahu['id_layers'].to_s.split(',')
    # Get the quantity of each of the preceding 'id_layers'.  To do this, get the 'id_layers_quantity_multipliers'
    # numbers from the 'hvac_vent_ahu' and convert them into an array
    id_quants = ahu['Id_layers_quantity_multipliers'].to_s.split(',')
    # Check that the number of ids is the same as the number of id_quants.  If it isn't something is wrong and raise an
    # error.
    raise "The number of id_layers does not match the number of id_layer_quantity_multipliers in the hvac_vent_auh sheet of the costing spreadsheet.  Please look for the air handler in the costing spreadsheet and check the appropriate columns.  The air handler characteristics are: #{ahu}" if ids.size != id_quants.size
    # Get the overall_mult.  This used to be used but does not seem to be used anymore.  I left it in just in case
    # (probably a bad idea).
    overall_mult = ahu['material_mult'].to_f
    overall_mult = 1.0 if overall_mult == 0

    # Create tags that will be added to the cost list output
    new_tags = vent_tags.clone
    new_tags << heating_fuel
    new_tags << cooling_type
    new_tags << "Required Air Flow (L/s): #{airloop_flow_lps.to_f.round(2)}"
    new_tags << "Total AHU Air Flow with Multipliers(L/s): #{(ahu['Supply_air'].to_f*mult).to_f.round(2)}"
    new_tags << "AHU Equipment"

    # Cost the ids (multiplied by the number associated id_quants) and maltiply everything by the number of air handlers
    # (if one was too small).
    ind_ahu_cost = vent_assembly_cost(ids: ids, id_quants: id_quants, overall_mult: overall_mult, vent_tags: new_tags, report_mult: (overall_mult*ahu_cost_mod*mult))
    # This is the total ahu cost without adjusting cost with airflow
    calc_ahu_cost = ind_ahu_cost*mult
    # Create the start of the return hash (done here because it is used in the 'gas_burner_cost' method)
    costed_ahu_info = {
      ahu: ahu,
      mult: mult,
      air_loop_flow_lps: airloop_flow_lps,
      ind_ahu_cost: ind_ahu_cost
    }
    new_tags.pop
    # Remove gas burner cost from ahu cost because it is accounted for in the heating and cooling equipment calculated later.
    new_tags << "AHU Cost Adjustment"
    ahu_mech_adj = gas_burner_cost(heating_fuel: heating_fuel, sys_type: sys_type, airloop_flow_cfm: airloop_flow_cfm, mech_sizing_info: mech_sizing_info, costed_ahu_info: costed_ahu_info, vent_tags: new_tags, report_mult: ahu_cost_mod)
    base_ahu_cost = calc_ahu_cost - ahu_mech_adj
    # Caclculate the adjusted ahu cost
    adj_ahu_cost = (ind_ahu_cost*mult- ahu_mech_adj)*ahu_cost_mod
    # Add costs to costing output
    @airloop_info[:ind_ahu_max_airflow_l_per_s] = ahu['Supply_air'].to_f.round(0)
    @airloop_info[:base_ahu_cost] = base_ahu_cost.round(2)
    @airloop_info[:revised_base_ahu_cost] = adj_ahu_cost.round(2)

    # Add ahu costs to return hash
    costed_ahu_info[:base_ahu_cost] = base_ahu_cost
    costed_ahu_info[:adjusted_base_ahu_cost] = adj_ahu_cost

    return costed_ahu_info
  end

  def mech_to_roof_cost(heat_type:, cool_type:, mech_room:, roof_cent:, rt_unit_num:)
    mech_to_roof_rep = {
        Gas_Line_m: 0.0,
        HW_Line_m: 0.0,
        CHW_Line_m: 0.0,
        Elec_Line_m: 0.0,
        Total_cost: 0.0
    }
    mech_dist = [(roof_cent[:roof_centroid][0] - mech_room['space_centroid'][0]), (roof_cent[:roof_centroid][1] - mech_room['space_centroid'][1]), (roof_cent[:roof_centroid][2] - mech_room['space_centroid'][2])]
    utility_dist = 0
    ut_search = []
    rt_roof_dist = OpenStudio.convert(10, 'm', 'ft').get
    mech_dist.each{|dist| utility_dist+= dist.abs}
    utility_dist = OpenStudio.convert(utility_dist, 'm', 'ft').get
    heat_type.each do |key, value|
      if value >= 1
        case key
        when 'HP'
          next
        when 'elec'
          next
        when 'Gas'
          ut_search << {
              mat: 'GasLine',
              unit: 'L.F.',
              size: 0,
              mult: utility_dist + rt_roof_dist*value
          }
          heat_type['Gas'] = 0
          mech_to_roof_rep[:Gas_Line_m] == (utility_dist + rt_roof_dist*value).round(1)
        when 'HW'
          ut_search << {
              mat: 'SteelPipe',
              unit: 'L.F.',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
          mech_to_roof_rep[:HW_Line_m] = (2*utility_dist + 2*rt_roof_dist*value).round(1)
          ut_search << {
              mat: 'PipeInsulation',
              unit: 'none',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
          ut_search << {
              mat: 'PipeJacket',
              unit: 'none',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
        end
      end
    end

    cool_type.each do |key, value|
      if value >= 1
        case key
        when 'DX'
          next
        when 'CHW'
          ut_search << {
              mat: 'SteelPipe',
              unit: 'L.F.',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
          mech_to_roof_rep[:CHW_Line_m] = (2*utility_dist + 2*rt_roof_dist*value).round(1)
          ut_search << {
              mat: 'PipeInsulation',
              unit: 'none',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
          ut_search << {
              mat: 'PipeJacket',
              unit: 'none',
              size: 4,
              mult: 2*utility_dist + 2*rt_roof_dist*value
          }
        end
      end
    end
    mech_to_roof_rep[:Elec_Line_m] = (utility_dist + rt_unit_num*rt_roof_dist).round(1)
    ut_search << {
        mat: 'Wiring',
        unit: 'CLF',
        size: 10,
        mult: (utility_dist + rt_unit_num*rt_roof_dist)/100
    }
    ut_search << {
        mat: 'Conduit',
        unit: 'L.F.',
        size: 0,
        mult: utility_dist + rt_unit_num*rt_roof_dist
    }
    total_comp_cost = get_comp_cost(cost_info: ut_search)
    mech_to_roof_rep[:Total_cost] = total_comp_cost.round(2)
    return total_comp_cost, mech_to_roof_rep
  end

  def reheat_recool_cost(airloop:, prototype_creator:, model:, roof_cent:, mech_sizing_info:, vent_tags: [], report_mult: 1.0)
    reheat_recool_tags = vent_tags.clone
    heat_cost = 0
    out_reheat_array = []
    airloop.thermalZones.sort.each do |thermalzone|
      tz_mult = thermalzone.multiplier.to_f
      thermalzone.equipment.sort.each do |eq|
        tz_eq_cost = 0
        terminal, box_name = get_airloop_terminal_type(eq: eq)
        next if box_name.nil?
        if terminal.isMaximumAirFlowRateAutosized.to_bool
          query = "SELECT Value FROM ComponentSizes WHERE CompName='#{eq.name.to_s.upcase}' AND Description='Design Size Maximum Air Flow Rate'"
          air_m3_per_s = model.sqlFile().get().execAndReturnFirstDouble(query).to_f/tz_mult
        else
          air_m3_per_s = terminal.maximumAirFlowRate.to_f/tz_mult
        end
        tz_centroids = prototype_creator.thermal_zone_get_centroid_per_floor(thermalzone)
        reheat_recool_tags << thermalzone.name.to_s
        if box_name == 'CVMixingBoxes'
          reheat_recool_tags << "Contant Volume Mixing Box" unless vent_tags.empty?
          tz_eq_cost, box_info = reheat_coil_costing(terminal: terminal, tz_centroids: tz_centroids, model: model, tz: thermalzone, roof_cent: roof_cent, tz_mult: tz_mult, mech_sizing_info: mech_sizing_info, air_m3_per_s: air_m3_per_s, box_name: box_name, vent_tags: reheat_recool_tags, report_mult: (tz_mult*report_mult))
          reheat_recool_tags.pop()
        else
          reheat_recool_tags << "VAV" unless vent_tags.empty?
          tz_eq_cost, box_info = vav_cost(terminal: terminal, tz_centroids: tz_centroids, tz: thermalzone, roof_cent: roof_cent, mech_sizing_info: mech_sizing_info, air_flow_m3_per_s: air_m3_per_s, box_name: box_name, vent_tags: reheat_recool_tags, report_mult: (tz_mult*report_mult))
          reheat_recool_tags.pop()
        end
        reheat_recool_tags.pop()
        heat_cost += tz_mult*tz_eq_cost
        out_reheat_array << {
            terminal: (terminal.iddObjectType.valueName.to_s)[3..-1],
            zone_mult: tz_mult,
            box_type: box_name,
            box_name: terminal.nameString,
            unit_info: box_info,
            cost: tz_eq_cost.round(2)
        }
      end
    end
    return heat_cost, out_reheat_array
  end

  def get_airloop_terminal_type(eq:)
    case eq.iddObject.name
    when /OS:AirTerminal:SingleDuct:ConstantVolume:Reheat/
      terminal = eq.to_AirTerminalSingleDuctConstantVolumeReheat.get
      box_name = 'CVMixingBoxes'
    when /OS:AirTerminal:SingleDuct:VAV:NoReheat/
      terminal = eq.to_AirTerminalSingleDuctVavNoReheat.get
      box_name = 'VAVFanMixingBoxesClg'
    when /OS:AirTerminal:SingleDuct:VAV:Reheat/
      terminal = eq.to_AirTerminalSingleDuctVAVReheat.get
      box_name = 'VAVFanMixingBoxesHtg'
    when /OS:AirTerminal:SingleDuct:ConstantVolume:NoReheat/
      terminal = eq.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
      box_nam = nil
    else
      terminal = nil
      box_name = nil
    end
    return terminal, box_name
  end

  def reheat_coil_costing(terminal:, tz_centroids:, model:, tz:, roof_cent:, tz_mult:, mech_sizing_info:, air_m3_per_s:, box_name:, vent_tags: [], report_mult: 1.0)
    coil_tags = vent_tags.clone
    coil_mat = 'none'
    coil_cost = 0
    coil = terminal.reheatCoil
    case coil.iddObject.name
    when /Water/
      coil = coil.to_CoilHeatingWater.get
      if coil.isRatedCapacityAutosized
        capacity = coil.autosizedRatedCapacity.to_f/(1000.0*tz_mult)
      else
        capacity = coil.ratedCapacity.to_f/(1000.0*tz_mult)
      end
      coil_mat = 'Coils'
      coil_tags << "water coil" unless coil_tags.empty?
    when /Electric/
      coil = coil.to_CoilHeatingElectric.get
      if coil.isNominalCapacityAutosized.to_bool
        capacity = (coil.autosizedNominalCapacity.to_f)/(1000.0*tz_mult)
      else
        capacity = (coil.nominalCapacity.to_f)/(1000.0*tz_mult)
      end
      coil_mat = 'ElecDuct'
      coil_tags << "electric duct heater" unless coil_tags.empty?
    end
    return 0, {size_kw: 0.0, air_flow_m3_per_s: 0.0, pipe_dist_m: 0.0, elect_dist_m: 0.0, num_units: 0} if coil_mat == 'none'
    pipe_length_m = 0
    elect_length_m = 0
    num_coils = 0
    tz_centroids.sort.each do |tz_cent|
      coil_tags << tz_cent[:story_name]
      story_floor_area = 0
      num_coils += 1
      tz_cent[:spaces].each { |space| story_floor_area += space.floorArea.to_f }
      floor_area_frac = (story_floor_area/tz.floorArea).round(2)
      floor_cap = floor_area_frac*capacity
      coil_cost += get_mech_costing(mech_name: coil_mat, size: floor_cap, terminal: terminal, vent_tags: coil_tags, report_mult: report_mult)
      coil_cost += get_mech_costing(mech_name: box_name, size: floor_area_frac*(OpenStudio.convert(air_m3_per_s, 'm^3/s', 'cfm').get), terminal: terminal, vent_tags: coil_tags, report_mult: report_mult)
      ut_dist = (tz_cent[:centroid][0].to_f - roof_cent[:roof_centroid][0].to_f).abs + (tz_cent[:centroid][1].to_f - roof_cent[:roof_centroid][1].to_f).abs
      if coil_mat == 'Coils'
        pipe_length_m += ut_dist
        coil_cost += piping_cost(pipe_dist_m: ut_dist, mech_sizing_info: mech_sizing_info, air_m3_per_s: air_m3_per_s, vent_tags: coil_tags, report_mult: report_mult)
      end
      elect_length_m += ut_dist
      coil_cost += vent_box_elec_cost(cond_dist_m: ut_dist, vent_tags: coil_tags, report_mult: report_mult)
      coil_tags.pop()
    end
    box_info = {size_kw: capacity.round(3), air_flow_m3_per_s: air_m3_per_s.round(3), pipe_dist_m: pipe_length_m.round(1), elect_dist_m: elect_length_m.round(1), num_units: num_coils}
    return coil_cost, box_info
  end

  def vav_cost(terminal:, tz_centroids:, tz:, roof_cent:, mech_sizing_info:, air_flow_m3_per_s:, box_name:, vent_tags: [], report_mult: 1.0)
    cost = 0
    pipe_length_m = 0
    elect_length_m = 0
    num_coils = 0
    tz_centroids.sort.each do |tz_cent|
      vav_tags = vent_tags.clone
      vav_tags << tz_cent[:story_name] unless vav_tags.empty?
      num_coils += 1
      story_floor_area = 0
      tz_cent[:spaces].each { |space| story_floor_area += space.floorArea.to_f }
      floor_area_frac = (story_floor_area/tz.floorArea).round(2)
      cost += get_mech_costing(mech_name: box_name, size: floor_area_frac*(OpenStudio.convert(air_flow_m3_per_s, 'm^3/s', 'cfm').get), terminal: terminal, vent_tags: vav_tags, report_mult: report_mult)
      ut_dist = (tz_cent[:centroid][0].to_f - roof_cent[:roof_centroid][0].to_f).abs + (tz_cent[:centroid][1].to_f - roof_cent[:roof_centroid][1].to_f).abs
      if /Htg/.match(box_name)
        pipe_length_m += ut_dist
        cost += piping_cost(pipe_dist_m: ut_dist, mech_sizing_info: mech_sizing_info, air_m3_per_s: floor_area_frac*air_flow_m3_per_s, vent_tags: vav_tags, report_mult: report_mult)
      end
      elect_length_m += ut_dist
      cost += vent_box_elec_cost(cond_dist_m: ut_dist, vent_tags: vav_tags, report_mult: report_mult)
    end
    box_info = {size_kw: 0.0, air_flow_m3_per_s: air_flow_m3_per_s.round(3), pipe_dist_m: pipe_length_m.round(1), elect_dist_m: elect_length_m.round(1), num_units: num_coils}
    return cost, box_info
  end

  # This method gets the cost of a piece of equipment.  I takes the following in:
  # mech_name:  The category or type of equipment that is being searched for in the 'Material' column of the
  # 'materials_hvac' sheet of the costing spreadsheet.
  # size: The size of the piece of equipment being searched for.
  # terminal: The openstudio object being costed (used to let the user know if there is an issue finding costing info).
  # mult: A switch which is used to determine if you want to cost multiple pieces of equipment.  If it is set to true
  # (the default) then if a piece of equipment is too large to be costed, then multiple smaller pieces of equipment will
  # be costed.  If it is set to false, then only 1 of the largest piece of equipment will be costed.
  def get_mech_costing(mech_name:, size:, terminal:, use_mult: true, vent_tags: [], report_mult: 1.0)
    mech_cost_tags = vent_tags.clone
    # Turn the input into something that the get_vent_cost_data method can use.
    mech_info = {
      cat_search: mech_name,
      mech_capacity_kw: size,
      supply_component: terminal
    }
    # Get the costing information and multiplier (if the piece of equipment is too large) for the equipment.
    mech_mult, cost_info = get_vent_cost_data(equipment_info: mech_info)
    # Use only one piece of equipment if use_mult is set to false
    mech_mult = 1.0 unless use_mult
    # Return the total cost for the piece of equipment.
    return get_vent_mat_cost(mat_cost_info: cost_info, vent_tags: mech_cost_tags, report_mult: (mech_mult*report_mult))*mech_mult
  end

  def piping_cost(pipe_dist_m:, mech_sizing_info:, air_m3_per_s:, is_cool: false, vent_tags: [], report_mult: 1.0)
    piping_tags = vent_tags.clone
    piping_tags << "piping" unless piping_tags.nil?
    pipe_dist = OpenStudio.convert(pipe_dist_m, 'm', 'ft').get
    air_flow = (OpenStudio.convert(air_m3_per_s, 'm^3/s', 'L/s').get)
    air_flow = 15000 if air_flow > 15000
    mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'piping')
    pipe_sz_info = mech_table.select {|pipe_choice|
      pipe_choice['ahu_airflow_range_Literpers'][0].to_f.round(0) < air_flow.round(0) and
          pipe_choice['ahu_airflow_range_Literpers'][1].to_f.round(0) >= air_flow.round(0)
    }.first
    pipe_dia = pipe_sz_info['heat_valve_pipe_dia_inch'].to_f.round(2)
    pipe_dia = pipe_sz_info['cool_valve_pipe_dia_inch'].to_f.round(2) if is_cool == true
    pipe_cost_search = []
    pipe_cost_search << {
        mat: 'Steelpipe',
        unit: 'L.F.',
        size: pipe_dia,
        mult: 2*pipe_dist
    }
    pipe_cost_search << {
        mat: 'SteelPipeElbow',
        unit: 'none',
        size: pipe_dia,
        mult: 2
    }
    pipe_cost_search << {
        mat: 'SteelPipeTee',
        unit: 'none',
        size: pipe_dia,
        mult: 2
    }
    pipe_cost_search << {
        mat: 'SteelPipeTeeRed',
        unit: 'none',
        size: pipe_dia,
        mult: 2
    }
    pipe_cost_search << {
        mat: 'SteelPipeRed',
        unit: 'none',
        size: pipe_dia,
        mult: 2
    }
    pipe_dia > 3 ? pipe_dia_union = 3 : pipe_dia_union = pipe_dia
    pipe_cost_search << {
        mat: 'SteelPipeUnion',
        unit: 'none',
        size: pipe_dia_union,
        mult: 2
    }
    return get_comp_cost(cost_info: pipe_cost_search, vent_tags: piping_tags, report_mult: report_mult)
  end

  def vent_box_elec_cost(cond_dist_m:, vent_tags: [], report_mult: 1.0)
    elec_tags = vent_tags.clone
    elec_tags << "electrical" unless elec_tags.empty?
    cond_dist = OpenStudio.convert(cond_dist_m, 'm', 'ft').get
    elec_cost_search = []
    elec_cost_search << {
        mat: 'Wiring',
        unit: 'CLF',
        size: 14,
        mult: cond_dist/100
    }
    elec_cost_search << {
        mat: 'Conduit',
        unit: 'L.F.',
        size: 0,
        mult: cond_dist
    }
    elec_cost_search << {
        mat: 'Box',
        unit: 'none',
        size: 4,
        mult: 1
    }
    elec_cost_search << {
        mat: 'Box',
        unit: 'none',
        size: 1,
        mult: 1
    }
    return get_comp_cost(cost_info: elec_cost_search, vent_tags: elec_tags, report_mult: report_mult)
  end

  def get_comp_cost(cost_info:, vent_tags: [], report_mult: 1.0)
    vent_comp_tags = vent_tags.clone
    cost = 0
    cost_info.each do |comp|
      comp_info = nil
      if comp[:unit].to_s == 'none'
        comp_info = @costing_database['raw']['materials_hvac'].select {|data|
          data['Material'].to_s.upcase == comp[:mat].to_s.upcase and
              data['Size'].to_f.round(2) == comp[:size].to_f.round(2)
        }.first
      elsif comp[:size].to_f == 0
        comp_info = @costing_database['raw']['materials_hvac'].select {|data|
          data['Material'].to_s.upcase == comp[:mat].to_s.upcase and
              data['unit'].to_s.upcase == comp[:unit].to_s.upcase
        }.first
      else
        comp_info = @costing_database['raw']['materials_hvac'].select {|data|
          data['Material'].to_s.upcase == comp[:mat].to_s.upcase and
              data['Size'].to_f.round(2) == comp[:size].to_f.round(2) and
              data['unit'].to_s.upcase == comp[:unit].to_s.upcase
        }.first
      end
      if comp_info.nil?
        puts("No data found for #{comp}!")
        raise
      end
      # report_mult included for cost list output.
      cost += get_vent_mat_cost(mat_cost_info: comp_info, vent_tags: vent_comp_tags, report_mult: (comp[:mult].to_f*report_mult))*(comp[:mult].to_f)
    end
    return cost
  end

  def get_mech_table(mech_size_info:, table_name:)
    table = mech_size_info.select {|hash|
      hash['component'].to_s.upcase == table_name.to_s.upcase
    }.first
    return table['table']
  end

  # This method finds the centroid of the ceiling line on a given story furthest from the specified point.  It only
  # takes into account ceilings that above conditioned spaces that are not plenums.  A line can be defined between the
  # supplied point (we'll call it point O) and the ceiling line centroid furthest from that point(we'll call it point A).
  # We will call this line AO.  If the full_length input argument is set to true the method will also return the point
  # where line AO intercepts the ceiling line on the other side of the building.  Note that the method only looks at x
  # and y coordinates and ignores the z coordinate of the point you pass it.  The method assumes that the ceilings of
  # all of the spaces on the floor you pass it are flat so generally ignores their z components as well.  This was done
  # to avoid further complicating things with 3D geometry.  If the ceilings of all of the spaces in the building story
  # you pass the method are not flat it will still work but pretend as though the ceilings are flat by ignoring the z
  # coordinate.
  #
  # The method works by going through each space in the supplied building story and finding the ones which are
  # conditioned (either heated or cooled) and which are not considered plenums.  It then goes through the surfaces of
  # the conditioned spaces and finds the ones which have an OpenStudio SurfaceType of 'RoofCeiling'.  It then goes
  # through each point on that surface and makes lines going from the current point (CP) to the previous point (PP).  It
  # calculates the centroid (LC) of the line formed between PP and CP by averaging each coordinate of PP and CP.  It then
  # determines which LC is furthest from the supplied point (point O) and this becomes point A.  Note that point A is not
  # necessarily on the outside of a building since no checks are made on where line P lies in the building (only that it
  # is on a RoofCeiling above a conditioned space that is not a plenum).  For example in the LargeOffice building
  # archetype point P generally lies on one of the short edges of the trapezoids forming the perimeter spaces.  This is
  # if this reference point (O) is the center of the building.
  #
  # The inputs arguments are are:
  # building_story:  OpenStudio BuildingStory object.  A building story defined in OpenStudio.
  # prototype_creator:  The Openstudio-standards object, containing all of the methods etc. in the nrcan branch of
  #                     Openstudio-standards.
  # target_cent:  Array.  The point you supply from which you want to find the furthest ceiling line centroid (point O
  #               in the description above).  This point should be a one dimensional array containing at least two
  #               elements target_cent[0] = x, target_cent[1] = y.  The array can have more points but they will be
  #               ignored.  This point should be inside the building.
  # tol:  Float.  The tolerence used by the method when rounding geometry (default is 8 digits after decimal).
  # full_length:  Boolean true/false
  #               The switch which tells the method whether or not it should find, and supply, the point where line AO (
  #               as defined above) intercepts the other side of the building.  It is defaulted to false, meaning it
  #               will only return points A and O.  If it set to 'true' it will return the point where line AO
  #               intercepts the other side of the building.  It does this by going through all of the ceiling lines
  #               in the specified building story and determining if any intercept line AO (let us call each intercepts
  #               point C).  It then runs through each intercept (point C) and determines which C makes line AOC the
  #               longest.
  #
  # The output is the following hash.
  #
  # {
  #   start_point:  Hash.  A hash which defines point A and provides a bunch of other information (see below),
  #   mid_point:  Hash.  This is a hash containing the array defining the point you passed the method in the first
  #               place.,
  #   end_point:  Hash.  If full_length was set to true then this defines point C and provides a bunch of other
  #               information (see below).  If full_length was not set to false or undefined then this is set to nil.
  #
  # The structure of the hashes start_point and end_point are identical.  I will only define the hash start_point below
  # noting differences for end_point.
  #
  # start_point: {
  #   space:  OpenStudio Space object.  The space that contains point A (or point C if in the end_point hash).,
  #   surface:  OpenStudio Surface object.  The surface in space that contains point A (should have a RoofCeiling
  #             SpaceType).  In the case of the end_point hash this is the surface that contains point C.,
  #   verts:  Two dimmensional array.  The points defining ':surface'.  These points are in the building coordinate
  #           system (rather than the space coordinate system).  These points are ordered clockwise when viewed with the
  #           surface normal pointed towards the viewer.  The array would be structured as follows:
  #           [1st point, 2nd point, ..., last point].  Each point is an array as follows:  [x coord, y coord, z coord].
  #           The points are in meters.,
  #   line:  Hash.  A hash defining the line containing point A (point C if this is in the 'end_point' hash).  See
  #          definition below.
  # }
  #
  # 'line' has the identical structure in the start_point and end_point hashes.  I will define it once but note any
  # differences for when it is containing in the start_point and end_point hashes.
  #
  # line: {
  #   verta:  Array.  The end point of the line containing point A (when in the start_point hash) or point C (when in
  #           the end_point hash).  It is formed as [x, y, z].  It is in the building coordinate system, in meters.
  #   ventb:  Array.  The start point of the line containing point A (when in the start_point hash) or point C (when in
  #           the end_point hash).  It is formed as [x, y, z].  It is in the building coordinate system, in meters.
  #   int:  Array.  If this is in the start_point hash then this is the centre of the line from vertb to verta.  If this
  #         is in the end_point hash then this is the intercept of the line AO with the line starting with vertb and
  #         ending with verta.  It is formed as [x, y, z].  It is in the building coordinate system, in meters.  If in
  #         the start_point hash then the z coordinate is the average of the z coordinates of verta and vertb.  If in
  #         the end_point hash then the z coordinate is calculated by first determining of the distance of the line
  #         between vertb and verta when only using their x and y coordinates (we will call it the xy_dist).  Then the
  #         distance from just the x and y coordinates of ventb to the x and y coordinates (the only ones provided) of
  #         point C is determined (we will call it the c_dist).  The fraction c_dist/xy_dist is then found and added to
  #         the z coordinate of ventb thus providing the z coordinate of point C.
  #   i:    Integer.  The index of verta in the verts array.
  #   ip:   Integer.  The index of vertb in the verts array.
  #   dist:  If in the start_point hash this is the distance between point A and point O using only the x and y
  #          coordinates of the respective points.  If in the end_point hash this is the distance between point A and
  #          point C using only the x and y coordinates of the respective points.  In meters.
  # }
  #
  def get_story_cent_to_edge(building_story:, prototype_creator:, target_cent:, tol: 8, full_length: false)
    ceiling_start = []
    space_mod = OpenstudioStandards::Space
    building_story.spaces.sort.each do |space|
      if (space_mod.space_heated?(space) || space_mod.space_cooled?(space)) && !space_mod.space_plenum?(space)
        origin = [space.xOrigin.to_f, space.yOrigin.to_f, space.zOrigin.to_f]
        space.surfaces.each do |surface|
          if surface.surfaceType.to_s.upcase == 'ROOFCEILING'
            verts = surface.vertices
            dists = []
            surf_verts = []
            for index in 1..verts.length
              index == verts.length ? i = 0 : i = index
              i == 0 ? ip = verts.length - 1 : ip = i - 1
              verta = [verts[i].x.to_f + origin[0], verts[i].y.to_f + origin[1], verts[i].z.to_f + origin[2]]
              vertb = [verts[ip].x.to_f + origin[0], verts[ip].y.to_f + origin[1], verts[ip].z.to_f + origin[2]]
              cent = [(verta[0] + vertb[0])/2.0 , (verta[1] + vertb[1])/2.0, (verta[2] + vertb[2])/2.0]
              dist = Math.sqrt((target_cent[0].to_f - cent[0])**2 + (target_cent[1].to_f - cent[1])**2)
              dists << {
                  verta: verta,
                  vertb: vertb,
                  int: cent,
                  i: i,
                  ip: ip,
                  dist: dist
              }
              surf_verts << vertb
            end
            max_dist = dists.max_by{|dist_el| dist_el[:dist].to_f}
            ceiling_start << {
                space: space,
                surface: surface,
                verts: surf_verts,
                line: max_dist
            }
          end
        end
      end
    end

    return nil if ceiling_start.empty?

    furthest_line = ceiling_start.max_by{|wall| wall[:line][:dist].to_f}

    return {start_point: furthest_line, mid_point: target_cent, end_point: nil} unless full_length

    x_dist_ref = (furthest_line[:line][:int][0].round(tol) - target_cent[0].round(tol))
    x_dist_ref == 1 if x_dist_ref == 0
    y_dist_ref = (furthest_line[:line][:int][1].round(tol) - target_cent[1].round(tol))
    y_dist_ref == 1 if y_dist_ref == 0
    x_side_ref = x_dist_ref/x_dist_ref.abs
    y_side_ref = y_dist_ref/y_dist_ref.abs
    linea_eq = get_line_eq(a: target_cent, b: furthest_line[:line][:int], tol: tol)
    ints = []
    ceiling_start.each do |side|
      verts = side[:verts]
      for index in 1..(verts.length)
        index == verts.length ? i = 0 : i = index
        i == 0 ? ip = verts.length-1 : ip = i - 1
        lineb = [verts[i], verts[ip]]
        int = line_int(line_seg: lineb, line: linea_eq, tol: tol)
        next if int.nil?
        x_dist = (int[0].round(tol) - target_cent[0].round(tol))
        x_dist = 1 if x_dist == 0
        y_dist = (int[1].round(tol) - target_cent[1].round(tol))
        y_dist = 1 if y_dist == 0
        x_side = x_dist/x_dist.abs
        y_side = y_dist/y_dist.abs
        next if x_side == x_side_ref && y_side == y_side_ref
        ceil_dist = Math.sqrt((furthest_line[:line][:int][0] - int[0])**2 + (furthest_line[:line][:int][1] - int[1])**2)
        int_dist = Math.sqrt((int[0] - verts[ip][0])**2 + (int[1] - verts[ip][1])**2)
        line_dist = Math.sqrt((verts[i][0] - verts[ip][0])**2 + (verts[i][1] - verts[ip][1])**2)
        z_coord = verts[ip][2] + ((verts[i][2] - verts[ip][2])*int_dist/line_dist)
        ints << {
            ceiling_info: side,
            line: lineb,
            int: [int[0], int[1], z_coord],
            i: i,
            ip: ip,
            dist: ceil_dist
        }
      end
    end

    return nil if ints.empty?
    end_wall = ints.max_by{|wall| wall[:dist].to_f}
    return {
        start_point: furthest_line,
        mid_point: target_cent,
        end_point: {
            space: end_wall[:ceiling_info][:space],
            surface: end_wall[:ceiling_info][:surface],
            verts: end_wall[:ceiling_info][:verts],
            line: {
                verta: end_wall[:line][0],
                vertb: end_wall[:line][1],
                int: end_wall[:int],
                i: end_wall[:i],
                ip: end_wall[:ip],
                dist: end_wall[:dist]
            },
        }
    }
  end

  def get_line_eq(a:, b:, tol: 8)
    if a[0].round(tol) == b[0].round(tol) and a[1].round(tol) == b[1].round(tol)
      return {
          slope: 0,
          int: 0,
          inf: true
      }
    elsif a[0].round(tol) == b[0].round(tol)
      return {
          slope: a[0].round(tol),
          int: 1,
          inf: true
      }
    else
      slope = (b[1].round(tol) - a[1].round(tol))/(b[0].round(tol) - a[0].round(tol))
      int = a[1].round(tol) - (slope*a[0].round(tol))
    end
    return {
        slope: slope,
        int: int,
        inf: false
    }
  end

  def line_int(line_seg:, line:, tol: 8)
    line[:inf] == true && line[:int] == 1 ? x_cross = line[:slope] : x_cross = nil
    if line_seg[0][0].round(tol) == line_seg[1][0].round(tol) && line_seg[0][1].round(tol) == line_seg[1][1].round(tol)
      if x_cross.nil?
        y_val = line[:slope]*line_seg[0][0] + line[:int]
        y_val.round(tol) == line_seg[0][1].round(tol) ? (return line_seg[0]) : (return nil)
      else
        x_cross.round(tol) == line_seg[0][0].round(tol) ? (return line_seg[0]) : (return nil)
      end
    elsif line_seg[0][0].round(tol) == line_seg[1][0]
      if x_cross.nil?
        y_val = line[:slope]*line_seg[0][0] + line[:int]
        if (line_seg[0][1].round(tol) >= y_val.round(tol) && y_val.round(tol) >= line_seg[1][1].round(tol)) ||
            (line_seg[0][1].round(tol) <= y_val.round(tol) && y_val.round(tol) <= line_seg[1][1].round(tol))
          return [line_seg[0][0] , y_val, line_seg[0][2]]
        else
          return nil
        end
      else
        if x_cross.round(tol) == line_seg[0][0]
          y_val = (line_seg[0][1] + line_seg[1][1])/2
          return [line_seg[0][0] , y_val, line_seg[0][2]]
        else
          return nil
        end
      end
    end
    lineb = get_line_eq(a: line_seg[0], b: line_seg[1], tol: tol)
    if lineb[:slope].round(tol) == 0 && line[:slope].round(tol) == 0
      if x_cross.nil?
        if lineb[:int].round(tol) == line[:int].round(tol)
          x_val = (line_seg[0][0] + line_seg[1][0])/2
          return [x_val, lineb[:slope], line_seg[0][2]]
        else
          return nil
        end
      else
        if (line_seg[0][0].round(tol) <= x_cross.round(tol) && x_cross.round(tol) <= line_seg[1][0].round(tol)) ||
            (line_seg[0][0].round(tol) >= x_cross.round(tol) && x_cross.round(tol) >= line_seg[1][0].round(tol))
          [x_cross, lineb[:slope]]
        else
          return nil
        end
      end
    end
    unless x_cross.nil?
      if (line_seg[0][0].round(tol) <= x_cross.round(tol) && x_cross.round(tol) <= line_seg[1][0].round(tol)) ||
          (line_seg[0][0].round(tol) >= x_cross.round(tol) && x_cross.round(tol) >= line_seg[1][0].round(tol))
        y_val = lineb[:slope]*x_cross + lineb[:int]
        return [x_cross , y_val, line_seg[0][2]]
      else
        return nil
      end
    end
    if lineb[:inf] == true && lineb[:int] == 1
      x_int = lineb[:slope]
      y_int = line[:slope].to_f*x_int + line[:int].to_f
    else
      x_int = (lineb[:int].to_f - line[:int].to_f)/(line[:slope].to_f - lineb[:slope].to_f)
      y_int = lineb[:slope].to_f*x_int + lineb[:int].to_f
    end
    if (line_seg[0][0].round(tol) <= x_int.round(tol) && x_int.round(tol) <= line_seg[1][0].round(tol)) ||
        (line_seg[0][0].round(tol) >= x_int.round(tol) && x_int.round(tol) >= line_seg[1][0].round(tol))
      if (line_seg[0][1].round(tol) >= y_int.round(tol) && y_int.round(tol) >= line_seg[1][1].round(tol)) ||
          (line_seg[0][1].round(tol) <= y_int.round(tol) && y_int.round(tol) <= line_seg[1][1].round(tol))
        return [x_int, y_int, line_seg[0][2]]
      end
    end
    return nil
  end

  def line_seg_int(linea:, lineb:, tol: 8)
    if linea[0][0].round(tol) == lineb[0][0].round(tol) && linea[0][1].round(tol) == lineb[0][1].round(tol) &&
    linea[1][0].round(tol) == lineb[1][0].round(tol) && linea[1][1].round(tol) == lineb[1][1].round(tol)
      return [(linea[0][0] + linea[1][0])/2 , (linea[0][1] + linea[1][1])/2]
    elsif linea[0][0].round(tol) == linea[1][0].round(tol) && linea[0][1].round(tol) == linea[1][1].round(tol)
      return linea[0]
    elsif lineb[0][0].round(tol) == lineb[1][0].round(tol) && lineb[0][1].round(tol) == lineb[1][1].round(tol)
      return lineb[0]
    end

    o1 = get_orient(p: linea[0], q: linea[1], r: lineb[0], tol: tol)
    o2 = get_orient(p: linea[0], q: linea[1], r: lineb[1], tol: tol)
    o3 = get_orient(p: lineb[0], q: lineb[1], r: linea[0], tol: tol)
    o4 = get_orient(p: lineb[0], q: lineb[1], r: linea[1], tol: tol)

    int_sect = 0
    int_sect = 1 if o1 != o2 && o3 != o4
    return lineb[0] if o1 == 0 && point_on_line(p: linea[0], q: lineb[0], r: linea[1], tol: tol)
    return lineb[1] if o2 == 0 && point_on_line(p: linea[0], q: lineb[1], r: linea[1], tol: tol)
    return linea[0] if o3 == 0 && point_on_line(p: lineb[0], q: linea[0], r: lineb[1], tol: tol)
    return linea[1] if o4 == 0 && point_on_line(p: lineb[0], q: linea[1], r: lineb[1], tol: tol)

    return nil if int_sect == 0

    eq_linea = get_line_eq(a: linea[0], b: linea[1], tol: tol)
    eq_lineb = get_line_eq(a: lineb[0], b: lineb[1], tol: tol)
    if eq_linea[:inf] == true && eq_linea[:slope].to_f == 1
      x_int = linea[0][0]
      y_int = eq_lineb[:slope].to_f*x_int + eq_lineb[:int].to_f
      return [x_int, y_int]
    elsif eq_lineb[:inf] == true && eq_lineb[:slope].to_f == 1
      x_int = lineb[0][0]
      y_int = eq_linea[:slope].to_f*x_int + eq_linea[:int].to_f
      return [x_int, y_int]
    else
      x_int = (eq_lineb[:int].to_f - eq_linea[:int].to_f) / (eq_linea[:slope].to_f - eq_lineb[:slope].to_f)
      y_int = eq_lineb[:slope].to_f*x_int + eq_lineb[:int].to_f
      return [x_int, y_int]
    end
  end

  def get_orient(p:, q:, r:, tol: 8)
    orient = (q[1].round(tol) - p[1].round(tol))*(r[0].round(tol) - q[0].round(tol)) - (q[0].round(tol) - p[0].round(tol))*(r[1].round(tol) - q[1].round(tol))
    return 0 if orient == 0
    orient > 0 ? (return 1) : (return 2)
  end

  def point_on_line(p:, q:, r:, tol: 8)
    q[0].round(tol) <= [p[0].round(tol), r[0].round(tol)].max ? crita = true : crita = false
    q[0].round(tol) >= [p[0].round(tol), r[0].round(tol)].min ? critb = true : critb = false
    q[1].round(tol) <= [p[1].round(tol), r[1].round(tol)].max ? critc = true : critc = false
    q[1].round(tol) >= [p[1].round(tol), r[1].round(tol)].min ? critd = true : critd = false
    return true if crita && critb && critc && critd
    return false
  end

  def get_lowest_space(spaces:)
    cents = []
    spaces.each do |space|
      test = space['space']
      origin = [space['space'].xOrigin.to_f, space['space'].yOrigin.to_f, space['space'].zOrigin.to_f]
      space['space'].surfaces.each do |surface|
        if surface.surfaceType.to_s.upcase == 'ROOFCEILING'
          cents <<{
              space: space['space'],
              roof_cent: [surface.centroid.x.to_f + origin[0], surface.centroid.y.to_f + origin[1], surface.centroid.z.to_f + origin[2]]
          }
        end
      end
    end
    min_space = cents.min_by{|cent| cent[:roof_cent][2]}
    return min_space
  end

  def vent_trunk_duct_cost(tot_air_m3pers:, min_space:, roof_cent:, mech_sizing_info:, sys_1_4:)
    sys_1_4 ? overall_mult = 1 : overall_mult = 2
    duct_cost_search = []
    mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'trunk')
    max_trunk_line = mech_table.max_by {|entry| entry['max_flow_range_m3pers'][0]}
    tot_air_m3pers = max_trunk_line['max_flow_range_m3pers'][0].to_f.round(2) if tot_air_m3pers.round(2) > max_trunk_line['max_flow_range_m3pers'][1].to_f.round(2)
    trunk_sz_info = mech_table.select {|trunk_choice|
      trunk_choice['max_flow_range_m3pers'][0].to_f.round(2) < tot_air_m3pers.round(2) and
          trunk_choice['max_flow_range_m3pers'][1].to_f.round(2) >= tot_air_m3pers.round(2)
    }.first
    duct_dia = trunk_sz_info['duct_dia_inch']
    duct_length_m = (roof_cent[:roof_centroid][2].to_f - min_space[:roof_cent][2].to_f).abs
    duct_length = (OpenStudio.convert(duct_length_m, 'm', 'ft').get)
    duct_cost_search << {
        mat: 'Ductwork-S',
        unit: 'L.F.',
        size: duct_dia,
        mult: duct_length*overall_mult
    }
    duct_area = (duct_dia/12)*Math::PI*duct_length*overall_mult
    duct_cost_search << {
        mat: 'Ductinsulation',
        unit: 'ft2',
        size: 1.5,
        mult: duct_area
    }
    duct_cost = get_comp_cost(cost_info: duct_cost_search)
    trunk_duct_info = {
        DuctSize_in: duct_dia.round(1),
        DuctLength_m: duct_length_m.round(1),
        NumberRuns: overall_mult,
        DuctCost: duct_cost.round(2)
    }
    return duct_cost, trunk_duct_info
  end

  def gen_hvac_info_by_floor(hvac_floors:, model:, prototype_creator:, airloop:, sys_type:, hrv_info:)
    airloop.thermalZones.sort.each do |tz|
      tz.equipment.sort.each do |eq|
        tz_mult = tz.multiplier.to_f
        terminal, box_name = get_airloop_terminal_type(eq: eq)
        next if terminal.nil?
        if terminal.isMaximumAirFlowRateAutosized.to_bool
          query = "SELECT Value FROM ComponentSizes WHERE CompName='#{eq.name.to_s.upcase}' AND Description='Design Size Maximum Air Flow Rate'"
          tz_air = model.sqlFile().get().execAndReturnFirstDouble(query).to_f/tz_mult
        else
          tz_air = terminal.maximumAirFlowRate.to_f/tz_mult
        end
        tz_cents = prototype_creator.thermal_zone_get_centroid_per_floor(tz)
        tz_cents.each do |tz_cent|
          story_floor_area = 0
          tz_outdoor_air_m3ps = 0
          tz_cent[:spaces].each do |space|
            # Note that space.floorArea gets the floor area for the space only and does not include a thermal zone multiplier.
            # Thus the outdoor air flow rate totaled here will be for only one thermal zone and will not include thermal zone multipliers.
            story_floor_area += space.floorArea.to_f
            outdoor_air_obj = space.designSpecificationOutdoorAir
            outdoor_air_obj.is_initialized ? outdoor_air_m3ps = (outdoor_air_obj.get.outdoorAirFlowperFloorArea)*(space.floorArea.to_f) : outdoor_air_m3ps = 0
            tz_outdoor_air_m3ps += outdoor_air_m3ps
          end
          story_obj = tz_cent[:spaces][0].buildingStory.get
          floor_area_frac = (story_floor_area/tz.floorArea).round(2)
          tz_floor_air = floor_area_frac*tz_air
          (sys_type == 1 || sys_type == 4) ? tz_floor_return = 0 : tz_floor_return = tz_floor_air
          tz_floor_system = {
              story_name: tz_cent[:story_name],
              story: story_obj,
              sys_name: airloop.nameString,
              sys_type: sys_type,
              sys_info: airloop,
              tz: tz,
              tz_mult: tz_mult,
              terminal: terminal,
              floor_area_frac: floor_area_frac,
              tz_floor_area: story_floor_area,
              tz_floor_supp_air_m3ps: tz_floor_air,
              tz_floor_ret_air_m3ps: tz_floor_return,
              tz_floor_outdoor_air_m3ps: tz_outdoor_air_m3ps,
              hrv_info: hrv_info,
              tz_cent: tz_cent
          }
          hvac_floors = add_floor_sys(hvac_floors: hvac_floors, tz_floor_sys: tz_floor_system)
        end
      end
    end
    return hvac_floors
  end

  def add_floor_sys(hvac_floors:, tz_floor_sys:)
    if hvac_floors.empty?
      hvac_floors << {
          story_name: tz_floor_sys[:story_name],
          story: tz_floor_sys[:story],
          supply_air_m3ps: tz_floor_sys[:tz_floor_supp_air_m3ps],
          return_air_m3ps: tz_floor_sys[:tz_floor_ret_air_m3ps],
          tz_mult: tz_floor_sys[:tz_mult],
          tz_num: 1,
          floor_tz: [tz_floor_sys]
      }
    else
      found_story = false
      hvac_floors.each do |hvac_floor|
        if hvac_floor[:story_name].to_s.upcase == tz_floor_sys[:story_name].to_s.upcase
          hvac_floor[:supply_air_m3ps] += tz_floor_sys[:tz_floor_supp_air_m3ps]
          hvac_floor[:return_air_m3ps] += tz_floor_sys[:tz_floor_ret_air_m3ps]
          hvac_floor[:tz_mult] += tz_floor_sys[:tz_mult]
          hvac_floor[:tz_num] += 1
          hvac_floor[:floor_tz] << tz_floor_sys
          found_story = true
        end
      end
      if found_story == false
        hvac_floors << {
            story_name: tz_floor_sys[:story_name],
            story: tz_floor_sys[:story],
            supply_air_m3ps: tz_floor_sys[:tz_floor_supp_air_m3ps],
            return_air_m3ps: tz_floor_sys[:tz_floor_ret_air_m3ps],
            tz_mult: tz_floor_sys[:tz_mult],
            tz_num: 1,
            floor_tz: [tz_floor_sys]
        }
      end
    end
    return hvac_floors
  end

  def floor_vent_dist_cost(hvac_floors:, prototype_creator:, roof_cent:, mech_sizing_info:)
    floor_duct_cost = 0
    build_floor_trunk_info = []
    mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'vel_prof')
    hvac_floors.each do |hvac_floor|
      next if hvac_floor[:tz_num] < 2 && hvac_floor[:floor_tz][0][:sys_type] == 3
      tz_floor_mult = (hvac_floor[:tz_mult].to_f)/(hvac_floor[:tz_num].to_f)
      floor_trunk_line = get_story_cent_to_edge(building_story: hvac_floor[:story], prototype_creator: prototype_creator, target_cent: roof_cent[:roof_centroid], full_length: true)
      current_floor_duct_cost, floor_trunk_info = get_floor_trunk_cost(mech_table: mech_table, hvac_floor: hvac_floor, prototype_creator: prototype_creator, floor_trunk_dist_m: floor_trunk_line[:end_point][:line][:dist])
      floor_duct_cost += current_floor_duct_cost*tz_floor_mult
      floor_trunk_info[:Floor] = hvac_floor[:story_name]
      floor_trunk_info[:Multiplier] = tz_floor_mult
      build_floor_trunk_info << floor_trunk_info
    end
    return floor_duct_cost, build_floor_trunk_info
  end

  def get_floor_trunk_cost(mech_table:, hvac_floor:, prototype_creator:, floor_trunk_dist_m:, fric_allow: 1)
    floor_trunk_info = {
        Floor: '',
        Predominant_space_type: 0,
        SupplyDuctSize_in: 0,
        SupplyDuctLength_m: 0,
        ReturnDuctSize_in: 0,
        ReturnDuctLength_m: 0,
        TotalDuctCost: 0,
        Multiplier: 1
    }
    floor_trunk_cost = 0
    duct_comp_search = []
    floor_trunk_dist = (OpenStudio.convert(floor_trunk_dist_m, 'm', 'ft').get)
    space_type = get_predominant_floor_space_type_area(hvac_floor: hvac_floor, prototype_creator: prototype_creator)
    floor_trunk_info[:Predominant_space_type] = space_type[:space_type]
    loor_vel_fpm = nil
    mech_table.each do |vel_prof|
      spc_type_name = nil
      spc_type_name = vel_prof['space_types'].select {|spc_type|
        spc_type.to_s.upcase == space_type[:space_type].to_s.upcase
      }.first
      floor_vel_fpm = vel_prof['vel_fpm'].to_f unless spc_type_name.nil?
    end
    floor_vel_fpm = mech_table[mech_table.size - 1]['vel_fpm'].to_f if floor_vel_fpm.nil?
    supply_flow_cfm = (OpenStudio.convert(hvac_floor[:supply_air_m3ps], 'm^3/s', 'cfm').get)
    sup_cross_in2 = ((supply_flow_cfm*fric_allow)/floor_vel_fpm)*144
    sup_dia_in = 2*Math.sqrt(sup_cross_in2/Math::PI)
    duct_cost_search = {
        mat: 'Ductwork-S',
        unit: 'L.F.',
        size: sup_dia_in,
        mult: floor_trunk_dist
    }
    duct_cost, comp_info = get_duct_cost(cost_info: duct_cost_search)
    floor_trunk_info[:SupplyDuctSize_in] = sup_dia_in.round(2)
    floor_trunk_info[:SupplyDuctLength_m] = floor_trunk_dist_m.round(1)
    floor_trunk_cost += duct_cost
    sup_area_sqrft = (comp_info['Size'].to_f/12)*Math::PI*floor_trunk_dist
    duct_comp_search << {
        mat: 'Ductinsulation',
        unit: 'ft2',
        size: 1.5,
        mult: sup_area_sqrft
    }
    if hvac_floor[:return_air_m3ps] == hvac_floor[:supply_air_m3ps]
      floor_trunk_cost += duct_cost
      duct_comp_search[0][:mult] = sup_area_sqrft*2
      floor_trunk_info[:ReturnDuctSize_in] = floor_trunk_info[:SupplyDuctSize_in]
      floor_trunk_info[:ReturnDuctLength_m] = floor_trunk_info[:SupplyDuctLength_m]
    elsif hvac_floor[:return_air_m3ps].to_f > 0
      return_flow_cfm = (OpenStudio.convert(hvac_floor[:return_air_m3ps], 'm^3/s', 'cfm').get)
      ret_cross_in2 = ((return_flow_cfm*fric_allow)/floor_vel_fpm)*144
      ret_dia_in = 2*Math.sqrt(ret_cross_in2/Math::PI)
      duct_cost_search = {
          mat: 'Ductwork-S',
          unit: 'L.F.',
          size: ret_dia_in,
          mult: floor_trunk_dist
      }
      duct_cost, comp_info = get_duct_cost(cost_info: duct_cost_search)
      floor_trunk_cost += duct_cost
      ret_area_sqrft = (comp_info['Size'].to_f/12)*Math::PI*floor_trunk_dist
      duct_comp_search << {
          mat: 'Ductinsulation',
          unit: 'ft2',
          size: 1.5,
          mult: ret_area_sqrft
      }
      floor_trunk_info[:ReturnDuctSize_in] = ret_dia_in.round(2)
      floor_trunk_info[:ReturnDuctLength_m] = floor_trunk_dist_m.round(1)
    end
    floor_trunk_cost += get_comp_cost(cost_info: duct_comp_search)
    floor_trunk_info[:TotalDuctCost] = floor_trunk_cost.round(2)
    return floor_trunk_cost, floor_trunk_info
  end

  def get_duct_cost(cost_info:)
    comp_info = nil
    comp_info_all = @costing_database['raw']['materials_hvac'].select {|data|
      data['Material'].to_s.upcase == cost_info[:mat].to_s.upcase and
          data['Size'].to_f.round(1) >= cost_info[:size].to_f.round(1) and
          data['unit'].to_s.upcase == cost_info[:unit].to_s.upcase
    }
    if comp_info_all.nil? || comp_info_all.empty?
      max_size_info = @costing_database['raw']['materials_hvac'].select {|data|
        data['Material'].to_s.upcase == cost_info[:mat].to_s.upcase
      }
      if max_size_info.nil?
        puts("No data found for #{cost_info}!")
        raise
      end
      comp_info = max_size_info.max_by {|element| element['Size'].to_f}
    elsif comp_info_all.size == 1
      comp_info = comp_info_all[0]
    else
      comp_info = comp_info_all.min_by{|data| data['Size'].to_f}
    end
    cost = get_vent_mat_cost(mat_cost_info: comp_info)*cost_info[:mult].to_f
    return cost, comp_info
  end

  def get_predominant_floor_space_type_area(hvac_floor:, prototype_creator:)
    spaces = hvac_floor[:story].spaces
    space_list = []
    space_mod = OpenstudioStandards::Space
    spaces.sort.each do |space|
      if (space_mod.space_cooled?(space) || space_mod.space_heated?(space)) && !space_mod.space_plenum?(space)
        space_type = space.spaceType.get.nameString[15..-1]
        if space_list.empty?
          space_list << {
              space_type: space_type,
              floor_area: space.floorArea
          }
        else
          new_space = nil
          space_list.each do |spc_lst|
            if space_type.upcase == spc_lst[:space_type]
              spc_lst[:floor_area] += space.floorArea
            else
              new_space = {
                  space_type: space_type,
                  floor_area: space.floorArea
              }
            end
          end
          unless new_space.nil?
            space_list << new_space
          end
        end
      end
    end
    max_space_type = space_list.max_by {|spc_lst| spc_lst[:floor_area]}
    return max_space_type
  end

  def tz_vent_dist_cost(hvac_floors:, mech_sizing_info:)
    dist_reporting = []
    vent_dist_cost = 0
    mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'tz_dist_info')
    flexduct_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'flex_duct')
    hvac_floors.each_with_index do |hvac_floor, index|
      dist_reporting << {
          Story: hvac_floor[:story_name],
          thermal_zones: []
      }
      hvac_floor[:floor_tz].each do |floor_tz|
        floor_vent_cost = 0
        airflow_m3ps = []
        airflow_m3ps << floor_tz[:tz_floor_supp_air_m3ps]*floor_tz[:floor_area_frac]
        airflow_m3ps << floor_tz[:tz_floor_ret_air_m3ps]*floor_tz[:floor_area_frac] if floor_tz[:tz_floor_ret_air_m3ps].to_f.round(6) > 0.0
        airflow_m3ps.each_with_index do |max_air_m3ps, flow_index|
          # Using max supply air flow rather than breathing zone outdoor airflow.  Keep breathing zone outdoor airflow in
          # case we change our minds.
          # breathing_zone_outdoor_airflow_vbz= model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName='Zone Ventilation Parameters' AND ColumnName='Breathing Zone Outdoor Airflow - Vbz' AND Units='m3/s' AND RowName='#{tz.nameString.to_s.upcase}' ")
          # bz_outdoor_airflow_m3_s = breathing_zone_outdoor_airflow_vbz.get unless breathing_zone_outdoor_airflow_vbz.empty?
          tz_dist_sz = mech_table.select {|size_range|
            max_air_m3ps > size_range['airflow_m3ps'][0] && max_air_m3ps <= size_range['airflow_m3ps'][1]
          }
          if tz_dist_sz.empty?
            size_range = mech_table[mech_table.size - 1]
            diffusers = (max_air_m3ps/size_range["diffusers"]).round(0)
            tz_dist_sz << {
                "airflow_m3ps" => size_range['airflow_m3ps'],
                "diffusers" => diffusers,
                "ducting_lbs" => (diffusers*size_range["ducting_lbs"]).round(0),
                "duct_insulation_ft2" => (diffusers*size_range["duct_insulation_ft2"]).round(0),
                "flex_duct_ft" => (diffusers*size_range["flex_duct_ft"]).round(0)
            }
          elsif tz_dist_sz[0] == mech_table[mech_table.size - 1]
            diffusers = (max_air_m3ps/tz_dist_sz[0]['diffusers']).round(0)
            tz_dist_sz[0] = {
                "airflow_m3ps" => tz_dist_sz[0]['airflow_m3ps'],
                "diffusers" => diffusers,
                "ducting_lbs" => (diffusers*tz_dist_sz[0]['ducting_lbs']).round(0),
                "duct_insulation_ft2" => (diffusers*tz_dist_sz[0]['duct_insulation_ft2']).round(0),
                "flex_duct_ft" => (diffusers*tz_dist_sz[0]['flex_duct_ft']).round(0)
            }
          end
          duct_cost_search = []
          duct_cost_search << {
              mat: 'Diffusers',
              unit: 'each',
              size: 36,
              mult: tz_dist_sz[0]['diffusers']
          }
          if tz_dist_sz[0]["ducting_lbs"] < 200
            duct_cost_search << {
                mat: 'Ductwork',
                unit: 'lb.',
                size: 199,
                mult: tz_dist_sz[0]['ducting_lbs']
            }
          else
            duct_cost_search << {
                mat: 'Ductwork',
                unit: 'lb.',
                size: 200,
                mult: tz_dist_sz[0]['ducting_lbs']
            }
          end
          duct_cost_search << {
              mat: 'DuctInsulation',
              unit: 'ft2',
              size: 1.5,
              mult: tz_dist_sz[0]['duct_insulation_ft2']
          }
          floor_vent_cost = get_comp_cost(cost_info: duct_cost_search)*floor_tz[:tz_mult]
          flex_duct_sz = flexduct_table.select {|flex_duct|
            max_air_m3ps > flex_duct['airflow_m3ps'][0] && max_air_m3ps <= flex_duct['airflow_m3ps'][1]
          }
          flex_duct_sz << flexduct_table[flexduct_table.size-1] if flex_duct_sz.empty?
          duct_cost_search = {
              mat: 'Ductwork-M',
              unit: 'L.F.',
              size: flex_duct_sz[0]['diameter_in'],
              mult: tz_dist_sz[0]['flex_duct_ft']
          }
          duct_cost, comp_info = get_duct_cost(cost_info: duct_cost_search)
          floor_vent_cost += duct_cost*floor_tz[:tz_mult]
          vent_dist_cost += floor_vent_cost
          if flow_index == 0
            flow_dir = 'Supply'
          else
            flow_dir = 'Return'
          end
          dist_reporting[index][:thermal_zones] << {
              ThermalZone: floor_tz[:tz].nameString,
              ducting_direction: flow_dir,
              tz_mult: floor_tz[:tz_mult],
              airflow_m3ps: max_air_m3ps.round(3),
              num_diff: tz_dist_sz[0]['diffusers'],
              ducting_lbs: tz_dist_sz[0]['ducting_lbs'],
              duct_insulation_ft2: tz_dist_sz[0]['duct_insulation_ft2'],
              flex_duct_sz_in: flex_duct_sz[0]['diameter_in'],
              flex_duct_length_ft: tz_dist_sz[0]['flex_duct_ft'],
              cost: floor_vent_cost.round(2)
          }
        end
      end
    end
    return vent_dist_cost, dist_reporting
  end

  def get_hrv_info(airloop:, model:)
    hrv_present = false
    hrv_data = nil
    hrv_design_flow_m3ps = 0
    airloop.oaComponents.each do |oaComp|
      if oaComp.iddObjectType.valueName.to_s == 'OS_HeatExchanger_AirToAir_SensibleAndLatent'
        hrv_present = true
        hrv_data = oaComp.to_HeatExchangerAirToAirSensibleAndLatent.get
        if hrv_data.isNominalSupplyAirFlowRateAutosized
          hrv_design_flow_m3ps = hrv_data.autosizedNominalSupplyAirFlowRate.to_f
        else
          hrv_design_flow_m3ps = hrv_data.nominalSupplyAirFlowRate.to_f
        end
      end
    end
    return {
      hrv_present: hrv_present,
      hrv_data: hrv_data,
      hrv_size_m3ps: hrv_design_flow_m3ps,
      supply_cap_m3ps: 0,
      return_cap_m3ps: 0
    } unless hrv_present
    airloop.supplyFan.is_initialized ? supply_fan_cap = get_fan_cap(fan: airloop.supplyFan.get, model: model) : supply_fan_cap = 0
    airloop.returnFan.is_initialized ? return_fan_cap = get_fan_cap(fan: airloop.returnFan.get, model: model) : return_fan_cap = 0
    return {
      hrv_present: hrv_present,
      hrv_data: hrv_data,
      hrv_size_m3ps: hrv_design_flow_m3ps,
      supply_cap_m3ps: supply_fan_cap,
      return_cap_m3ps: return_fan_cap
    }
  end

  def get_fan_cap(fan:, model:)
    fan_type = fan.iddObjectType.valueName.to_s
    case fan_type
    when /OS_Fan_VariableVolume/
      fan_obj = fan.to_FanVariableVolume.get
      if fan_obj.isMaximumFlowRateAutosized
        fan_cap_m3ps = fan_obj.autosizedMaximumFlowRate.to_f
      else
        fan_cap_m3ps = fan_obj.maximumFlowRate.to_f
      end
    when /OS_Fan_ConstantVolume/
      fan_obj = fan.to_FanConstantVolume.get
      if fan_obj.isMaximumFlowRateAutosized
        fan_cap_m3ps = fan_obj.autosizedMaximumFlowRate.to_f
      else
        fan_cap_m3ps = fan_obj.maximumFlowRate.to_f
      end
    else
      fan_cap_m3ps = 0
    end
    return fan_cap_m3ps
  end

  def hrv_duct_cost(prototype_creator:, roof_cent:, mech_sizing_info:, hvac_floors:)
    hrv_cost_tot = 0
    mech_table = get_mech_table(mech_size_info: mech_sizing_info, table_name: 'trunk')
    air_system_totals = []
    hrv_dist_rep = []
    hvac_floors.each_with_index do |hvac_floor, floor_index|
      hrv_dist_rep << {
          floor: hvac_floor[:story_name],
          air_systems: []
      }
      floor_systems = sort_tzs_by_air_system(hvac_floor: hvac_floor)
      floor_systems.each_with_index do |air_system, air_index|
        next if air_system[:sys_hrv_flow_m3ps].round(2) == 0.0 || air_system[:hrv_info][:hrv_present] == false
        floor_trunk_line = nil
        floor_air_sys = {
            air_system: air_system[:air_sys].nameString,
            hrv: air_system[:hrv_info][:hrv_data].nameString,
            floor_mult: 1,
            hrv_ret_trunk: {},
            tz_dist: [],
        }
        if air_system[:num_tz] > 1
          sys_floor_mult = air_system[:tz_mult]/(air_system[:num_tz])
          floor_trunk_line = get_story_cent_to_edge(building_story: hvac_floor[:story], prototype_creator: prototype_creator, target_cent: roof_cent[:roof_centroid], full_length: true)
          hrv_trunk_cost, floor_air_sys[:hrv_ret_trunk] = get_hrv_floor_trunk_cost(mech_table: mech_table, air_system: air_system, floor_trunk_dist_m: floor_trunk_line[:end_point][:line][:dist])
          hrv_cost_tot += hrv_trunk_cost*sys_floor_mult
          floor_air_sys[:floor_mult] = sys_floor_mult
        end
        air_system[:floor_tz].each do |floor_tz|
          floor_tz[:tz_floor_ret_air_m3ps] >= floor_tz[:tz_floor_outdoor_air_m3ps] ? hrv_air = 0 : hrv_air = (floor_tz[:tz_floor_outdoor_air_m3ps] - floor_tz[:tz_floor_ret_air_m3ps]).abs
          next if hrv_air.round(2) == 0.0
          air_system_total = {
              dist_to_roof_m: (roof_cent[:roof_centroid][2] - floor_tz[:tz_cent][:centroid][2]).abs,
              hrv_air_m3ps: hrv_air*floor_tz[:tz_mult],
              num_systems: floor_tz[:tz_mult]
          }
          if floor_trunk_line.nil?
            floor_duct_coords = [roof_cent[:roof_centroid][0] - floor_tz[:tz_cent][:centroid][0], roof_cent[:roof_centroid][1] - floor_tz[:tz_cent][:centroid][1], roof_cent[:roof_centroid][2] - floor_tz[:tz_cent][:centroid][2]]
            floor_duct_dist_m = floor_duct_coords[0].abs + floor_duct_coords[1].abs
          else
            line = {
                start: floor_trunk_line[:start_point][:line][:int],
                end: floor_trunk_line[:end_point][:line][:int]
            }
            floor_duct_dist_m = short_dist_point_and_line(point: floor_tz[:tz_cent][:centroid], line: line).abs
            if floor_duct_dist_m.nil?
              floor_duct_dist_m = (line[:start][0] - floor_tz[:tz_cent][:centroid][0]).abs + (line[:start][1] - floor_tz[:tz_cent][:centroid][1]).abs
            end
          end
          if floor_duct_dist_m.round(2) > 0.1
            floor_duct_dist_ft = (OpenStudio.convert(floor_duct_dist_m, 'm', 'ft').get)
            branch_duct_sz = mech_table.select {|sz_range|
              hrv_air > sz_range['max_flow_range_m3pers'][0] && hrv_air <= sz_range['max_flow_range_m3pers'][1]
            }
            branch_duct_sz << mech_table[mech_table.size-1] if branch_duct_sz.empty?
            duct_comp_search = []
            duct_dia_in = branch_duct_sz[0]['duct_dia_inch']
            duct_surface_area = floor_duct_dist_ft*(duct_dia_in.to_f/12)*Math::PI
            duct_comp_search << {
                mat: 'Ductinsulation',
                unit: 'ft2',
                size: 1.5,
                mult: duct_surface_area
            }
            duct_comp_search << {
                mat: 'Ductwork-S',
                unit: 'L.F.',
                size: duct_dia_in,
                mult: floor_duct_dist_ft
            }
            hrv_branch_cost = get_comp_cost(cost_info: duct_comp_search)
            hrv_cost_tot += hrv_branch_cost*floor_tz[:tz_mult]
            floor_air_sys[:tz_dist] << {
                tz: floor_tz[:tz].nameString,
                tz_mult: floor_tz[:tz_mult],
                hrv_ret_dist_m: floor_duct_dist_m.round(1),
                hrv_ret_size_in: duct_dia_in.round(2),
                cost: hrv_branch_cost.round(2)
            }
          end
          air_system_totals = add_tz_to_air_sys(air_system: air_system, air_system_total: air_system_total, air_system_totals: air_system_totals, floor_tz: floor_tz)
        end
        hrv_dist_rep[floor_index][:air_systems] << floor_air_sys
      end
    end
    unless air_system_totals.empty?
      air_system_totals.each do |air_system|
        next if air_system[:hrv_air_m3ps].round(2) == 0
        # In addition to distance from floor to roof add 20' of duct from roof centre to box
        main_trunk_dist_ft = (OpenStudio.convert(air_system[:dist_to_roof_m], 'm', 'ft').get) + 20
        main_trunk_sz = mech_table.select {|sz_range|
          air_system[:hrv_air_m3ps] > sz_range['max_flow_range_m3pers'][0] && air_system[:hrv_air_m3ps] <= sz_range['max_flow_range_m3pers'][1]
        }
        main_trunk_sz << mech_table[mech_table.size-1] if main_trunk_sz.empty?
        duct_comp_search = []
        duct_dia_in = main_trunk_sz[0]['duct_dia_inch']
        duct_surf_area_ft2 = main_trunk_dist_ft*(duct_dia_in.to_f/12)*Math::PI
        duct_comp_search << {
            mat: 'Ductinsulation',
            unit: 'ft2',
            size: 1.5,
            mult: duct_surf_area_ft2
        }
        duct_comp_search << {
            mat: 'Ductwork-S',
            unit: 'L.F.',
            size: duct_dia_in,
            mult: main_trunk_dist_ft
        }
        main_trunk_cost = get_comp_cost(cost_info: duct_comp_search)
        hrv_cost_tot += main_trunk_cost
        hrv_dist_rep << {
            air_system: air_system[:air_system].nameString,
            hrv: air_system[:hrv_info][:hrv_data].nameString,
            hrv_building_trunk_length_m: air_system[:dist_to_roof_m].round(1),
            hrv_building_trunk_dia_in: duct_dia_in.round(2),
            cost: main_trunk_cost.round(2)
        }
      end
    end
    return hrv_cost_tot, hrv_dist_rep
  end

  def sort_tzs_by_air_system(hvac_floor:)
    floor_systems = []
    hvac_floor[:floor_tz].each do |floor_tz|
      air_sys = floor_tz[:sys_info]
      next if floor_tz[:hrv_info][:hrv_present] == false
      floor_tz[:tz_floor_ret_air_m3ps] >= floor_tz[:tz_floor_outdoor_air_m3ps] ? hrv_ret_air_m3ps = 0 : hrv_ret_air_m3ps = (floor_tz[:tz_floor_outdoor_air_m3ps] - floor_tz[:tz_floor_ret_air_m3ps]).abs
      if floor_systems.empty?
        floor_systems << {
            air_sys: air_sys,
            sys_hrv_flow_m3ps: hrv_ret_air_m3ps,
            num_tz: 1,
            tz_mult: floor_tz[:tz_mult],
            hrv_info: floor_tz[:hrv_info],
            floor_tz: [floor_tz]
        }
      else
        current_sys = floor_systems.select {|floor_sys| floor_sys[:air_sys] == air_sys}
        if current_sys.empty?
          floor_systems << {
              air_sys: air_sys,
              sys_hrv_flow_m3ps: hrv_ret_air_m3ps,
              num_tz: 1,
              tz_mult: floor_tz[:tz_mult],
              hrv_info: floor_tz[:hrv_info],
              floor_tz: [floor_tz]
          }
        else
          current_sys[0][:sys_hrv_flow_m3ps] += hrv_ret_air_m3ps
          current_sys[0][:num_tz] += 1
          current_sys[0][:tz_mult] += floor_tz[:tz_mult]
          current_sys[0][:floor_tz] << floor_tz
        end
      end
    end
    return floor_systems
  end

  def add_tz_to_air_sys(air_system:, air_system_total:, air_system_totals:, floor_tz:)
    if air_system_totals.empty?
      air_system_totals << {
          air_system: air_system[:air_sys],
          hrv_air_m3ps: air_system_total[:hrv_air_m3ps],
          dist_to_roof_m: air_system_total[:dist_to_roof_m],
          num_systems: air_system_total[:num_systems],
          hrv_info: air_system[:hrv_info],
          floor_tz: [floor_tz]
      }
    else
      curr_air_sys = air_system_totals.select {|air_sys| air_sys[:air_system] == air_system[:air_sys]}
      if curr_air_sys.empty?
        air_system_totals << {
            air_system: air_system[:air_sys],
            hrv_air_m3ps: air_system_total[:hrv_air_m3ps],
            dist_to_roof_m: air_system_total[:dist_to_roof_m],
            num_systems: air_system_total[:num_systems],
            hrv_info: air_system[:hrv_info],
            floor_tz: [floor_tz]
        }
      else
        curr_air_sys[0][:hrv_air_m3ps] += air_system_total[:hrv_air_m3ps]
        curr_air_sys[0][:dist_to_roof_m] = [curr_air_sys[0][:dist_to_roof_m], air_system_total[:dist_to_roof_m]].max
        curr_air_sys[0][:num_systems] += air_system_total[:num_systems]
        curr_air_sys[0][:floor_tz] << floor_tz
      end
    end
    return air_system_totals
  end

  def get_hrv_floor_trunk_cost(mech_table:, air_system:, floor_trunk_dist_m:)
    return 0 if air_system[:sys_hrv_flow_m3ps].round(2) == 0.0
    hrv_trunk_cost = 0
    duct_comp_search = []
    floor_trunk_dist = (OpenStudio.convert(floor_trunk_dist_m, 'm', 'ft').get)
    trunk_duct_sz = mech_table.select {|sz_range|
      air_system[:sys_hrv_flow_m3ps] > sz_range['max_flow_range_m3pers'][0] && air_system[:sys_hrv_flow_m3ps] <= sz_range['max_flow_range_m3pers'][1]
    }
    trunk_duct_sz << mech_table[mech_table.size-1] if trunk_duct_sz.empty?
    trunk_dia_in = (trunk_duct_sz[0]['duct_dia_inch'])
    duct_comp_search << {
        mat: 'Ductwork-S',
        unit: 'L.F.',
        size: trunk_dia_in,
        mult: floor_trunk_dist
    }
    trunk_area_sqrft = (trunk_dia_in.to_f/12)*Math::PI*floor_trunk_dist
    duct_comp_search << {
        mat: 'Ductinsulation',
        unit: 'ft2',
        size: 1.5,
        mult: trunk_area_sqrft
    }
    hrv_trunk_cost += get_comp_cost(cost_info: duct_comp_search)
    hrv_trunk_cost_rep = {
        duct_length_m: floor_trunk_dist_m.round(1),
        dia_in: trunk_dia_in.round(2),
        cost: hrv_trunk_cost.round(2)
    }
    return hrv_trunk_cost, hrv_trunk_cost_rep
  end

  def short_dist_point_and_line(point:, line:)
    line_eq = get_line_eq(a: line[:start], b: line[:end])
    if line_eq[:int] == 1 and line_eq[:inf] == true
      dist = point[0] - line_eq[:slope]
    elsif line_eq[:int] == 0 and line_eq[:inf] == true
      dist = nil
    else
      # Turn equation of line as:  y = slope*x + intercept
      # into:  a*x + b*y + c = 0
      # a = slope, b = -1, c = intercept
      a = line_eq[:slope]
      b = -1
      c = line_eq[:int]
      # Use dot product to get shortest distance from point to line
      dist = (a*point[0] + b*point[1] + c) / Math.sqrt(a**2 + b**2)
    end
    return dist
  end

  # This method consumes the following:
  # hrv_info: (hash)  Information about the modeled HRV.
  # airloop: (OpenStudio Object)  The OpenStudio air loop object.
  # vent_tags: (array of strings)  Tags used to associate the costing output list with whichever component of the
  #            building is being costed.
  # report_mult:  (float)  When recreating the cost of items from the costing output list this multiplier is used to
  #               multiply the total of the localized material and labour costs.
  def hrv_cost(hrv_info:, airloop:, vent_tags: [], report_mult: 1.0)
    hrv_tags = vent_tags.clone
    hrv_tags << "ERV duct cost"
    hrv_cost_tot = 0
    number_zones = 0
    duct_comp_search = []
    # Calculate the number of thermal zones served by the ERV
    airloop.thermalZones.each do |tz|
      number_zones += tz.multiplier
    end

    # Get additional ductwork costs
    duct_comp_search << {
        mat: 'Ductwork-Fitting',
        unit: 'each',
        size: 8,
        mult: number_zones
    }
    hrv_cost_tot += get_comp_cost(cost_info: duct_comp_search, vent_tags: hrv_tags, report_mult: report_mult)
    hrv_tags.pop

    # Get the return air fan cost (if applicable)
    hrv_info[:return_cap_m3ps] >= hrv_info[:hrv_size_m3ps] ? hrv_return_flow_m3ps = 0.0 : hrv_return_flow_m3ps = hrv_info[:hrv_size_m3ps] - hrv_info[:return_cap_m3ps]
    hrv_tags << "ERV return air fan"
    unless hrv_return_flow_m3ps.round(2) == 0
      hrv_return_flow_cfm = (OpenStudio.convert(hrv_return_flow_m3ps, 'm^3/s', 'cfm').get)
      if hrv_return_flow_cfm < 800
        hrv_cost_tot += get_mech_costing(mech_name: 'FansDD-LP', size: hrv_return_flow_cfm, terminal: hrv_info[:hrv_data], use_mult: true, vent_tags: hrv_tags, report_mult: report_mult)
      else
        hrv_cost_tot += get_mech_costing(mech_name: 'FansBelt', size: hrv_return_flow_cfm, terminal: hrv_info[:hrv_data], use_mult: true, vent_tags: hrv_tags, report_mult: report_mult)
      end
    end


    hrv_tags.pop
    hrv_tags << "ERV with adjustment factor"

    hrv_size_cfm = (OpenStudio.convert(hrv_info[:hrv_size_m3ps], 'm^3/s', 'cfm').get)
    # Turn the HRV information into something the 'get_vent_cost_data' method expects.
    hrv_requirements = {
      cat_search: 'ERV',
      mech_capacity_kw: hrv_size_cfm, # This key really should just be called mech_capacity since the units vary.
      supply_component: hrv_info[:hrv_data]
    }
    # Get the HRV costing information
    hrv_mult, hrv_cost_info = get_vent_cost_data(equipment_info: hrv_requirements)
    # Calculate the HRV cost adjustment factor
    hrv_cost_adj = hrv_size_cfm*hrv_mult/(hrv_cost_info['Size'].to_f)
    ind_hrv_cost = get_vent_mat_cost(mat_cost_info: hrv_cost_info, vent_tags: hrv_tags, report_mult: hrv_cost_adj)

    ind_hrv_cost_rep = hrv_cost_tot + ind_hrv_cost
    hrv_cost_tot += ind_hrv_cost*hrv_cost_adj
    hrv_rep = {
      hrv_type: (hrv_info[:hrv_data].iddObjectType.valueName.to_s)[3..-1],
      hrv_name: hrv_info[:hrv_data].nameString,
      hrv_size_m3ps: hrv_info[:hrv_size_m3ps].round(3),
      hrv_return_fan_size_m3ps: hrv_return_flow_m3ps.round(3),
      hrv_cost: ind_hrv_cost_rep.round(2),
      revised_hrv_cost: hrv_cost_tot.round(2)
    }

    return hrv_rep
  end

  # This method collects air loop heating and cooling costing information into the al_eq_reporting_info hash.  This hash
  # will be included in the ventilation costing report.  It collects air loops by system type.
  def add_heat_cool_to_report(equipment_info:, heat_cool_cost:, al_eq_reporting_info:)
    # If there is no air loop heating or cooling equipment casting information add it to the hash.
    if al_eq_reporting_info.empty?
      al_eq_reporting_info << {
          eq_category: equipment_info[:obj_type][3..-1],
          heating_fuel: equipment_info[:heating_fuel],
          cooling_type: equipment_info[:cooling_type],
          total_modeled_capacity_kw: equipment_info[:mech_capacity_kw].round(3),
          cost: heat_cool_cost.round(2)
      }
    else
      # look for an air loop with the appropriate system type.
      ahu_heat_cool = al_eq_reporting_info.select {|aloop|
        aloop[:eq_category] == equipment_info[:obj_type][3..-1]
      }
      # If air loops with that system type are present add a new one.
      if ahu_heat_cool.empty?
        al_eq_reporting_info << {
            eq_category: equipment_info[:obj_type][3..-1],
            heating_fuel: equipment_info[:heating_fuel],
            cooling_type: equipment_info[:cooling_type],
            total_modeled_capacity_kw: equipment_info[:mech_capacity_kw].round(3),
            cost: heat_cool_cost.round(2)
        }
      else
        # If there is an air loop with the appropriate system type add the capacity and cost to the hash.
        ahu_heat_cool[0][:total_modeled_capacity_kw] += equipment_info[:mech_capacity_kw].round(3)
        ahu_heat_cool[0][:cost] += heat_cool_cost.round(2)
      end
    end
  end

  # This method oversees the costing of heating and cooling equipment in an air loop.  It takes in:
  # airloop_equipment:  A hash containing all heating and cooling supply equipment in the air loop
  # The method retruns the airloop_equip_return_info hash which contains:
  # al_eq_reporting_info:  A hash containing information that will be included in the ventilation costing report
  # heat_cool_cost:  The total cost of heating and cooling equipment in the air loop
  def airloop_equipment_costing(airloop_equipment:, ahu_mult:, vent_tags: [])
    # Initialize return data
    ret_heat_cool_cost = 0
    al_eq_reporting_info = []
    ccashp_cost = 0
    vent_equip_tags = vent_tags.clone
    vent_equip_tags << "air loop equipment"

    # Look for a heat pump.  Heat pump air loop equipment costing is treated differently.
    heat_pumps = airloop_equipment.select{|airloop_eq| airloop_eq[:heating_fuel].to_s.include?('HP')}
    unless heat_pumps.empty?
      cool_eq = airloop_equipment.select{|airloop_eq| airloop_eq[:cooling_type].to_s.include?("DX")}
      unless cool_eq.empty?
        heat_pumps[0][:mech_capacity_kw] = cool_eq[0][:mech_capacity_kw].to_f if cool_eq[0][:mech_capacity_kw].to_f > heat_pumps[0][:mech_capacity_kw].to_f
        heat_pumps[0][:cooling_type] = heat_pumps[0][:heating_fuel]
        airloop_equipment.delete_if{|data| data[:cooling_type].to_s.include?("DX")}
      end
      if heat_pumps[0][:heating_fuel].to_s == "CCASHP"
        ccashp_cost = cost_ccashp_additional_components(ahu_mult: ahu_mult, heat_pump: heat_pumps[0], vent_tags: vent_equip_tags)
      end
      elec_eq = airloop_equipment.select{|airloop_eq| airloop_eq[:heating_fuel] == 'elec'}
      # If a backup electric heating coil is present look for a different item in the 'hvac_materials' costing sheet
      # than if the coil where part of an air loop without a heat pump.
      elec_eq.each do |el_eq|
        el_eq[:cat_search] = 'elecduct'
      end
      #airloop_equipment.select.with_index{|airloop_eq, index| airloop_eq[:cooling_type] == 'DX' || airloop_eq[:cooling_type] == 'CCASHP'}
    end

    # Cost all of the heating and cooling equipment in the air loop
    airloop_equipment.each do |airloop_eq|
      # Costing of air loop equipment should be done on a per air handler basis.  Thus, divide the total capacity of the
      # piece of air loop equipment by the number of air handlers required.
      total_modeled_capacity = airloop_eq[:mech_capacity_kw].to_f
      airloop_eq[:mech_capacity_kw] = total_modeled_capacity / ahu_mult
      # Get ventilation heating and cooling equipment costs.
      heat_cool_cost = cost_heat_cool_equip(equipment_info: airloop_eq, vent_tags: vent_equip_tags, report_mult: ahu_mult) * ahu_mult
      heat_cool_cost += ccashp_cost if airloop_eq[:heating_fuel].to_s == "CCASHP"
      # Add the equipment cost to the total air loop equipment cost
      ret_heat_cool_cost += heat_cool_cost
      # Only the total modeled capacity of the piece of air loop equipment should be reported to the user rather than
      # the capacity per air handler.
      airloop_eq[:mech_capacity_kw] = total_modeled_capacity
      # Add the air loop hetaing/cooling equipment information to the total air loop heating/cooling equipment report hash
      al_eq_reporting_info = add_heat_cool_to_report(equipment_info: airloop_eq, heat_cool_cost: heat_cool_cost, al_eq_reporting_info: al_eq_reporting_info)
    end

    # Create the return hash and return it.
    airloop_equip_return_info = {
      al_eq_reporting_info: al_eq_reporting_info,
      heat_cool_cost: ret_heat_cool_cost
    }
    return airloop_equip_return_info
  end

  # This method calculates the costs of CCASHP equipment beyond the coil cost and any backup heating costs.  It takes in
  # ahu_mult:  The number of air handlers required to meet the model air loop flow rate, cooling type, heating type and
  # system type.
  # heat_pumps:  The heat pump hash for the ccashp which contains the OpenStudio heat pump object and the size of the
  # heat pump in kW.
  # The method uses a number of different costing methods to get equipment costs.  The methods used depend on what best
  # suits the costing.  For example evaporator costing is found by size and material so the get_vent_cost_data method
  # is most appropriate.  Wiring has a material and size but the size should be an exact match so the get_comp_cost
  # method is used.  Finally, a number of pieces of equipment with no size are costed.  The esiest way to cost these
  # items was to refer to their 'materials_hvac' sheet 'material_id' column numbers and associated quantities and use
  # the vent_assembly_cost method.
  def cost_ccashp_additional_components(ahu_mult:, heat_pump:, vent_tags: [], report_mult: 1.0)
    ccashp_tags = vent_tags.clone
    # Initialize the ccashp additional equipment cost.
    ccashp_add_cost = 0
    # Set a variable to represent the capacity of each heat pump per air handler
    cap = heat_pump[:mech_capacity_kw].to_f/ahu_mult
    # Set a variable to represent the capacity in tons of cooling (for costing the refrigerent line).
    # cap_tonc = (OpenStudio.convert(cap.to_f, 'kW', 'kBtu/hr').get)/12.0 # No longer needed but keeping for future reference

    # This variable holds the number of condensing units.
    cond_mult = 1.0

    # An array of hashes containing the information required to cost the heat pump evaporator valve and condenser.
    ccashp_lrg_equips = []
    ccashp_lrg_equips << {
      supply_comp: heat_pump[:supply_comp],
      mech_capacity_kw: cap,
      cat_search: "EV_valve"
    }
    ccashp_lrg_equips << {
      supply_comp: heat_pump[:supply_comp],
      mech_capacity_kw: cap,
      cat_search: "ccashp_condensor"
    }

    # Cost the heat pump evaporator valve and condenser.
    ccashp_lrg_equips.each do |ccashp_lrg_equip|
      equip_mult, cost_info = get_vent_cost_data(equipment_info: ccashp_lrg_equip)
      ccashp_add_cost += get_vent_mat_cost(mat_cost_info: cost_info, vent_tags: ccashp_tags, report_mult: (report_mult*equip_mult*ahu_mult)) * equip_mult * ahu_mult
      # cond_mult is supposed to be the number of condensors there are.  It is set to be the multiplier if one condensor
      # is not enough.  It should be set to the number of condesors because the condensors should be the last item in
      # this loop to be costed.
      cond_mult = equip_mult
    end

    # Cost the wiring per heat pump condenser.  Correcting to use 20 ft rather than 20 m.
    #ccashp_wiring_dist = (OpenStudio.convert(20, 'm', 'ft').get)/100.0
    ccashp_add_equip = [
      {
        mat: "Wiring",
        unit: "CLF",
        size: 10,
        mult: 0.2 * ahu_mult * cond_mult
    }
    ]
    # Get the Wiring costs.
    ccashp_add_cost += get_comp_cost(cost_info: ccashp_add_equip, vent_tags: ccashp_tags)

    # Set an array containing the equipment 'material_id' references to search in the costing spreadsheet
    # 'materials_hvac' sheet.
    ids = [
      #1307, #Low Temperature Kit this belongs with the air handlers not the equipment
      1295, # Remote Condensor Controller
      1662, # Refrigerant tubing-large, 20' of 0.5" supply and 1-1/8" return
      30, # 1.25" pipe insulation for refrigerant tubing
      1415 # Safety Switch
    ]

    # Set the quantities associated with the above ids.  Note that ahu_mult is included when getting the cost.
    id_quants = [
      #1.0,
      cond_mult,
      cond_mult,
      cond_mult * 20 * 2, # 20' of supply and return pipe insulation for refrigerant tubing
      cond_mult
    ]

    # Get the costs for equipment in the ids with id_quants quantities above.
    ccashp_add_cost += vent_assembly_cost(ids: ids, id_quants: id_quants, overall_mult: ahu_mult, vent_tags: ccashp_tags)
    return ccashp_add_cost
  end
end
