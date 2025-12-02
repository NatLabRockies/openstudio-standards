require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# *** Needs a re-write to use std paths etc ***


#This test will check that the ERVs are added and the assignment from the erv.json library works.

class ECM_ERV_Tests < Minitest::Test

  def test_ecm_erv()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_ecm_erv')
    @expected_results_file = File.join(__dir__, '../expected_results/ecm_erv_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/ecm_erv-test_results.json')
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')

    # Intial test condition
    @test_passed = true

    #Range of test options.
    @templates = [
        'NECB2011',
        #'NECB2015',
        #'NECB2017'
    ]
    @building_types = [
        'FullServiceRestaurant',
        #'HighriseApartment',
        #'Hospital',
        #'LargeHotel',
        #'LargeOffice',
        #'MediumOffice',
        #'MidriseApartment',
        #'Outpatient',
        #'PrimarySchool',
        #'QuickServiceRestaurant',
        #'RetailStandalone',
        #'SecondarySchool',
        #'SmallHotel',
        #'Warehouse'
    ]
    @epw_files = ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw']
    #@epw_files = ['CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw']
    @primary_heating_fuels = ['Electricity']
    @erv_packages = ["NECB_Default","NECB_Default_All","Plate-Existing", 'Plate-All','Rotary-All']

    # Helper to print out numerical data to 3 sig figs.
    def roundOrNA(data, figs = 3)
      if data.is_a?(Numeric)
        return data.signif(figs)
      end
      return 'NA'
    end

    # Test results storage array.
    @test_results_array = []

    @templates.sort.each do |template|
      @epw_files.sort.each do |epw_file|
        @building_types.sort.each do |building_type|
          @primary_heating_fuels.sort.each do |primary_heating_fuel|
            @erv_packages.sort.each do |erv_package|
              standard = Standard.build(template)
              #puts "************* #{template}; #{erv_package}; #{epw_file}; #{building_type}; #{primary_heating_fuel}"
              model  = standard.model_create_prototype_model(template:template,
                                               building_type: building_type,
                                               epw_file: epw_file,
                                               sizing_run_dir: @sizing_run_dir,
                                               primary_heating_fuel: primary_heating_fuel,
                                               erv_package: erv_package
              )

              # Get number of ERVs
              result = {}
              result['building_type'] = building_type
              result['erv_package'] = erv_package

              ervs = model.getHeatExchangerAirToAirSensibleAndLatents
              result['number_of_ervs'] = ervs.length
              ervs.each { |erv| puts "##### #{erv}"}
              model.getAirLoopHVACs.each do |air_loop_hvac| 
                #puts "####### air loop kW #{standard.calculate_exhaust_heat(air_loop_hvac)}"
                #puts "####### has ERV #{standard.air_loop_hvac_energy_recovery_ventilator_required?(air_loop_hvac, 'NECB')}"
                erv_comp = air_loop_hvac.components('OS:HeatExchanger:AirToAir:SensibleAndLatent'.to_IddObjectType).first
                #puts "### ERV: #{erv_comp}"
                #puts "####### components #{air_loop_hvac.components('OS:HeatExchanger:AirToAir:SensibleAndLatent'.to_IddObjectType).first.name}"
              end
              if ervs.length >0
                heat_exchanger_air_to_air_sensible_and_latent = ervs[0]
                result['heatExchangerType'] = heat_exchanger_air_to_air_sensible_and_latent.heatExchangerType()
                result['sensibleEffectivenessat100HeatingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.sensibleEffectivenessat100HeatingAirFlow())
                result['latentEffectivenessat100HeatingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.latentEffectivenessat100HeatingAirFlow())
                result['sensibleEffectivenessat75HeatingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.sensibleEffectivenessat75HeatingAirFlow())
                result['latentEffectivenessat75HeatingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.latentEffectivenessat75HeatingAirFlow())
                result['sensibleEffectivenessat100CoolingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.sensibleEffectivenessat100CoolingAirFlow())
                result['latentEffectivenessat100CoolingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.latentEffectivenessat100CoolingAirFlow())
                result['sensibleEffectivenessat75CoolingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.sensibleEffectivenessat75CoolingAirFlow())
                result['latentEffectivenessat75CoolingAirFlow'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.latentEffectivenessat75CoolingAirFlow())
                result['supplyAirOutletTemperatureControl'] = heat_exchanger_air_to_air_sensible_and_latent.supplyAirOutletTemperatureControl()
                result['frostControlType'] = heat_exchanger_air_to_air_sensible_and_latent.frostControlType()
                result['economizerLockout'] = heat_exchanger_air_to_air_sensible_and_latent.economizerLockout()
                result['thresholdTemperature'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.thresholdTemperature())
                result['initialDefrostTimeFraction'] = roundOrNA(heat_exchanger_air_to_air_sensible_and_latent.initialDefrostTimeFraction().get)
              end
              #puts ">> #{result}"
              @test_results_array << result

            end #@erv_package.sort.each do |dcv_type|
          end #@primary_heating_fuels.sort.each do |primary_heating_fuel|
        end #@building_types.sort.each do |building_type|
      end #@epw_files.sort.each do |epw_file|
    end #@templates.sort.each do |template|


    # Save test results to file.
    File.open(@test_results_file, 'w') {|f| f.write(JSON.pretty_generate(@test_results_array))}

    # Compare results
    compare_message = ''
    # Check if expected file exists.
    if File.exist?(@expected_results_file)
      # Load expected results from file.
      @expected_results = JSON.parse(File.read(@expected_results_file))
      if @expected_results.size == @test_results_array.size
        # Iterate through each test result.
        @expected_results.each_with_index do |expected, row|
          # Compare if row /hash is exactly the same.
          if expected != @test_results_array[row]
            #if not set test flag to false
            @test_passed = false
            compare_message << "\nERROR: This row was different expected/result\n"
            compare_message << "EXPECTED:#{expected.to_s}\n"
            compare_message << "TEST:    #{@test_results_array[row].to_s}\n\n"
          end
        end
      else
        assert(false, "#{@expected_results_file} # of rows do not match the #{@test_results_array}..cannot compare")
      end
    else
      assert(false, "#{@expected_results_file} does not exist..cannot compare")
    end
    puts compare_message
    assert(@test_passed, "Error: This test failed to produce the same result as in the #{@expected_results_file}\n")
  end

end
