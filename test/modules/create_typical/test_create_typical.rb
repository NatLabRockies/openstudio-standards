require_relative '../../helpers/minitest_helper'

class TestCreateTypical < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_create_typical_building_from_model
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_building_from_model_comstock
    # load model and set up weather file
    template = 'ComStock DOE Ref 1980-2004'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEMediumOffice.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_deer_building_from_model
    # load model and set up weather file
    template = 'DEER Pre-1975'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_ESe.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_comstock_deer_building_from_model
    # load model and set up weather file
    template = 'ComStock DEER 2017'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_ESe.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        hvac_system_type: 'PVAV with gas boiler reheat',
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_space_types_and_constructions
    model = OpenStudio::Model::Model.new
    building_type = 'PrimarySchool'
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    result = @create.create_space_types_and_constructions(model, building_type, template, climate_zone)
    assert(result)
    assert(model.getSpaceTypes.size > 0)
    assert(model.getDefaultConstructionSets.size > 0)
  end

  def test_create_typical_building_from_model_with_hvac_mapping
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESmallOffice.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # Read in HVAC to zone mapping with 4 zones served by PTAC and 1 by a PSZ AC
    hvac_zone_json_path = File.join(File.dirname(__FILE__),'data','hvac_zone_mapping.json')
    hvac_zone_json = File.read(hvac_zone_json_path)
    hvac_mapping_hash = JSON.parse(hvac_zone_json)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical with zone mapping
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        user_hvac_mapping: hvac_mapping_hash,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    psz_ac = model.getAirLoopHVACUnitarySystems

    # Check that JSON specs were applied
    assert(result)
    assert(starting_size < ending_size)
    assert_equal(4, ptacs.length)
    assert_equal(1, psz_ac.length)
  end

  def test_create_typical_ese_op_hrs_overnight
    # load model and set up weather file
    template = 'DEER Pre-1975'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_ESe.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model,
                                                        template,
                                                        climate_zone: climate_zone,
                                                        modify_wkdy_op_hrs: true,
                                                        wkdy_op_hrs_start_time: 12.50,
                                                        wkdy_op_hrs_duration: 13.0,
                                                        modify_wknd_op_hrs: true,
                                                        wknd_op_hrs_start_time: 8.00,
                                                        wknd_op_hrs_duration: 6.00,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_building_from_model_comstock_restaurant
    # load model and set up weather file
    # template = 'ComStock DOE Ref 1980-2004'
    # climate_zone = 'ASHRAE 169-2013-3C'
    # geometry_file = 'ASHRAEFullServiceRestaurant.osm'

    template = 'ComStock DEER Pre-1975'
    climate_zone = 'CEC T24-CEC2'
    geometry_file = 'DEER_RSD.osm'

    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/#{geometry_file}")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_building_from_model_comstock_retail_pthp
    # load model and set up weather file
    template = 'ComStock 90.1-2007'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAERetailStripmall.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        hvac_system_type: 'PTHP',
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_laboratory_building
    # load model and set up weather file
    template = '90.1-2016'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAELaboratory.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_comstock_supermarket
    # load model and set up weather file
    template = 'ComStock 90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESuperMarket.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    outvar1 = OpenStudio::Model::OutputVariable.new('Refrigeration Case Defrost Electricity Energy', model)
    outvar2 = OpenStudio::Model::OutputVariable.new('Refrigeration Walk In Defrost Electricity Energy', model)
    outvar3 = OpenStudio::Model::OutputVariable.new('Zone Air Relative Humidity', model)
    outvar1.setReportingFrequency('hourly')
    outvar1.setKeyValue('*')
    outvar2.setReportingFrequency('hourly')
    outvar2.setKeyValue('*')
    outvar3.setReportingFrequency('hourly')
    outvar3.setKeyValue('*')

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir,
                                                        refrigeration_template: 'advanced')
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)

    # baseline run
    std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_0KW_latent")

    # add latent load
    space = model.getSpaceByName('Main Sales').get
    latent_load_def = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    latent_load_def.setName('latent load')
    latent_load_def.setDesignLevel(2000.0)
    latent_load_def.setFractionLatent(1.0)
    latent_load_def.setFractionRadiant(0.0)
    latent_load_def.setFractionLost(0.0)

    latent_load = OpenStudio::Model::ElectricEquipment.new(latent_load_def)
    latent_load.setName('latent load')
    latent_load.setSchedule(model.alwaysOnDiscreteSchedule)
    latent_load.setSpace(space)
    std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_2KW_latent")

    # latent_load_def.setDesignLevel(4000.0)
    # std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_4KW_latent")

    # latent_load_def.setDesignLevel(6000.0)
    # std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_6KW_latent")

    # latent_load_def.setDesignLevel(8000.0)
    # std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_8KW_latent")

    # latent_load_def.setDesignLevel(10000.0)
    # std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_10KW_latent")

    latent_load_def.setDesignLevel(20000.0)
    std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR_20KW_latent")
  end

  def test_create_typical_deer_gro
    # load model and set up weather file
    template = 'ComStock DEER Pre-1975'
    climate_zone = 'CEC T24-CEC6'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/DEER_Gro.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end

  def test_create_typical_old_pthp
    # load model and set up weather file
    template = 'ComStock DOE Ref Pre-1980'
    climate_zone = 'ASHRAE 169-2013-3A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESmallOffice.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create typical
    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                        climate_zone: climate_zone,
                                                        hvac_system_type: 'PTHP',
                                                        sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert(starting_size < ending_size)
  end
end
