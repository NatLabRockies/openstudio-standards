class ASHRAE9012019 < ASHRAE901
  # @!group Pump

  # Determine type of pump part load control type
  # @note code_sections [90.1-2019_6.5.4.2]
  #
  # @param pump [OpenStudio::Model::PumpVariableSpeed] OpenStudio pump object
  # @param plant_loop_type [String] Type of plant loop
  # @param pump_nominal_hp [Float] Pump nominal horsepower
  # @return [String] Pump part load control type
  def pump_variable_speed_get_control_type(pump, plant_loop_type, pump_nominal_hp)
    # Sizing factor to take into account that pumps
    # are typically sized to handle a ~10% pressure
    # increase and ~10% flow increase.
    design_sizing_factor = 1.25

    # Get climate zone
    climate_zone = pump.plantLoop.get.model.getClimateZones.getClimateZone(0)
    climate_zone = "#{climate_zone.institution} 169-#{climate_zone.year}-#{climate_zone.value}"

    # Get nameplate hp threshold:
    # The thresholds below represent the nameplate
    # hp one level lower than the threshold in the
    # code. Motor size from table in section 10 are
    # used as reference.
    case plant_loop_type
      when 'Heating'
        case climate_zone
          when 'ASHRAE 169-2006-7A',
               'ASHRAE 169-2006-7B',
               'ASHRAE 169-2006-8A',
               'ASHRAE 169-2006-8B',
               'ASHRAE 169-2013-7A',
               'ASHRAE 169-2013-7B',
               'ASHRAE 169-2013-8A',
               'ASHRAE 169-2013-8B'
            threshold = 3
          when 'ASHRAE 169-2006-3C',
               'ASHRAE 169-2006-5A',
               'ASHRAE 169-2006-5C',
               'ASHRAE 169-2006-6A',
               'ASHRAE 169-2006-6B',
               'ASHRAE 169-2013-3C',
               'ASHRAE 169-2013-5A',
               'ASHRAE 169-2013-5C',
               'ASHRAE 169-2013-6A',
               'ASHRAE 169-2013-6B'
            threshold = 5
          when 'ASHRAE 169-2006-4A',
               'ASHRAE 169-2006-4C',
               'ASHRAE 169-2006-5B',
               'ASHRAE 169-2013-4A',
               'ASHRAE 169-2013-4C',
               'ASHRAE 169-2013-5B'
            threshold = 7.5
          when 'ASHRAE 169-2006-4B',
               'ASHRAE 169-2013-4B'
            threshold = 10
          when 'ASHRAE 169-2006-2A',
               'ASHRAE 169-2006-2B',
               'ASHRAE 169-2006-3A',
               'ASHRAE 169-2006-3B',
               'ASHRAE 169-2013-2A',
               'ASHRAE 169-2013-2B',
               'ASHRAE 169-2013-3A',
               'ASHRAE 169-2013-3B'
            threshold = 20
          when 'ASHRAE 169-2006-1B',
               'ASHRAE 169-2013-1B'
            threshold = 75
          when 'ASHRAE 169-2006-0A',
               'ASHRAE 169-2006-0B',
               'ASHRAE 169-2006-1A',
               'ASHRAE 169-2013-0A',
               'ASHRAE 169-2013-0B',
               'ASHRAE 169-2013-1A'
            threshold = 150
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.ashrae_90_1_2019.PumpVariableSpeed', "Pump flow control requirement missing for heating water pumps in climate zone: #{climate_zone}.")
        end
      when 'Cooling'
        case climate_zone
          when 'ASHRAE 169-2006-0A',
               'ASHRAE 169-2006-0B',
               'ASHRAE 169-2006-1A',
               'ASHRAE 169-2006-1B',
               'ASHRAE 169-2006-2B',
               'ASHRAE 169-2013-0A',
               'ASHRAE 169-2013-0B',
               'ASHRAE 169-2013-1A',
               'ASHRAE 169-2013-1B',
               'ASHRAE 169-2013-2B'
            threshold = 1.5
          when 'ASHRAE 169-2006-2A',
               'ASHRAE 169-2006-3B',
               'ASHRAE 169-2013-2A',
               'ASHRAE 169-2013-3B'
            threshold = 2
          when 'ASHRAE 169-2006-3A',
               'ASHRAE 169-2006-3C',
               'ASHRAE 169-2006-4A',
               'ASHRAE 169-2006-4B',
               'ASHRAE 169-2013-3A',
               'ASHRAE 169-2013-3C',
               'ASHRAE 169-2013-4A',
               'ASHRAE 169-2013-4B'
            threshold = 3
          when 'ASHRAE 169-2006-4C',
               'ASHRAE 169-2006-5A',
               'ASHRAE 169-2006-5B',
               'ASHRAE 169-2006-5C',
               'ASHRAE 169-2006-6A',
               'ASHRAE 169-2006-6B',
               'ASHRAE 169-2013-4C',
               'ASHRAE 169-2013-5A',
               'ASHRAE 169-2013-5B',
               'ASHRAE 169-2013-5C',
               'ASHRAE 169-2013-6A',
               'ASHRAE 169-2013-6B'
            threshold = 5
          when 'ASHRAE 169-2006-7A',
               'ASHRAE 169-2006-7B',
               'ASHRAE 169-2006-8A',
               'ASHRAE 169-2006-8B',
               'ASHRAE 169-2013-7A',
               'ASHRAE 169-2013-7B',
               'ASHRAE 169-2013-8A',
               'ASHRAE 169-2013-8B'
            threshold = 10
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.ashrae_90_1_2019.PumpVariableSpeed', "Pump flow control requirement missing for chilled water pumps in climate zone: #{climate_zone}.")
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.ashrae_90_1_2019.PumpVariableSpeed', "No pump flow requirement for #{plant_loop_type} plant loops.")
        return false
    end

    return 'VSD DP Reset' if pump_nominal_hp * design_sizing_factor > threshold

    # else
    return 'Riding Curve'
  end
end
