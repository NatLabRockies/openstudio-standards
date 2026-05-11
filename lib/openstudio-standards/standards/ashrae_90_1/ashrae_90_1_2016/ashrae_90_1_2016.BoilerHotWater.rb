class ASHRAE9012016 < ASHRAE901
  # Determine what part load efficiency degredation curve should be used for a boiler
  #
  # @param boiler_hot_water [OpenStudio::Model::BoilerHotWater] hot water boiler object
  # @return [String] returns name of the boiler curve to be used, or nil if not applicable
  def boiler_get_eff_fplr(boiler_hot_water)
    capacity_w = OpenstudioStandards::HVAC.boiler_hot_water_get_capacity(boiler_hot_water)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    fplr = capacity_btu_per_hr >= 1_000_000 ? 'Boiler with Minimum Turndown' : 'Boiler with No Minimum Turndown'
    return fplr
  end
end
