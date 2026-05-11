class Standard
  # @!group Motor

  # Determine the type of motor to model
  #
  # @param nominal_hp [Float] nominal or nameplate motor horsepower
  # @return [String] motor type
  def motor_type(nominal_hp)
    return 'PSC'
  end

  # Determine the efficiency of fractional horsepower motors
  #
  # @param nominal_hp [Float] nominal or nameplate motor horsepower
  # @param motor_type [String] motor type, either 'PSC' or 'ECM'
  # @return [Hash, NilClass] motor efficiency
  def motor_fractional_hp_efficiencies(nominal_hp, motor_type = 'PSC')
    # Unless specified otherwise, the efficiencies are calculated from
    # Table 5-3 from Energy Savings Potential and Research & Development Opportunities for Commercial Refrigeration, Navigant, 2009
    # https://www1.eere.energy.gov/buildings/pdfs/commercial_refrigeration_equipment_research_opportunities.pdf
    #
    # efficiency = (rated shaft output) / (input power)
    case motor_type
    when 'PSC'
      if nominal_hp <= 1.0 / 20.0
        efficiency = 37.0 / 70.0
      elsif nominal_hp <= 1.0 / 15.0
        efficiency = 50.0 / 90.0
      elsif nominal_hp <= 1.0 / 6.0
        efficiency = 125.0 / 202.0
      elsif nominal_hp <= 1.0 / 3.0
        efficiency = 249.0 / 370.0
      elsif nominal_hp <= 1.0 / 2.0
        efficiency = 373.0 / 530.0
      elsif nominal_hp <= 3.0 / 4.0
        efficiency = 560.0 / 699.0 # data obtained from motorboss.com
      else
        return nil
      end
    when 'ECM'
      if nominal_hp <= 1.0 / 20.0
        efficiency = 37.0 / 49.0
      elsif nominal_hp <= 1.0 / 15.0
        efficiency = 50.0 / 65.0
      elsif nominal_hp <= 1.0 / 6.0
        efficiency = 125.0 / 155.0
      elsif nominal_hp <= 1.0 / 3.0
        efficiency = 249.0 / 304.0
      elsif nominal_hp <= 1.0 / 2.0
        efficiency = 373.0 / 450.0
      elsif nominal_hp <= 3.0 / 4.0
        efficiency = 560.0 / 674.0 # data obtained from motorboss.com
      else
        return nil
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.motor', "#{motor_type} was passed as a motor_type, it should either be ECM or PSC.")
      return nil
    end
    motor_properties = {
      'nominal_full_load_efficiency' => efficiency,
      'maximum_capacity' => nominal_hp
    }
    return motor_properties
  end
end
