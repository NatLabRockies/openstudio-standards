require_relative '../helpers/minitest_helper'
require_relative 'create_performance_rating_method_helper'

class ACM179dASHRAE9012007BaselineBuildingTest < Minitest::Test

  def setup
    @standard_name = '179D 90.1-2007'
    @standard = Standard.build(@standard_name)
  end

  def get_expected_value_for_building_type(base_model, building_type, key)
    search_criteria = {
      'template' => @standard.template,
      'building_type' => building_type,
      'space_type' => @standard.whole_building_space_type_name(base_model, building_type),
    }

    space_type_properties = @standard.model_find_object(@standard.standards_data['space_types'], search_criteria)
    raise "Standards data not found for search_criteria=#{search_criteria}" if space_type_properties.nil?
    raise "#{key} not found in space_type_properties, available keys: #{space_type_properties.keys}" unless space_type_properties.has_key?(key)

    space_type_properties[key]
  end

  def test_179d_warehouse
    model_name = 'Warehouse_5A'
    building_type = 'Warehouse'
    climate_zone = 'ASHRAE 169-2013-5A'
    # Use addenda dn (heated only systems)
    custom = nil
    debug = true
    load_existing_model = true

    base_model = create_baseline_model(model_name, @standard_name, climate_zone, building_type, custom, debug, load_existing_model)
    prop_model = load_test_model(model_name)

    # base and prop should have the same number of space types
    assert_equal(base_model.getSpaceTypes.size, prop_model.getSpaceTypes.size)

    # Make sure we get space types in the same order, and that the name is
    # still the same
    base_space_types = base_model.getSpaceTypes.sort_by(&:nameString)
    prop_space_types = base_space_types.map(&:nameString).map{|n| prop_model.getSpaceTypeByName(n).get}

    # We check that the LPDs were changed
    lighting_per_area_ip = get_expected_value_for_building_type(base_model, building_type, 'lighting_per_area')
    assert_equal(0.8, lighting_per_area_ip)
    lighting_per_area_si = OpenStudio.convert(lighting_per_area_ip, 'W/ft^2', 'W/m^2').get

    base_space_types.zip(prop_space_types).each do |base_sp, prop_sp|
      refute_empty(base_sp.lightingPowerPerFloorArea)
      base_lpd_si = base_sp.lightingPowerPerFloorArea.get

      refute_empty(prop_sp.lightingPowerPerFloorArea)
      prop_lpd_si = prop_sp.lightingPowerPerFloorArea.get

      # We get different LPD
      refute_in_delta(prop_lpd_si, base_lpd_si, 0.001)

      # We get the right LPD in the baseline
      assert_in_delta(lighting_per_area_si, base_lpd_si, 0.001, "LPD failure for #{base_sp.nameString}")
    end

  end
end
