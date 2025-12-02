require_relative '../helpers/minitest_helper'
require_relative 'create_performance_rating_method_helper'

class CreatePerformanceRatingMethodBaselineBuildingTest < Minitest::Test

  def test_jmarrec
    model_name = '19.1.before_create_179d_gem_baseline_building'
    standard = '90.1-2007'
    climate_zone = 'ASHRAE 169-2013-5B'
    # Use addenda dn (heated only systems)
    custom = '90.1-2007 with addenda dn'
    base_model = create_baseline_model(model_name, standard, climate_zone, 'SmallOffice', custom, debug = true, load_existing_model = true)
  end

end
