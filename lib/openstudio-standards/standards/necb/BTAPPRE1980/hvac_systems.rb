class BTAPPRE1980
  # Check if ERV is required on this airloop.
  #
  # @param (see #economizer_required?)
  # @return [Boolean] Returns true if required, false if not.
  def air_loop_hvac_energy_recovery_ventilator_required?(air_loop_hvac, climate_zone)
    # Do not apply ERV to BTAPPRE1980 buildings.
    erv_required = false
    return erv_required
  end

  # Applies the standard efficiency ratings and typical performance curves to this object from MNECB Supplement 5.4.8.3.
  #
  # @return [Boolean] true if successful, false if not
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir, clg_tower_objs)
    chillers = standards_data['chillers']

    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    cooling_type = search_criteria['cooling_type']
    condenser_type = search_criteria['condenser_type']
    compressor_type = search_criteria['compressor_type']

    # Get the chiller capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)

    # All chillers must be modulating down to 25% of their capacity
    chiller_electric_eir.setChillerFlowMode('LeavingSetpointModulated')
    chiller_electric_eir.setMinimumPartLoadRatio(0.25)
    chiller_electric_eir.setMinimumUnloadingRatio(0.25)

    chiller_capacity = capacity_w
    if (capacity_w / 1000.0) <= 700.0
      # As per MNECB if chiller capacity <= 700 kW the compressor should be reciprocating so change the type here in
      # the name, compressor_type and search_criteria which is where the compressor type is used.
      search_criteria['compressor_type'] = 'Reciprocating'
      compressor_type = search_criteria['compressor_type']
      chiller_electric_eir = replace_compressor_name(chiller: chiller_electric_eir, comp_type: compressor_type, chillers: chillers)
      if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
        chiller_capacity = capacity_w
      elsif chiller_electric_eir.name.to_s.include? 'Secondary Chiller'
        chiller_capacity = 0.001
      end
    elsif ((capacity_w / 1000.0) > 700.0) && ((capacity_w / 1000.0) <= 2100.0)
      # As per MNECB if chiller capacity > 700 kW the compressor should be centrifugal so change the type here in
      # the name, compressor_type and search_criteria which is where the compressor type is used.
      search_criteria['compressor_type'] = 'Centrifugal'
      compressor_type = search_criteria['compressor_type']
      chiller_electric_eir = replace_compressor_name(chiller: chiller_electric_eir, comp_type: compressor_type, chillers: chillers)
      if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
        chiller_capacity = capacity_w
      elsif chiller_electric_eir.name.to_s.include? 'Secondary Chiller'
        chiller_capacity = 0.001
      end
    else
      search_criteria['compressor_type'] = 'Centrifugal'
      compressor_type = search_criteria['compressor_type']
      chiller_electric_eir = replace_compressor_name(chiller: chiller_electric_eir, comp_type: compressor_type, chillers: chillers)
      chiller_capacity = capacity_w / 2.0
    end
    chiller_electric_eir.setReferenceCapacity(chiller_capacity)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(chiller_capacity, 'W', 'ton').get

    # Get the chiller properties
    chlr_table = @standards_data['chillers']
    chlr_props = model_find_object(chlr_table, search_criteria, capacity_tons, Date.today)
    unless chlr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller properties, cannot apply standard efficiencies or curves.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the CAPFT curve
    cool_cap_ft = model_add_curve(chiller_electric_eir.model, chlr_props['capft'])
    if cool_cap_ft
      chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFT curve
    cool_eir_ft = model_add_curve(chiller_electric_eir.model, chlr_props['eirft'])
    if cool_eir_ft
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFPLR curve
    # which may be either a CurveBicubic or a CurveQuadratic based on chiller type
    cool_plf_fplr = model_add_curve(chiller_electric_eir.model, chlr_props['eirfplr'])
    if cool_plf_fplr
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Set the efficiency value
    kw_per_ton = nil
    cop = nil
    if chlr_props['cop']
      cop = chlr_props['cop']
      kw_per_ton = OpenstudioStandards::HVAC.cop_to_kw_per_ton(cop)
      chiller_electric_eir.setReferenceCOP(cop)
    elsif !chlr_props['cop'] && chlr_props['minimum_full_load_efficiency']
      kw_per_ton = chlr_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
      chiller_electric_eir.setReferenceCOP(cop)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      successfully_set_all_properties = false
    end

    # Set cooling tower properties now that the new COP of the chiller is set
    if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
      # Single speed tower model assumes 25% extra for compressor power
      tower_cap = capacity_w * (1.0 + 1.0 / chiller_electric_eir.referenceCOP)
      if (tower_cap / 1000.0) < 1750
        clg_tower_objs[0].setNumberofCells(1)
      else
        clg_tower_objs[0].setNumberofCells((tower_cap / (1000 * 1750) + 0.5).round)
      end
      clg_tower_objs[0].setFanPoweratDesignAirFlowRate(0.015 * tower_cap)
    end

    # Append the name with size and kw/ton
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(1)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: #{cooling_type} #{condenser_type} #{compressor_type} Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(1)}kW/ton)")

    return successfully_set_all_properties
  end

  # Determines the minimum pump motor efficiency and nominal size
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method picks
  # the next nominal motor catgory larger than the required brake
  # horsepower, and the efficiency is based on that size.  For example,
  # if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.  This method assumes
  # 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)
    motor_eff = 0.85
    nominal_hp = motor_bhp

    # Don't attempt to look up motor efficiency
    # for zero-hp pumps (required for circulation-pump-free
    # service water heating systems).
    return [1.0, 0] if motor_bhp == 0.0

    # Lookup the minimum motor efficiency
    motors = @standards_data['motors']

    # Assuming all pump motors are 4-pole ODP
    search_criteria = {
      'motor_use' => 'PUMP',
      'number_of_poles' => 4.0,
      'type' => 'Enclosed'
    }

    motor_properties = model_find_object(motors, search_criteria, motor_bhp)
    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Pump', "For #{pump.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
      return [motor_eff, nominal_hp]
    end

    motor_eff = motor_properties['nominal_full_load_efficiency']
    nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    # Get the efficiency based on the nominal horsepower
    # Add 0.01 hp to avoid search errors.
    motor_properties = model_find_object(motors, search_criteria, nominal_hp + 0.01)
    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{pump.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
      return [motor_eff, nominal_hp]
    end
    motor_eff = motor_properties['nominal_full_load_efficiency']

    # Change the pump design shaft power per unit flow rate per unit head to use MNECB combined efficiency values
    apply_pump_impeller_efficiency(pump: pump, motor_eff: motor_eff)
    return [motor_eff, nominal_hp]
  end

  # Replace the chiller compressor type in the chiller name.
  def replace_compressor_name(chiller:, comp_type:, chillers:)
    # Get the current name.
    chiller_name = chiller.name.to_s
    # Get the unique compressor types from the chiller table (from the chillers.json file.)
    chiller_types = chillers.uniq { |chill_param| chill_param['compressor_type'] }
    new_name = chiller_name
    # Go through each chiller compressor type from the chiller table and see if it is in the chiller name.  If it is,
    # then replace the old compressor type in the name with the new one.
    chlr_name_updated = false
    chiller_types.each do |chill_type|
      if chiller_name.include? chill_type['compressor_type']
        new_name = chiller_name.sub(chill_type['compressor_type'], comp_type)
        chlr_name_updated = true
        break
      end
    end
    new_name = chiller_name + ' ' + comp_type if !chlr_name_updated
    chiller.setName(new_name)
    return chiller
  end

  # Set the pump design shaft power per unit flow rate per unit head to incorporate total pump efficiency (adjusted for
  # motor efficiency).
  def apply_pump_impeller_efficiency(pump:, motor_eff:)
    # Get the pump efficiency table from the pump_efficiencies.json
    pump_data = @standards_data['pump_combined_eff']
    pump_info = nil
    # Go through the components of the plant loop the plant is attached to.  Find the type of plant loop based on the
    # equipment in it (e.g. it is a hot water loop if the loop contains a boiler supply component).  Once we know the
    # type of plant loop get the combined pump efficiency from pump_data
    pump.plantLoop.get.supplyComponents.each do |comp|
      obj_type = comp.iddObjectType.valueName.to_s
      break if pump_info == pump_data.find { |plant_pump| plant_pump['components'].find { |component| component.include?(obj_type) } }
    end

    return if pump_info.nil?

    # DesignShaftPowerPerUnitFlowRatePerUnitHead seems to be the inverse of an efficiency so get the inverse efficiency
    # by dividing the motor efficiency from the total pump efficiency.
    inv_impeller_eff = motor_eff / pump_info['comb_eff'].to_f
    pump.setDesignShaftPowerPerUnitFlowRatePerUnitHead(inv_impeller_eff)
  end

  # Adjust the total efficiency, motor efficiency (if applicable), and pressure rise for fans used in BTAPPRE1980 and
  # BTAP1980TO2010.  This probably should be implemented a different way but rather than truly understanding the code
  # I wrote this.  So far it applies fan performance to system 3 return fans and to zone exhaust fans which were added
  # to BTAPPRE1980 and BTAP1980TO2010 since they are not used in NECB2011, NECB2015, or NECB2017.
  def model_apply_existing_building_fan_performance(model:)
    ret_fans = model.getFanConstantVolumes.select { |ret_fan| ret_fan.endUseSubcategory.to_s == 'Return_Fan' }
    return if ret_fans.empty?

    fan_type = 'CONSTANT-RETURN'
    motor_type = 'CONSTANT-RETURN'
    pressure_rise = 'return_fan_constant_volume_pressure_rise_value'
    fan_hash = get_fan_chars(fan_type: fan_type, motor_type: motor_type, press_rise: pressure_rise)
    ret_fans.each do |ret_fan|
      ret_fan.setPressureRise(fan_hash[:press_rise].to_f)
      ret_fan.setFanTotalEfficiency(fan_hash[:total_eff].to_f)
      ret_fan.setMotorEfficiency(fan_hash[:motor_eff].to_f)
    end
    exhaust_fans = model.getFanZoneExhausts

    return if exhaust_fans.empty?

    fan_type = 'EXHAUST'
    pressure_rise = 'exhaust_fan_pressure_rise_value'
    fan_hash = get_fan_chars(fan_type: fan_type, press_rise: pressure_rise)
    exhaust_fans.sort.each do |exhaust_fan|
      exhaust_fan.setFanTotalEfficiency(fan_hash[:total_eff])
      exhaust_fan.setPressureRise(fan_hash[:press_rise])
    end
  end

  # This method gets the required fan performance characteristics.  It would probably be better to change the
  # appropriate methods in standards or prototype or create another class but I did this here for expediency.
  # The method looks for:
  # -the total fan efficiency in fans.json (a custom json just for BTAP vintage files)
  # -the motor efficiency (if applicable) in moters.json
  # -the pressure rise in constants.json
  # If the above cannot be found it defaults values (this should not happen).
  # The method return a hash containing the total fan efficiency, motor efficiency and pressure rise.
  def get_fan_chars(fan_type:, motor_type: nil, press_rise:)
    standards_fan_total_efficiency = @standards_data['fans'].select { |standards_fan| standards_fan['fan_type'] == fan_type }
    if standards_fan_total_efficiency.empty?
      fan_total_efficiency = 0.25
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.model_apply_existing_building_fan_characteristics', "Cannot find fan data in standards fans data.  Defaulting total fan efficiency to #{fan_total_efficiency}.")
    else
      fan_total_efficiency = standards_fan_total_efficiency[0]['fan_total_efficiency']
    end
    fan_motor_efficiency = nil
    unless motor_type.nil?
      standards_fan_motor_efficiency = @standards_data['motors'].select { |standards_motor| (standards_motor['motor_use'] == 'FAN' && standards_motor['motor_type'] == motor_type) }
      if standards_fan_motor_efficiency.empty?
        fan_motor_efficiency = 0.385
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.model_apply_existing_building_fan_characteristics', "Cannot find fan motor data in standards fans data.  Defaulting fan moter efficinecy to #{fan_motor_efficiency}.")
      else
        fan_motor_efficiency = standards_fan_motor_efficiency[0]['nominal_full_load_efficiency']
      end
    end
    fan_pressure_rise = @standards_data['constants'][press_rise]['value']
    if fan_pressure_rise.nil?
      fan_pressure_rise = 150.0
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.model_apply_existing_building_fan_characteristics', "Cannot find fan pressure data in constants data.  Defaulting total fan pressure rise to #{fan_pressure_rise}.")
    end
    return {
      total_eff: fan_total_efficiency,
      motor_eff: fan_motor_efficiency,
      press_rise: fan_pressure_rise
    }
  end

  # This adds a zone exhaust fan to the zone passed to it.  The flow rate for the exhaust fan is set to the sum of the
  # outdoor air requirements for the spaces in the zone.  If the exhaust fan is set to run whenever the supply fan runs.
  def add_exhaust_fan(zone:, model:, name:)
    outdoor_air = 0.0
    zone.spaces.sort.each do |space|
      outdoor_air_rate = space.designSpecificationOutdoorAir.get.outdoorAirFlowperFloorArea
      floor_area = space.floorArea
      outdoor_air += (outdoor_air_rate * floor_area)
    end
    exhaust_fan = OpenStudio::Model::FanZoneExhaust.new(model)
    exhaust_fan.setName(name)
    exhaust_fan.setSystemAvailabilityManagerCouplingMode('Coupled')
    exhaust_fan.setMaximumFlowRate(outdoor_air.to_f)
    exhaust_fan.addToThermalZone(zone)
  end
end
