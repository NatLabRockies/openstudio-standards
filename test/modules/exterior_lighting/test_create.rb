require_relative '../../helpers/minitest_helper'

class TestExteriorLightingCreate < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @ext = OpenstudioStandards::ExteriorLighting
  end

  def test_model_create_exterior_lights
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    @ext.model_create_exterior_lights(model,
                                      name: 'Parking Areas and Drives',
                                      power: 0.04,
                                      units: 'W/ft^2',
                                      multiplier: 10000.0)
    lights = model.getExteriorLightsByName('Parking Areas and Drives 0.04 W/ft^2').get
    assert_in_delta(10000.0, lights.multiplier, 1.0)
    ext_lights_def = lights.exteriorLightsDefinition
    assert_in_delta(0.04, ext_lights_def.designLevel, 0.001)

    @ext.model_create_exterior_lights(model,
                                      name: 'Base Site Allowance',
                                      power: 1000.0)
    lights = model.getExteriorLightsByName('Base Site Allowance 1000.0 W').get
    assert_in_delta(1.0, lights.multiplier, 0.001)
    ext_lights_def = lights.exteriorLightsDefinition
    assert_in_delta(1000.0, ext_lights_def.designLevel, 0.001)
  end

  def test_create_typical_exterior_lighting
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/example_model_multipliers.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                            standard: Standard.build('90.1-2013'),
                                                            lighting_zone: 3,
                                                            add_base_site_allowance: true)
    # check results
    assert(exterior_lights.size == 5)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.1 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.15 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 30 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 20 W/ft' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.1 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.1)
    assert(parking_lighting.multiplier == 93150.0)
    base_lighting = exterior_lights.select { |e| e.name.get == 'Base Site Allowance 750 W' }[0]
    assert(base_lighting.exteriorLightsDefinition.designLevel == 750.0)
  end

  def test_create_typical_exterior_lighting_default
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/example_model_multipliers.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                            lighting_generation: 'default',
                                                            lighting_zone: 3,
                                                            add_base_site_allowance: true)
    # check results
    assert(exterior_lights.size == 5)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.04 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.15 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 30.0 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 20.0 W/ft' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.04 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.041)
    assert(parking_lighting.multiplier == 93150.0)
    base_lighting = exterior_lights.select { |e| e.name.get == 'Base Site Allowance 750.0 W' }[0]
    assert(base_lighting.exteriorLightsDefinition.designLevel == 750.0)
  end

  def test_create_typical_exterior_lighting_small_hotel
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/SmallHotel_5B_2004.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                            standard: Standard.build('90.1-2004'),
                                                            lighting_zone: 4)

    # check results
    assert(exterior_lights.size == 5)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.15 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.2 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 30 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 20 W/ft' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.15 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.15)
    assert_in_delta(31590.0, parking_lighting.multiplier, 100.0) # 405 ft^2 per spot * 78 rooms * 1 unit per spot
    main_entry_lighting = exterior_lights.select { |e| e.name.get == 'Main Entries 30 W/ft' }[0]
    assert_in_delta(17.28, main_entry_lighting.multiplier, 1.0) #  8 ft per entry * 2 entries per 10,000 ft^2 * 10,800 ft^2 ground floor area / 10,000 ft^2
    other_entry_lighting = exterior_lights.select { |e| e.name.get == 'Other Doors 20 W/ft' }[0]
    assert_in_delta(124.9, other_entry_lighting.multiplier, 1.0) #  4 ft per entry * 28.91 entries per 10,000 ft^2 * 10,800 ft^2 ground floor area / 10,000 ft^2
    entry_canopies_lighting = exterior_lights.select { |e| e.name.get == 'Entry Canopies 1.25 W/ft^2' }[0]
    assert_in_delta(720.0, entry_canopies_lighting.multiplier, 1.0)
    assert(entry_canopies_lighting.exteriorLightsDefinition.designLevel == 1.25)
  end

  def test_create_typical_exterior_lighting_hospital
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/Hospital_4B_Pre1980.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                                  standard: Standard.build('DOE Ref Pre-1980'),
                                                                  lighting_zone: 4)

    # check results
    assert(exterior_lights.size == 5)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.18 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.25 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 30.0 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 25.0 W/ft' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.18 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.18)
    assert_in_delta(122000.0, parking_lighting.multiplier, 1000.0) # 405 ft^2 per spot * 250 beds / 0.83 beds per spot
    emergency_canopies_lighting = exterior_lights.select { |e| e.name.get == 'Emergency Canopies 4.0 W/ft^2' }[0]
    assert_in_delta(720.0, emergency_canopies_lighting.multiplier, 1.0)
    assert(emergency_canopies_lighting.exteriorLightsDefinition.designLevel == 4.0)
  end

  def test_create_typical_exterior_lighting_secondary
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/SecondarySchool_6A_1980-2004.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                                  standard: Standard.build('DOE Ref 1980-2004'),
                                                                  lighting_zone: 2)

    # check results
    assert(exterior_lights.size == 4)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.18 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.25 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 30.0 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 25.0 W/ft' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.18 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.18)
  end

  def test_create_typical_exterior_lighting_quick_service
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{__dir__}/../../doe_prototype/models/QuickServiceRestaurant_2A_2010.osm")
    model = translator.loadModel(path)
    model = model.get

    # add lights
    exterior_lights = @ext.create_typical_exterior_lighting(model,
                                                            standard: Standard.build('90.1-2010'),
                                                            lighting_zone: 1)

    # check results
    assert(exterior_lights.size == 5)
    assert(!exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.04 W/ft^2' }.empty?)
    # assert(!exterior_lights.select { |e| e.name.get == 'Building Facades 0.0 W/ft^2' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Main Entries 20 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Other Doors 20 W/ft' }.empty?)
    assert(!exterior_lights.select { |e| e.name.get == 'Drive Through Windows 400 W/ft^2' }.empty?)
    parking_lighting = exterior_lights.select { |e| e.name.get == 'Parking Areas and Drives 0.04 W/ft^2' }[0]
    assert(parking_lighting.exteriorLightsDefinition.designLevel == 0.04)
    drive_lighting = exterior_lights.select { |e| e.name.get == 'Drive Through Windows 400 W/ft^2' }[0]
    assert_in_delta(1.0, drive_lighting.multiplier, 0.001) # 2501 ft^2 / drive through per 2501
  end
end
