require_relative '../../helpers/minitest_helper'

class TestExteriorLightingInformation < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @ext = OpenstudioStandards::ExteriorLighting
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  def test_model_get_exterior_lighting_sizes_primary_school
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/test_primary_school"
    FileUtils.mkdir_p output_dir

    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)

    areas = @ext.model_get_exterior_lighting_sizes(model)
  end

  def test_model_get_exterior_lighting_sizes_supermarket
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESuperMarket.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/test_supermarket"
    FileUtils.mkdir_p output_dir

    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)

    areas = @ext.model_get_exterior_lighting_sizes(model)
    assert(areas[:parking_area_and_drives_area] > 0, 'Parking area and drives area should be greater than 0.')
  end

  def test_exterior_lighting_properties
    ext_lighting_properties = @ext.exterior_lighting_properties
    assert(!ext_lighting_properties.nil?, 'Exterior lighting properties should not be nil.')

    ext_lighting_properties = @ext.exterior_lighting_properties(lighting_generation: 'default')
    assert(!ext_lighting_properties.nil?, 'Exterior lighting properties should not be nil.')

    ext_lighting_properties = @ext.exterior_lighting_properties(lighting_zone: 1)
    assert(ext_lighting_properties.nil?, 'Data should not yet be available for this lighting zone.')
  end
end