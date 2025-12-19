require_relative '../../helpers/minitest_helper'

class TestInfiltration < Minitest::Test
  def setup
    @infiltration = OpenstudioStandards::Infiltration
    @sch = OpenstudioStandards::Schedules
    @create = OpenstudioStandards::CreateTypical
  end

  def test_nist_building_types
    building_types = @infiltration.nist_building_types
    assert_equal(11, building_types.size)
  end

  def test_model_infer_nist_building_type
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('SecondarySchool', building_type)

    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAELargeHotel.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('LargeHotel', building_type)

    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESmallOffice.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('SmallOffice', building_type)

    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_RtL.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('RetailStripmall', building_type)

    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_SUn.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('RetailStripmall', building_type)

    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_MFm.osm")
    building_type = @infiltration.model_infer_nist_building_type(model)
    assert('', building_type)
  end

  def test_model_set_nist_infiltration_correlations
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # defaults
    result = @infiltration.model_set_nist_infiltration(model)
    assert(result)
    obj = model.getSpaceInfiltrationDesignFlowRateByName('Computer_Class_ZN_1_FLR_1 HVAC Off Infiltration').get
    assert_in_delta(0.00057, obj.flowperExteriorSurfaceArea.get, 0.0001)
    assert_in_delta(0.0, obj.constantTermCoefficient, 0.0001)
    assert_in_delta(0.0073, obj.temperatureTermCoefficient, 0.0001)
    assert_in_delta(0.0, obj.velocityTermCoefficient, 0.0001)
    assert_in_delta(0.0397, obj.velocitySquaredTermCoefficient, 0.0001)
    obj = model.getSpaceInfiltrationDesignFlowRateByName('Computer_Class_ZN_1_FLR_1 HVAC On Infiltration').get
    assert_in_delta(-0.0028, obj.constantTermCoefficient, 0.0001)
    assert_in_delta(0.0037, obj.temperatureTermCoefficient, 0.0001)
    assert_in_delta(0.0, obj.velocityTermCoefficient, 0.0001)
    assert_in_delta(0.0336, obj.velocitySquaredTermCoefficient, 0.0001)

    # bad airtightness value
    result = @infiltration.model_set_nist_infiltration(model,
                                                       airtightness_value: -5.0)
    assert(!result)

    # 4-sided
    result = @infiltration.model_set_nist_infiltration(model,
                                                       airtightness_area_covered: '4-sided')
    assert(result)

    # 6-sided
    result = @infiltration.model_set_nist_infiltration(model,
                                                       airtightness_area_covered: '6-sided')
    assert(result)
    obj = model.getSpaceInfiltrationDesignFlowRateByName('Computer_Class_ZN_1_FLR_1 HVAC Off Infiltration').get
    assert_in_delta(0.000988, obj.flowperExteriorSurfaceArea.get, 0.0001)

    # air barrier
    result = @infiltration.model_set_nist_infiltration(model,
                                                       airtightness_value: 3.0,
                                                       air_barrier: true)
    assert(result)

    # alternate building type
    result = @infiltration.model_set_nist_infiltration(model,
                                                       nist_building_type: 'SecondarySchool')
    assert(result)
    obj = model.getSpaceInfiltrationDesignFlowRateByName('Computer_Class_ZN_1_FLR_1 HVAC Off Infiltration').get
    assert_in_delta(0.00057, obj.flowperExteriorSurfaceArea.get, 0.0001)
    assert_in_delta(0.0, obj.constantTermCoefficient, 0.0001)
    assert_in_delta(0.0174, obj.temperatureTermCoefficient, 0.0001)
    assert_in_delta(0.0, obj.velocityTermCoefficient, 0.0001)
    assert_in_delta(0.1016, obj.velocitySquaredTermCoefficient, 0.0001)
    obj = model.getSpaceInfiltrationDesignFlowRateByName('Computer_Class_ZN_1_FLR_1 HVAC On Infiltration').get
    assert_in_delta(0.0725, obj.constantTermCoefficient, 0.0001)
    assert_in_delta(0.0091, obj.temperatureTermCoefficient, 0.0001)
    assert_in_delta(0.0, obj.velocityTermCoefficient, 0.0001)
    assert_in_delta(0.0893, obj.velocitySquaredTermCoefficient, 0.0001)

    # test specifying hvac schedule
    rules = []
    rules << ['Tuesdays and Thursdays', '1/1-12/31', 'Tue/Thu', [4, 0], [4.33, 1], [18, 0], [18.66, 1], [24, 0]]
    test_options = {
      'name' => 'Complex HVAC Schedule',
      'winter_design_day' => [[24, 0]],
      'summer_design_day' => [[24, 1]],
      'default_day' => ['Complex HVAC Schedule Default', [11, 0], [11.33, 1], [23, 0], [23.33, 1], [24, 0]],
      'rules' => rules
    }
    schedule = @sch.create_complex_schedule(model, test_options)
    result = @infiltration.model_set_nist_infiltration(model,
                                                       hvac_schedule_name: 'Complex HVAC Schedule' )
    assert(result)

    # test climate zone 0
    climate_zone = 'ASHRAE 169-2013-0A'
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)
    result = @infiltration.model_set_nist_infiltration(model)
    assert(result)
  end

  def test_model_set_nist_infiltration_schedules
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # defaults
    result = @infiltration.model_set_nist_infiltration(model)
    assert(result)

    # create output directory
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
    output_dir = "#{__dir__}/output/test_nist_infil_sch"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical to add HVAC and schedules
    @create.create_typical_building_from_model(model, template,
                                               climate_zone: climate_zone,
                                               sizing_run_directory: output_dir)
    hvac_schedule = @sch.model_get_hvac_schedule(model)

    # update infiltration schedules with hvac_schedule
    result = @infiltration.model_set_nist_infiltration_schedules(model, hvac_schedule: hvac_schedule)
    assert(result)

    # update infiltration schedules with default
    result = @infiltration.model_set_nist_infiltration_schedules(model)
    assert(result)
  end
end