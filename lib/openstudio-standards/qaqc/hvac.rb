# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group HVAC

    # Check the air loop and zone operational vs. sizing temperatures and make sure everything is coordinated.
    # This identifies problems caused by sizing to one set of conditions and operating at a different set.
    #
    # @param category [String] category to bin this check into
    # @param max_sizing_temp_delta [Double] threshold for throwing an error for design sizing temperatures
    # @param max_operating_temp_delta [Double] threshold for throwing an error on operating temperatures
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_air_loop_temperatures(category, max_sizing_temp_delta: 2.0, max_operating_temp_delta: 5.0, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Air System Temperatures')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that air system sizing and operation temperatures are coordinated.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      begin
        # get the weather file run period (as opposed to design day run period)
        ann_env_pd = nil
        @sql = @model.sqlFile.get
        @sql.availableEnvPeriods.each do |env_pd|
          env_type = @sql.environmentType(env_pd)
          if env_type.is_initialized && (env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod'))
            ann_env_pd = env_pd
            break
          end
        end

        # only try to get the annual timeseries if an annual simulation was run
        if ann_env_pd.nil?
          check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot check equipment part load ratios.')
          return check_elems
        end

        @model.getAirLoopHVACs.sort.each do |air_loop|
          supply_outlet_node_name = air_loop.supplyOutletNode.name.to_s
          design_cooling_sat = air_loop.sizingSystem.centralCoolingDesignSupplyAirTemperature
          design_cooling_sat = OpenStudio.convert(design_cooling_sat, 'C', 'F').get
          design_heating_sat = air_loop.sizingSystem.centralHeatingDesignSupplyAirTemperature
          design_heating_sat = OpenStudio.convert(design_heating_sat, 'C', 'F').get

          # check if the system is a unitary system
          is_unitary_system = OpenstudioStandards::HVAC.air_loop_hvac_unitary_system?(air_loop)
          is_direct_evap = OpenstudioStandards::HVAC.air_loop_hvac_direct_evap?(air_loop)

          if is_unitary_system && !is_direct_evap
            unitary_system_name = nil
            unitary_system_type = '<unspecified>'
            unitary_min_temp_f = nil
            unitary_max_temp_f = nil
            air_loop.supplyComponents.each do |component|
              obj_type = component.iddObjectType.valueName.to_s
              case obj_type
              when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
                unitary_system_name = component.name.to_s
                unitary_system_type = obj_type
                unitary_system_temps = OpenstudioStandards::HVAC.unitary_system_min_max_temperature_value(component)
                unitary_min_temp_f = unitary_system_temps['min_temp']
                unitary_max_temp_f = unitary_system_temps['max_temp']
              end
            end
            # set expected minimums for operating temperatures
            expected_min = unitary_min_temp_f.nil? ? design_cooling_sat : [design_cooling_sat, unitary_min_temp_f].min
            expected_max = unitary_max_temp_f.nil? ? design_heating_sat : [design_heating_sat, unitary_max_temp_f].max
          else
            # get setpoint manager
            spm_name = nil
            spm_type = '<unspecified>'
            spm_min_temp_f = nil
            spm_max_temp_f = nil
            @model.getSetpointManagers.each do |spm|
              if spm.setpointNode.is_initialized
                spm_node = spm.setpointNode.get
                if spm_node.name.to_s == supply_outlet_node_name
                  spm_name = spm.name
                  spm_type = spm.iddObjectType.valueName.to_s
                  spm_temps_f = OpenstudioStandards::HVAC.setpoint_manager_min_max_temperature(spm)
                  spm_min_temp_f = spm_temps_f['min_temp']
                  spm_max_temp_f = spm_temps_f['max_temp']
                  break
                end
              end
            end

            # check setpoint manager temperatures against design temperatures
            if spm_min_temp_f && ((spm_min_temp_f - design_cooling_sat).abs > max_sizing_temp_delta)
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_cooling_sat.round(1)}F design cooling supply air temperature, but the setpoint manager operates down to #{spm_min_temp_f.round(1)}F.")
            end
            if spm_max_temp_f && ((spm_max_temp_f - design_heating_sat).abs > max_sizing_temp_delta)
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_heating_sat.round(1)}F design heating supply air temperature, but the setpoint manager operates up to #{spm_max_temp_f.round(1)}F.")
            end

            # set expected minimums for operating temperatures
            expected_min = spm_min_temp_f.nil? ? design_cooling_sat : [design_cooling_sat, spm_min_temp_f].min
            expected_max = spm_max_temp_f.nil? ? design_heating_sat : [design_heating_sat, spm_max_temp_f].max

            # check zone sizing temperature against air loop design temperatures
            air_loop.thermalZones.each do |zone|
              # if this zone has a reheat terminal, get the reheat temp for comparison
              reheat_op_f = nil
              reheat_zone = false
              zone.equipment.each do |equipment|
                obj_type = equipment.iddObjectType.valueName.to_s
                case obj_type
                when 'OS_AirTerminal_SingleDuct_ConstantVolume_Reheat'
                  term = equipment.to_AirTerminalSingleDuctConstantVolumeReheat.get
                  reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                  reheat_zone = true
                when 'OS_AirTerminal_SingleDuct_VAV_HeatAndCool_Reheat'
                  term = equipment.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.get
                  reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                  reheat_zone = true
                when 'OS_AirTerminal_SingleDuct_VAV_Reheat'
                  term = equipment.to_AirTerminalSingleDuctVAVReheat.get
                  reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                  reheat_zone = true
                when 'OS_AirTerminal_SingleDuct_ParallelPIU_Reheat', 'OS_AirTerminal_SingleDuct_SeriesPIU_Reheat'
                  # reheat_op_f = # Not an OpenStudio input
                  reheat_zone = true
                end
              end

              # get the zone heating and cooling SAT for sizing
              sizing_zone = zone.sizingZone
              zone_siz_htg_f = OpenStudio.convert(sizing_zone.zoneHeatingDesignSupplyAirTemperature, 'C', 'F').get
              zone_siz_clg_f = OpenStudio.convert(sizing_zone.zoneCoolingDesignSupplyAirTemperature, 'C', 'F').get

              # check cooling temperatures
              if (design_cooling_sat - zone_siz_clg_f).abs > max_sizing_temp_delta
                check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_cooling_sat.round(1)}F design cooling supply air temperature but the sizing for zone #{zone.name} uses a cooling supply air temperature of #{zone_siz_clg_f.round(1)}F.")
              end

              # check heating temperatures
              if reheat_zone && reheat_op_f
                if (reheat_op_f - zone_siz_htg_f).abs > max_sizing_temp_delta
                  check_elems << OpenStudio::Attribute.new('flag', "Minor Error: For zone '#{zone.name}', the reheat air temperature is set to #{reheat_op_f.round(1)}F, but the sizing for the zone is done with a heating supply air temperature of #{zone_siz_htg_f.round(1)}F.")
                end
              elsif reheat_zone && !reheat_op_f
                # reheat zone but no reheat temperature available from terminal object
              elsif (design_heating_sat - zone_siz_htg_f).abs > max_sizing_temp_delta
                check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_heating_sat.round(1)}F design heating supply air temperature but the sizing for zone #{zone.name} uses a heating supply air temperature of #{zone_siz_htg_f.round(1)}F.")
              end
            end
          end

          # get supply air temperatures for supply outlet node
          supply_temp_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Temperature', supply_outlet_node_name)
          if supply_temp_timeseries.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{air_loop.name}'")
            next
          else
            # convert to ruby array
            temperatures = []
            supply_temp_vector = supply_temp_timeseries.get.values
            for i in (0..supply_temp_vector.size - 1)
              temperatures << supply_temp_vector[i]
            end
          end

          # get supply air flow rates for supply outlet node
          supply_flow_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Standard Density Volume Flow Rate', supply_outlet_node_name)
          if supply_flow_timeseries.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{air_loop.name}'")
            next
          else
            # convert to ruby array
            flowrates = []
            supply_flow_vector = supply_flow_timeseries.get.values
            for i in (0..supply_flow_vector.size - 1)
              flowrates << supply_flow_vector[i]
            end
          end
          # check reasonableness of supply air temperatures when supply air flow rate is operating
          flow_tolerance = OpenStudio.convert(10.0, 'cfm', 'm^3/s').get
          operating_temperatures = temperatures.select.with_index { |_t, k| flowrates[k] > flow_tolerance }
          operating_temperatures = operating_temperatures.map { |t| ((t * 1.8) + 32.0) }

          next if operating_temperatures.empty?

          runtime_fraction = operating_temperatures.size.to_f / temperatures.size
          temps_out_of_bounds = operating_temperatures.select { |t| ((t < 40.0) || (t > 110.0) || ((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) }

          next if temps_out_of_bounds.empty?

          min_op_temp_f = temps_out_of_bounds.min
          max_op_temp_f = temps_out_of_bounds.max
          # avg_F = temps_out_of_bounds.inject(:+).to_f / temps_out_of_bounds.size
          err = []
          err << 'Major Error:'
          err << "Expected supply air temperatures out of bounds for air loop '#{air_loop.name}'"
          err << "with #{design_cooling_sat.round(1)}F design cooling SAT"
          err << "and #{design_heating_sat.round(1)}F design heating SAT."
          unless is_unitary_system && !is_direct_evap
            err << "Air loop setpoint manager '#{spm_name}' of type '#{spm_type}' with a"
            err << "#{spm_min_temp_f.round(1)}F minimum setpoint temperature and"
            err << "#{spm_max_temp_f.round(1)}F maximum setpoint temperature."
          end
          if is_unitary_system && !is_direct_evap
            err << "Unitary system '#{unitary_system_name}' of type '#{unitary_system_type}' with"
            temp_str = unitary_min_temp_f.nil? ? 'no' : "#{unitary_min_temp_f.round(1)}F"
            err << "#{temp_str} minimum setpoint temperature and"
            temp_str = unitary_max_temp_f.nil? ? 'no' : "#{unitary_max_temp_f.round(1)}F"
            err << "#{temp_str} maximum setpoint temperature."
          end
          err << "Out of #{operating_temperatures.size}/#{temperatures.size} (#{(runtime_fraction * 100.0).round(1)}%) operating supply air temperatures"
          err << "#{temps_out_of_bounds.size}/#{operating_temperatures.size} (#{((temps_out_of_bounds.size.to_f / operating_temperatures.size) * 100.0).round(1)}%)"
          err << "are out of bounds with #{min_op_temp_f.round(1)}F min and #{max_op_temp_f.round(1)}F max."
          check_elems << OpenStudio::Attribute.new('flag', err.join(' ').gsub(/\n/, ''))
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Major Error: Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the fan power (W/cfm) for each air loop fan in the model to identify unrealistically sized fans.
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_pct_delta [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_air_loop_fan_power(category, target_standard, max_pct_delta: 0.3, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Fan Power')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that fan power vs flow makes sense.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      begin
        # Check each air loop
        @model.getAirLoopHVACs.sort.each do |air_loop|
          # Set the expected W/cfm
          if air_loop.thermalZones.size.to_i == 1
            # expect single zone systems to be lower
            expected_w_per_cfm = 0.5
          else
            expected_w_per_cfm = 1.1
          end

          # Check the W/cfm for each fan on each air loop
          air_loop.supplyComponents.each do |component|
            # Get the W/cfm for the fan
            obj_type = component.iddObjectType.valueName.to_s
            case obj_type
            when 'OS_Fan_ConstantVolume'
              actual_w_per_cfm = std.fan_rated_w_per_cfm(component.to_FanConstantVolume.get)
            when 'OS_Fan_OnOff'
              actual_w_per_cfm = std.fan_rated_w_per_cfm(component.to_FanOnOff.get)
            when 'OS_Fan_VariableVolume'
              actual_w_per_cfm = std.fan_rated_w_per_cfm(component.to_FanVariableVolume.get)
            else
              next # Skip non-fan objects
            end

            # Compare W/cfm to expected/typical values
            if ((expected_w_per_cfm - actual_w_per_cfm) / actual_w_per_cfm).abs > max_pct_delta
              check_elems << OpenStudio::Attribute.new('flag', "For #{component.name} on #{air_loop.name}, the actual fan power of #{actual_w_per_cfm.round(1)} W/cfm is more than #{(max_pct_delta * 100.0).round(2)}% different from the expected #{expected_w_per_cfm} W/cfm.")
            end
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # checks the HVAC system type against 90.1 baseline system type
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_hvac_system_type(category, target_standard, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Type')
      check_elems << OpenStudio::Attribute.new('category', category)

      # add ASHRAE to display of target standard if includes with 90.1
      if target_standard.include?('90.1 2013')
        check_elems << OpenStudio::Attribute.new('description', 'Check against ASHRAE 90.1 2013 Tables G3.1.1 A-B. Infers the baseline system type based on the equipment serving the zone and their heating/cooling fuels. Only does a high-level inference; does not look for the presence/absence of required controls, etc.')
      else
        check_elems << OpenStudio::Attribute.new('description', 'Check against ASHRAE 90.1. Infers the baseline system type based on the equipment serving the zone and their heating/cooling fuels. Only does a high-level inference; does not look for the presence/absence of required controls, etc.')
      end

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      begin
        # Get the actual system type for all zones in the model
        act_zone_to_sys_type = {}
        @model.getThermalZones.each do |zone|
          act_zone_to_sys_type[zone] = std.thermal_zone_infer_system_type(zone)
        end

        # Get the baseline system type for all zones in the model
        climate_zone = std.model_get_building_properties(@model)['climate_zone']
        req_zone_to_sys_type = std.model_get_baseline_system_type_by_zone(@model, climate_zone)

        # Compare the actual to the correct
        @model.getThermalZones.each do |zone|
          is_plenum = false
          zone.spaces.each do |space|
            if OpenstudioStandards::Space.space_plenum?(space)
              is_plenum = true
            end
          end
          next if is_plenum

          req_sys_type = req_zone_to_sys_type[zone]
          act_sys_type = act_zone_to_sys_type[zone]

          unless act_sys_type == req_sys_type
            if req_sys_type == '' then req_sys_type = 'Unknown' end
            check_elems << OpenStudio::Attribute.new('flag', "#{zone.name} baseline system type is incorrect. Supposed to be #{req_sys_type}, but was #{act_sys_type} instead.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check mechanical equipment capacity against typical sizing
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_hvac_capacity(category, target_standard, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Capacity')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check HVAC capacity against ASHRAE rules of thumb for chiller max flow rate, air loop max flow rate, air loop cooling capciaty, and zone heating capcaity. Zone heating check will skip thermal zones without any exterior exposure, and thermal zones that are not conditioned.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      # Sizing benchmarks.  Each option has a target value, min and max fractional tolerance, and units.
      # In the future climate zone specific targets may be in standards
      sizing_benchmarks = {}
      sizing_benchmarks['chiller_max_flow_rate'] = { 'min_error' => 1.5, 'min_warning' => 2.0, 'max_warning' => 3.0, 'max_error' => 3.5, 'units' => 'gal/ton*min' }
      sizing_benchmarks['air_loop_max_flow_rate'] = { 'min_error' => 0.2, 'min_warning' => 0.5, 'max_warning' => 2.0, 'max_error' => 4.0, 'units' => 'cfm/ft^2' }
      sizing_benchmarks['air_loop_cooling_capacity'] = { 'min_error' => 200.0, 'min_warning' => 300.0, 'max_warning' => 1500.0, 'max_error' => 2000.0, 'units' => 'ft^2/ton' }
      sizing_benchmarks['zone_heating_capacity'] = { 'min_error' => 4.0, 'min_warning' => 8.0, 'max_warning' => 30.0, 'max_error' => 60.0, 'units' => 'Btu/ft^2*h' }

      begin
        # check max flow rate of chillers in model
        @model.getPlantLoops.sort.each do |plant_loop|
          # next if no chiller on plant loop
          chillers = []
          plant_loop.supplyComponents.each do |sc|
            if sc.to_ChillerElectricEIR.is_initialized
              chillers << sc.to_ChillerElectricEIR.get
            end
          end
          next if chillers.empty?

          # gather targets for chiller capacity
          chiller_max_flow_rate_min_error = sizing_benchmarks['chiller_max_flow_rate']['min_error']
          chiller_max_flow_rate_min_warning = sizing_benchmarks['chiller_max_flow_rate']['min_warning']
          chiller_max_flow_rate_max_warning = sizing_benchmarks['chiller_max_flow_rate']['max_warning']
          chiller_max_flow_rate_max_error = sizing_benchmarks['chiller_max_flow_rate']['max_error']
          chiller_max_flow_rate_units_ip = options['chiller_max_flow_rate']['units']

          # get capacity of loop (not individual chiller but entire loop)
          total_cooling_capacity_w = std.plant_loop_total_cooling_capacity(plant_loop)
          total_cooling_capacity_ton = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/h').get / 12_000.0

          # get the max flow rate (not individual chiller)
          maximum_loop_flow_rate = std.plant_loop_find_maximum_loop_flow_rate(plant_loop)
          maximum_loop_flow_rate_ip = OpenStudio.convert(maximum_loop_flow_rate, 'm^3/s', 'gal/min').get

          if total_cooling_capacity_ton < 0.01
            check_elems <<  OpenStudio::Attribute.new('flag', "Cooling capacity for #{plant_loop.name.get} is too small for flow rate #{maximum_loop_flow_rate_ip.round(2)} gal/min.")
          end

          # calculate the flow per tons of cooling
          model_flow_rate_per_ton_cooling_ip = maximum_loop_flow_rate_ip / total_cooling_capacity_ton

          # check flow rate per capacity
          if model_flow_rate_per_ton_cooling_ip < chiller_max_flow_rate_min_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is below #{chiller_max_flow_rate_min_error.round(2)} #{chiller_max_flow_rate_units_ip}.")
          elsif model_flow_rate_per_ton_cooling_ip < chiller_max_flow_rate_min_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is below #{chiller_max_flow_rate_min_warning.round(2)} #{chiller_max_flow_rate_units_ip}.")
          elsif model_flow_rate_per_ton_cooling_ip > chiller_max_flow_rate_max_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is above #{chiller_max_flow_rate_max_warning.round(2)} #{chiller_max_flow_rate_units_ip}.")
          elsif model_flow_rate_per_ton_cooling_ip > chiller_max_flow_rate_max_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is above #{chiller_max_flow_rate_max_error.round(2)} #{chiller_max_flow_rate_units_ip}.")
          end
        end

        # loop through air loops to get max flow rate and cooling capacity.
        @model.getAirLoopHVACs.sort.each do |air_loop|
          # skip DOAS systems for now
          sizing_system = air_loop.sizingSystem
          next if sizing_system.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'

          # gather argument sizing_benchmarks for air_loop_max_flow_rate checks
          air_loop_max_flow_rate_min_error = sizing_benchmarks['air_loop_max_flow_rate']['min_error']
          air_loop_max_flow_rate_min_warning = sizing_benchmarks['air_loop_max_flow_rate']['min_warning']
          air_loop_max_flow_rate_max_warning = sizing_benchmarks['air_loop_max_flow_rate']['max_warning']
          air_loop_max_flow_rate_max_error = sizing_benchmarks['air_loop_max_flow_rate']['max_error']
          air_loop_max_flow_rate_units_ip = sizing_benchmarks['air_loop_max_flow_rate']['units']

          # get values from model for air loop checks
          floor_area_served = std.air_loop_hvac_floor_area_served(air_loop)
          design_supply_air_flow_rate = std.air_loop_hvac_find_design_supply_air_flow_rate(air_loop)

          # check max flow rate of air loops in the model
          model_normalized_flow_rate_si = design_supply_air_flow_rate / floor_area_served
          model_normalized_flow_rate_ip = OpenStudio.convert(model_normalized_flow_rate_si, 'm^3/m^2*s', air_loop_max_flow_rate_units_ip).get
          if model_normalized_flow_rate_ip < air_loop_max_flow_rate_min_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is below #{air_loop_max_flow_rate_min_error.round(2)} #{air_loop_max_flow_rate_units_ip}.")
          elsif model_normalized_flow_rate_ip < air_loop_max_flow_rate_min_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is below #{air_loop_max_flow_rate_min_warning.round(2)} #{air_loop_max_flow_rate_units_ip}.")
          elsif model_normalized_flow_rate_ip > air_loop_max_flow_rate_max_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is above #{air_loop_max_flow_rate_max_warning.round(2)} #{air_loop_max_flow_rate_units_ip}.")
          elsif model_normalized_flow_rate_ip > air_loop_max_flow_rate_max_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is above #{air_loop_max_flow_rate_max_error.round(2)} #{air_loop_max_flow_rate_units_ip}.")
          end

          # loop through air loops to get max flow rate and cooling capacity.

          # check if DOAS, don't check airflow or cooling capacity if it is
          sizing_system = air_loop.sizingSystem
          next if sizing_system.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'

          # gather argument options for air_loop_cooling_capacity checks
          air_loop_cooling_capacity_min_error = sizing_benchmarks['air_loop_cooling_capacity']['min_error']
          air_loop_cooling_capacity_min_warning = sizing_benchmarks['air_loop_cooling_capacity']['min_warning']
          air_loop_cooling_capacity_max_warning = sizing_benchmarks['air_loop_cooling_capacity']['max_warning']
          air_loop_cooling_capacity_max_error = sizing_benchmarks['air_loop_cooling_capacity']['max_error']
          air_loop_cooling_capacity_units_ip = sizing_benchmarks['air_loop_cooling_capacity']['units']

          # check cooling capacity of air loops in the model
          floor_area_served = std.air_loop_hvac_floor_area_served(air_loop)
          capacity = std.air_loop_hvac_total_cooling_capacity(air_loop)
          model_normalized_capacity_si = capacity / floor_area_served
          model_normalized_capacity_ip = OpenStudio.convert(model_normalized_capacity_si, 'W/m^2', 'Btu/ft^2*h').get / 12_000.0

          # want to display in tons/ft^2 so invert number and display for checks
          model_tons_per_area_ip = 1.0 / model_normalized_capacity_ip
          if model_tons_per_area_ip < air_loop_cooling_capacity_min_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is below #{air_loop_cooling_capacity_min_error.round} #{air_loop_cooling_capacity_units_ip}.")
          elsif model_tons_per_area_ip < air_loop_cooling_capacity_min_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is below #{air_loop_cooling_capacity_min_warning.round} #{air_loop_cooling_capacity_units_ip}.")
          elsif model_tons_per_area_ip > air_loop_cooling_capacity_max_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is above #{air_loop_cooling_capacity_max_warning.round} #{air_loop_cooling_capacity_units_ip}.")
          elsif model_tons_per_area_ip > air_loop_cooling_capacity_max_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is above #{air_loop_cooling_capacity_max_error.round} #{air_loop_cooling_capacity_units_ip}.")
          end
        end

        # check heating capacity of thermal zones in the model with exterior exposure
        report_name = 'HVACSizingSummary'
        table_name = 'Zone Sensible Heating'
        column_name = 'User Design Load per Area'
        min_error = sizing_benchmarks['zone_heating_capacity']['min_error']
        min_warning = sizing_benchmarks['zone_heating_capacity']['min_warning']
        max_warning = sizing_benchmarks['zone_heating_capacity']['max_warning']
        max_error = sizing_benchmarks['zone_heating_capacity']['max_error']
        units_ip = sizing_benchmarks['zone_heating_capacity']['units']

        @model.getThermalZones.sort.each do |thermal_zone|
          next if thermal_zone.canBePlenum
          next if thermal_zone.exteriorSurfaceArea < 0.01

          # check actual against target
          query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='#{report_name}' and TableName='#{table_name}' and RowName= '#{thermal_zone.name.get.upcase}' and ColumnName= '#{column_name}'"
          results = @sql.execAndReturnFirstDouble(query)
          model_zone_heating_capacity_ip = OpenStudio.convert(results.to_f, 'W/m^2', units_ip).get
          if model_zone_heating_capacity_ip < min_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is below #{min_error.round(1)} Btu/ft^2*h.")
          elsif model_zone_heating_capacity_ip < min_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is below #{min_warning.round(1)} Btu/ft^2*h.")
          elsif model_zone_heating_capacity_ip > max_warning
            check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is above #{max_warning.round(1)} Btu/ft^2*h.")
          elsif model_zone_heating_capacity_ip > max_error
            check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is above #{max_error.round(1)} Btu/ft^2*h.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the mechanical system efficiencies against a standard
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_hvac_efficiency(category, target_standard, min_pass_pct: 0.3, max_pass_pct: 0.3, name_only: false)
      component_type_array = ['ChillerElectricEIR', 'CoilCoolingDXSingleSpeed', 'CoilCoolingDXTwoSpeed', 'CoilHeatingDXSingleSpeed', 'BoilerHotWater', 'FanConstantVolume', 'FanVariableVolume', 'PumpConstantSpeed', 'PumpVariableSpeed']

      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Efficiency')
      check_elems << OpenStudio::Attribute.new('category', category)

      if target_standard.include?('90.1-2013')
        check_elems << OpenStudio::Attribute.new('description', "Check against #{target_standard} Tables 6.8.1 A-K for the following component types: #{component_type_array.join(', ')}.")
      else
        check_elems << OpenStudio::Attribute.new('description', "Check against #{target_standard} for the following component types: #{component_type_array.join(', ')}.")
      end

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      begin
        # check ChillerElectricEIR objects (will also have curve check in different script)
        @model.getChillerElectricEIRs.sort.each do |component|
          # eff values from model
          reference_cop = component.referenceCOP

          # get eff values from standards (if name doesn't have expected strings find object returns first object of multiple)
          standard_minimum_full_load_efficiency = std.chiller_electric_eir_standard_minimum_full_load_efficiency(component)

          # check actual against target
          if standard_minimum_full_load_efficiency.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target full load efficiency for #{component.name}.")
          elsif reference_cop < standard_minimum_full_load_efficiency * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "COP of #{reference_cop.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_full_load_efficiency.round(2)}.")
          elsif reference_cop > standard_minimum_full_load_efficiency * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "COP  of #{reference_cop.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_full_load_efficiency.round(2)}.")
          end
        end

        # check CoilCoolingDXSingleSpeed objects (will also have curve check in different script)
        @model.getCoilCoolingDXSingleSpeeds.each do |component|
          # eff values from model
          rated_cop = component.ratedCOP.get

          # get eff values from standards
          standard_minimum_cop = std.coil_cooling_dx_single_speed_standard_minimum_cop(component)

          # check actual against target
          if standard_minimum_cop.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
          elsif rated_cop < standard_minimum_cop * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The COP of #{rated_cop.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          elsif rated_cop > standard_minimum_cop * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The COP of  #{rated_cop.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          end
        end

        # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
        @model.getCoilCoolingDXTwoSpeeds.sort.each do |component|
          # eff values from model
          rated_high_speed_cop = component.ratedHighSpeedCOP.get
          rated_low_speed_cop = component.ratedLowSpeedCOP.get

          # get eff values from standards
          standard_minimum_cop = std.coil_cooling_dx_two_speed_standard_minimum_cop(component)

          # check actual against target
          if standard_minimum_cop.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
          elsif rated_high_speed_cop < standard_minimum_cop * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The high speed COP of #{rated_high_speed_cop.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          elsif rated_high_speed_cop > standard_minimum_cop * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The high speed COP of  #{rated_high_speed_cop.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          end
          if standard_minimum_cop.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
          elsif rated_low_speed_cop < standard_minimum_cop * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The low speed COP of #{rated_low_speed_cop.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          elsif rated_low_speed_cop > standard_minimum_cop * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The low speed COP of  #{rated_low_speed_cop.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          end
        end

        # check CoilHeatingDXSingleSpeed objects
        # @todo need to test this once json file populated for this data
        @model.getCoilHeatingDXSingleSpeeds.sort.each do |component|
          # eff values from model
          rated_cop = component.ratedCOP

          # get eff values from standards
          standard_minimum_cop = std.coil_heating_dx_single_speed_standard_minimum_cop(component)

          # check actual against target
          if standard_minimum_cop.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
          elsif rated_cop < standard_minimum_cop * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The COP of #{rated_cop.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
          elsif rated_cop > standard_minimum_cop * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The COP of  #{rated_cop.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)}. for #{target_standard}")
          end
        end

        # check BoilerHotWater
        @model.getBoilerHotWaters.sort.each do |component|
          # eff values from model
          nominal_thermal_efficiency = component.nominalThermalEfficiency

          # get eff values from standards
          standard_minimum_thermal_efficiency = std.boiler_hot_water_standard_minimum_thermal_efficiency(component)

          # check actual against target
          if standard_minimum_thermal_efficiency.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target thermal efficiency for #{component.name}.")
          elsif nominal_thermal_efficiency < standard_minimum_thermal_efficiency * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Nominal thermal efficiency of #{nominal_thermal_efficiency.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_thermal_efficiency.round(2)} for #{target_standard}.")
          elsif nominal_thermal_efficiency > standard_minimum_thermal_efficiency * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Nominal thermal efficiency of  #{nominal_thermal_efficiency.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_thermal_efficiency.round(2)} for #{target_standard}.")
          end
        end

        # check FanConstantVolume
        @model.getFanConstantVolumes.sort.each do |component|
          # eff values from model
          motor_eff = component.motorEfficiency

          # get eff values from standards
          motor_bhp = std.fan_brake_horsepower(component)
          standard_minimum_motor_efficiency_and_size = std.fan_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

          # check actual against target
          if standard_minimum_motor_efficiency_and_size.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}.")
          elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          end
        end

        # check FanVariableVolume
        @model.getFanVariableVolumes.sort.each do |component|
          # eff values from model
          motor_eff = component.motorEfficiency

          # get eff values from standards
          motor_bhp = std.fan_brake_horsepower(component)
          standard_minimum_motor_efficiency_and_size = std.fan_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

          # check actual against target
          if standard_minimum_motor_efficiency_and_size.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}.")
          elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          end
        end

        # check PumpConstantSpeed
        @model.getPumpConstantSpeeds.sort.each do |component|
          # eff values from model
          motor_eff = component.motorEfficiency

          # get eff values from standards
          motor_bhp = OpenstudioStandards::HVAC.pump_get_brake_horsepower(component)
          next if motor_bhp < 0.0001 # less than 1 watt

          standard_minimum_motor_efficiency_and_size = std.pump_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

          # check actual against target
          if standard_minimum_motor_efficiency_and_size.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}.")
          elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          end
        end

        # check PumpVariableSpeed
        @model.getPumpVariableSpeeds.sort.each do |component|
          # eff values from model
          motor_eff = component.motorEfficiency

          # get eff values from standards
          motor_bhp = OpenstudioStandards::HVAC.pump_get_brake_horsepower(component)
          next if motor_bhp < 0.0001 # less than 1 watt

          standard_minimum_motor_efficiency_and_size = std.pump_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

          # check actual against target
          if standard_minimum_motor_efficiency_and_size.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}.")
          elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the mechanical system part load efficiencies against a standard
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_hvac_part_load_efficiency(category, target_standard, min_pass_pct: 0.3, max_pass_pct: 0.3, name_only: false)
      component_type_array = ['ChillerElectricEIR', 'CoilCoolingDXSingleSpeed', 'CoilCoolingDXTwoSpeed', 'CoilHeatingDXSingleSpeed']

      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Part Load Efficiency')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', "Check 40% and 80% part load efficency against #{target_standard} for the following compenent types: #{component_type_array.join(', ')}. Checking EIR Function of Part Load Ratio curve for chiller and EIR Function of Flow Fraction for DX coils.")

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      # @todo add in check for VAV fan
      begin
        # @todo dynamically generate a list of possible options from the standards json
        chiller_air_cooled_condenser_types = ['WithCondenser', 'WithoutCondenser']
        chiller_water_cooled_compressor_types = ['Reciprocating', 'Scroll', 'Rotary Screw', 'Centrifugal']
        absorption_types = ['Single Effect', 'Double Effect Indirect Fired', 'Double Effect Direct Fired']

        # check getChillerElectricEIRs objects (will also have curve check in different script)
        @model.getChillerElectricEIRs.sort.each do |component|
          # get curve and evaluate
          electric_input_to_cooling_output_ratio_function_of_plr = component.electricInputToCoolingOutputRatioFunctionOfPLR
          curve_40_pct = electric_input_to_cooling_output_ratio_function_of_plr.evaluate(0.4)
          curve_80_pct = electric_input_to_cooling_output_ratio_function_of_plr.evaluate(0.8)

          # find ac properties
          search_criteria = std.chiller_electric_eir_find_search_criteria(component)

          # extend search_criteria for absorption_type
          absorption_types.each do |absorption_type|
            if component.name.to_s.include?(absorption_type)
              search_criteria['absorption_type'] = absorption_type
              next
            end
          end
          # extend search_criteria for condenser type or compressor type
          if search_criteria['cooling_type'] == 'AirCooled'
            chiller_air_cooled_condenser_types.each do |condenser_type|
              if component.name.to_s.include?(condenser_type)
                search_criteria['condenser_type'] = condenser_type
                next
              end
            end
            # if no match and also no absorption_type then issue warning
            if (!search_criteria.key?('condenser_type') || search_criteria['condenser_type'].nil?) &&
               (!search_criteria.key?('absorption_type') || search_criteria['absorption_type'].nil?)
              check_elems <<  OpenStudio::Attribute.new('flag', "Can't find unique search criteria for #{component.name}. #{search_criteria}")
              next # don't go past here
            end
          elsif search_criteria['cooling_type'] == 'WaterCooled'
            chiller_air_cooled_condenser_types.each do |compressor_type|
              if component.name.to_s.include?(compressor_type)
                search_criteria['compressor_type'] = compressor_type
                next
              end
            end
            # if no match and also no absorption_type then issue warning
            if (!search_criteria.key?('compressor_type') || search_criteria['compressor_type'].nil?) &&
               (!search_criteria.key?('absorption_type') || search_criteria['absorption_type'].nil?)
              check_elems <<  OpenStudio::Attribute.new('flag', "Can't find unique search criteria for #{component.name}. #{search_criteria}")
              next # don't go past here
            end
          end

          # lookup chiller
          capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(component)
          capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get
          chlr_props = std.model_find_object(std.standards_data['chillers'], search_criteria, capacity_tons, Date.today)
          if chlr_props.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Didn't find chiller for #{component.name}. #{search_criteria}")
            next # don't go past here in loop if can't find curve
          end

          # temp model to hold temp curve
          model_temp = OpenStudio::Model::Model.new

          # create temp curve
          target_curve_name = chlr_props['eirfplr']
          if target_curve_name.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target eirfplr curve for #{component.name}")
            next # don't go past here in loop if can't find curve
          end
          temp_curve = std.model_add_curve(model_temp, target_curve_name)

          target_curve_40_pct = temp_curve.evaluate(0.4)
          target_curve_80_pct = temp_curve.evaluate(0.8)

          # check curve at two points
          if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          end
          if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          end
        end

        # check getCoilCoolingDXSingleSpeeds objects (will also have curve check in different script)
        @model.getCoilCoolingDXSingleSpeeds.sort.each do |component|
          # get curve and evaluate
          eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionOfFlowFractionCurve
          curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
          curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

          # find ac properties
          search_criteria = std.coil_dx_find_search_criteria(component)
          capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(component)
          capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
          if OpenstudioStandards::HVAC.coil_dx_heat_pump?(component)
            ac_props = std.model_find_object(std.standards_data['heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)
          else
            ac_props = std.model_find_object(std.standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)
          end

          # temp model to hold temp curve
          model_temp = OpenStudio::Model::Model.new

          # create temp curve
          target_curve_name = ac_props['cool_eir_fflow']
          if target_curve_name.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target cool_eir_fflow curve for #{component.name}")
            next # don't go past here in loop if can't find curve
          end
          temp_curve = std.model_add_curve(model_temp, target_curve_name)
          target_curve_40_pct = temp_curve.evaluate(0.4)
          target_curve_80_pct = temp_curve.evaluate(0.8)

          # check curve at two points
          if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          end
          if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          end
        end

        # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
        @model.getCoilCoolingDXTwoSpeeds.sort.each do |component|
          # get curve and evaluate
          eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionOfFlowFractionCurve
          curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
          curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

          # find ac properties
          search_criteria = std.coil_dx_find_search_criteria(component)
          capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_two_speed_get_capacity(component)
          capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
          ac_props = std.model_find_object(std.standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)

          # temp model to hold temp curve
          model_temp = OpenStudio::Model::Model.new

          # create temp curve
          target_curve_name = ac_props['cool_eir_fflow']
          if target_curve_name.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target cool_eir_flow curve for #{component.name}")
            next # don't go past here in loop if can't find curve
          end
          temp_curve = std.model_add_curve(model_temp, target_curve_name)
          target_curve_40_pct = temp_curve.evaluate(0.4)
          target_curve_80_pct = temp_curve.evaluate(0.8)

          # check curve at two points
          if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          end
          if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          end
        end

        # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
        @model.getCoilHeatingDXSingleSpeeds.sort.each do |component|
          # get curve and evaluate
          eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionofFlowFractionCurve # why lowercase of here but not in CoilCoolingDX objects
          curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
          curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

          # find ac properties
          search_criteria = std.coil_dx_find_search_criteria(component)
          capacity_w = OpenstudioStandards::HVAC.coil_heating_get_paired_coil_cooling_capacity(component)
          capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
          ac_props = std.model_find_object(std.standards_data['heat_pumps_heating'], search_criteria, capacity_btu_per_hr, Date.today)
          if ac_props.nil?
            target_curve_name = nil
          else
            target_curve_name = ac_props['heat_eir_fflow']
          end

          # temp model to hold temp curve
          model_temp = OpenStudio::Model::Model.new

          # create temp curve
          if target_curve_name.nil?
            check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target curve for #{component.name}")
            next # don't go past here in loop if can't find curve
          end
          temp_curve = std.model_add_curve(model_temp, target_curve_name)

          # Ensure that the curve was found in standards before attempting to evaluate
          if temp_curve.nil?
            check_elems << OpenStudio::Attribute.new('flag', "Can't find coefficients of curve called #{target_curve_name} for #{component.name}, cannot check part-load performance.")
            next
          end

          target_curve_40_pct = temp_curve.evaluate(0.4)
          target_curve_80_pct = temp_curve.evaluate(0.8)

          # check curve at two points
          if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          end
          if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          end
        end

        # check
        @model.getFanVariableVolumes.sort.each do |component|
          # skip if not on multi-zone system.
          if component.airLoopHVAC.is_initialized
            airloop = component.airLoopHVAC.get

            next unless airloop.thermalZones.size > 1.0
          end

          # skip of brake horsepower is 0
          next if std.fan_brake_horsepower(component) < 0.0001 # less than 1 wat

          # temp model for use by temp model and target curve
          model_temp = OpenStudio::Model::Model.new

          # get coeficents for fan
          model_fan_coefs = []
          model_fan_coefs << component.fanPowerCoefficient1.get
          model_fan_coefs << component.fanPowerCoefficient2.get
          model_fan_coefs << component.fanPowerCoefficient3.get
          model_fan_coefs << component.fanPowerCoefficient4.get
          model_fan_coefs << component.fanPowerCoefficient5.get

          # make model curve
          model_curve = OpenStudio::Model::CurveQuartic.new(model_temp)
          model_curve.setCoefficient1Constant(model_fan_coefs[0])
          model_curve.setCoefficient2x(model_fan_coefs[1])
          model_curve.setCoefficient3xPOW2(model_fan_coefs[2])
          model_curve.setCoefficient4xPOW3(model_fan_coefs[3])
          model_curve.setCoefficient5xPOW4(model_fan_coefs[4])
          curve_40_pct = model_curve.evaluate(0.4)
          curve_80_pct = model_curve.evaluate(0.8)

          # get target coefs
          target_fan = OpenStudio::Model::FanVariableVolume.new(model_temp)
          OpenstudioStandards::HVAC.fan_variable_volume_set_control_type(target_fan, control_type: 'Multi Zone VAV with Static Pressure Setpoint Reset')

          # get coeficents for fan
          target_fan_coefs = []
          target_fan_coefs << target_fan.fanPowerCoefficient1.get
          target_fan_coefs << target_fan.fanPowerCoefficient2.get
          target_fan_coefs << target_fan.fanPowerCoefficient3.get
          target_fan_coefs << target_fan.fanPowerCoefficient4.get
          target_fan_coefs << target_fan.fanPowerCoefficient5.get

          # make model curve
          target_curve = OpenStudio::Model::CurveQuartic.new(model_temp)
          target_curve.setCoefficient1Constant(target_fan_coefs[0])
          target_curve.setCoefficient2x(target_fan_coefs[1])
          target_curve.setCoefficient3xPOW2(target_fan_coefs[2])
          target_curve.setCoefficient4xPOW3(target_fan_coefs[3])
          target_curve.setCoefficient5xPOW4(target_fan_coefs[4])
          target_curve_40_pct = target_curve.evaluate(0.4)
          target_curve_80_pct = target_curve.evaluate(0.8)

          # check curve at two points
          if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
          end
          if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
            check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check primary plant loop heating and cooling equipment capacity against coil loads to find equipment that is significantly oversized or undersized.
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_pct_delta [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_plant_loop_capacity(category, target_standard, max_pct_delta: 0.3, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Plant Capacity')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that plant equipment capacity matches loads.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      begin
        # Check the heating and cooling capacity of the plant loops against their coil loads
        @model.getPlantLoops.sort.each do |plant_loop|
          # Heating capacity
          htg_cap_w = std.plant_loop_total_heating_capacity(plant_loop)

          # Cooling capacity
          clg_cap_w = std.plant_loop_total_cooling_capacity(plant_loop)

          # Sum the load for each coil on the loop
          htg_load_w = 0.0
          clg_load_w = 0.0
          plant_loop.demandComponents.each do |dc|
            obj_type = dc.iddObjectType.valueName.to_s
            case obj_type
            when 'OS_Coil_Heating_Water'
              coil = dc.to_CoilHeatingWater.get
              if coil.ratedCapacity.is_initialized
                htg_load_w += coil.ratedCapacity.get
              elsif coil.autosizedRatedCapacity.is_initialized
                htg_load_w += coil.autosizedRatedCapacity.get
              end
            when 'OS_Coil_Cooling_Water'
              coil = dc.to_CoilCoolingWater.get
              if coil.autosizedDesignCoilLoad.is_initialized
                clg_load_w += coil.autosizedDesignCoilLoad.get
              end
            end
          end

          # Don't check loops with no loads.  These are probably SWH or non-typical loops that can't be checked by simple methods.
          # Heating
          if htg_load_w > 0
            htg_cap_kbtu_per_hr = OpenStudio.convert(htg_cap_w, 'W', 'kBtu/hr').get.round(1)
            htg_load_kbtu_per_hr = OpenStudio.convert(htg_load_w, 'W', 'kBtu/hr').get.round(1)
            if ((htg_cap_w - htg_load_w) / htg_cap_w).abs > max_pct_delta
              check_elems << OpenStudio::Attribute.new('flag', "For #{plant_loop.name}, the total heating capacity of #{htg_cap_kbtu_per_hr} kBtu/hr is more than #{(max_pct_delta * 100.0).round(2)}% different from the combined coil load of #{htg_load_kbtu_per_hr} kBtu/hr.  This could indicate significantly oversized or undersized equipment.")
            end
          end

          # Cooling
          if clg_load_w > 0
            clg_cap_tons = OpenStudio.convert(clg_cap_w, 'W', 'ton').get.round(1)
            clg_load_tons = OpenStudio.convert(clg_load_w, 'W', 'ton').get.round(1)
            if ((clg_cap_w - clg_load_w) / clg_cap_w).abs > max_pct_delta
              check_elems << OpenStudio::Attribute.new('flag', "For #{plant_loop.name}, the total cooling capacity of #{clg_load_tons} tons is more than #{(max_pct_delta * 100.0).round(2)}% different from the combined coil load of #{clg_load_tons} tons.  This could indicate significantly oversized or undersized equipment.")
            end
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the plant loop operational vs. sizing temperatures and make sure everything is coordinated.
    # This identifies problems caused by sizing to one set of conditions and operating at a different set.
    #
    # @param category [String] category to bin this check into
    # @param max_sizing_temp_delta [Double] threshold for throwing an error for design sizing temperatures
    # @param max_operating_temp_delta [Double] threshold for throwing an error on operating temperatures
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_plant_loop_temperatures(category, max_sizing_temp_delta: 2.0, max_operating_temp_delta: 5.0, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Plant Loop Temperatures')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that plant loop sizing and operation temperatures are coordinated.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      begin
        # get the weather file run period (as opposed to design day run period)
        ann_env_pd = nil
        @sql.availableEnvPeriods.each do |env_pd|
          env_type = @sql.environmentType(env_pd)
          if env_type.is_initialized
            if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
              ann_env_pd = env_pd
              break
            end
          end
        end

        # only try to get the annual timeseries if an annual simulation was run
        if ann_env_pd.nil?
          check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot check equipment part load ratios.')
          return check_elems
        end

        # Check each plant loop in the model
        @model.getPlantLoops.sort.each do |plant_loop|
          supply_outlet_node_name = plant_loop.supplyOutletNode.name.to_s
          design_supply_temperature = plant_loop.sizingPlant.designLoopExitTemperature
          design_supply_temperature = OpenStudio.convert(design_supply_temperature, 'C', 'F').get
          design_temperature_difference = plant_loop.sizingPlant.loopDesignTemperatureDifference
          design_temperature_difference = OpenStudio.convert(design_temperature_difference, 'K', 'R').get

          # get min and max temperatures from setpoint manager
          spm_name = ''
          spm_type = '<unspecified>'
          spm_min_temp_f = nil
          spm_max_temp_f = nil
          spms = plant_loop.supplyOutletNode.setpointManagers
          unless spms.empty?
            spm = spms[0] # assume first setpoint manager is only setpoint manager
            spm_name = spm.name
            spm_type = spm.iddObjectType.valueName.to_s
            spm_temps_f = OpenstudioStandards::HVAC.setpoint_manager_min_max_temperature(spm)
            spm_min_temp_f = spm_temps_f['min_temp']
            spm_max_temp_f = spm_temps_f['max_temp']
          end

          # check setpoint manager temperatures against design temperatures
          case plant_loop.sizingPlant.loopType
          when 'Heating'
            if spm_max_temp_f && ((spm_max_temp_f - design_supply_temperature).abs > max_sizing_temp_delta)
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: #{plant_loop.name} sizing uses a #{design_supply_temperature.round(1)}F supply water temperature, but the setpoint manager operates up to #{spm_max_temp_f.round(1)}F.")
            end
          when 'Cooling'
            if spm_min_temp_f && ((spm_min_temp_f - design_supply_temperature).abs > max_sizing_temp_delta)
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: #{plant_loop.name} sizing uses a #{design_supply_temperature.round(1)}F supply water temperature, but the setpoint manager operates down to #{spm_min_temp_f.round(1)}F.")
            end
          end

          # get supply water temperatures for supply outlet node
          supply_temp_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Temperature', supply_outlet_node_name)
          if supply_temp_timeseries.empty?
            check[:items] << { type: 'warning', msg: "No supply node temperature timeseries found for '#{plant_loop.name}'" }
            next
          else
            # convert to ruby array
            temperatures = []
            supply_temp_vector = supply_temp_timeseries.get.values
            for i in (0..supply_temp_vector.size - 1)
              temperatures << supply_temp_vector[i]
            end
          end

          # get supply water flow rates for supply outlet node
          supply_flow_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Standard Density Volume Flow Rate', supply_outlet_node_name)
          if supply_flow_timeseries.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{plant_loop.name}'")
            next
          else
            # convert to ruby array
            flowrates = []
            supply_flow_vector = supply_flow_timeseries.get.values
            for i in (0..supply_flow_vector.size - 1)
              flowrates << supply_flow_vector[i].to_f
            end
          end

          # check reasonableness of supply water temperatures when supply water flow rate is operating
          operating_temperatures = temperatures.select.with_index { |_t, k| flowrates[k] > 1e-8 }
          operating_temperatures = operating_temperatures.map { |t| ((t * 1.8) + 32.0) }

          if operating_temperatures.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Warning: Flowrates are all zero in supply node timeseries for '#{plant_loop.name}'")
            next
          end

          runtime_fraction = operating_temperatures.size / temperatures.size.to_f
          temps_out_of_bounds = []
          case plant_loop.sizingPlant.loopType
          when 'Heating'
            design_return_temperature = design_supply_temperature - design_temperature_difference
            expected_max = spm_max_temp_f.nil? ? design_supply_temperature : [design_supply_temperature, spm_max_temp_f].max
            expected_min = spm_min_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_min_temp_f].min
            temps_out_of_bounds = (operating_temperatures.select { |t| (((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) })
          when 'Cooling'
            design_return_temperature = design_supply_temperature + design_temperature_difference
            expected_max = spm_max_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_max_temp_f].max
            expected_min = spm_min_temp_f.nil? ? design_supply_temperature : [design_supply_temperature, spm_min_temp_f].min
            temps_out_of_bounds = (operating_temperatures.select { |t| (((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) })
          when 'Condenser'
            design_return_temperature = design_supply_temperature + design_temperature_difference
            expected_max = spm_max_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_max_temp_f].max
            temps_out_of_bounds = (operating_temperatures.select { |t| ((t < 35.0) || (t > 100.0) || ((t - max_operating_temp_delta) > expected_max)) })
          end

          next if temps_out_of_bounds.empty?

          min_op_temp_f = temps_out_of_bounds.min
          max_op_temp_f = temps_out_of_bounds.max
          # avg_F = temps_out_of_bounds.inject(:+).to_f / temps_out_of_bounds.size
          spm_min_temp_f = spm_min_temp_f.round(1) unless spm_min_temp_f.nil?
          spm_max_temp_f = spm_max_temp_f.round(1) unless spm_max_temp_f.nil?
          err = []
          err << 'Major Error:'
          err << 'Expected supply water temperatures out of bounds for'
          err << "#{plant_loop.sizingPlant.loopType} plant loop '#{plant_loop.name}'"
          err << "with a #{design_supply_temperature.round(1)}F design supply temperature and"
          err << "#{design_return_temperature.round(1)}F design return temperature and"
          err << "a setpoint manager '#{spm_name}' of type '#{spm_type}' with a"
          err << "#{spm_min_temp_f}F minimum setpoint temperature and"
          err << "#{spm_max_temp_f}F maximum setpoint temperature."
          err << "Out of #{operating_temperatures.size}/#{temperatures.size} (#{(runtime_fraction * 100.0).round(1)}%) operating supply water temperatures"
          err << "#{temps_out_of_bounds.size}/#{operating_temperatures.size} (#{((temps_out_of_bounds.size.to_f / operating_temperatures.size) * 100.0).round(1)}%)"
          err << "are out of bounds with #{min_op_temp_f.round(1)}F min and #{max_op_temp_f.round(1)}F max."
          check_elems << OpenStudio::Attribute.new('flag', err.join(' ').gsub(/\n/, ''))
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the pumping power (W/gpm) for each pump in the model to identify unrealistically sized pumps.
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_pct_delta [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_pump_power(category, target_standard, max_pct_delta: 0.3, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Pump Power')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that pump power vs flow makes sense.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      std = Standard.build(target_standard)

      begin
        # Check each plant loop
        @model.getPlantLoops.sort.each do |plant_loop|
          # Set the expected/typical W/gpm
          loop_type = plant_loop.sizingPlant.loopType
          case loop_type
          when 'Heating', 'Condenser'
            expected_w_per_gpm = 19.0
          when 'Cooling'
            expected_w_per_gpm = 22.0
          end

          # Check the W/gpm for each pump on each plant loop
          plant_loop.supplyComponents.each do |component|
            # Get the W/gpm for the pump
            obj_type = component.iddObjectType.valueName.to_s
            case obj_type
            when 'OS_Pump_ConstantSpeed'
              actual_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(component.to_PumpConstantSpeed.get)
            when 'OS_Pump_VariableSpeed'
              actual_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(component.to_PumpVariableSpeed.get)
            when 'OS_HeaderedPumps_ConstantSpeed'
              actual_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(component.to_HeaderedPumpsConstantSpeed.get)
            when 'OS_HeaderedPumps_VariableSpeed'
              actual_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(component.to_HeaderedPumpsVariableSpeed.get)
            else
              next # Skip non-pump objects
            end

            # Compare W/gpm to expected/typical values
            if ((expected_w_per_gpm - actual_w_per_gpm) / actual_w_per_gpm).abs > max_pct_delta
              if plant_loop.name.get.to_s.downcase.include? 'service water loop'
                # some service water loops use just water main pressure and have a dummy pump
                check_elems << OpenStudio::Attribute.new('flag', "Warning: For #{component.name} on #{plant_loop.name}, the pumping power is #{actual_w_per_gpm.round(1)} W/gpm.")
              else
                check_elems << OpenStudio::Attribute.new('flag', "For #{component.name} on #{plant_loop.name}, the actual pumping power of #{actual_w_per_gpm.round(1)} W/gpm is more than #{(max_pct_delta * 100.0).round(2)}% different from the expected #{expected_w_per_gpm} W/gpm for a #{loop_type} plant loop.")
              end
            end
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check for excess simulataneous heating and cooling
    #
    # @param category [String] category to bin this check into
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_simultaneous_heating_and_cooling(category, max_pass_pct: 0.1, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Simultaneous Heating and Cooling')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check for simultaneous heating and cooling by looping through all Single Duct VAV Reheat Air Terminals and analyzing hourly data when there is a cooling load. ')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      begin
        # get the weather file run period (as opposed to design day run period)
        ann_env_pd = nil
        @sql.availableEnvPeriods.each do |env_pd|
          env_type = @sql.environmentType(env_pd)
          if env_type.is_initialized && (env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod'))
            ann_env_pd = env_pd
            break
          end
        end

        # only try to get the annual timeseries if an annual simulation was run
        if ann_env_pd.nil?
          check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot determine simultaneous heating and cooling.')
          return check_elem
        end

        # For each VAV reheat terminal, calculate
        # the annual total % reheat hours.
        @model.getAirTerminalSingleDuctVAVReheats.sort.each do |term|
          # Reheat coil heating rate
          rht_coil = term.reheatCoil
          key_value =  rht_coil.name.get.to_s.upcase # must be in all caps.
          time_step = 'Hourly' # "Zone Timestep", "Hourly", "HVAC System Timestep"
          variable_name = 'Heating Coil Heating Rate'
          variable_name_alt = 'Heating Coil Air Heating Rate'
          rht_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.

          # try and alternate variable name
          if rht_rate_ts.empty?
            rht_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name_alt, key_value) # key value would go at the end if we used it.
          end

          if rht_rate_ts.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Heating Coil (Air) Heating Rate Timeseries not found for #{key_value}.")
          else

            rht_rate_ts = rht_rate_ts.get.values
            # Put timeseries into array
            rht_rate_vals = []
            for i in 0..(rht_rate_ts.size - 1)
              rht_rate_vals << rht_rate_ts[i]
            end

            # Zone Air Terminal Sensible Heating Rate
            key_value = "ADU #{term.name.get.to_s.upcase}" # must be in all caps.
            time_step = 'Hourly' # "Zone Timestep", "Hourly", "HVAC System Timestep"
            variable_name = 'Zone Air Terminal Sensible Cooling Rate'
            clg_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.
            if clg_rate_ts.empty?
              check_elems << OpenStudio::Attribute.new('flag', "Zone Air Terminal Sensible Cooling Rate Timeseries not found for #{key_value}.")
            else

              clg_rate_ts = clg_rate_ts.get.values
              # Put timeseries into array
              clg_rate_vals = []
              for i in 0..(clg_rate_ts.size - 1)
                clg_rate_vals << clg_rate_ts[i]
              end

              # Loop through each timestep and calculate the hourly
              # % reheat value.
              ann_rht_hrs = 0
              ann_clg_hrs = 0
              ann_pcts = []
              rht_rate_vals.zip(clg_rate_vals).each do |rht_w, clg_w|
                # Skip hours with no cooling (in heating mode)
                next if clg_w == 0

                pct_overcool_rht = rht_w / (rht_w + clg_w)
                ann_rht_hrs += pct_overcool_rht # implied * 1hr b/c hrly results
                ann_clg_hrs += 1
                ann_pcts << pct_overcool_rht.round(3)
              end

              # Calculate annual % reheat hours
              ann_pct_reheat = ((ann_rht_hrs / ann_clg_hrs) * 100).round(1)

              # Compare to limit
              if ann_pct_reheat > max_pass_pct * 100.0
                check_elems << OpenStudio::Attribute.new('flag', "#{term.name} has #{ann_pct_reheat}% overcool-reheat, which is greater than the limit of #{max_pass_pct * 100.0}%. This terminal is in cooling mode for #{ann_clg_hrs} hours of the year.")
              end

            end

          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Bin the hourly part load ratios into 10% bins
    #
    # @param hourly_part_load_ratios
    # @return [Array<Integer>] Array of 11 integers for each bin
    def self.hourly_part_load_ratio_bins(hourly_part_load_ratios)
      bins = Array.new(11, 0)
      hourly_part_load_ratios.each do |plr|
        if plr <= 0
          bins[0] += 1
        elsif plr > 0 && plr <= 0.1
          bins[1] += 1
        elsif plr > 0.1 && plr <= 0.2
          bins[2] += 1
        elsif plr > 0.2 && plr <= 0.3
          bins[3] += 1
        elsif plr > 0.3 && plr <= 0.4
          bins[4] += 1
        elsif plr > 0.4 && plr <= 0.5
          bins[5] += 1
        elsif plr > 0.5 && plr <= 0.6
          bins[6] += 1
        elsif plr > 0.6 && plr <= 0.7
          bins[7] += 1
        elsif plr > 0.7 && plr <= 0.8
          bins[8] += 1
        elsif plr > 0.8 && plr <= 0.9
          bins[9] += 1
        elsif plr > 0.9 # add over-100% PLRs to final bin
          bins[10] += 1
        end
      end

      # Convert bins from hour counts to % of operating hours.
      bins.each_with_index do |bin, i|
        bins[i] = bins[i] * 1.0 / hourly_part_load_ratios.size
      end

      return bins
    end

    # Checks part loads ratios for a piece of equipment using the part load timeseries
    #
    # @param sql [OpenStudio::SqlFile] OpenStudio SqlFile
    # @param ann_env_pd [String] EnvPeriod, typically 'WeatherRunPeriod'
    # @param time_step [String] timestep, typically 'Hourly'
    # @param variable_name [String] part load ratio variable name
    # @param equipment [OpenStudio::Model::ModelObject] OpenStudio ModelObject, usually an HVACComponent
    # @param design_power [Double] equipment design power, typically in watts
    # @param units [String] design_power units, typically 'W', default ''
    # @param expect_low_plr [Boolean] toggle for whether to expect very low part load ratios and not report a message if found
    # @return [String] string with error message, or nil if none
    def self.hvac_equipment_part_load_ratio_message(sql, ann_env_pd, time_step, variable_name, equipment, design_power, units: '', expect_low_plr: false)
      msg = nil
      key_value = equipment.name.get.to_s.upcase # must be in all caps
      ts = sql.timeSeries(ann_env_pd, time_step, variable_name, key_value)
      if ts.empty?
        msg = "Warning: #{variable_name} Timeseries not found for #{key_value}."
        return msg
      end

      if design_power.zero?
        return msg
      end

      # Convert to array
      ts = ts.get.values
      plrs = []
      for i in 0..(ts.size - 1)
        plrs << (ts[i] / design_power.to_f)
      end

      # Bin part load ratios
      bins = OpenstudioStandards::HVAC.hourly_part_load_ratio_bins(plrs)
      frac_hrs_above_90 = bins[10]
      frac_hrs_above_80 = frac_hrs_above_90 + bins[9]
      frac_hrs_above_70 = frac_hrs_above_80 + bins[8]
      frac_hrs_above_60 = frac_hrs_above_70 + bins[7]
      frac_hrs_above_50 = frac_hrs_above_60 + bins[6]
      frac_hrs_zero = bins[0]

      pretty_bins = bins.map { |x| (x * 100).round(2) }

      # Check top-end part load ratio bins
      if expect_low_plr
        msg = "Warning: For #{equipment.name} with design size #{design_power.round(2)} #{units} is expected to have a low part load ratio. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_zero == 1.0
        msg = "Warning: For #{equipment.name}, all hrs are zero; equipment never runs."
      elsif frac_hrs_above_50 < 0.01
        msg = "Major Error: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_50 * 100).round(2)}% of hrs are above 50% part load.  This indicates significantly oversized equipment.  Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_above_60 < 0.01
        msg = "Minor Error: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_60 * 100).round(2)}% of hrs are above 60% part load.  This indicates significantly oversized equipment. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_above_80 < 0.01
        msg = "Warning: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_80 * 100).round(2)}% of hrs are above 80% part load.  This indicates oversized equipment. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_above_90 > 0.05
        msg = "Warning: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_90 * 100).round(2)}% of hrs are above 90% part load.  This indicates undersized equipment. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_above_90 > 0.1
        msg = "Minor Error: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_90 * 100).round(2)}% of hrs are above 90% part load.  This indicates significantly undersized equipment. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      elsif frac_hrs_above_90 > 0.2
        msg = "Major Error: For #{equipment.name} with design size #{design_power.round(2)} #{units}, #{(frac_hrs_above_90 * 100).round(2)}% of hrs are above 90% part load.  This indicates significantly undersized equipment. Bins of PLR [0%,0%-10%,...]: #{pretty_bins}."
      end
      return msg
    end

    # Check primary heating and cooling equipment part load ratios to find equipment that is significantly oversized or undersized.
    #
    # @param category [String] category to bin this check into
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_hvac_equipment_part_load_ratios(category, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Part Load')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that equipment operates at reasonable part load ranges.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = []
        check_elems.each do |elem|
          results << elem.valueAsString
        end
        return results
      end

      begin
        # Establish limits for % of operating hrs expected above 90% part load
        expected_pct_hrs_above_90 = 0.1

        # get the weather file run period (as opposed to design day run period)
        ann_env_pd = nil
        @sql.availableEnvPeriods.each do |env_pd|
          env_type = @sql.environmentType(env_pd)
          if env_type.is_initialized && (env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod'))
            ann_env_pd = env_pd
            break
          end
        end

        # only try to get the annual timeseries if an annual simulation was run
        if ann_env_pd.nil?
          check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot check equipment part load ratios.')
          return check_elem
        end

        # Boilers
        @model.getBoilerHotWaters.sort.each do |boiler|
          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Boiler Part Load Ratio', boiler, 1.0)
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Chillers
        @model.getChillerElectricEIRs.sort.each do |chiller|
          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Chiller Part Load Ratio', chiller, 1.0)
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Cooling Towers (Single Speed)
        @model.getCoolingTowerSingleSpeeds.sort.each do |cooling_tower|
          # Get the design fan power
          if cooling_tower.fanPoweratDesignAirFlowRate.is_initialized
            design_power = cooling_tower.fanPoweratDesignAirFlowRate.get
          elsif cooling_tower.autosizedFanPoweratDesignAirFlowRate.is_initialized
            design_power = cooling_tower.autosizedFanPoweratDesignAirFlowRate.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine peak power for #{cooling_tower.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Tower Fan Electric Power', cooling_tower, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Cooling Towers (Two Speed)
        @model.getCoolingTowerTwoSpeeds.sort.each do |cooling_tower|
          # Get the design fan power
          if cooling_tower.highFanSpeedFanPower.is_initialized
            design_power = cooling_tower.highFanSpeedFanPower.get
          elsif cooling_tower.autosizedHighFanSpeedFanPower.is_initialized
            design_power = cooling_tower.autosizedHighFanSpeedFanPower.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine peak power for #{cooling_tower.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Tower Fan Electric Power', cooling_tower, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Cooling Towers (Variable Speed)
        @model.getCoolingTowerVariableSpeeds.sort.each do |cooling_tower|
          # Get the design fan power
          if cooling_tower.designFanPower.is_initialized
            design_power = cooling_tower.designFanPower.get
          elsif cooling_tower.autosizedDesignFanPower.is_initialized
            design_power = cooling_tower.autosizedDesignFanPower.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine peak power for #{cooling_tower.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Tower Fan Electric Power', cooling_tower, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # DX Cooling Coils (Single Speed)
        @model.getCoilCoolingDXSingleSpeeds.sort.each do |dx_coil|
          # Get the design coil capacity
          if dx_coil.ratedTotalCoolingCapacity.is_initialized
            design_power = dx_coil.ratedTotalCoolingCapacity.get
          elsif dx_coil.autosizedRatedTotalCoolingCapacity.is_initialized
            design_power = dx_coil.autosizedRatedTotalCoolingCapacity.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{dx_coil.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Coil Total Cooling Rate', dx_coil, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # DX Cooling Coils (Two Speed)
        @model.getCoilCoolingDXTwoSpeeds.sort.each do |dx_coil|
          # Get the design coil capacity
          if dx_coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
            design_power = dx_coil.ratedHighSpeedTotalCoolingCapacity.get
          elsif dx_coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
            design_power = dx_coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{dx_coil.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Coil Total Cooling Rate', dx_coil, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # DX Cooling Coils (Variable Speed)
        @model.getCoilCoolingDXVariableSpeeds.sort.each do |dx_coil|
          # Get the design coil capacity
          if dx_coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
            design_power = dx_coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.get
          elsif dx_coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
            design_power = dx_coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{dx_coil.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Cooling Coil Total Cooling Rate', dx_coil, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Gas Heating Coils
        @model.getCoilHeatingGass.sort.each do |gas_coil|
          # Get the design coil capacity
          if gas_coil.nominalCapacity.is_initialized
            design_power = gas_coil.nominalCapacity.get
          elsif gas_coil.autosizedNominalCapacity.is_initialized
            design_power = gas_coil.autosizedNominalCapacity.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{gas_coil.name}, cannot check part load ratios.")
            next
          end

          if (gas_coil.name.to_s.include? 'Backup') || (gas_coil.name.to_s.include? 'Supplemental')
            msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Heating Coil Heating Rate', gas_coil, design_power, units: 'W', expect_low_plr: true)
          else
            msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Heating Coil Heating Rate', gas_coil, design_power, units: 'W')
          end
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # Electric Heating Coils
        @model.getCoilHeatingElectrics.sort.each do |electric_coil|
          # Get the design coil capacity
          if electric_coil.nominalCapacity.is_initialized
            design_power = electric_coil.nominalCapacity.get
          elsif electric_coil.autosizedNominalCapacity.is_initialized
            design_power = electric_coil.autosizedNominalCapacity.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{electric_coil.name}, cannot check part load ratios.")
            next
          end

          if (electric_coil.name.to_s.include? 'Backup') || (electric_coil.name.to_s.include? 'Supplemental')
            msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Heating Coil Heating Rate', electric_coil, design_power, units: 'W', expect_low_plr: true)
          else
            msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Heating Coil Heating Rate', electric_coil, design_power, units: 'W')
          end
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end

        # DX Heating Coils (Single Speed)
        @model.getCoilHeatingDXSingleSpeeds.sort.each do |dx_coil|
          # Get the design coil capacity
          if dx_coil.ratedTotalHeatingCapacity.is_initialized
            design_power = dx_coil.ratedTotalHeatingCapacity.get
          elsif dx_coil.autosizedRatedTotalHeatingCapacity.is_initialized
            design_power = dx_coil.autosizedRatedTotalHeatingCapacity.get
          else
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine capacity for #{dx_coil.name}, cannot check part load ratios.")
            next
          end

          msg = OpenstudioStandards::HVAC.hvac_equipment_part_load_ratio_message(@sql, ann_env_pd, 'Hourly', 'Heating Coil Heating Rate', dx_coil, design_power, units: 'W')
          unless msg.nil?
            check_elems << OpenStudio::Attribute.new('flag', msg)
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end
  end
end
