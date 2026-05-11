require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'

class TestSimControl < CreateDOEPrototypeBuildingTest

  def self.model_test(template, building_type)
    climate_zone = 'ASHRAE 169-2006-2A'
    epw_file = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'
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
    model = prototype_creator.model_create_prototype_model(climate_zone, epw_file, run_dir)
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

  def test_sim_control
    cases = {
        'FullServiceRestaurant' => 1.2,
        'Hospital' => 1.0,
        'HighriseApartment' => 1.2,
        'LargeHotel' => 1.0,
        'LargeOffice' => 1.0,
        'MediumOffice' => 1.0,
        'MidriseApartment' => 1.2,
        'Outpatient' => 1.0,
        'PrimarySchool' => 1.0,
        'QuickServiceRestaurant' => 1.2,
        'RetailStandalone' => 1.2,
        'SecondarySchool' => 1.0,
        'SmallHotel' => 1.2,
        'SmallOffice' => 1.2,
        'RetailStripmall' => 1.2,
        'Warehouse' => 1.2
    }
    templates = ['90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013']

    templates.each do |template|
      cases.each do |building_type, exp_factor|
        model = TestSimControl.model_test(template, building_type)
        timestep = model.getTimestep.numberOfTimestepsPerHour

        sizing_parameters = model.getSizingParameters
        htg_factor = sizing_parameters.heatingSizingFactor
        clg_factor = sizing_parameters.coolingSizingFactor
        sizing_timestep = sizing_parameters.timestepsinAveragingWindow

        convergence_limits = model.getConvergenceLimits
        min_sys_timestep = convergence_limits.minimumSystemTimestep
        max_hvac_iter = convergence_limits.maximumHVACIterations

        asserts = {
            'Timestep' => [timestep, 6],
            'Sizing:Parameters Heating Factor' => [htg_factor, exp_factor],
            'Sizing:Parameters Cooling Factor' => [clg_factor, exp_factor],
            'Sizing:Parameters Timesteps in Averaging Window' => [sizing_timestep, 6],
            'ConvergenceLimits Minimum System Timestep' => [min_sys_timestep, 1],
            'ConvergenceLimits Maximum HVAC Iterations' => [max_hvac_iter, 20]
        }
        asserts.each do |assert_key, assert_content|
          assert(assert_content[0].to_s.to_f == assert_content[1].to_s.to_f, "#{building_type} #{template} - #{assert_key} - #{assert_content[0]}:#{assert_content[1]}")
        end
      end
    end
  end
end
