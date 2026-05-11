require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'

class TestMisc < Minitest::Test
  def create_model(building_type, climate_zone, template)
    # Initialize weather file, necessary but not used
    epw_file = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'

    # Create output folder if it doesn't already exist
    @test_dir = "#{File.dirname(__FILE__)}/output"
    if !Dir.exist?(@test_dir)
      Dir.mkdir(@test_dir)
    end

    # Define model name and run folder if it doesn't already exist,
    # if it does, remove it and re-create it.
    model_name = "#{building_type}-#{template}-#{climate_zone}"
    run_dir = "#{@test_dir}/#{model_name}"
    if !Dir.exist?(run_dir)
      Dir.mkdir(run_dir)
    else
      FileUtils.rm_rf(run_dir)
      Dir.mkdir(run_dir)
    end

    # Create standard and prototype
    std = Standard.build("#{template}_#{building_type}")
    model = std.model_create_prototype_model(climate_zone, epw_file, run_dir)

    return std, model
  end

  # def test_plenum_space_conditioning
  #   # Create prototype
  #   std, model = create_model('LargeOffice', 'ASHRAE 169-2013-4A', '90.1-2019')

  #   # Test return plenum space conditioning
  #   model.getSpaces.sort.each do |space|
  #     if space.name.to_s.downcase.include?('plenum')
  #       assert(std.space_conditioning_category(space) == 'NonResConditioned', 'Wrong plenum space conditioning type.')
  #     end
  #   end
  # end

  def test_add_table_lookup_curve
    model = OpenStudio::Model::Model.new
    std = Standard.build('ECMS')
    curve1 = std.model_add_curve(model, 'Mitsubishi Hyper Heating VRF Outdoor Unit HPLFFPLR curve')
    curve2 = std.model_add_curve(model, 'Mitsubishi Hyper Heating VRF Outdoor Unit CCAPFPL curve')
    assert(curve1.to_Curve.is_initialized, 'table lookup curve was not added to the model')
    assert(curve2.to_Curve.is_initialized, 'table lookup curve was not added to the model')
  end

  def test_add_material
    model = OpenStudio::Model::Model.new
    std = Standard.build("90.1-2019")

    # Complete definition
    mat_1 = std.model_add_material(model, "Simple Glazing U 0.1 SHGC 0.2 VT 0.3")
    assert(mat_1.uFactor.round(2) == OpenStudio.convert(0.1,'Btu/hr*ft^2*R', 'W/m^2*K').get.round(2))
    assert(mat_1.solarHeatGainCoefficient == 0.2)
    assert(mat_1.visibleTransmittance.get == 0.3)

    # Missing information
    mat_2 = std.model_add_material(model, "U 0.51 SHGC 0.23 Simple Glazing")
    assert(mat_2.uFactor.round(2) == OpenStudio.convert(0.51, 'Btu/hr*ft^2*R', 'W/m^2*K').get.round(2))
    assert(mat_2.solarHeatGainCoefficient == 0.23)
    assert(mat_2.visibleTransmittance.get == 0.81)

    # Missing info so look in library; Expected to return an optional material since it is not in the library
    mat_3 = std.model_add_material(model, "U 0.51 SHGC 0.23 Simp G Window")
    assert(mat_3.is_a?(OpenStudio::Model::OptionalMaterial))
  end
end
