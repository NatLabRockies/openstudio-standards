module OpenstudioStandards
  # The ServiceWaterHeating module provides methods to create, modify, and get information about service water heating
  module ServiceWaterHeating
    # @!group Information
    # Methods to add get information about service water heating equipment and loops

    # Determines water heater capacity and volume from an array of water use equipment.
    #
    # @param water_use_equipment_array [Array<OpenStudio::Model::WaterUseEquipment>] Array of water use equipment objects served by this water heater
    # @param capacity_to_volume_ratio [Double] storage volume in gallons per kBtu/hr of capacity
    # @param water_heater_efficiency [Double] water heater thermal efficiency, fraction
    # @param inlet_temperature [Double] inlet cold water temperature, degrees Fahrenheit
    # @param supply_temperature [Double] supply water temperature from the tank, degrees Fahrenheit
    # @param peak_flow_fraction [Double] a variable for system diversity as fraction of peak flow when setting water heater capacity
    # @param minimum_volume [Double] minimum allowable volume of the water heater, in gallons
    # @return [Hash] hash with water_heater_capacity in watts and water_heater_volume in m^3
    def self.water_heater_sizing_from_water_use_equipment(water_use_equipment_array,
                                                          capacity_to_volume_ratio: 1.0,
                                                          water_heater_efficiency: 0.8,
                                                          inlet_temperature: 40.0,
                                                          supply_temperature: 140.0,
                                                          peak_flow_fraction: 1.0,
                                                          minimum_volume: 40.0)
      # Initialize hash
      water_heater_sizing = {}

      # Get the maximum flow rates for all pieces of water use equipment
      adjusted_max_flow_rates_gal_per_hr = []
      water_use_equipment_array.sort.each do |water_use_equip|
        water_use_equip_sch = water_use_equip.flowRateFractionSchedule
        next if water_use_equip_sch.empty?

        water_use_equip_sch = water_use_equip_sch.get
        max_sch_value = OpenstudioStandards::Schedules.schedule_get_min_max(water_use_equip_sch)['max']

        # Get peak flow rate from water use equipment definition
        peak_flow_rate_m3_per_s = water_use_equip.waterUseEquipmentDefinition.peakFlowRate

        # Calculate adjusted flow rate based on the peak fraction found in the flow rate fraction schedule
        adjusted_peak_flow_rate_m3_per_s = max_sch_value * peak_flow_rate_m3_per_s
        adjusted_max_flow_rates_gal_per_hr << OpenStudio.convert(adjusted_peak_flow_rate_m3_per_s, 'm^3/s', 'gal/hr').get
      end

      # Sum gph values from water use equipment to use in formula
      total_adjusted_flow_rate_gal_per_hr = adjusted_max_flow_rates_gal_per_hr.sum

      # Calculate capacity based on analysis of combined water use equipment maximum flow rates and schedules
      # Max gal/hr * 8.4 lb/gal * 1 Btu/lb F * (120F - 40F)/0.8 = Btu/hr
      water_heater_capacity_btu_per_hr = peak_flow_fraction * total_adjusted_flow_rate_gal_per_hr * 8.4 * 1.0 * (supply_temperature - inlet_temperature) / water_heater_efficiency
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Capacity of #{water_heater_capacity_btu_per_hr.round} Btu/hr = #{peak_flow_fraction} peak fraction * #{total_adjusted_flow_rate_gal_per_hr.round} gal/hr * 8.4 lb/gal * 1.0 Btu/lb F * (#{supply_temperature.round} - #{inlet_temperature.round} deltaF / #{water_heater_efficiency} htg eff).")
      water_heater_capacity_w = OpenStudio.convert(water_heater_capacity_btu_per_hr, 'Btu/hr', 'W').get

      # Calculate volume based on capacity
      # A.1.4 Total Storage Volume and Water Heater Capacity of PrototypeModelEnhancements_2014_0.pdf shows 1 gallon of storage to 1 kBtu/h of capacity
      water_heater_capacity_kbtu_per_hr = OpenStudio.convert(water_heater_capacity_btu_per_hr, 'Btu/hr', 'kBtu/hr').get
      water_heater_volume_gal = water_heater_capacity_kbtu_per_hr * capacity_to_volume_ratio

      # increase tank size to the minimum volume if calculated value is smaller
      water_heater_volume_gal = minimum_volume if water_heater_volume_gal < minimum_volume # gal
      water_heater_volume_m3 = OpenStudio.convert(water_heater_volume_gal, 'gal', 'm^3').get

      # Populate return hash
      water_heater_sizing[:water_heater_capacity] = water_heater_capacity_w
      water_heater_sizing[:water_heater_volume] = water_heater_volume_m3

      return water_heater_sizing
    end
  end
end
