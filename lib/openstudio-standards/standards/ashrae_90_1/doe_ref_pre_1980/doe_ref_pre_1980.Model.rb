class DOERefPre1980 < ASHRAE901
  # @!group Model

  # Determine which climate zone to use.
  # For Pre-1980 and 1980-2004, use the most specific climate zone set.
  # For example, 2A and 2 both contain 2A, so use 2A.
  # The exceptions are climate zones 1, 7, and 8, which
  # combine 1A/1B, 7A/7B, and 8A/8B into 1, 7, and 8.
  def model_get_climate_zone_set_from_list(model, possible_climate_zone_sets)
    climate_zone_set = if possible_climate_zone_sets.include? 'ClimateZone 1'
                         possible_climate_zone_sets.min
                       elsif possible_climate_zone_sets.include? 'ClimateZone 7'
                         possible_climate_zone_sets.min
                       elsif possible_climate_zone_sets.include? 'ClimateZone 8'
                         possible_climate_zone_sets.min
                       else
                         possible_climate_zone_sets.max
                       end
    return climate_zone_set
  end
end
