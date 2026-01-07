require_relative '../../helpers/minitest_helper'

class TestCreateTypicalServiceWaterHeating < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating

    # load model and set up weather file
    template = '90.1-2010'
    @climate_zone = 'ASHRAE 169-2013-2A'
    @std = Standard.build(template)

    # create output directory
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  def test_create_typical_service_water_heating_restaurant
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    model = @std.safe_load_model("#{__dir__}/../../os_stds_methods/models/QuickServiceRestaurant_2A_2010.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each(&:remove)

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert_equal(1, created_loops.size)

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    model = @std.safe_load_model("#{__dir__}/../../os_stds_methods/models/test_school.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert(created_loops.size > 1)

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_apartment_units
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    model = @std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEMidriseApartment.osm")
    model.save("#{output_dir}/in.osm", true)

    model.getSpaces.each do |space|
      space.additionalProperties.setFeature('num_units', 1) if space.name.get.include?('Apartment')
      space.additionalProperties.setFeature('num_units', 2) if space.name.get.include?('G N1 Apartment')
    end

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert(created_loops.size > 10)

    space = model.getSpaceByName('G N1 Apartment').get
    water_use_equip_def = space.waterUseEquipment[0].waterUseEquipmentDefinition
    assert(water_use_equip_def.name.get.include?('2 unit(s)'))

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_secondary_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # gather inputs
    template = 'DOE Ref 1980-2004'
    standard = Standard.build(template)

    model = standard.safe_load_model("#{__dir__}/../../doe_prototype/models/SecondarySchool_6A_1980-2004.osm")
    model.save("#{output_dir}/in.osm", true)

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
    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_large_hotel
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # gather inputs
    template = '90.1-2010'
    standard = Standard.build(template)

    model = standard.safe_load_model("#{__dir__}/../../doe_prototype/models/LargeHotel_3A_2010.osm")
    model.save("#{output_dir}/in.osm", true)

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
    assert_in_epsilon(215.0, non_booster_capacity_kbtu_hr, 0.40)
    assert_in_epsilon(215.0, non_booster_volume_gal, 0.40)
    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_midrise
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # gather inputs
    template = '90.1-2013'
    standard = Standard.build(template)

    model = standard.safe_load_model("#{__dir__}/../../doe_prototype/models/MidriseApartment_2A_2013.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check results
    assert_equal(15, created_loops.size, 'Expected 1 loop per apartment, for a total of 15 loops.')

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_stripmall
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # gather inputs
    template = '90.1-2004'
    standard = Standard.build(template)

    model = standard.safe_load_model("#{__dir__}/../../doe_prototype/models/RetailStripmall_2A_2004.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    # check results
    assert_equal(10, created_loops.size, 'Expected 1 loop per space, for a total of 10 loops.')

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_multiuse
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    # gather inputs
    template = '90.1-2010'
    standard = Standard.build(template)

    model = standard.safe_load_model("#{__dir__}/../../doe_prototype/models/Multiuse_Office_LargeHotel.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # create typical service water loops
    created_loops = @swh.create_typical_service_water_heating(model)

    model.save("#{output_dir}/out.osm", true)
  end

  def test_create_typical_service_water_heating_deer_school
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir

    model = @std.safe_load_model("#{__dir__}/../../deer_prototype/models/epr_test.osm")
    model.save("#{output_dir}/in.osm", true)

    # remove swh loops
    model.getPlantLoops.each { |swh_loop| swh_loop.remove unless (swh_loop.name == 'Hot Water Loop') }

    # default water heater
    created_loops = @swh.create_typical_service_water_heating(model)
    assert(created_loops.size > 1, "Expected more than 1 service water heating loop.")

    model.save("#{output_dir}/out.osm", true)
  end
end
