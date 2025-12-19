class ASHRAE9012019 < ASHRAE901
  # Applies the standard efficiency ratings to CoilHeatingGas.
  #
  # @param coil_heating_gas [OpenStudio::Model::CoilHeatingGas] coil heating gas object
  # @param search_criteria [Hash] search criteria for looking up furnace data
  # @return [Hash] updated search criteria
  def coil_heating_gas_additional_search_criteria(coil_heating_gas, search_criteria)
    capacity_w = OpenstudioStandards::HVAC.coil_heating_gas_get_capacity(coil_heating_gas)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    if capacity_btu_per_hr < 225_000
      search_criteria['subtype'] = 'Weatherized' # assumption; could be based on input
    end
    return search_criteria
  end
end
