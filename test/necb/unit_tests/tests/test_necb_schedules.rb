require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This class will perform tests that are Spacetype dependant, Test model will be created
# to specifically test aspects of the NECB2011 code that are Spacetype dependant.
class NECB_Schedules_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end


  # Tests to ensure that the NECB default schedules are being defined correctly.
  def test_schedule_type_defaults()
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: true,
                        fuel_type: 'Electricity' }
    
    # Define test cases.
    test_cases = {}

    test_cases_hash = {
      vintage: ['NECB2011', 'NECB2015', 'BTAPPRE1980'], # @AllTemplates,
      :SpaceType => @SpaceTypes,
      TestCase: ["ZoneResults"],
      TestPars: {  } # Nothing specific in this case.
    }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), { symbolize_names: true })

    # Check if test results match expected.
    msg = "Default schedule test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

    
  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_schedule_type_defaults that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_schedule_type_defaults(test_pars:, test_case:)
    
    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"
    
    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    space_type = test_pars[:SpaceType]

    name = "#{vintage}_building_type_#{space_type}_schedule"
    name_short = "#{vintage}_#{space_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}/")
    logger.info "Starting individual test: #{name}"
    results = Array.new

    # (1) load fsr 3 zone model (2 occupied, 1 attic zone)
    # (2) loop through space types in the model and change them to the desired space type
    # (3) call standard.model_add_loads(model, 'NECB_Default', 1.0) 
    # (4) check ventilation

    # Wrap test in begin/rescue/ensure.
    begin
      
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "fsr.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
    

      # Create new model for testing.
      model = OpenStudio::Model::Model.new

      # Create only above ground geometry (Used for infiltration tests).
      length = 100.0; width = 100.0; num_above_ground_floors = 1; num_under_ground_floors = 0; floor_to_floor_height = 3.8 ; plenum_height = 1; perimeter_zone_depth = 4.57; initial_height = 10.0
      OpenstudioStandards::Geometry.create_shape_rectangle(model, length, width, num_above_ground_floors,num_under_ground_floors, floor_to_floor_height, plenum_height,perimeter_zone_depth, initial_height )

      output_array = []
      # Iterate through all spacetypes/buildingtypes.

      # Set applicable standard.
      standard = get_standard(vintage)
      search_criteria = {
        "template" => vintage,
      }

      # Lookup space type properties.
      standards_table = standard.standards_data['space_types']
      standard.model_find_objects(standards_table, search_criteria).each do |space_type_properties|

        # Create a space type.
        st = OpenStudio::Model::SpaceType.new(model)
        st.setStandardsBuildingType(space_type_properties['building_type'])
        st.setStandardsSpaceType(space_type_properties['space_type'])
        st.setName("#{vintage}-#{space_type_properties['building_type']}-#{space_type_properties['space_type']}")
        standard.space_type_apply_rendering_color(st)
        standard.model_add_loads(model, 'NECB_Default', 1.0)

        # Set all spaces to spacetype.
        model.getSpaces.each do |space|
          space.setSpaceType(st)
        end

        # Add Infiltration rates to the space objects themselves.
        standard.model_apply_infiltration_standard(model)


        # Get handle for space.
        space = model.getSpaces[0]
        space_area = space.floorArea #m2

        space_sched_array = []
        header_info = {
            "Space_Type" => st.name,
            "StandardsSpaceType" => st.standardsSpaceType.get,
            "StandardsBuildingType" => st.standardsBuildingType.get
        }

        unless header_info.nil?
          space_sched_array << header_info
        end

        # People / Occupancy.
        occ_scheds = []
        total_occ_dens = []
        occ_sched = []
        st.people.each {|people_def| total_occ_dens << people_def.peoplePerFloorArea ; occ_sched << people_def.numberofPeopleSchedule.get}
        assert(total_occ_dens.size <= 1 , "#{total_occ_dens.size} people definitions given. Expecting <= 1.")

        # Get occupancy rules from default occupancy ruleset and add to schedule array for this space type.
        unless occ_sched[0].nil?
          occ_sched[0].to_ScheduleRuleset.get.scheduleRules.sort.each do |occ_day|
            sched_entry = {
                "ScheduleName" => occ_day.daySchedule.name.get,
                "ScheduleTimes" => occ_day.daySchedule.times,
                "ScheduleValues" => occ_day.daySchedule.values
            }
            occ_scheds << sched_entry
          end
          occ_entry = {
              "ScheduleType" => occ_sched[0].name.get,
              "Schedules" => occ_scheds
          }
          space_sched_array << occ_entry
        end

        # Lights.
        lpd_scheds = []
        lpd_sched = []
        st.lights.each {|light| lpd_sched << light.schedule.get}
        assert(lpd_sched.size <= 1 , "#{lpd_sched.size} light definitions given. Expecting <= 1.")

        # Get lighting rules from default lighting ruleset and add to schedule array for this space type.
        unless lpd_sched[0].nil?
          lpd_sched[0].to_ScheduleRuleset.get.scheduleRules.sort.each do |lpd_day|
            sched_entry = {
                "ScheduleName" => lpd_day.daySchedule.name.get,
                "ScheduleTimes" => lpd_day.daySchedule.times,
                "ScheduleValues" => lpd_day.daySchedule.values
            }
            lpd_scheds << sched_entry
          end
          lpd_entry = {
              "ScheduleType" => lpd_sched[0].name.get,
              "Schedules" => lpd_scheds
          }
          space_sched_array << lpd_entry
        end

        # Equipment - Electric.
        elec_equip_scheds = []
        elec_equip_sched = []
        st.electricEquipment.each {|elec_equip| elec_equip_sched << elec_equip.schedule.get}
        assert( elec_equip_sched.size <= 1 , "#{elec_equip_sched.size} electric definitions given. Expecting <= 1." )

        # Get electrical equipment rules from default electrical equipment ruleset and add to schedule array for this space type.
        unless elec_equip_sched[0].nil?
          elec_equip_sched[0].to_ScheduleRuleset.get.scheduleRules.sort.each do |elec_day|
            sched_entry = {
                "ScheduleName" => elec_day.daySchedule.name.get,
                "ScheduleTimes" => elec_day.daySchedule.times,
                "ScheduleValues" => elec_day.daySchedule.values
            }
            elec_equip_scheds << sched_entry
          end
          elec_equip_entry = {
              "ScheduleType" => elec_equip_sched[0].name.get,
              "Schedules" => elec_equip_scheds
          }
          space_sched_array << elec_equip_entry
        end

        # Hot Water Equipment.
        swh_scheds = []
        hw_equip_power = []
        hw_equip_sched = []
        st.hotWaterEquipment.each {|equip| hw_equip_power << equip.powerPerFloorArea.get ; hw_equip_sched << equip.schedule.get.name}
        assert( hw_equip_power.size <= 1 , "#{hw_equip_power.size} hw definitions given. Expecting <= 1." )

        # SWH.
        swh_loop = OpenStudio::Model::PlantLoop.new(model)
        swh_peak_flow_per_area = []
        swh_heating_target_temperature = []
        swh__schedule = ""
        area_per_occ = 0.0
        area_per_occ = 1/total_occ_dens[0].to_f unless total_occ_dens[0].nil?
        water_fixture = standard.model_add_swh_end_uses_by_space(model, swh_loop, space)

        # Get swh schedule rules from swh equipment for this space type and add to schedule array for this space type.
        unless water_fixture.nil?
          swh__fraction_schedule = water_fixture.flowRateFractionSchedule.get.name
          water_fixture.flowRateFractionSchedule.get.to_ScheduleRuleset.get.scheduleRules.sort.each do |swh_day|
            sched_entry = {
                "ScheduleName" => swh_day.daySchedule.name.get,
                "ScheduleTimes" => swh_day.daySchedule.times,
                "ScheduleValues" => swh_day.daySchedule.values
            }
            swh_scheds << sched_entry
          end
          swh_entry = {
              "ScheduleType" => swh__fraction_schedule,
              "Schedules" => swh_scheds
          }
          space_sched_array << swh_entry
        end

        # Cycle through rulesets and determine which are the NECB heating and cooling setpoint schedules.  Get the
        # appropriate rules from these schedules and add them to the schedule array for this space type.
        model.getScheduleRulesets.sort.each do |sched_ruleset|
          ruleset_name = sched_ruleset.name.get
          if sched_ruleset.name.get.start_with?("NECB")
            if sched_ruleset.name.get.end_with?("Thermostat Setpoint-Heating")
              heat_sched = []
              sched_ruleset.scheduleRules.sort.each do |heat_set_day|
                sched_entry = {
                    "ScheduleName" => heat_set_day.daySchedule.name.get,
                    "ScheduleTimes" => heat_set_day.daySchedule.times,
                    "ScheduleValues" => heat_set_day.daySchedule.values
                }
                heat_sched << sched_entry
              end
              heat_entry = {
                  "ScheduleType" => sched_ruleset.name.get,
                  "Schedules" => heat_sched
              }
              space_sched_array << heat_entry
            elsif sched_ruleset.name.get.end_with?("Thermostat Setpoint-Cooling")
              cool_sched = []
              sched_ruleset.scheduleRules.sort.each do |cool_set_day|
                sched_entry = {
                    "ScheduleName" => cool_set_day.daySchedule.name.get,
                    "ScheduleTimes" => cool_set_day.daySchedule.times,
                    "ScheduleValues" => cool_set_day.daySchedule.values
                }
                cool_sched << sched_entry
              end
              cool_entry = {
                  "ScheduleType" => sched_ruleset.name.get,
                  "Schedules" => cool_sched
              }
              space_sched_array << cool_entry
            end
          end

          # remove the the schedule ruleset when done with it.  This prevents irrelevant schedules being carried over
          # to the next space type test.
          sched_ruleset.remove
        end

        # Add the schedules for this spacetype to giant output array.
        unless space_sched_array.empty?
          output_array << space_sched_array
        end

        # Remove space_type (This speeds things up a bit).
        st.remove
        swh_loop.remove
        water_fixture.remove unless water_fixture.nil?
      end # loop spacetypes
      
    rescue StandardError => error
      msg = "Model creation failed for #{vintage} #{space_type}\n#{__FILE__}::#{__method__} #{error.message}"
      logger.error(msg)
      return [ERROR: msg]
    end
    return output_array
  end
end