require_relative '../../helpers/minitest_helper'

class TestCreateTypicalServiceWaterHeating < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating

    # create output directory
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  def test_outpatient_procedure_room_uses_dedicated_space_and_service_water_profile
    model = OpenStudio::Model::Model.new
    outpatient_or = OpenStudio::Model::SpaceType.new(model)
    outpatient_or.setStandardsBuildingType('Outpatient')
    outpatient_or.setStandardsSpaceType('OR')
    outpatient_preop = OpenStudio::Model::SpaceType.new(model)
    outpatient_preop.setStandardsBuildingType('Outpatient')
    outpatient_preop.setStandardsSpaceType('PreOp')
    outpatient_procedure_room = OpenStudio::Model::SpaceType.new(model)
    outpatient_procedure_room.setStandardsBuildingType('Outpatient')
    outpatient_procedure_room.setStandardsSpaceType('ProcedureRoom')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('operating room', outpatient_or.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('exam/treatment', outpatient_preop.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('procedure room', outpatient_procedure_room.additionalProperties.getFeatureAsString('standards_space_type').get)

    or_category = outpatient_or.additionalProperties.getFeatureAsString('service_water_space_type').get
    preop_category = outpatient_preop.additionalProperties.getFeatureAsString('service_water_space_type').get
    procedure_room_category = outpatient_procedure_room.additionalProperties.getFeatureAsString('service_water_space_type').get
    assert_equal('operating_room', or_category)
    assert_equal('exam_treatment', preop_category)
    assert_equal('procedure_room', procedure_room_category)
    assert_equal('procedure_room_ventilation', outpatient_procedure_room.additionalProperties.getFeatureAsString('ventilation_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    assert_equal([or_category], @swh.service_water_data_for_space_type(data, outpatient_or).map { |r| r[:service_water_space_type] })
    assert_equal([preop_category], @swh.service_water_data_for_space_type(data, outpatient_preop).map { |r| r[:service_water_space_type] })
    assert_equal([procedure_room_category], @swh.service_water_data_for_space_type(data, outpatient_procedure_room).map { |r| r[:service_water_space_type] })
    preop_profile = @swh.service_water_data_for_space_type(data, outpatient_preop).first
    assert_equal(0.007590133, preop_profile[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
    procedure_room_profile = @swh.service_water_data_for_space_type(data, outpatient_procedure_room).first
    assert_equal(0.007017544, procedure_room_profile[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
  end

  def test_every_pair_specific_catalog_mapping_has_a_service_water_profile
    catalog_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/space_types.json', __dir__)
    prototype_path = File.expand_path('../../../lib/openstudio-standards/prototypes/common/data/prototype_space_type_map.json', __dir__)
    water_data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    catalog = JSON.parse(File.read(catalog_path), symbolize_names: true)
    prototype_map = JSON.parse(File.read(prototype_path), symbolize_names: true)
    water_data = JSON.parse(File.read(water_data_path), symbolize_names: true)

    overrides = catalog.reject { |r| r[:prototype_standards_building_type].nil? }
    profiles = water_data.fetch(:service_water_space_types)
    assert_empty(overrides)
    overrides.each do |override|
      pair = [override[:prototype_standards_building_type], override[:prototype_standards_space_type]]
      mapping = prototype_map.find { |r| pair == [r[:standards_building_type], r[:standards_space_type]] }
      refute_nil(mapping, "no prototype mapping for #{pair.join(' / ')}")
      assert_equal(mapping[:new_standards_space_type], override[:space_type_name])
      assert_equal(1, profiles.count do |profile|
        profile[:standards_building_type] == pair[0] &&
          profile[:service_water_space_type] == override[:service_water_space_type_name]
      end)
    end
  end

  def test_office_whole_building_spaces_use_dedicated_catalog_profile
    standards_space_types = [
      'WholeBuilding - Lg Office',
      'WholeBuilding - Lg Office-basement',
      'WholeBuilding - Lg Office-others',
      'WholeBuilding - Md Office',
      'WholeBuilding - Sm Office'
    ]
    model = OpenStudio::Model::Model.new
    space_types = standards_space_types.map do |standards_space_type|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsBuildingType('Office')
      space_type.setStandardsSpaceType(standards_space_type)
      space_type
    end

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    space_types.each do |space_type|
      assert_equal('whole building office', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
      assert_equal('whole_building_office', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)
    end

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    space_types.each do |space_type|
      records = @swh.service_water_data_for_space_type(data, space_type)
      assert_equal(1, records.size)
      assert_equal(0.000516521, records.first[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
    end
  end

  def test_stripmall_whole_building_retail_uses_type_2_service_water_profile
    standards_space_types = [
      'Strip mall - type 1',
      'Strip mall - type 2',
      'Strip mall - type 3'
    ]
    model = OpenStudio::Model::Model.new
    space_types = standards_space_types.map do |standards_space_type|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsBuildingType('StripMall')
      space_type.setStandardsSpaceType(standards_space_type)
      space_type
    end

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    space_types.each do |space_type|
      assert_equal('whole building retail', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
      assert_equal('whole_building_retail', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)
    end

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    space_types.each do |space_type|
      records = @swh.service_water_data_for_space_type(data, space_type)
      assert_equal(1, records.size)
      equipment = records.first[:water_use_equipment].first
      assert_equal(1.8, equipment[:peak_flow_rate_gph])
      assert_equal('One Per Space', equipment[:loop_type])
      assert_equal(110.0, equipment[:mixed_water_temperature_f])
      assert_equal('RetailStripmall Type2_SWH_SCH', equipment[:flow_rate_schedule])
    end
  end

  def test_classroom_has_no_service_water_profile
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('ERC')
    space_type.setStandardsSpaceType('Classroom')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('classroom/lecture/training', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('na', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    assert_empty(@swh.service_water_data_for_space_type(data, space_type))
  end

  def test_hospital_exam_treatment_profile_uses_existing_category_for_er_and_icu
    model = OpenStudio::Model::Model.new
    er_exam = OpenStudio::Model::SpaceType.new(model)
    er_exam.setStandardsBuildingType('Hospital')
    er_exam.setStandardsSpaceType('ER_Exam')
    icu = OpenStudio::Model::SpaceType.new(model)
    icu.setStandardsBuildingType('Hospital')
    icu.setStandardsSpaceType('ICU_Open')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    [er_exam, icu].each do |space_type|
      assert_equal('exam/treatment', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
      assert_equal('exam_treatment', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)
    end

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    [er_exam, icu].each do |space_type|
      records = @swh.service_water_data_for_space_type(data, space_type)
      assert_equal(1, records.size)
      assert_equal(0.003333333, records.first[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
    end
  end

  def test_hospital_radiology_uses_existing_imaging_catalog_entry
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Hospital')
    space_type.setStandardsSpaceType('Radiology')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('imaging', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('imaging', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    records = @swh.service_water_data_for_space_type(data, space_type)
    assert_equal(1, records.size)
    assert_equal('Hospital', records.first[:standards_building_type])
    assert_equal(0.000190476, records.first[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
  end

  def test_outpatient_anesthesia_uses_existing_exam_treatment_profile
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Outpatient')
    space_type.setStandardsSpaceType('Anesthesia')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('exam/treatment', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('exam_treatment', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    records = @swh.service_water_data_for_space_type(data, space_type)
    assert_equal(1, records.size)
    assert_equal(0.007590133, records.first[:water_use_equipment].first[:peak_flow_rate_gph_per_floor_area_ft2])
  end

  def test_outpatient_imaging_uses_existing_catalog_category_without_swh_data
    model = OpenStudio::Model::Model.new
    space_types = %w[MRI MRI_Control Xray].map do |standards_space_type|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsBuildingType('Outpatient')
      space_type.setStandardsSpaceType(standards_space_type)
      space_type
    end

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    space_types.each do |space_type|
      assert_equal('imaging', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
      assert_equal('imaging', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)
    end

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    space_types.each do |space_type|
      assert_empty(@swh.service_water_data_for_space_type(data, space_type))
    end
  end

  def test_small_hotel_vacant_guest_room_uses_existing_vacant_catalog_entry
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('SmallHotel')
    space_type.setStandardsSpaceType('GuestRoom123Vac')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('guest room vacant', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('guest_room_vacant', space_type.additionalProperties.getFeatureAsString('schedule_set').get)
    assert_equal('guest room vacant', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    records = @swh.service_water_data_for_space_type(data, space_type)
    assert_equal(1, records.size)
    assert_equal('HotelSmall AlwaysOff', records.first[:water_use_equipment].first[:flow_rate_schedule])
  end

  def test_small_hotel_laundry_uses_existing_laundry_profile
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('SmallHotel')
    space_type.setStandardsSpaceType('Laundry')

    Standard.build('90.1-2013').prototype_space_type_map(model, set_additional_properties: true)

    assert_equal('laundry/washing', space_type.additionalProperties.getFeatureAsString('standards_space_type').get)
    assert_equal('laundry_washing', space_type.additionalProperties.getFeatureAsString('service_water_space_type').get)

    data_path = File.expand_path('../../../lib/openstudio-standards/service_water_heating/data/typical_water_use_equipment.json', __dir__)
    data = JSON.parse(File.read(data_path), symbolize_names: true)
    records = @swh.service_water_data_for_space_type(data, space_type)
    assert_equal(1, records.size)
    assert_equal('One Per Space', records.first[:water_use_equipment].first[:loop_type])
  end

  def test_create_typical_service_water_heating_restaurant
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{__dir__}/../../os_stds_methods/models/QuickServiceRestaurant_2A_2010.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each(&:remove)

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert_equal(1, created_loops.size)
  end

  def test_create_typical_service_water_heating_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{__dir__}/../../os_stds_methods/models/test_school.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert(created_loops.size > 1)
  end

  def test_create_typical_service_water_heating_apartment_units
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEMidriseApartment.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    model.getSpaces.each do |space|
      space.additionalProperties.setFeature('num_units', 1) if space.name.get.include?('Apartment')
      space.additionalProperties.setFeature('num_units', 2) if space.name.get.include?('G N1 Apartment')
    end

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    model.save("#{output_dir}/out.osm", true)
    assert(created_loops.size > 10)

    space = model.getSpaceByName('G N1 Apartment').get
    water_use_equip_def = space.waterUseEquipment[0].waterUseEquipmentDefinition
    assert(water_use_equip_def.name.get.include?('2 unit(s)'))
  end

  def test_create_typical_service_water_heating_secondary_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('DOE Ref 1980-2004')
    model = std.safe_load_model("#{__dir__}/../../doe_prototype/models/SecondarySchool_6A_1980-2004.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check the capacity and volume of the water heaters against Table A.1. Water Heating Equipment in PrototypeModelEnhancements_2014_0.pdf
    non_booster_capacity = 0.0 # combine kitchen and shared
    non_booster_volume = 0.0 # combine kitchen and shared
    swh_loop = model.getPlantLoopByName('Shared Service Water Loop').get
    booster_loop = model.getPlantLoopByName('Booster Service Water Loop').get

    # get shared loop water heater properties
    swh_loop.supplyComponents.each do |component|
      next if !component.to_WaterHeaterMixed.is_initialized

      water_heater = component.to_WaterHeaterMixed.get
      non_booster_capacity += water_heater.heaterMaximumCapacity.get
      non_booster_volume += water_heater.tankVolume.get
    end

    # get booster loop water heater properties
    booster_loop.supplyComponents.each do |component|
      next if !component.to_WaterHeaterMixed.is_initialized

      booster_water_heater = component.to_WaterHeaterMixed.get
      booster_capacity = booster_water_heater.heaterMaximumCapacity.get
      booster_capacity_kbtu_hr = OpenStudio::convert(booster_capacity, 'W', 'kBtu/hr').get
      assert_in_epsilon(22.0, booster_capacity_kbtu_hr, 0.25) # kBtu/hr
    end

    # convert to IP
    non_booster_capacity_kbtu_hr = OpenStudio::convert(non_booster_capacity, 'W', 'kBtu/hr').get
    non_booster_volume_gal = OpenStudio::convert(non_booster_volume, 'm^3', 'gal').get

    # check results
    assert_in_epsilon(264.0, non_booster_capacity_kbtu_hr, 0.40)
    assert_in_epsilon(264.0, non_booster_volume_gal, 0.40)
  end

  def test_create_typical_service_water_heating_large_hotel
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2010')
    model = std.safe_load_model("#{__dir__}/../../doe_prototype/models/LargeHotel_3A_2010.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check the capacity and volume of the water heaters against Table A.1. Water Heating Equipment in PrototypeModelEnhancements_2014_0.pdf
    non_booster_capacity = 0.0 # combine kitchen and shared
    non_booster_volume = 0.0 # combine kitchen and shared
    swh_loop = model.getPlantLoopByName('Shared Service Water Loop').get
    booster_loop = model.getPlantLoopByName('Booster Service Water Loop').get

    # get shared loop water heater properties
    swh_loop.supplyComponents.each do |component|
      next if !component.to_WaterHeaterMixed.is_initialized

      water_heater = component.to_WaterHeaterMixed.get
      non_booster_capacity += water_heater.heaterMaximumCapacity.get
      non_booster_volume += water_heater.tankVolume.get
    end

    # get booster loop water heater properties
    booster_loop.supplyComponents.each do |component|
      next if !component.to_WaterHeaterMixed.is_initialized

      booster_water_heater = component.to_WaterHeaterMixed.get
      booster_capacity = booster_water_heater.heaterMaximumCapacity.get
      booster_capacity_kbtu_hr = OpenStudio::convert(booster_capacity, 'W', 'kBtu/hr').get
      assert_in_epsilon(16.0, booster_capacity_kbtu_hr, 0.25) # kBtu/hr
    end

    # convert to IP
    non_booster_capacity_kbtu_hr = OpenStudio::convert(non_booster_capacity, 'W', 'kBtu/hr').get
    non_booster_volume_gal = OpenStudio::convert(non_booster_volume, 'm^3', 'gal').get

    # # check results
    assert_in_epsilon(315.7, non_booster_capacity_kbtu_hr, 0.40)
    assert_in_epsilon(315.7, non_booster_volume_gal, 0.40)
    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_midrise
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{__dir__}/../../doe_prototype/models/MidriseApartment_2A_2013.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check results
    assert_equal(23, created_loops.size, 'Expected 1 loop per apartment, for a total of 23 loops.')
  end

  def test_create_typical_service_water_heating_stripmall
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2004')
    model = std.safe_load_model("#{__dir__}/../../doe_prototype/models/RetailStripmall_2A_2004.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check results
    assert_equal(10, created_loops.size, 'Expected strip mall whole-building retail spaces to receive dedicated loops.')
  end

  def test_create_typical_service_water_heating_supermarket
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2004')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESuperMarket.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)
  end

  def test_create_typical_service_water_heating_multiuse
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # load model
    std = Standard.build('90.1-2010')
    model = std.safe_load_model("#{__dir__}/../../doe_prototype/models/Multiuse_Office_LargeHotel.osm")

    # add new standards space types and set additional properties
    std.prototype_space_type_map(model, set_additional_properties: true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)
  end

  def test_create_typical_service_water_heating_deer_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # create model
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'ESe'
    args['template'] = 'DEER 2011'
    result = OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(model, args)
    model.getBuilding.setStandardsBuildingType('ESe')

    # add new standards space types and set additional properties
    std = Standard.build('DEER 2011')
    std.prototype_space_type_map(model, set_additional_properties: true)

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert(created_loops.size > 0, "Expected at least one service water heating loop.")
  end
end
