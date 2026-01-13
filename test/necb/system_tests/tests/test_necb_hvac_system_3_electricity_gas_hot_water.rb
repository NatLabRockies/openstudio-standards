require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'


#This will run all the combinations possible with the inputs for each system.  The test will.
#0. Save the baseline file as baseline.osm
#1.	Add the system to the model using the hvac.rb routines and save that step as *.rb
#2.	Run the Standards methods and save that as the *.osm.
#3.	The name of the file will represent the combination used for that system
#4.	Only after all the system files are created the files will then be simulated.
#5.	Annual results will be contained in the Annual_results.csv file and failed simulations will be in the Failted.txt file.
#
#All output is in the test/output folder.
#Set the switch true to run the standards in the test
#PERFORM_STANDARDS = true
#Set to true to run the simulations.
#FULL_SIMULATIONS = true
#
#NOTE: The test will fail on the first error for each system to save time.
#NOTE: You can use Kdiff3 three file to select the baseline, *.hvac.rb, and *.osm
#      file for a three way diff of before sizing, and then standard application.
#NOTE: To focus on a single system type "dont_" in front of the tests you do not want to run.
#       EX: def dont_test_system_1()
# Hopefully this makes is easier to debug the HVAC stuff!


class NECB_HVAC_System_3_Test < Minitest::Test

  def test_necb_hvac_system_3_electricity_gas_hot_water()
    weather_file = 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'
    template_osm_file = "#{__dir__}/../resources/5ZoneNoHVAC.osm"
    system_name = 'system_3'
    vintage = 'NECB2011'
    boiler_fueltype = 'Electricity'
    baseboard_type = 'Hot Water'
    heating_coil_type_sys3 = 'Gas'

    output_folder = "#{File.dirname(__FILE__)}/output/test_necb_hvac_system_3_electricity_gas_hot_water"

    name = String.new
    # FileUtils.rm_rf(output_folder)
    FileUtils::mkdir_p(output_folder)
    standard = Standard.build(vintage)
    name = "sys3_Boiler-#{boiler_fueltype}_HeatingCoilType-#{heating_coil_type_sys3}_BaseboardType-#{baseboard_type}"
    puts "***************************************#{name}*******************************************************\n"
    model = standard.load_building_type_from_library(building_type: 'SmallOffice')

    standard.assign_building_activity(model: model)
    standard.assign_building_structure(model: model, activity: @activity, massive: false)
    standard.apply_weather_data(model: model, epw_file: weather_file)
    standard.assign_building_activity(model: model)
    standard.assign_building_structure(model: model, activity: @activity)
    standard.apply_loads(model: model)
    standard.apply_envelope(model: model)
    standard.apply_fdwr_srr_daylighting(model: model)
    standard.apply_auto_zoning(model: model, sizing_run_dir: output_folder)
    hw_loop = nil
    if (baseboard_type == "Hot Water")
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      standard.setup_hw_loop_with_components(model, hw_loop, boiler_fueltype, boiler_fueltype,model.alwaysOnDiscreteSchedule)
    end
    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
        model: model,
        zones: model.getThermalZones,
        heating_coil_type: heating_coil_type_sys3,
        baseboard_type: baseboard_type,
        hw_loop: hw_loop)
    #Save the model after btap hvac.
    BTAP::FileIO::save_osm(model, "#{output_folder}/#{name}.hvacrb")
    result = run_the_measure(model, standard, "#{output_folder}/#{name}/sizing")
    #Save model after standards
    BTAP::FileIO::save_osm(model, "#{output_folder}/#{name}.osm")
    assert_equal(true, result, "Failure in Standards for #{name}")
    #Run Sims
    result = standard.model_run_simulation_and_log_errors(model, "#{output_folder}/#{name}/")
    warnings = model.sqlFile().get().execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='0' ").get
    fatal = model.sqlFile().get().execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='2' ").get
    severe = model.sqlFile().get().execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='1' ").get
    if severe.size > 0 or fatal.size > 0
      puts "#############################ERRORS########################################"
      puts severe
      puts fatal
      result = false
    end
    assert_equal(true, result, "Failure in Standards for #{name}")
  end

  def run_the_measure(model, standard, sizing_dir)
    # Hard-code the building vintage
    building_type = 'FullServiceRestaurant' # Does not use this...
    climate_zone = 'NECB HDD Method'

    if !Dir.exist?(sizing_dir)
      FileUtils.mkdir_p(sizing_dir)
    end
    # Perform a sizing run
    if standard.model_run_sizing_run(model, "#{sizing_dir}/SizingRun1") == false
      puts "could not find sizing run #{sizing_dir}/SizingRun1"
      raise("could not find sizing run #{sizing_dir}/SizingRun1")
      return false
    else
      puts "found sizing run #{sizing_dir}/SizingRun1"
    end

    # BTAP::FileIO::save_osm(model, "#{File.dirname(__FILE__)}/before.osm")
    # need to set prototype assumptions so that HRV added
    standard.model_apply_prototype_hvac_assumptions(model, building_type, climate_zone)
    # Apply the HVAC efficiency standard
    standard.model_apply_hvac_efficiency_standard(model, climate_zone)
    #self.getCoilCoolingDXSingleSpeeds.sort.each {|obj| obj.setStandardEfficiencyAndCurves(self.template, self.standards)}
    # BTAP::FileIO::save_osm(model, "#{File.dirname(__FILE__)}/after.osm")
    return true
  end
end
