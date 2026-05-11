require_relative '../../helpers/minitest_helper'

class TestCreateTypicalSpaceTypeInformation < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_school
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/test_school"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    space_hash = @create.model_get_space_information(model)

    space_type_hash = @create.model_get_space_type_information(model)
    space_type_hash = space_type_hash.select { |h, k| k[:standards_space_type] == 'Classroom' }
    classroom_space_type = space_type_hash[space_type_hash.keys[0]]
    assert(886, classroom_space_type[:number_of_people].round)
    assert(842, classroom_space_type[:number_of_students].round)

    building_hash = @create.model_get_building_information(model)
    assert(1478, building_hash[:number_of_people].round)
    assert(0, building_hash[:number_of_units].round)
    assert(0, building_hash[:number_of_beds].round)
    assert(842, building_hash[:number_of_students].round)
  end
end