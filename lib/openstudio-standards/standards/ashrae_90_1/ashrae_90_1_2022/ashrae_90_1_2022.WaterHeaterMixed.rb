class ASHRAE9012022 < ASHRAE901
  # Add additional search criteria for water heater lookup efficiency.
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @param search_criteria [Hash] search criteria for looking up water heater data
  # @return [Hash] updated search criteria
  def water_heater_mixed_additional_search_criteria(water_heater_mixed, search_criteria)
    search_criteria['draw_profile'] = 'medium' # assumption; could be based on inputs
    return search_criteria
  end
end

