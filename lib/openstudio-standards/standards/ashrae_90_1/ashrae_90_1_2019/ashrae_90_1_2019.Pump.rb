class ASHRAE9012019 < ASHRAE901
  # @!group Pump

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
    return [1.0, 0] if motor_bhp < 0.0001

    # Lookup the minimum motor efficiency
    motors = standards_data['motors']

    # Assuming all pump motors are 4-pole ODP
    search_criteria = {
      'template' => template,
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

    # Get flow rate (whether autosized or hard-sized)
    flow_m3_per_s = 0
    flow_m3_per_s = if pump.to_PumpVariableSpeed.is_initialized || pump.to_PumpConstantSpeed.is_initialized
                      if pump.ratedFlowRate.is_initialized
                        pump.ratedFlowRate.get
                      elsif pump.autosizedRatedFlowRate.is_initialized
                        pump.autosizedRatedFlowRate.get
                      end
                    elsif pump.to_HeaderedPumpsVariableSpeed.is_initialized || pump.to_HeaderedPumpsConstantSpeed.is_initialized
                      if pump.totalRatedFlowRate.is_initialized
                        pump.totalRatedFlowRate.get / pump.numberofPumpsinBank
                      elsif pump.autosizedTotalRatedFlowRate.is_initialized
                        pump.autosizedTotalRatedFlowRate.get / pump.numberofPumpsinBank
                      end
                    end
    flow_gpm = OpenStudio.convert(flow_m3_per_s, 'm^3/s', 'gal/min').get

    # Adjustment for clean water pumps requirement:
    # The adjustment is made based on results included
    # in https://www.energy.gov/sites/prod/files/2015/12/f28/Pumps%20ECS%20Final%20Rule.pdf
    # Table 1 summarizes final rule efficiency levels
    # analyzed with corresponding C-values. With the
    # rulemaking adopted TSL/EL2 from the report, it shows
    # about 4.3% of average efficiency improvement, and after
    # considering 25% of the market, about 1.1% of the
    # final average efficiency improvement is estimated.
    #
    # The clean water pump requirement is only
    # applied to pumps with a flow rate of at least 25 gpm
    motor_eff *= 1.011 unless flow_gpm < 25.0

    return [motor_eff, nominal_hp]
  end
end
