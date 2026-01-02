require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)
require 'parallel'
require 'time'

# This class will perform tests to ensure that the NECB SHW tank and pump are being sized correctly and that the water
# use equipment are being defined correctly.  Test takes all space types defined in the appropriate NECB spacetypes.json
# file and applies them to the outpatient.osm file (actually, it just changes the name of the space types in the
# outpatient.osm file).
class ECM_SWH_Tests < Minitest::Test

  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the eff of water_heaters
  def test_add_swh_test_output_info
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: true,
                        baseboard_type: 'Hot Water',
                        heating_coil_type: 'DX' }

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 Table 6.2.2.1." }
    test_cases[:NECB2015] = { Reference: "NECB 2015 Table 6.2.2.1." }
    test_cases[:NECB2017] = { Reference: "NECB 2017 Table 6.2.2.1." }
    test_cases[:NECB2020] = { Reference: "NECB 2020 Table 6.2.2.1." }

    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: ["BTAPPRE1980", "BTAP1980TO2010", "NECB2011"],
                        fuel_type: ["NaturalGas"],
                        :shw_ecms => ["NECB_Default", "Natural Gas Power Vent with Electric Ignition"],
                        TestCase: ["AB_Calgary"],
                        TestPars: { :epw_file => "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: ["BTAPPRE1980", "BTAP1980TO2010", "NECB2011"],
                        fuel_type: ["NaturalGas"],
                        :shw_ecms => ["NECB_Default", "Natural Gas Power Vent with Electric Ignition"],
                        TestCase: ["NT_Yellowknife"],
                        TestPars: { :epw_file => "CAN_NT_Yellowknife.AP.719360_CWEC2020.epw" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), { symbolize_names: true })
    # Check if test results match expected.
    msg = "Water heater efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')

    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_add_swh_test_output_info that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_add_swh_test_output_info(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    fuel_type = test_pars[:fuel_type]
    shw_ecm = test_pars[:shw_ecms]
    epw_file = test_case[:epw_file]
    epw_file_name = epw_file.split(".")[0]
    # Define the test name.
    name = "#{vintage}_#{fuel_type}_#{epw_file_name}_#{shw_ecm}"
    name_short = "#{vintage}_#{fuel_type}_#{epw_file_name}_#{shw_ecm}"

    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    # get shw efficiency measure data from ECMS class shw_set.json
    ecm_standard = get_standard("ECMS")
    shw_measures = ecm_standard.standards_data['tables']['shw_eff_ecm']['table']

    results = {}
    output_array = []
    index = 0
    break_time = false
    # There are many more spacetypes in the spacetypes.json file than in Outpatient.osm.  The test takes the first
    # however many spacetypes can fit in Outpatient.osm from the spacetypes.json file and then applies them.  I
    # think it is 20 for NECB2011 and 18 for NECB2015.  It then runs the model_add_swh method from the NECB2011
    # standards class and gets information for the shw tank, pump, and water use equipment from the resulting model.
    # It then repeats the process until all spacetypes in the spacetypes.json file have been applied and testing
    # on the Outpatient file.

    # Configure variables that are constant during while loop (through space types).
    # Load model.
    model_orig = BTAP::FileIO.load_osm(File.join(@resources_folder, "NECB2011Outpatient.osm"))
    BTAP::FileIO.save_osm(model_orig, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

    # Get spacetypes from JSON.  I say I use all of the spacetypes but really it is only those with a
    # "buliding_type" of "Space Function".
    standard = get_standard(vintage)

    search_criteria = {
      "template" => vintage,
      "building_type" => "Space Function"
    }
    standards_table = standard.standards_data['space_types']
    space_type_data = standard.model_find_objects(standards_table, search_criteria)

    # Determine the total number of space types retrieved from the JSON file.
    space_type_data_size = space_type_data.size

    logger.info "Starting while loop"
    while break_time == false do

      # Need to reset the model each time, so do a deep copy and retrieve the space types. This is ~5x faster than 
      # loading the model here.
      model = model_orig.clone.to_Model
      space_types = model.getSpaceTypes.sort
      space_type_names = []

      # Go through each space type in the model and change its name to that of the next space type in the JSON file.
      space_types.each do |space_type|
        space_type.setNameProtected("Space Function" + " " + space_type_data[index]["space_type"])
        space_type_names << space_type.name
        # If you still have space types left in the JSON file go to the next one.  If not, start at the beginning
        # again and when you finish renaming the space types in the osm file go to the next weather location or
        # version of NECB (or stop when you are done).
        if index >= (space_type_data_size - 1)
          index = 0
          logger.info "Breaking from while loop"
          break_time = true
        else
          index += 1
        end
      end

      # apply swh to the renamed space types (model_add_swh only looks at the name of the space type not what is
      # actually in it).
      logger.info "model_add_swh"
      standard.model_add_swh(model: model, swh_fueltype: fuel_type, shw_scale: 'NECB_Default')

      # Apply the water heater mixed efficiencies.
      model.getWaterHeaterMixeds.sort.each { |obj| standard.water_heater_mixed_apply_efficiency(obj) }

      logger.info "extracting results"
      model.getWaterHeaterMixeds.sort.each do |waterheater_test|
        wh_name = waterheater_test.name
        if waterheater_test.heaterFuelType == "NaturalGas"
          shw_measure = shw_measures.select { |shw_measure_info| shw_measure_info["name"] == shw_ecm }[0]
          ecm_standard.modify_shw_efficiency(model: model, shw_eff: shw_measure)
        end
        add_shw_test_output_info(model: model, output_array: output_array, template: vintage, epw_file: epw_file, space_type_names: space_type_names)
      end
    end
    logger.info "Completed individual test: #{name}"
    results[name] = output_array
    return results
  end

  def add_shw_test_output_info(model:, output_array:, template:, epw_file:, space_type_names:)

    # Go through the model and check what tank, pump, and water use connections were added.
    plantloops = model.getPlantLoops

    # Before doing anything check if any plant loops are present.  If it is continue, otherwise skip to the next
    # set of space types.
    unless plantloops.empty?

      # Start with the demand components (water use connections).
      demand_comps = plantloops[0].demandComponents
      water_conns = []
      demand_equip_info = []

      # Get all the water use connections and add them to an array.
      demand_comps.sort.each do |demand_comp|
        if demand_comp.iddObjectType.valueName.to_s == "OS_WaterUse_Connections"
          water_conns << demand_comp.to_WaterUseConnections.get
        end
      end

      # Go through the water use connections and get the flow rate and schedule information.
      water_conns.sort.each do |water_conn|
        day_scheds = []
        water_equip = water_conn.waterUseEquipment
        flow_rate_fract_sched = water_equip[0].flowRateFractionSchedule.get.to_ScheduleRuleset.get
        flow_rate_fract_sched.scheduleRules.sort.each do |sched_rule|
          day_sched = {
            "day_sched_name" => sched_rule.daySchedule.name,
            "times" => sched_rule.daySchedule.times,
            "values" => sched_rule.daySchedule.values
          }
          day_scheds << day_sched
        end

        # The next bit of code truncates the flow rate because sometimes the last digit will change depending on
        # the vagaries of Ruby, the processor, whatever and cause the test to fail when really it should have
        # passed.  Thinking about this more I made it way too complicated.  I could have just truncated the result
        # but decided to keep the same number of (non-zero) significant digits regardless of if the result was
        # scaled by 10E-6 or 10E-7 the two common ones).  Hence the next few lines of code where I check if the flow
        # rate is 10E-6 or 10E-7, keep the result to 12 digits, then convert it back to the right flow rate.
        water_equip_def = water_equip[0].waterUseEquipmentDefinition
        digit_exponent = 10 ** 7
        last_digit_check = water_equip_def.peakFlowRate * digit_exponent
        if last_digit_check >= 10
          digit_exponent = 10 ** 6
        end
        exponent_mult = (10 ** 12) * digit_exponent
        last_digit_check = (water_equip_def.peakFlowRate * exponent_mult).to_i
        water_flow_out = last_digit_check.to_f / exponent_mult

        # Put the water use equipment name, flow rate, and schedule in a hash
        equip_info = {
          "equip_name" => water_equip[0].name,
          "flow_rate_m3_per_s" => water_flow_out,
          "day_schedules" => day_scheds
        }

        # Add the above hash containing info for all of the water use equipment defined in the model.
        demand_equip_info << equip_info
      end
      pumps = []
      water_heaters = []

      # Next get the supply component information.
      supply_comps = plantloops[0].supplyComponents

      # Go through each of the supply components and get either the pumps or the water heaters.
      supply_comps.sort.each do |supplycomp|
        case supplycomp.iddObjectType.valueName.to_s
        when 'OS_Pump_ConstantSpeed'
          pumps << supplycomp.to_PumpConstantSpeed.get
        when 'OS_WaterHeater_Mixed'
          water_heaters << supplycomp.to_WaterHeaterMixed.get
        end
      end

      # Add the water heater tank volume and capacity and the pump head and moter efficiency to a hash.  Although
      # I collect all of the pumps and water heaters in the plant loop above here I assume there is only one of
      # each in the model.  I really should check, but I don't.
      # Adding water heater efficiency and part load curve (if one is applied).
      part_load_curve_name = "none"
      if water_heaters[0].partLoadFactorCurve.is_initialized
        part_load_curve_name = water_heaters[0].partLoadFactorCurve.get.name.to_s
      end
      supply_equip_info = {
        "water_heater_fuel_type" => water_heaters[0].heaterFuelType,
        "water_heater_vol_m3" => water_heaters[0].tankVolume,
        "water_heater_capacity_w" => water_heaters[0].heaterMaximumCapacity,
        "water_heater_efficiency" => water_heaters[0].heaterThermalEfficiency,
        "water_heater_part_load_curve_name" => part_load_curve_name,
        "pump_head_Pa" => pumps[0].ratedPumpHead.to_f.round(8),
        "pump_motor_eff" => pumps[0].motorEfficiency
      }

      # make hash containing the template applied, weather file used, water heater name, space types applied (or
      # I should say renamed), the supply equipment info (from the supply_equip_info hash) and demand equipment info
      # (from the demand_equip_info array defined above).
      set_output = {
        "template" => template,
        "epw_file" => epw_file,
        "water_heater_name" => water_heaters[0].name,
        "space_types" => space_type_names,
        "suppy_equipment" => supply_equip_info,
        "demand_equipment" => demand_equip_info
      }

      # Add this hash to an array containing the same info for all of the sets of space types applied to the model.
      output_array << set_output
    end
  end
end