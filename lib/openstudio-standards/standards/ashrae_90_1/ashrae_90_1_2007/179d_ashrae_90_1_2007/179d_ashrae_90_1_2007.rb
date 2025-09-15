# This class holds methods that apply a version of ASHRAE 90.1-2007 that has
# been modified to suit 179D needs
# @ref [References::ASHRAE9012007]
class ACM179dASHRAE9012007 < ASHRAE9012007
  register_standard '179D 90.1-2007'
  attr_reader :template, :whole_building_space_type_name

  def initialize
    # Lazy load the patch
    require_relative '179d_ashrae_90_1_2007.Siz.HeatingCoolingFuels'
    @template = '179d-90.1-2007'
    load_standards_database

    # This is super weird, but this is for resolving ventilation and exhaust
    # per the space type's... and merging with the rest
    @std_2007 = ASHRAE9012007.new
  end

  def almost_equal?(value_actual, value_expected, epsilon = 0.01)
    (value_actual - value_expected).abs / value_actual < epsilon
  end

  # Loads the openstudio standards dataset for this standard.
  #
  # It will load ASHRAE90.1-2007, and do the following:
  # * space_types: overwritten completely
  # * schedules: are added onto the ASHRAE90.1-2007 ones
  #
  # @param data_directories [Array<String>] array of file paths that contain standards data
  # @return [Hash] a hash of standards data
  def load_standards_database(data_directories = [])
    # Load ASHRAE 90.1-2007 data
    super(data_directories)
    # And patch in our own
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Extending with JSON files from #{__dir__}")
    files = Dir.glob("#{__dir__}/data/*.json").select { |e| File.file? e }
    files.each do |file|
      data = JSON.parse(File.read(file))
      data.each_pair do |key, objs|
        # Override the template in inherited files to match the instantiated template
        objs.each do |obj|
          if obj.key?('template')
            obj['template'] = template
          end
        end
        if @standards_data[key].nil?
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Adding #{key} from #{File.basename(file)}")
          @standards_data[key] = objs
        elsif ['schedules', 'constructions', 'materials'].include?(key)
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Extending #{key} with #{File.basename(file)}")
          @standards_data[key] += objs
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Overriding #{key} with #{File.basename(file)}")
          @standards_data[key] = objs
        end
      end
    end

    # override values in 90.1-2007 jsons that are no longer correct compared to the latest 90.1-2007
    # packaged ac units
    @standards_data['unitary_acs'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(64999.0, info['minimum_capacity']) &&
         almost_equal?(134999.0, info['maximum_capacity'])
        info['minimum_energy_efficiency_ratio'] = 11.0
        info['minimum_seasonal_energy_efficiency_ratio'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['unitary_acs'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(135000.0, info['minimum_capacity']) &&
         almost_equal?(239999.0, info['maximum_capacity'])
        info['minimum_energy_efficiency_ratio'] = 10.8
        info['minimum_seasonal_energy_efficiency_ratio'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['unitary_acs'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(240000.0, info['minimum_capacity']) &&
         almost_equal?(759999.0, info['maximum_capacity'])
        info['minimum_energy_efficiency_ratio'] = 9.8
        info['minimum_seasonal_energy_efficiency_ratio'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['unitary_acs'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(760000.0, info['minimum_capacity']) &&
         almost_equal?(9999999.0, info['maximum_capacity'])
        info['minimum_energy_efficiency_ratio'] = 9.5
        info['minimum_seasonal_energy_efficiency_ratio'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    # boilers
    @standards_data['boilers'].each do |info|
      if info['fluid_type'] == 'Hot Water' &&
         almost_equal?(300000.0, info['minimum_capacity']) &&
         almost_equal?(2500000.0, info['maximum_capacity'])
        info['minimum_thermal_efficiency'] = 0.8
        info['minimum_annual_fuel_utilization_efficiency'] = nil
        info['minimum_combustion_efficiency'] = nil
      end
    end
    @standards_data['boilers'].each do |info|
      if info['fluid_type'] == 'Hot Water' &&
         almost_equal?(2500000.01, info['minimum_capacity']) &&
         almost_equal?(9999999999.0, info['maximum_capacity'])
        info['minimum_thermal_efficiency'] = nil
        info['minimum_annual_fuel_utilization_efficiency'] = nil
        info['minimum_combustion_efficiency'] = 0.82
      end
    end
    # packaged heat pumps
    @standards_data['heat_pumps'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(65000.0, info['minimum_capacity']) &&
         almost_equal?(134999.0, info['maximum_capacity'])
        info['minimum_seasonal_efficiency'] = nil
        info['minimum_full_load_efficiency'] = 10.8
        info['minimum_iplv'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['heat_pumps'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(135000.0, info['minimum_capacity']) &&
         almost_equal?(239999.0, info['maximum_capacity'])
        info['minimum_seasonal_efficiency'] = nil
        info['minimum_full_load_efficiency'] = 10.4
        info['minimum_iplv'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['heat_pumps'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['heating_type'] == 'All Other' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(240000.0, info['minimum_capacity']) &&
         almost_equal?(9999999.0, info['maximum_capacity'])
        info['minimum_seasonal_efficiency'] = nil
        info['minimum_full_load_efficiency'] = 9.3
        info['minimum_iplv'] = nil
        info['minimum_integrated_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['heat_pumps_heating'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(65000.0, info['minimum_capacity']) &&
         almost_equal?(134999.0, info['maximum_capacity'])
        info['minimum_heating_seasonal_performance_factor'] = nil
        info['minimum_coefficient_of_performance_heating'] = 3.3
        info['minimum_energy_efficiency_ratio'] = nil
      end
    end
    @standards_data['heat_pumps_heating'].each do |info|
      if info['cooling_type'] == 'AirCooled' &&
         info['subcategory'] == 'Single Package' &&
         almost_equal?(135000.0, info['minimum_capacity']) &&
         almost_equal?(9999999.0, info['maximum_capacity'])
        info['minimum_heating_seasonal_performance_factor'] = nil
        info['minimum_coefficient_of_performance_heating'] = 3.2
        info['minimum_energy_efficiency_ratio'] = nil
      end
    end
  end
end
