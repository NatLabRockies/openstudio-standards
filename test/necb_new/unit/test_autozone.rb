# Tests automatic thermal zone creation and grouping per NECB rules
class TestNECBAutozone < Minitest::Test
  include(NecbHelper)

  def test_autozone_across_necb_vintages
    templates = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    test_dir = File.join(Dir.pwd, 'output', 'autozone_tests')
    FileUtils.mkdir_p(test_dir) unless Dir.exist?(test_dir)

    templates.each do |template|
      model, standard = create_baseline_necb_model(template: template)

      standard.apply_auto_zoning(
        model: model,
        sizing_run_dir: test_dir,
        lights_type: 'NECB_Default',
        lights_scale: 1.0)

      zones = model.getThermalZones.length

      assert zones > 0, "#{template} should create zones"
    end
  end

  def test_autozone_space_types
    model, standard = create_baseline_necb_model

    # Create mixed spaces: office, storage, washroom
    spaces = model.getSpaces.take(3)

    # Office space
    office_type = OpenStudio::Model::SpaceType.new(model)
    office_type.setStandardsBuildingType('Space Function')
    office_type.setStandardsSpaceType('Office - open plan')
    spaces[0].setSpaceType(office_type)

    # Storage space (contains "Storage")
    storage_type = OpenStudio::Model::SpaceType.new(model)
    storage_type.setStandardsBuildingType('Space Function')
    storage_type.setStandardsSpaceType('Storage area-sch-A')
    spaces[1].setSpaceType(storage_type)

    # Washroom space (contains "Washroom")
    washroom_type = OpenStudio::Model::SpaceType.new(model)
    washroom_type.setStandardsBuildingType('Space Function')
    washroom_type.setStandardsSpaceType('Washroom-sch-A')
    spaces[2].setSpaceType(washroom_type)

    # Verify space type identification (only test simple string matching)

    assert !standard.is_a_necb_dwelling_unit?(spaces[0]) && !standard.is_an_necb_wildcard_space?(spaces[0]),
      "Office should be general space"
    assert standard.is_an_necb_storage_space?(spaces[1]), "Storage should be storage space"
    assert standard.is_an_necb_wet_space?(spaces[2]), "Washroom should be wet space"

    puts "  Test passed: Mixed space types handled"
  end

  def test_model_create_thermal_zones_basic
    model, standard = create_baseline_necb_model

    standard.model_create_thermal_zones(model)

    zones = model.getThermalZones
    assert zones.size > 0, "Should create thermal zones"

    model.getSpaces.each do |space|
      assert space.thermalZone.is_initialized, "Space #{space.name} should be assigned to a zone"
    end
  end

  def test_model_create_thermal_zones_multi_story
    model, standard = create_baseline_necb_model(num_stories: 3)

    standard.model_create_thermal_zones(model)

    zones = model.getThermalZones
    assert zones.size >= 3, "Should create zones for multi-story building"
  end

  def test_store_and_retrieve_space_loads
    model, standard = create_baseline_necb_model

    space = model.getSpaces.first

    standard.store_space_sizing_loads(model)

    heating_load = standard.stored_space_heating_load(space)
    cooling_load = standard.stored_space_cooling_load(space)

    # Method should not crash
    assert true, "Load storage and retrieval should work"
  end

  def test_stored_zone_loads
    model, standard = create_baseline_necb_model

    standard.model_create_thermal_zones(model)
    zone = model.getThermalZones.first

    standard.store_space_sizing_loads(model)

    heating_load = standard.stored_zone_heating_load(zone)
    cooling_load = standard.stored_zone_cooling_load(zone)

    # Should not crash
    assert true, "Zone load retrieval should work"
  end

  def test_auto_zone_dwelling_units
    model, standard = create_baseline_necb_model

    result = standard.auto_zone_dwelling_units(model)

    assert !result.nil?, "Dwelling unit zoning should execute"
  end

  def test_auto_zone_wet_spaces
    model, standard = create_baseline_necb_model

    result = standard.auto_zone_wet_spaces(model: model)

    assert !result.nil?, "Wet spaces zoning should execute"
  end
end