class NECB2011
  def model_add_swh(model:, swh_fueltype: nil, shw_scale:)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding Service Water Heating')
    # Get default fuel based on the system fuels if not defined.
    if swh_fueltype.nil?
      swh_fueltype = self.fuel_type_set.swh_fueltype
    end

    # Calculate the tank size and service water pump information
    shw_sizing = auto_size_shw_capacity(model: model, shw_scale: shw_scale)
    if shw_sizing['loop_peak_flow_rate_SI'] == 0
      # Only add a shw_loop if at least one space calls for shw.  If no space calls for shw put out a warning but do not
      # add a shw loop.
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'No Service Water Heating Added')
      return true
    else
      shw_pump_head = auto_size_shw_pump_head(model, default: false)
    end

    # Add the main service water heating loop
    shw_pump_motor_eff = 0.9

    main_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                               system_name: 'Main Service Water Loop',
                                                                                               service_water_temperature: shw_sizing['max_temp_SI'],
                                                                                               service_water_pump_head: shw_pump_head,
                                                                                               service_water_pump_motor_efficiency: shw_pump_motor_eff,
                                                                                               water_heater_capacity: shw_sizing['tank_capacity_SI'],
                                                                                               water_heater_volume: shw_sizing['tank_volume_SI'],
                                                                                               water_heater_fuel: swh_fueltype,
                                                                                               on_cycle_parasitic_fuel_consumption_rate: shw_sizing['parasitic_loss'],
                                                                                               off_cycle_parasitic_fuel_consumption_rate: shw_sizing['parasitic_loss'])

    # Note that when water use equipment is assigned to spaces then the water used by the equipment is multiplied by
    # the space (ultimately thermal zone) multiplier.  Note that there is a separate water use equipment multiplier
    # as well which is different than the space (ultimately thermal zone) multiplier.
    shw_sizing['spaces_w_dhw'].each do |space|
      OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                name: "#{space['shw_spaces'].name.get.capitalize}",
                                                                flow_rate: space['shw_peakflow_ind_SI'],
                                                                flow_rate_fraction_schedule: model_add_schedule(model, space['shw_sched']),
                                                                water_use_temperature: space['shw_temp_SI'],
                                                                service_water_loop: main_swh_loop,
                                                                space: space['shw_spaces'])
    end
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding Service Water Heating')

    return true
  end

  # add swh

  # Applies the standard efficiency ratings and typical losses and paraisitic loads to this object.
  # Efficiency and skin loss coefficient (UA)
  # Per PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
  # Appendix A: Service Water Heating
  #
  # @return [Boolean] true if successful, false if not
  def water_heater_mixed_apply_efficiency(water_heater_mixed)
    # Get the capacity of the water heater
    # @todo add capability to pull autosized water heater capacity
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    capacity_w = water_heater_mixed.heaterMaximumCapacity
    if capacity_w.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find capacity, standard will not be applied.")
      return false
    else
      capacity_w = capacity_w.get
    end
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get the volume of the water heater
    # @todo add capability to pull autosized water heater volume
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    volume_m3 = water_heater_mixed.tankVolume
    if volume_m3.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find volume, standard will not be applied.")
      return false
    else
      volume_m3 = volume_m3.get
    end
    volume_gal = OpenStudio.convert(volume_m3, 'm^3', 'gal').get

    # Get the heater fuel type
    fuel_type = water_heater_mixed.heaterFuelType
    unless fuel_type == 'NaturalGas' || fuel_type == 'Electricity' || fuel_type == 'FuelOilNo2'
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, fuel type of #{fuel_type} is not yet supported, standard will not be applied.")
    end

    # Calculate the water heater efficiency and
    # skin loss coefficient (UA)
    # Calculate the energy factor (EF)
    # From PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
    # Appendix A: Service Water Heating
    water_heater_eff = nil
    ua_btu_per_hr_per_f = nil
    sl_btu_per_hr = nil
    case fuel_type
    when 'Electricity'
      volume_l_per_s = volume_m3 * 1000
      if capacity_btu_per_hr <= OpenStudio.convert(12, 'kW', 'Btu/hr').get
        # Fixed water heater efficiency per PNNL
        water_heater_eff = 1
        # Calculate the max allowable standby loss (SL)
        sl_w = if volume_l_per_s < 270
                 40 + 0.2 * volume_l_per_s # assume bottom inlet
               else
                 0.472 * volume_l_per_s - 33.5
                 # assume bottom inlet
               end
        sl_btu_per_hr = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get
      else
        # Fixed water heater efficiency per PNNL
        water_heater_eff = 1
        # Calculate the max allowable standby loss (SL)   # use this - NECB does not give SL calculation for cap > 12 kW
        sl_btu_per_hr = 20 + (35 * Math.sqrt(volume_gal))
      end
      # Calculate the skin loss coefficient (UA)
      ua_btu_per_hr_per_f = sl_btu_per_hr / 70
    when 'NaturalGas'
      if capacity_btu_per_hr <= 75_000
        # Fixed water heater thermal efficiency per PNNL
        water_heater_eff = 0.82
        # Calculate the minimum Energy Factor (EF)
        base_ef = 0.67
        vol_drt = 0.0019
        ef = base_ef - (vol_drt * volume_gal)
        # Calculate the Recovery Efficiency (RE)
        # based on a fixed capacity of 75,000 Btu/hr
        # and a fixed volume of 40 gallons by solving
        # this system of equations:
        # ua = (1/.95-1/re)/(67.5*(24/41094-1/(re*cap)))
        # 0.82 = (ua*67.5+cap*re)/cap
        cap = 75_000.0
        re = (Math.sqrt(6724 * ef**2 * cap**2 + 40_409_100 * ef**2 * cap - 28_080_900 * ef * cap + 29_318_000_625 * ef**2 - 58_636_001_250 * ef + 29_318_000_625) + 82 * ef * cap + 171_225 * ef - 171_225) / (200 * ef * cap)
        # Calculate the skin loss coefficient (UA)
        # based on the actual capacity.
        ua_btu_per_hr_per_f = (water_heater_eff - re) * capacity_btu_per_hr / 67.5
      else
        # Thermal efficiency requirement from 90.1
        et = 0.8
        # Calculate the max allowable standby loss (SL)
        cap_adj = 800
        vol_drt = 110
        sl_btu_per_hr = (capacity_btu_per_hr / cap_adj + vol_drt * Math.sqrt(volume_gal))
        # Calculate the skin loss coefficient (UA)
        ua_btu_per_hr_per_f = (sl_btu_per_hr * et) / 70
        # Calculate water heater efficiency
        water_heater_eff = (ua_btu_per_hr_per_f * 70 + capacity_btu_per_hr * et) / capacity_btu_per_hr
      end
    when 'FuelOilNo2'
      if capacity_btu_per_hr <= 75_000
        # Fixed water heater thermal efficiency per PNNL
        water_heater_eff = 0.82
        # Calculate the minimum Energy Factor (EF)
        base_ef = 0.67
        vol_drt = 0.0019
        ef = base_ef - (vol_drt * volume_gal)
        # Calculate the Recovery Efficiency (RE)
        # based on a fixed capacity of 75,000 Btu/hr
        # and a fixed volume of 40 gallons by solving
        # this system of equations:
        # ua = (1/.95-1/re)/(67.5*(24/41094-1/(re*cap)))
        # 0.82 = (ua*67.5+cap*re)/cap
        cap = 75_000.0
        re = (Math.sqrt(6724 * ef**2 * cap**2 + 40_409_100 * ef**2 * cap - 28_080_900 * ef * cap + 29_318_000_625 * ef**2 - 58_636_001_250 * ef + 29_318_000_625) + 82 * ef * cap + 171_225 * ef - 171_225) / (200 * ef * cap)
        # Calculate the skin loss coefficient (UA)
        # based on the actual capacity.
        ua_btu_per_hr_per_f = (water_heater_eff - re) * capacity_btu_per_hr / 67.5
      else
        # Thermal efficiency requirement from 90.1
        et = 0.8
        # Calculate the max allowable standby loss (SL)
        cap_adj = 800
        vol_drt = 110
        sl_btu_per_hr = (capacity_btu_per_hr / cap_adj + vol_drt * Math.sqrt(volume_gal))
        # Calculate the skin loss coefficient (UA)
        ua_btu_per_hr_per_f = (sl_btu_per_hr * et) / 70
        # Calculate water heater efficiency
        water_heater_eff = (ua_btu_per_hr_per_f * 70 + capacity_btu_per_hr * et) / capacity_btu_per_hr
      end
    end

    # Convert to SI
    ua_btu_per_hr_per_c = OpenStudio.convert(ua_btu_per_hr_per_f, 'Btu/hr*R', 'W/K').get
    # Set the water heater properties
    # Efficiency
    water_heater_mixed.setHeaterThermalEfficiency(water_heater_eff)
    # Skin loss
    water_heater_mixed.setOffCycleLossCoefficienttoAmbientTemperature(ua_btu_per_hr_per_c)
    water_heater_mixed.setOnCycleLossCoefficienttoAmbientTemperature(ua_btu_per_hr_per_c)
    # @todo Parasitic loss (pilot light)
    # PNNL document says pilot lights were removed, but IDFs
    # still have the on/off cycle parasitic fuel consumptions filled in
    water_heater_mixed.setOnCycleParasiticFuelType(fuel_type)
    # self.setOffCycleParasiticFuelConsumptionRate(??)
    water_heater_mixed.setOnCycleParasiticHeatFractiontoTank(0)
    water_heater_mixed.setOffCycleParasiticFuelType(fuel_type)
    # self.setOffCycleParasiticFuelConsumptionRate(??)
    water_heater_mixed.setOffCycleParasiticHeatFractiontoTank(0.8)

    # set part-load performance curve
    if (fuel_type == 'NaturalGas') || (fuel_type == 'FuelOilNo2')
      plf_vs_plr_curve = model_add_curve(water_heater_mixed.model, 'SWH-EFFFPLR-NECB2011')
      water_heater_mixed.setPartLoadFactorCurve(plf_vs_plr_curve)
    end

    # Append the name with standards information
    water_heater_mixed.setName("#{water_heater_mixed.name} #{water_heater_eff.round(3)} Therm Eff")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.WaterHeaterMixed', "For #{template}: #{water_heater_mixed.name}; thermal efficiency = #{water_heater_eff.round(3)}, skin-loss UA = #{ua_btu_per_hr_per_f.round}Btu/hr-R")
    return true
  end

  # This calculates the volume and capacity of one mixed tank that is assumed to service all shw in the building
  # u is the tank insulation in W/(m^2*K), height_to_radius is the ratio of tank radius to tank height and is dimensionless
  def auto_size_shw_capacity(model:, u: 0.45, height_to_radius: 2, shw_scale: 'NECB_Default')
    peak_flow_rate = 0
    shw_space_types = []
    space_peak_flows = []
    water_use = 0
    weekly_peak_flow = {
      'Default|Wkdy' => Array.new(24, 0),
      'Sat' => Array.new(24, 0),
      'Sun|Hol' => Array.new(24, 0)
    }
    peak_day_sched = nil
    peak_hour_sched = 0
    peak_flow_sched = 0
    next_hour_day = nil
    next_hour_hour = 0
    next_hour_flow = 0
    total_peak_flow_rate = 0
    shw_spaces = []
    shw_sched_names = []

    ##### Modify shw_scale if required
    if shw_scale.instance_of?(String)
      shw_scale = shw_scale.strip # remove leading or trailing whitespace in case users add them in shw_scale
    end
    if shw_scale == 'NECB_Default' or shw_scale.nil? or shw_scale == 'none' or shw_scale == false
      shw_scale = 1.0
    elsif shw_scale.instance_of?(String) # Convert a string to a float
      shw_scale = shw_scale.to_f
    end

    # First go through all the spaces in the building and determine and determine their shw requirements
    space_types_table = @standards_data['space_types']
    model.getSpaces.sort.each do |space|
      space_peak_flow = 0
      data = nil
      space_type_name = space.spaceType.get.standardsSpaceType.get.to_s
      tank_temperature = 60
      # find the specific space_type properties from standard.json
      space_types_table.each do |space_type|
        if (space_type['building_type'] + ' ' + space_type_name) == (space_type['building_type'] + ' ' + space_type['space_type'])
          break if space_type['necb_hvac_system_selection_type'] == '- undefined -'
          # If there is no service hot water load.. Don't bother adding anything.
          break if (space_type['service_water_heating_peak_flow_per_area'].to_f == 0.0 && space_type['service_water_heating_peak_flow_rate'].to_f == 0.0) || space_type['service_water_heating_schedule'].nil?

          # If there is a service hot water load collect the space information
          data = space_type
          break
        end
      end
      # If there is no service hot water load.. Don't bother adding anything.
      # Skip space types with no data
      next if data.nil?
      space_area = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get # ft2
      # Calculate the peak shw flow rate for the space.  Peak flow from JSON file is in US Gal/hr/ft^2
      # space_peak_flow_ind is the peak flow rate for the space while space_peak_flow is the peak flow
      # rate for the space multiplied by the space (ultimately thermal zone) multiplier.  space_peak_flow is used for
      # much of the rest as it reflects how much water is used.  space_peak_flow_ind is recorded and used later on
      # when defining water use equipment.  When when water use equipment is assigned to spaces then the water use
      # by the equipment is multiplied by the space multiplier.  Note that there is a separate water use equipment
      # multiplier as well which is different than the space (ultimately thermal zone) multiplier.
      space_peak_flow_ind = data['service_water_heating_peak_flow_per_area'].to_f * space_area * shw_scale
      space_peak_flow = space_peak_flow_ind * space.multiplier
      #      space_peak_flows << space_peak_flow
      # Add the peak shw flow rate for the space to the total for the entire building
      total_peak_flow_rate += space_peak_flow
      # Get the tank temperature for the space.  This should always be 60 C but I added this part in case something changes in the future.
      if data['service_water_heating_target_temperature'].nil? || (data['service_water_heating_target_temperature'] <= 16)
        tank_temperature = 60
      else
        tank_temperature = data['service_water_heating_target_temperature']
      end
      # Get the shw schedule
      #      shw_sched_names << data['service_water_heating_schedule']
      # 'shw_peakflow_ind_SI' is the shw peak flow rate of the individual space (without the space multiplier)
      space_info = {
        'shw_spaces' => space,
        'shw_peakflow_SI' => OpenStudio.convert(space_peak_flow, 'gal/hr', 'm^3/s').get,
        'shw_peakflow_ind_SI' => OpenStudio.convert(space_peak_flow_ind, 'gal/hr', 'm^3/s').get,
        'shw_temp_SI' => tank_temperature,
        'shw_sched' => data['service_water_heating_schedule']
      }
      shw_spaces << space_info

      # The following gets the water use schedule for space and applies it to the peak flow rate for the space.  This
      # creates an array containing the hourly shw consumption for the space for each day type (Weekday/default, Saturday,
      # Sunday/Holiday).  The hourly shw consumption for each space is added to the array ultimately producing an array
      # containing the hourly shw demand for the entire building.  This is used to determine the peak shw demand
      # hour and rate for the building.  This is different than the overall peak shw demand for the building in that it
      # takes into account the shw schedule.  The peak shw demand hour and rate should always be less than the overall peak
      # shw demand.

      # Cycle through the hash accumulating the shw rates for each day type.
      weekly_peak_flow.sort.each do |day_peak_sched|
        day_sched = []
        # Create the search criteria and retrieve the schedule for the current space and current day type.
        search_criteria = {
          'template' => template,
          'name' => data['service_water_heating_schedule'],
          'day_types' => day_peak_sched[0]
        }
        schedules_table = @standards_data['schedules']

        day_sched = model_find_object(schedules_table, search_criteria)
        # Make sure the schedule is not empty and contains 24 hours.
        if day_sched.empty? || day_sched['values'].size != 24
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.model_add_swh', "The water use schedule called #{data['service_water_heating_schedule']} for #{space_type_name} is corrupted or could not be found.  Please check that the schedules.json file is available and that the schedule names are spelled correctly")
          return false
        end
        # For each hour of the current day type multiply the shw schedule fractional multiplier (representing the fraction of the total shw
        # rate used in that hour) times the overall peak shw rate for the current space.  Add the resulting values to the
        # array tracking hourly shw demand for the building.  Also, determine what the highest hourly demand is for the
        # building.
        day_peak_sched[1].sort.each_with_index do |hour_flow, hour_index|
          weekly_peak_flow[day_peak_sched[0]][hour_index] += day_sched['values'][hour_index] * space_peak_flow
          if weekly_peak_flow[day_peak_sched[0]][hour_index] > peak_flow_sched
            peak_flow_sched = weekly_peak_flow[day_peak_sched[0]][hour_index]
          end
        end
      end
    end
    if shw_spaces.empty?
      space_info = {
        'shw_spaces' => nil,
        'shw_peakflow_SI' => 0,
        'shw_peakflow_ind_SI' => 0,
        'shw_temp_SI' => 60,
        'shw_sched' => []
      }
      shw_spaces << space_info
      tank_param = {
        'tank_volume_SI' => 0,
        'tank_capacity_SI' => 0,
        'max_temp_SI' => 60,
        'loop_peak_flow_rate_SI' => 0,
        'parasitic_loss' => 0,
        'spaces_w_dhw' => shw_spaces
      }
      return tank_param
    end
    next_day_test = nil
    next_hour_test = 0
    # The following loop goes through each hour in the array tracking hourly shw demand to find which hours contain the
    # peak hourly shw demand (this is in case the peak hourly shw demand occurs more than once).  It then determines what
    # the hourly shw demand is for the following hour.  It is meant to determine, of the peak hourly shw times, which has
    # the highest shw demand the following hour.  This is used to determine shw capacity and volume.
    weekly_peak_flow.sort.each do |day_peak_sched|
      day_peak_sched[1].sort.each_with_index do |hour_flow, hour_index|
        if hour_flow == peak_flow_sched
          if hour_index == 23
            next_hour_test = 0
            case day_peak_sched[0]
            when 'Default|Wkdy'
              next_day_test = 'Sat'
            when 'Sat'
              next_day_test = 'Sun|Hol'
            when 'Sun|Hol'
              next_day_test = 'Default|Wkdy'
            end
          else
            next_hour_test = hour_index + 1
            next_day_test = day_peak_sched[0]
          end
          if next_hour_flow < weekly_peak_flow[next_day_test][next_hour_test]
            next_hour_flow = weekly_peak_flow[next_day_test][next_hour_test]
            next_hour_hour = next_hour_test
            next_hour_day = next_day_test
            peak_day_sched = day_peak_sched[0]
            peak_hour_sched = hour_index
          end
        end
      end
    end
    # The shw tank is sized so that it can fulfill the hour with the highest shw needs.  Since the flow is in US Gal/hr
    # No conversion is necessary.
    tank_volume = peak_flow_sched
    # Interperite the fractional shw schedules as being the fraction of the hour that the maximum shw rate is used and determine
    # what this fraction is for the entire building.
    peak_time_fraction = 1 - (peak_flow_sched / total_peak_flow_rate)
    # Assume the shw tank needs some minimum amount of time to recover (avoids requiring a ridiculously high capacity).
    # If the recovery time is to short then the tank needs to hold enough water to service the peak shw hour and the one
    # after.  Then give the tank the entire hour to heat up again.  Note again that since peak flows are per hour, and
    # we are only looking at an hour, no conversion is necessary.
    if peak_time_fraction <= 0.2
      tank_volume += next_hour_flow
      peak_time_fraction = 1
    end
    tank_volume_SI = OpenStudio.convert(tank_volume, 'gal', 'm^3').get
    # Determine the tank capacity as the heat output required to heat up the entire volume of the tank in time remaining
    # in the hour after the peak shw draw is stopped (assume water is provided to the building at 15C ).
    max_temp = -273
    shw_spaces.each do |shw_space|
      if shw_space['shw_temp_SI'] > max_temp
        max_temp = shw_space['shw_temp_SI']
      end
    end
    tank_capacity_SI = tank_volume_SI * 1000 * 4180 * (max_temp - 15) / (3600 * peak_time_fraction)
    tank_radius = (tank_volume_SI / (height_to_radius * Math::PI))**(1.0 / 3)
    tank_area = 2 * (1 + height_to_radius) * Math::PI * (tank_radius**2)
    room_temp = OpenStudio.convert(70, 'F', 'C').get
    parasitic_loss = u * tank_area * (max_temp - room_temp)
    tank_param = {
      'tank_volume_SI' => tank_volume_SI,
      'tank_capacity_SI' => tank_capacity_SI,
      'max_temp_SI' => max_temp,
      'loop_peak_flow_rate_SI' => OpenStudio.convert(total_peak_flow_rate, 'gal/hr', 'm^3/s').get,
      'parasitic_loss' => parasitic_loss,
      'spaces_w_dhw' => shw_spaces
    }
    return tank_param
  end

  # Autosize the pump head by calculating the piping longest piping length and deriving required head from that.
  # If default is set to true then it returns a default pump head of 179532 Pa which is based on the OpenStudio 2.4.1
  # defaults for a constant speed pump.  The method first assumes that the tank and pump are located in the space closest
  # to the center of the bottom of the building.  It then assumes that water is delivered to the bottom center of every
  # space that has a demand for shw.  It calculates the x, y, and z components of the vector between the shw space and the
  # spaces with demand for shw.  The distance of the piping run is calculated by adding the x, y, and z components of the
  # vector (rather than the magnitude of the vector).  For the purposes of calculating pressure loss along the pipe bends,
  # and other minor losses are accounted by doubling the calculated length of the pipe.  The default kinematic viscosity
  # of water is assumed to be that at 60 C (in m^2/s).  The default density of water is assumed to be 983 kg/m^3 as per
  # https://hypertextbook.com/facts/2007/AllenMa.shtml accessed 2018-07-27.  The pipe is assumed to be made out of PVC and
  # have a roughness height of 1.5*10^-6 m as per:
  # www.pipeflow.com/pipe-pressure-drop-calculations/pipe-roughness accessed on 2018-07-25.
  # The default maximum velocity is from the table from 'The Engineering Toolbox' link:
  # https://www.engineeringtoolbox.com/flow-velocity-water-pipes-d_385.html
  # Chris Kirney 2018-07-27.
  def auto_size_shw_pump_head(model, default: true, pipe_vel: 1.75, kin_visc_SI: 0.000004736, density_SI: 983, pipe_rough_m: 0.0000015)
    return 179532 if default

    mech_room, cond_spaces = find_mech_room(model)
    return 179532 if mech_room.nil? || cond_spaces.nil?

    space_coord_dists = []
    total_peak_flow = 0
    hl_Pas = []
    # Now go through each space with a shw load and determine the x, y, and z components of a vector from the centroid
    # of the floor of the space containing the shw_tank and the centroid of the floor of the given space
    cond_spaces.each do |cond_space|
      # Find the specific space_type properties from standard.json
      spaceType_name = cond_space['space'].spaceType.get.nameString
      sp_type = spaceType_name[15..-1]
      # Including regular expressions in the following match for cases where extra characters, which do not belong, are
      # added to either the space type in the model or the space type reference file.
      sp_type_info = @standards_data['tables']['space_types']['table'].detect do |data|
        (Regexp.new(data['space_type'].to_s.upcase).match(sp_type.upcase) || Regexp.new(sp_type.upcase).match(data['space_type'].to_s.upcase) || (data['space_type'].to_s.upcase == sp_type.upcase)) &&
          (data['building_type'].to_s == 'Space Function')
      end

      # If the space type could not be found let the use know and go on to the next space.
      if sp_type_info.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.model_add_swh', "The space type called #{sp_type} could not be found.  Please check that the schedules.json file is available and that the space types are spelled correctly")
        next
      end
      next if sp_type_info['service_water_heating_peak_flow_per_area'].to_f == 0.0 && sp_type_info['service_water_heating_peak_flow_rate'].to_f == 0.0 || sp_type_info['service_water_heating_schedule'].nil?

      space_area = OpenStudio.convert(cond_space['space'].floorArea, 'm^2', 'ft^2').get # ft2
      # Calculate the peak shw flow rate for the space
      space_peak_flow = (sp_type_info['service_water_heating_peak_flow_per_area'].to_f * space_area) * cond_space['space'].multiplier
      space_peak_flow_SI = OpenStudio.convert(space_peak_flow, 'gal/hr', 'm^3/s').get
      # Determine the total shw peak flow for the building.
      total_peak_flow += space_peak_flow_SI
      # I use centroid for the floor as the location of the source or point of use for the shw system.
      if space_peak_flow_SI > 0
        space_coord_dist = []
        cond_space['space_centroid'].each_with_index do |dist, coord|
          space_coord_dist << (dist - mech_room['space_centroid'][coord]).abs
        end
        space_coord_dists << space_coord_dist
      end
    end
    # The piping run length from the shw tank to a given space is assumed to be the sum of the coordinates of the vector
    # described above.  The longest piping run becomes the one used for sizing.  Note that I double the length of this
    # piping run below when calculating head loss.
    space_coord_dists.sort.each do |space_coord_dist|
      sizing_pipe_length = space_coord_dist[0] + space_coord_dist[1] + space_coord_dist[2]
      # The shw pump is sized by assuming that the sum of the peak shw volume flow rates for each space has to be fed
      # through the longest piping run.  So for the sizing calculations below, the flow rate is the sum of the peak volume
      # flow rates for the entire building.  The length of the piping run is twice the calculated longest piping run
      # described above.
      # Step 1:  Calculate the Reynold's number.  Note kinematic viscosity is set for water at 60 C and pipe diameter is
      #          set to 3/4".  These can be changed by passing different values to the method.  I got the kinematic
      #          viscosity from www.engineeringtoolbox.com/water-dynamic-kinematic-viscosity-d_596.html accessed 2018-07-05.
      #          I got the pipe roughness from www.pipeflow.com/pipe-pressure-drop-calculations/pipe-roughness accessed on
      #          2018-07-25.  I assume 3/4" pipe because that is what Mike Lubun says is used in most cases (unless it
      #          it is for process water but we assume that is not the case).
      # Determine the bulk velocity of the shw through the pipe.
      # find pipe diameter for the peak flow
      pipe_dia_m = (4.0 * total_peak_flow / (Math::PI * pipe_vel))**0.5
      # Get the Reynolds number.
      re_pipe = (pipe_vel * pipe_dia_m) / kin_visc_SI
      # Step 2:  Figure out what the Darcy-Weisbach friction factor is.
      relative_rough = pipe_rough_m / pipe_dia_m
      f = friction_factor(re_pipe, relative_rough)
      # Step 3:  Calculate the major head loss
      #          Note that you may be thinking that I forgot to divide the last term by 2 in the equation below.  I didn't.
      #          I multiplied the piping length by 2 because I did not take pipe bends etc. into account and I calculate the
      #          maximum piping run in a really approximate way.  Thus I multiply the piping run by 2.  If you can think
      #          of something better please replace what I have.
      # hl is taken from https://neutrium.net/fluid_flow/pressure-loss-in-pipe accessed 2018-07-26 (I added the height
      # component).  Note that while I allow all of the other physical values to be set I assume that you are building on
      # earth hence g is hard coded to 9.81 m/s^2.
      hl_Pa = (f * (sizing_pipe_length / pipe_dia_m) * (pipe_vel**2) * density_SI) + density_SI * space_coord_dist[2] * 9.81
      if hl_Pa < 1
        hl_Pa = 1
      end
      hl_Pas << hl_Pa
    end
    # If no spaces with shw were found return the default pump head.
    return 179532 if hl_Pas.empty?

    return hl_Pas.max_by { |hl| hl }
  end

  def friction_factor(re_pipe, relative_rough)
    # This method determines the Darcy-Weisbach friction factor assuming the pipe is circular and filled.
    if re_pipe <= 2100
      # Laminar flow use the Uagen-Poiseuille equation.  https://neutrium.net/fluid_flow/pressure-loss-in-pipe
      # accessed 2018-07-25.
      f = 64.to_f / re_pipe.to_f
    elsif re_pipe > 2100 && re_pipe <= 4000
      # In the transition flow region I interpolate by Reynolds number between laminar and turbulent regimes.  Yeah, that's
      # crap but if you can come up with something better you are welcome to replace what I have below.
      flam = 64.to_f / 2100.to_f
      pipe_rough_fact = relative_rough / 3.7
      factor_A = -2 * Math.log10(pipe_rough_fact + (12.to_f / 4000.to_f))
      factor_B = -2 * Math.log10(pipe_rough_fact + ((2.51 * factor_A) / 4000))
      factor_C = -2 * Math.log10(pipe_rough_fact + ((2.51 * factor_B) / 4000))
      fturb = 1 / ((factor_A - (((factor_B - factor_A)**2) / (factor_C - 2 * factor_B + factor_A)))**2)
      re_int = (re_pipe - 2100.to_f) / 1900.to_f
      f = ((fturb - flam) * re_int) + flam
    elsif re_pipe > 4000
      # Turbulent flow use Serghide's Equation which I got from https://neutrium.net/fluid_flow/pressure-loss-in-pipe
      # accessed 2018-07-25.  Apparently it is good for 4000 < Re < 1x10^10 and relative roughness between 1x10-7 and 1.
      pipe_rough_fact = relative_rough / 3.7
      factor_A = -2 * Math.log10(pipe_rough_fact + (12 / re_pipe))
      factor_B = -2 * Math.log10(pipe_rough_fact + ((2.51 * factor_A) / re_pipe))
      factor_C = -2 * Math.log10(pipe_rough_fact + ((2.51 * factor_B) / re_pipe))
      f = 1 / ((factor_A - (((factor_B - factor_A)**2) / (factor_C - 2 * factor_B + factor_A)))**2)
    end
    return f
  end

  # This method determines where the mechanical room is in a building.  Mechanical rooms are assumed to be conditioned
  # spaces that are not plenums.  It goes through all of the spaces in a model ignoring unconditioned spaces and plenums.
  # It then determines the floor of the space, and the centroid of the floor.  It accumulates space floor area*floor
  # centroid information and total floor area.  It uses this to determine the centroid of the building.  It also notes
  # if the space has a space type with 'Electrical/Mechanical' in it.  If it does then it assumes that this is a
  # mechanical room and tracks it separately.  Once it has gone through all of the spaces it determines if any mechanical
  # rooms were found.  If some were found it finds the lowest one in the building (if more than one) and returns that
  # along with all of the conditioned, non-plenum, spaces.  If none were found then it searches for the lowest space in
  # the building closest to the building centroid and returns that as the centroid (along with eth conditioned,
  # non-plenum, spaces).
  def find_mech_room(model)
    cond_spaces = []
    total_peak_flow = 0
    mech_rooms = []
    check_spaces = nil
    building_centre = Array.new(3, 0)
    total_peak_flow = 0
    lowest_space = 1000000000000000
    sp_func_regex = Regexp.new('Space Function')
    mech_regex = Regexp.new('Electrical/Mechanical')
    mech_flag = false
    index = 0
    model.getSpaces.sort.each do |space|
      spaceType_name = space.spaceType.get.nameString
      sp_type = spaceType_name[15..-1]
      # Including regular expressions in the following match for cases where extra characters, which do not belong, are
      # added to either the space type in the model or the space type reference file.
      sp_type_info = @standards_data['tables']['space_types']['table'].detect do |data|
        (Regexp.new(data['space_type'].to_s.upcase).match(sp_type.upcase) || Regexp.new(sp_type.upcase).match(data['space_type'].to_s.upcase) || (data['space_type'].to_s.upcase == sp_type.upcase)) &&
          (data['building_type'].to_s == 'Space Function')
      end
      if sp_type_info.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.model_add_swh', "The space type called #{sp_type} could not be found.  Please check that the schedules.json file is available and that the space types are spelled correctly")
        next
      end
      # Determine if space is heated or cooled via spacetype heating or cooling setpoints also checking if the space is
      # a plenum by checking if there is a hvac system associtated with it
      if sp_type_info['heating_setpoint_schedule'].nil?
        heated = false
      else
        heated = true
      end
      if sp_type_info['cooling_setpoint_schedule'].nil?
        cooled = false
      else
        cooled = true
      end
      if (sp_type_info['necb_hvac_system_selection_type'] == '- undefined -') || /undefined/.match(sp_type_info['necb_hvac_system_selection_type'])
        not_plenum = false
      else
        not_plenum = true
      end

      # Determine the bottom surface of the space and calculate it's centroid.  Although the mech room is assumed to
      # be in a space that conditioned and is not a plenum (or attic space) all spaces in the building may not be.
      # Doing the following to determine the centroid for the entire building (including unconditioned or plenum
      # spaces).

      # Get the coordinates of the origin for the space (the coordinates of points in the space are relative to this).
      xOrigin = space.xOrigin
      yOrigin = space.yOrigin
      zOrigin = space.zOrigin
      # Get the surfaces for the space.
      space_surfaces = space.surfaces
      # Find the floor (aka the surface with the lowest centroid).
      min_surf = space_surfaces.min_by { |sp_surface| sp_surface.centroid.z.to_f }
      # The following is added to determine the overall floor centroid because some spaces have floors composed of more than one surface.
      floor_centroid = [0, 0, 0]
      space_surfaces.each do |sp_surface|
        if min_surf.centroid.z.to_f == sp_surface.centroid.z.to_f
          floor_centroid[0] = floor_centroid[0] + sp_surface.centroid.x.to_f * sp_surface.grossArea.to_f
          floor_centroid[1] = floor_centroid[1] + sp_surface.centroid.y.to_f * sp_surface.grossArea.to_f
          floor_centroid[2] = floor_centroid[2] + sp_surface.grossArea
        end
      end

      floor_centroid[0] = floor_centroid[0] / floor_centroid[2]
      floor_centroid[1] = floor_centroid[1] / floor_centroid[2]

      if lowest_space > (min_surf.centroid.z.to_f + zOrigin)
        lowest_space = min_surf.centroid.z.to_f + zOrigin
      end
      # This part is used to determine the overall x, y centre of the building.  This is determined by summing the x
      # and y components times the floor area and diving by the total floor area.  This is only for conditioned spaces.
      building_centre[0] += (floor_centroid[0] + xOrigin) * floor_centroid[2]
      building_centre[1] += (floor_centroid[1] + yOrigin) * floor_centroid[2]
      building_centre[2] += (floor_centroid[2])

      # Check if the space is conditioned and not a plenum.  If it is then add it to the list of conditioned, non-plenum,
      # spaces and check if it has a 'Mechanical/Electrical' space type.  Note that the mech room is assumed to
      # be in a space that conditioned and is not a plenum (or attic space).

      if (heated == true || cooled == true) && (not_plenum == true)
        if mech_regex.match(spaceType_name)
          mech_rooms << index
        end
        cond_space = {
          'space_name' => space.nameString,
          'space' => space,
          'space_centroid' => [floor_centroid[0] + xOrigin, floor_centroid[1] + yOrigin, min_surf.centroid.z.to_f + zOrigin],
          'building_cent_dist' => 0
        }
        cond_spaces << cond_space
        index += 1
      end
    end

    return [cond_spaces[mech_rooms[0]], cond_spaces] if mech_rooms.size == 1

    if mech_rooms.size > 1
      check_spaces = []
      lowest_space = 10000000000000
      mech_rooms.each do |mech_room|
        check_spaces << cond_spaces[mech_room]
        if cond_spaces[mech_room]['space_centroid'][2].to_f < lowest_space
          lowest_space = cond_spaces[mech_room]['space_centroid'][2].to_f
        end
      end
    else
      check_spaces = cond_spaces
    end

    # If no heated or cooled spaces were found then return false
    if cond_spaces.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.model_add_swh', 'No heated or cooled spaces types could be found which were not also a plenum.')
      return false
    end

    # This is where the average happens
    building_centre[0] /= building_centre[2]
    building_centre[1] /= building_centre[2]
    # Go through each space on the lowest floor of the building and determine the distance between the centroid of the
    # space's floors and the center of the building I calculated just above.
    centre_spaces = []
    check_spaces.each do |check_space|
      if check_space['space_centroid'][2] == lowest_space
        check_space['building_cent_dist'] = Math.sqrt(((check_space['space_centroid'][0] - building_centre[0])**2) + ((check_space['space_centroid'][1] - building_centre[1])**2))
        centre_spaces << check_space
      end
    end
    # Determine which of the floor spaces is closest to the centre of the building and that one becomes the location of
    # the mechanical room.
    centre_space = centre_spaces.min_by { |dist| dist['building_cent_dist'].round(1) }
    return [centre_space, cond_spaces]
  end
end
