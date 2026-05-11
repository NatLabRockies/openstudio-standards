require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'

class TestDaylighting_Ctrl < CreateDOEPrototypeBuildingTest

  def self.model_test(template, building_type, climate_zone)
    epw_file_name = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'
    @test_dir = "#{__dir__}/output"
    if !Dir.exist?(@test_dir)
      Dir.mkdir(@test_dir)
    end
    model_name = "#{building_type}-#{template}-#{climate_zone}"
    run_dir = "#{@test_dir}/#{model_name}"
    if !Dir.exist?(run_dir)
        Dir.mkdir(run_dir)
    end
    prototype_creator = Standard.build("#{template}_#{building_type}")
    model = prototype_creator.model_create_prototype_model(climate_zone, epw_file_name, run_dir)
    osm_path_string = "#{run_dir}/#{model_name}.osm"
    osm_path = OpenStudio::Path.new(osm_path_string)
    idf_path_string = "#{run_dir}/#{model_name}.idf"
    idf_path = OpenStudio::Path.new(idf_path_string)
    model.save(osm_path, true)
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
    idf = forward_translator.translateModel(model)
    idf.save(idf_path,true)

    return model
  end

  def test_daylighting_ctrl
    # Small Office
    template = '90.1-2010'
    building_type = 'SmallOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_ZN_3 Daylt Sensor 2" => [24.3664, 16.8598, 0.762],
                         "Perimeter_ZN_1 Daylt Sensor 1" => [3.3236, 1.6002, 0.762],
                         "Perimeter_ZN_4 Daylt Sensor 1" => [1.6002, 15.1364, 0.762],
                         "Perimeter_ZN_2 Daylt Sensor 1" => [26.0898, 3.3236, 0.762],
                         "Perimeter_ZN_1 Daylt Sensor 2" => [8.9611, 1.6002, 0.762],
                         "Perimeter_ZN_2 Daylt Sensor 2" => [26.0898, 9.23, 0.762],
                         "Perimeter_ZN_3 Daylt Sensor 1" => [13.8684, 16.8598, 0.762],
                         "Perimeter_ZN_4 Daylt Sensor 2" => [1.6002, 9.2446, 0.762]}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Small Office - 2010 - 2A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_ZN_1" => [0.02, 0.1],
                         "Attic" => [1.0, 0.0],
                         "Perimeter_ZN_2" => [0.06, 0.15],
                         "Perimeter_ZN_3" => [0.1, 0.02],
                         "Perimeter_ZN_4" => [0.06, 0.15],
                         "Core_ZN"=>[1.0, 0.0]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Small Office - 2010 - 2A - Fraction Incorrect')
    end

    # Small Office
    template = '90.1-2013'
    building_type = 'SmallOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_ZN_3 Daylt Sensor 2" => [18.288, 15.1925, 0.762],
                         "Perimeter_ZN_1 Daylt Sensor 1" => [9.144, 1.6337, 0.762],
                         "Perimeter_ZN_4 Daylt Sensor 1" => [1.6337, 9.144, 0.762],
                         "Perimeter_ZN_2 Daylt Sensor 1" => [26.0898, 9.144, 0.762],
                         "Perimeter_ZN_1 Daylt Sensor 2" => [9.144, 3.2675, 0.762],
                         "Perimeter_ZN_2 Daylt Sensor 2" => [24.4561, 9.144, 0.762],
                         "Perimeter_ZN_3 Daylt Sensor 1" => [18.288, 16.825, 0.762],
                         "Perimeter_ZN_4 Daylt Sensor 2" => [3.2675, 9.144, 0.762]}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Small Office - 2013 - 2A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_ZN_1" => [0.2399, 0.0302],
                         "Attic" => [1.0, 0.0],
                         "Perimeter_ZN_2" => [0.2399, 0.0302],
                         "Perimeter_ZN_3" => [0.2399, 0.0302],
                         "Perimeter_ZN_4" => [0.2399, 0.0302],
                         "Core_ZN"=>[1.0, 0.0]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Small Office - 2013 - 2A - Fraction Incorrect')
    end

    # Medium Office
    template = '90.1-2010'
    building_type = 'MediumOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_bot_ZN_1 Daylt Sensor 1" => [3.048, 1.524, 0.762],
                         "Perimeter_bot_ZN_1 Daylt Sensor 2" => [24.9555, 1.524, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 2" => [48.387, 3.048, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 1" => [24.9514, 31.7498, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 2" => [46.863, 31.7498, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 2" => [1.524, 30.2514, 0.762],
                         "Perimeter_mid_ZN_1 Daylt Sensor 1" => [3.048, 1.524, 4.7244],
                         "Perimeter_mid_ZN_1 Daylt Sensor 2" => [24.9555, 1.524, 4.7244],
                         "Perimeter_mid_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 4.7244],
                         "Perimeter_mid_ZN_2 Daylt Sensor 2" => [48.387, 3.048, 4.7244],
                         "Perimeter_mid_ZN_3 Daylt Sensor 1" => [24.9514, 31.7498, 4.7244],
                         "Perimeter_mid_ZN_3 Daylt Sensor 2" => [46.863, 31.7498, 4.7244],
                         "Perimeter_mid_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 4.7244],
                         "Perimeter_mid_ZN_4 Daylt Sensor 2" => [1.524, 30.2514, 4.7244],
                         "Perimeter_top_ZN_1 Daylt Sensor 1" => [3.048, 1.524, 8.687],
                         "Perimeter_top_ZN_1 Daylt Sensor 2" => [24.9555, 1.524, 8.687],
                         "Perimeter_top_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 8.687],
                         "Perimeter_top_ZN_2 Daylt Sensor 2" => [48.387, 3.048, 8.687],
                         "Perimeter_top_ZN_3 Daylt Sensor 1" => [24.9514, 31.7498, 8.687],
                         "Perimeter_top_ZN_3 Daylt Sensor 2" => [46.863, 31.7498, 8.687],
                         "Perimeter_top_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 8.687],
                         "Perimeter_top_ZN_4 Daylt Sensor 2" => [1.524, 30.2514, 8.687],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Medium Office - 2010 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_bot_ZN_1" => [0.08, 0.46],
                         "Perimeter_bot_ZN_2" => [0.43, 0.12],
                         "Perimeter_bot_ZN_3" => [0.46, 0.08],
                         "Perimeter_bot_ZN_4" => [0.43, 0.12],
                         "Perimeter_mid_ZN_1" => [0.08, 0.46],
                         "Perimeter_mid_ZN_2" => [0.43, 0.12],
                         "Perimeter_mid_ZN_3" => [0.46, 0.08],
                         "Perimeter_mid_ZN_4" => [0.43, 0.12],
                         "Perimeter_top_ZN_1" => [0.08, 0.46],
                         "Perimeter_top_ZN_2" => [0.43, 0.12],
                         "Perimeter_top_ZN_3" => [0.46, 0.08],
                         "Perimeter_top_ZN_4" => [0.43, 0.12]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Medium Office - 2010 - 1A - Fraction Incorrect')
      end
    end

    # Medium Office
    template = '90.1-2013'
    building_type = 'MediumOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_bot_ZN_1 Daylt Sensor 1" => [24.9555, 1.524, 0.762],
                         "Perimeter_bot_ZN_1 Daylt Sensor 2" => [24.9555, 3.048, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 2" => [46.863, 16.6369, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 1" => [24.9555, 31.7498, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 2" => [24.9555, 30.2258, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 2" => [3.048, 16.6369, 0.762],
                         "Perimeter_mid_ZN_1 Daylt Sensor 1" => [24.9555, 1.524, 4.7244],
                         "Perimeter_mid_ZN_1 Daylt Sensor 2" => [24.9555, 3.048, 4.7244],
                         "Perimeter_mid_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 4.7244],
                         "Perimeter_mid_ZN_2 Daylt Sensor 2" => [46.863, 16.6369, 4.7244],
                         "Perimeter_mid_ZN_3 Daylt Sensor 1" => [24.9555, 31.7498, 4.7244],
                         "Perimeter_mid_ZN_3 Daylt Sensor 2" => [24.9555, 30.2258, 4.7244],
                         "Perimeter_mid_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 4.7244],
                         "Perimeter_mid_ZN_4 Daylt Sensor 2" => [3.048, 16.6369, 4.7244],
                         "Perimeter_top_ZN_1 Daylt Sensor 1" => [24.9555, 1.524, 8.687],
                         "Perimeter_top_ZN_1 Daylt Sensor 2" => [24.9555, 3.048, 8.687],
                         "Perimeter_top_ZN_2 Daylt Sensor 1" => [48.387, 16.6369, 8.687],
                         "Perimeter_top_ZN_2 Daylt Sensor 2" => [46.863, 16.6369, 8.687],
                         "Perimeter_top_ZN_3 Daylt Sensor 1" => [24.9555, 31.7498, 8.687],
                         "Perimeter_top_ZN_3 Daylt Sensor 2" => [24.9555, 30.2258, 8.687],
                         "Perimeter_top_ZN_4 Daylt Sensor 1" => [1.524, 16.6369, 8.687],
                         "Perimeter_top_ZN_4 Daylt Sensor 2" => [3.048, 16.6369, 8.687],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Medium Office - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_bot_ZN_1" => [0.3835, 0.1395],
                         "Perimeter_bot_ZN_2" => [0.3835, 0.1395],
                         "Perimeter_bot_ZN_3" => [0.3835, 0.1395],
                         "Perimeter_bot_ZN_4" => [0.3835, 0.1395],
                         "Perimeter_mid_ZN_1" => [0.3835, 0.1395],
                         "Perimeter_mid_ZN_2" => [0.3835, 0.1395],
                         "Perimeter_mid_ZN_3" => [0.3835, 0.1395],
                         "Perimeter_mid_ZN_4" => [0.3835, 0.1395],
                         "Perimeter_top_ZN_1" => [0.3835, 0.1395],
                         "Perimeter_top_ZN_2" => [0.3835, 0.1395],
                         "Perimeter_top_ZN_3" => [0.3835, 0.1395],
                         "Perimeter_top_ZN_4" => [0.3835, 0.1395]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Medium Office - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Large Office
    template = '90.1-2010'
    building_type = 'LargeOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_bot_ZN_1 Daylt Sensor 1" => [3.1242, 1.6764, 0.762],
                         "Perimeter_bot_ZN_1 Daylt Sensor 2" => [36.5536, 1.6764, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 1" => [71.4308, 24.3691, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 2" => [71.4308, 3.1242, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 1" => [36.5536, 47.0617, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 2" => [70.0034, 47.0617, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 1" => [1.6764, 24.3691, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 2" => [1.6764, 45.6194, 0.762],
                         "Perimeter_mid_ZN_1 Daylt Sensor 1" => [3.1242, 1.6764, 17.526],
                         "Perimeter_mid_ZN_1 Daylt Sensor 2" => [36.5536, 1.6764, 17.526],
                         "Perimeter_mid_ZN_2 Daylt Sensor 1" => [71.4308, 24.3691, 17.526],
                         "Perimeter_mid_ZN_2 Daylt Sensor 2" => [71.4308, 3.1242, 17.526],
                         "Perimeter_mid_ZN_3 Daylt Sensor 1" => [36.5536, 47.0617, 17.526],
                         "Perimeter_mid_ZN_3 Daylt Sensor 2" => [70.0034, 47.0617, 17.526],
                         "Perimeter_mid_ZN_4 Daylt Sensor 1" => [1.6764, 24.3691, 17.526],
                         "Perimeter_mid_ZN_4 Daylt Sensor 2" => [1.6764, 45.6194, 17.526],
                         "Perimeter_top_ZN_1 Daylt Sensor 1" => [3.1242, 1.6764, 34.29],
                         "Perimeter_top_ZN_1 Daylt Sensor 2" => [36.5536, 1.6764, 34.29],
                         "Perimeter_top_ZN_2 Daylt Sensor 1" => [71.4308, 24.3691, 34.29],
                         "Perimeter_top_ZN_2 Daylt Sensor 2" => [71.4308, 3.1242, 34.29],
                         "Perimeter_top_ZN_3 Daylt Sensor 1" => [36.5536, 47.0617, 34.29],
                         "Perimeter_top_ZN_3 Daylt Sensor 2" => [70.0034, 47.0617, 34.29],
                         "Perimeter_top_ZN_4 Daylt Sensor 1" => [1.6764, 24.3691, 34.29],
                         "Perimeter_top_ZN_4 Daylt Sensor 2" => [1.6764, 45.6194, 34.29],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Large Office - 2010 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_bot_ZN_1" => [0.05, 0.51],
                         "Perimeter_bot_ZN_2" => [0.49, 0.08],
                         "Perimeter_bot_ZN_3" => [0.51, 0.05],
                         "Perimeter_bot_ZN_4" => [0.49, 0.08],
                         "Perimeter_mid_ZN_1" => [0.05, 0.51],
                         "Perimeter_mid_ZN_2" => [0.49, 0.08],
                         "Perimeter_mid_ZN_3" => [0.51, 0.05],
                         "Perimeter_mid_ZN_4" => [0.49, 0.08],
                         "Perimeter_top_ZN_1" => [0.05, 0.51],
                         "Perimeter_top_ZN_2" => [0.49, 0.08],
                         "Perimeter_top_ZN_3" => [0.51, 0.05],
                         "Perimeter_top_ZN_4" => [0.49, 0.08]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Large Office - 2010 - 1A - Fraction Incorrect')
      end
    end

    # Large Office
    template = '90.1-2013'
    building_type = 'LargeOffice'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Perimeter_bot_ZN_1 Daylt Sensor 1" => [36.576, 1.6764, 0.762],
                         "Perimeter_bot_ZN_1 Daylt Sensor 2" => [36.576, 3.3528, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 1" => [71.4308, 24.384, 0.762],
                         "Perimeter_bot_ZN_2 Daylt Sensor 2" => [69.7544, 24.384, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 1" => [36.576, 47.0617, 0.762],
                         "Perimeter_bot_ZN_3 Daylt Sensor 2" => [36.576, 45.3847, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 1" => [1.6764, 24.384, 0.762],
                         "Perimeter_bot_ZN_4 Daylt Sensor 2" => [3.3528, 24.384, 0.762],
                         "Perimeter_mid_ZN_1 Daylt Sensor 1" => [36.576, 1.6764, 17.526],
                         "Perimeter_mid_ZN_1 Daylt Sensor 2" => [36.576, 3.3528, 17.526],
                         "Perimeter_mid_ZN_2 Daylt Sensor 1" => [71.4308, 24.384, 17.526],
                         "Perimeter_mid_ZN_2 Daylt Sensor 2" => [69.7544, 24.384, 17.526],
                         "Perimeter_mid_ZN_3 Daylt Sensor 1" => [36.576, 47.0617, 17.526],
                         "Perimeter_mid_ZN_3 Daylt Sensor 2" => [36.576, 45.3847, 17.526],
                         "Perimeter_mid_ZN_4 Daylt Sensor 1" => [1.6764, 24.384, 17.526],
                         "Perimeter_mid_ZN_4 Daylt Sensor 2" => [3.3528, 24.384, 17.526],
                         "Perimeter_top_ZN_1 Daylt Sensor 1" => [36.576, 1.6764, 34.29],
                         "Perimeter_top_ZN_1 Daylt Sensor 2" => [36.576, 3.3528, 34.29],
                         "Perimeter_top_ZN_2 Daylt Sensor 1" => [71.4308, 24.384, 34.29],
                         "Perimeter_top_ZN_2 Daylt Sensor 2" => [69.7544, 24.384, 34.29],
                         "Perimeter_top_ZN_3 Daylt Sensor 1" => [36.576, 47.0617, 34.29],
                         "Perimeter_top_ZN_3 Daylt Sensor 2" => [36.576, 45.3847, 34.29],
                         "Perimeter_top_ZN_4 Daylt Sensor 1" => [1.6764, 24.384, 34.29],
                         "Perimeter_top_ZN_4 Daylt Sensor 2" => [3.3528, 24.384, 34.29]}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Large Office - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Perimeter_bot_ZN_1" => [0.3857, 0.1385],
                         "Perimeter_bot_ZN_2" => [0.3857, 0.1385],
                         "Perimeter_bot_ZN_3" => [0.3857, 0.1385],
                         "Perimeter_bot_ZN_4" => [0.3857, 0.1385],
                         "Perimeter_mid_ZN_1" => [0.3857, 0.1385],
                         "Perimeter_mid_ZN_2" => [0.3857, 0.1385],
                         "Perimeter_mid_ZN_3" => [0.3857, 0.1385],
                         "Perimeter_mid_ZN_4" => [0.3857, 0.1385],
                         "Perimeter_top_ZN_1" => [0.3857, 0.1385],
                         "Perimeter_top_ZN_2" => [0.3857, 0.1385],
                         "Perimeter_top_ZN_3" => [0.3857, 0.1385],
                         "Perimeter_top_ZN_4" => [0.3857, 0.1385]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Large Office - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Warehouse
    template = '90.1-2010'
    building_type = 'Warehouse'
    climate_zone = 'ASHRAE 169-2013-6A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Zone3 Bulk Storage Daylt Sensor 1" => [6.096, 45.718514, 0],
                         "Zone1 Office Daylt Sensor 1" => [2.4384, 2.4384, 0.762],
                         "Zone1 Office Daylt Sensor 2" => [20.4216, 1.6154, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Warehouse - 2010 - 6A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Zone3 Bulk Storage" => [0.116, 0],
                         "Zone1 Office" => [0.11, 0.11]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Warehouse - 2010 - 6A - Fraction Incorrect')
      end
    end

    # Warehouse
    template = '90.1-2010'
    building_type = 'Warehouse'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Zone3 Bulk Storage Daylt Sensor 1" => [22.9, 48, 0],
                         "Zone3 Bulk Storage Daylt Sensor 2" => [22.9, 34.7, 0],
                         "Zone2 Fine Storage Daylt Sensor 1" => [27.8892, 24.9936, 0.762],
                         "Zone2 Fine Storage Daylt Sensor 2" => [3.81, 24.9936, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      # @todo Office should not have daylighting control
      if true_daylght_ctrl.include?(daylght_ctrl.name.to_s)
        assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Warehouse - 2010 - 1A - Sensor Position Incorrect')
      end
    end
    true_daylght_ctrl = {"Zone3 Bulk Storage" => [0.25, 0.25],
                         "Zone2 Fine Storage" => [0.25, 0.25]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Warehouse - 2010 - 1A - Fraction Incorrect')
      end
    end

    # Warehouse
    template = '90.1-2013'
    building_type = 'Warehouse'
    climate_zone = 'ASHRAE 169-2013-6A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Zone3 Bulk Storage Daylt Sensor 1" => [6.096, 45.718514, 0],
                         "Zone1 Office Daylt Sensor 1" => [3.2675, 4.5718, 0.762],
                         "Zone1 Office Daylt Sensor 2" => [20.4216, 4.5718, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Warehouse - 2013 - 6A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Zone3 Bulk Storage" => [0.116, 0],
                         "Zone1 Office" => [0.29, 0.1]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Warehouse - 2013 - 6A - Fraction Incorrect')
      end
    end

    # Warehouse
    template = '90.1-2013'
    building_type = 'Warehouse'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Zone1 Office Daylt Sensor 1" => [3.2675, 4.5718, 0.762],
                         "Zone1 Office Daylt Sensor 2" => [20.4216, 4.5718, 0.762],
                         "Zone3 Bulk Storage Daylt Sensor 1" => [22.9, 48, 0],
                         "Zone3 Bulk Storage Daylt Sensor 2" => [22.9, 34.7, 0],
                         "Zone2 Fine Storage Daylt Sensor 1" => [27.8892, 24.9936, 0.762],
                         "Zone2 Fine Storage Daylt Sensor 2" => [3.81, 24.9936, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Warehouse - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Zone1 Office" => [0.29, 0.1],
                         "Zone3 Bulk Storage" => [0.25, 0.25],
                         "Zone2 Fine Storage" => [0.25, 0.25]}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Warehouse - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Full Service Restaurant
    template = '90.1-2010'
    building_type = 'FullServiceRestaurant'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Dining Daylt Sensor 1" => [1.9812, 1.9812, 0.762],
                         "Dining Daylt Sensor 2" => [20.574, 1.9812, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Full Service Restaurant - 2010 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Dining" => [0.135, 0.135],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Full Service Restaurant - 2010 - 1A - Fraction Incorrect')
      end
    end

    # Full Service Restaurant
    template = '90.1-2013'
    building_type = 'FullServiceRestaurant'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Dining Daylt Sensor 1" => [2.6548, 2.6548, 0.762],
                         "Dining Daylt Sensor 2" => [19.9539, 2.6548, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Full Service Restaurant - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Dining" => [0.25, 0.25],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Full Service Restaurant - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Quick Service Restaurant
    template = '90.1-2010'
    building_type = 'QuickServiceRestaurant'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Dining Daylt Sensor 1" => [1.9812, 1.9812, 0.762],
                         "Dining Daylt Sensor 2" => [13.2588, 1.9812, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Full Service Restaurant - 2010 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Dining" => [0.22, 0.22],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Full Service Restaurant - 2010 - 1A - Fraction Incorrect')
      end
    end

    # Full Service Restaurant
    template = '90.1-2013'
    building_type = 'QuickServiceRestaurant'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Dining Daylt Sensor 1" => [2.6548, 2.6548, 0.762],
                         "Dining Daylt Sensor 2" => [12.588, 2.6548, 0.762],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Full Service Restaurant - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Dining" => [0.38, 0.38],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Full Service Restaurant - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Retail Standalone
    template = '90.1-2013'
    building_type = 'RetailStandalone'
    climate_zone = 'ASHRAE 169-2013-1A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Core_Retail Daylt Sensor 1" => [14.2, 14.2, 0],
                         "Core_Retail Daylt Sensor 2" => [3.4, 14.2, 0],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Standalone Retail - 2013 - 1A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Core_Retail" => [0.25, 0.25],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Standalone Retail - 2013 - 1A - Fraction Incorrect')
      end
    end

    # Retail Standalone
    template = '90.1-2013'
    building_type = 'RetailStandalone'
    climate_zone = 'ASHRAE 169-2013-8A'
    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
    true_daylght_ctrl = {"Core_Retail Daylt Sensor 1" => [9.144, 24.698, 0],}
    model.getDaylightingControls.each do |daylght_ctrl|
      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Standalone Retail - 2013 - 8A - Sensor Position Incorrect')
    end
    true_daylght_ctrl = {"Core_Retail" => [0.1724, 0],}
    model.getSpaces.each do |space|
      zone = space.thermalZone.get
      if true_daylght_ctrl.keys.include? (space.name.to_s)
        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Standalone Retail - 2013 - 8A - Fraction Incorrect')
      end
    end

#    # Secondary School
#    # @todo finish aligning the daylighting controls input
#    template = '90.1-2010'
#    building_type = 'SecondarySchool'
#    climate_zone = 'ASHRAE 169-2013-1A'
#    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
#    true_daylght_ctrl = {"Gym_ZN_1_FLR_1 Daylt Sensor 1" => [19, 24, 0],
#                         "Gym_ZN_1_FLR_1 Daylt Sensor 2" => [2, 24, 0],
#                         "Aux_Gym_ZN_1_FLR_1 Daylt Sensor 1" => [12, 24, 0],
#                         "Aux_Gym_ZN_1_FLR_1 Daylt Sensor 2" => [2, 24, 0],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [1.6764, 4.5, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [5.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [13.2588, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [39.7764, 1.6764, 0.762],
#                         "Offices_ZN_1_FLR_1 Daylt Sensor 1" => [18.9982, 1.6764, 0.762],
#                         "Offices_ZN_1_FLR_1 Daylt Sensor 2" => [36.3322, 7.0104, 0.762],
#                         "Offices_ZN_1_FLR_2 Daylt Sensor 1" => [18.9982, 1.6764, 0.762],
#                         "Offices_ZN_1_FLR_2 Daylt Sensor 2" => [36.3322, 7.0104, 0.762],}
#    model.getDaylightingControls.each do |daylght_ctrl|
#      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Secondary School - 2010 - 1A - Sensor Position Incorrect')
#    end
#    true_daylght_ctrl = {'Auditorium_ZN_1_FLR_1 ZN' => [0.125, 0.125],
#                         'Aux_Gym_ZN_1_FLR_1 ZN' => [0.5, 0.5],
#                         'Cafeteria_ZN_1_FLR_1 ZN' => [0.095, 0.095],
#                         'Corner_Class_1_Pod_1_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_1_Pod_1_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Corner_Class_1_Pod_2_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_1_Pod_2_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Corner_Class_1_Pod_3_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_1_Pod_3_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_1_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_1_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_2_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_2_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_3_ZN_1_FLR_1 ZN' => [0.22, 0.22],
#                         'Corner_Class_2_Pod_3_ZN_1_FLR_2 ZN' => [0.22, 0.22],
#                         'Gym_ZN_1_FLR_1 ZN' => [0.5, 0.5],
#                         'LIBRARY_MEDIA_CENTER_ZN_1_FLR_2 ZN' => [0.085, 0.085],
#                         'Lobby_ZN_1_FLR_1 ZN' => [0.09, 0.09],
#                         'Lobby_ZN_1_FLR_2 ZN' => [0.09, 0.09],
#                         'Mult_Class_1_Pod_1_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_1_Pod_1_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_1_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_1_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Mult_Class_1_Pod_2_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_1_Pod_2_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_2_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_2_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Mult_Class_1_Pod_3_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_1_Pod_3_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_3_ZN_1_FLR_1 ZN' => [0.14, 0.14],
#                         'Mult_Class_2_Pod_3_ZN_1_FLR_2 ZN' => [0.14, 0.14],
#                         'Offices_ZN_1_FLR_1 ZN' => [0.115, 0.115],
#                         'Offices_ZN_1_FLR_2 ZN' => [0.115, 0.115],}
#    model.getSpaces.each do |space|
#      zone = space.thermalZone.get
#      if true_daylght_ctrl.keys.include? (space.name.to_s)
#        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Secondary School - 2010 - 1A - Fraction Incorrect')
#      end
#    end
#
#    # Secondary School
#    template = '90.1-2013'
#    building_type = 'SecondarySchool'
#    climate_zone = 'ASHRAE 169-2013-1A'
#    model = TestDaylighting_Ctrl.model_test(template, building_type, climate_zone)
#    true_daylght_ctrl = {"Gym_ZN_1_FLR_1 Daylt Sensor 1" => [19, 24, 0],
#                         "Gym_ZN_1_FLR_1 Daylt Sensor 2" => [2, 24, 0],
#                         "Aux_Gym_ZN_1_FLR_1 Daylt Sensor 1" => [12, 24, 0],
#                         "Aux_Gym_ZN_1_FLR_1 Daylt Sensor 2" => [2, 24, 0],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [7.6198, 3.3711, 0.762],
#                         "Corner_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [3.3711, 6.0313, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_1_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_1_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_2_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_1 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 1" => [26.5, 1.6764, 0.762],
#                         "Mult_Class_2_Pod_3_ZN_1_FLR_2 Daylt Sensor 2" => [26.5, 3.3528, 0.762],
#                         "Offices_ZN_1_FLR_1 Daylt Sensor 1" => [18.9982, 3.3528, 0.762],
#                         "Offices_ZN_1_FLR_1 Daylt Sensor 2" => [34.6472, 7.0104, 0.762],
#                         "Offices_ZN_1_FLR_2 Daylt Sensor 1" => [18.9982, 3.3528, 0.762],
#                         "Offices_ZN_1_FLR_2 Daylt Sensor 2" => [34.6472, 7.0104, 0.762],}
#    model.getDaylightingControls.each do |daylght_ctrl|
#      assert([daylght_ctrl.positionXCoordinate.to_f, daylght_ctrl.positionYCoordinate.to_f, daylght_ctrl.positionZCoordinate.to_f] == true_daylght_ctrl[daylght_ctrl.name.to_s], 'Secondary School - 2013 - 1A - Sensor Position Incorrect')
#    end
#    true_daylght_ctrl = {'Auditorium_ZN_1_FLR_1 ZN' => [0.125, 0.125],
#                         'Aux_Gym_ZN_1_FLR_1 ZN' => [0.5, 0.5],
#                         'Cafeteria_ZN_1_FLR_1 ZN' => [0.21, 0.15],
#                         'Corner_Class_1_Pod_1_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_1_Pod_1_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Corner_Class_1_Pod_2_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_1_Pod_2_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Corner_Class_1_Pod_3_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_1_Pod_3_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_1_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_1_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_2_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_2_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_3_ZN_1_FLR_1 ZN' => [0.56, 0.2],
#                         'Corner_Class_2_Pod_3_ZN_1_FLR_2 ZN' => [0.56, 0.2],
#                         'Gym_ZN_1_FLR_1 ZN' => [0.5, 0.5],
#                         'LIBRARY_MEDIA_CENTER_ZN_1_FLR_2 ZN' => [0.21, 0.11],
#                         'Lobby_ZN_1_FLR_1 ZN' => [0.18, 0.18],
#                         'Lobby_ZN_1_FLR_2 ZN' => [0.18, 0.18],
#                         'Mult_Class_1_Pod_1_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_1_Pod_1_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_1_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_1_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Mult_Class_1_Pod_2_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_1_Pod_2_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_2_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_2_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Mult_Class_1_Pod_3_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_1_Pod_3_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_3_ZN_1_FLR_1 ZN' => [0.28, 0.28],
#                         'Mult_Class_2_Pod_3_ZN_1_FLR_2 ZN' => [0.28, 0.28],
#                         'Offices_ZN_1_FLR_1 ZN' => [0.36, 0.08],
#                         'Offices_ZN_1_FLR_2 ZN' => [0.36, 0.08],}
#    model.getSpaces.each do |space|
#      zone = space.thermalZone.get
#      if true_daylght_ctrl.keys.include? (space.name.to_s)
#        assert([zone.fractionofZoneControlledbyPrimaryDaylightingControl, zone.fractionofZoneControlledbySecondaryDaylightingControl] == true_daylght_ctrl[space.name.to_s], 'Secondary School - 2013 - 1A - Fraction Incorrect')
#      end
#    end

  end
end