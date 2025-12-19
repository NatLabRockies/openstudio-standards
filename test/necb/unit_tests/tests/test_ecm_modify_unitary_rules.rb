require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class NECB_HVAC_Unitary_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the cooling efficiency generated against expected values stored in files:
  # 'modify_unitary_carrier_weather_expert_expected_results.csv' and
  # 'modify_unitary_lennox_ultra_high_efficiency_expected_results.csv'
  def test_modify_unitary_efficiency

    # Set up remaining parameters for test.
    output_folder = method_output_folder
    templates = ['NECB2015'] #list of templates
    save_intermediate_models = false

    # Generate the osm files for all relevant cases to generate the test data for system 3.
    fuel_type = 'NaturalGas'
    baseboard_type = 'Hot Water'
    unitary_heating_types = ['Electric Resistance', 'All Other']
    unitary_ecms = ['Carrier WeatherExpert','Lennox Model L Ultra High Efficiency']
    num_cap_intv = {'Carrier WeatherExpert' => 4,'Lennox Model L Ultra High Efficiency' => 12}
    speeds = ['single']

    templates.each do |template|
      unitary_ecms.each do |unitary_ecm|
        unitary_expected_result_file = File.join(@expected_results_folder, "ecm_modify_unitary_#{unitary_ecm.downcase.gsub(' ','_')}_expected_results.csv")
        standard = get_standard(template)
        ecm = get_standard('ECMS')
        unitary_res_file_output_text = "Heating Type,Min Capacity (W),Max Capacity (W),Seasonal Energy Efficiency Ratio (SEER),Energy Efficiency Ratio (EER),Coefficient of Performance (COP)\n"

        # Initialize hashes for storing expected unitary efficiency data from file.
        heating_type_min_cap = {}
        heating_type_min_cap['Electric Resistance'] = []
        heating_type_min_cap['All Other'] = []
        heating_type_max_cap = {}
        heating_type_max_cap['Electric Resistance'] = []
        heating_type_max_cap['All Other'] = []
        efficiency_type = {}
        efficiency_type['Electric Resistance'] = []
        efficiency_type['All Other'] = []

        # Read the file for the expected unitary efficiency values for different heating types and equipment capacity ranges.
        CSV.foreach(unitary_expected_result_file, headers: true) do |data|
          heating_type_min_cap[data['Heating Type']] << data['Min Capacity (W)']
          heating_type_max_cap[data['Heating Type']] << data['Max Capacity (W)']
          if data['Seasonal Energy Efficiency Ratio (SEER)'].to_f > 0.0
            efficiency_type[data['Heating Type']] << 'Seasonal Energy Efficiency Ratio (SEER)'
          elsif data['Energy Efficiency Ratio (EER)'].to_f > 0.0
            efficiency_type[data['Heating Type']] << 'Energy Efficiency Ratio (EER)'
          elsif data['Coefficient of Performance (COP)'].to_f > 0.0
            efficiency_type[data['Heating Type']] << 'Coefficient of Performance (COP)'
          end
        end

        # Use the expected unitary efficiency data to generate suitable equipment capacities for the test to cover all
        # the relevant equipment capacity ranges.
        heating_type_cap = {}
        heating_type_min_cap.each do |heating_type, cap|
          unless heating_type_cap.key? heating_type then
            heating_type_cap[heating_type] = []
          end
          for i in 0..num_cap_intv[unitary_ecm] - 2
            heating_type_cap[heating_type] << 0.5 * (heating_type_min_cap[heating_type][i].to_f + heating_type_min_cap[heating_type][i + 1].to_f)
          end
          heating_type_cap[heating_type] << (heating_type_min_cap[heating_type][num_cap_intv[unitary_ecm] - 1].to_f + 10000.0)
        end

        speeds.each do |speed|
          actual_unitary_cop = {}
          actual_unitary_cop['Electric Resistance'] = []
          actual_unitary_cop['All Other'] = []
          unitary_heating_types.each do |heating_type|
            if heating_type == 'Electric Resistance'
              heating_coil_type = 'Electric'
            elsif heating_type == 'All Other'
              heating_coil_type = 'Gas'
            end
            heating_type_cap[heating_type].each do |unitary_cap|
              name = "#{unitary_ecm.delete(' ')}_sys3_MuaHtgCoilType~#{heating_coil_type}_Speed~#{speed}_UnitaryCap~#{unitary_cap}watts"
              name.gsub!(/\s+/, "-")
              puts "***************#{name}***************\n"

              # Load model and set climate file.
              model = BTAP::FileIO.load_osm(File.join(@resources_folder,"5ZoneNoHVAC.osm"))
              weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
              OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
              BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

              hw_loop = OpenStudio::Model::PlantLoop.new(model)
              always_on = model.alwaysOnDiscreteSchedule
              standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
              case speed
              when 'single'
                standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model: model,
                                                                                                          zones: model.getThermalZones,
                                                                                                          heating_coil_type: heating_coil_type,
                                                                                                          baseboard_type: baseboard_type,
                                                                                                          hw_loop: hw_loop,
                                                                                                          new_auto_zoner: false)
                model.getCoilCoolingDXSingleSpeeds.each do |dxcoil|
                  dxcoil.setRatedTotalCoolingCapacity(unitary_cap)
                  flow_rate = unitary_cap * 5.0e-5
                  dxcoil.setRatedAirFlowRate(flow_rate)
                end
              end

              # Run sizing.
              sql_db_vars_map = {}
              ecm.modify_unitary_cop(model: model, unitary_cop: "#{unitary_ecm}", sizing_done: false, sql_db_vars_map: sql_db_vars_map)
              run_sizing(model: model, template: template, save_model_versions: save_intermediate_models, output_dir: output_folder)
              ecm.modify_unitary_cop(model: model, unitary_cop: "#{unitary_ecm}", sizing_done: true, sql_db_vars_map: sql_db_vars_map)

              case speed
              when 'single'
                actual_unitary_cop[heating_type] << model.getCoilCoolingDXSingleSpeeds[0].ratedCOP.to_f
              end
            end
          end

          # Generate table of test unitary efficiencies
          actual_unitary_eff = {}
          actual_unitary_eff['Electric Resistance'] = []
          actual_unitary_eff['All Other'] = []
          unitary_heating_types.each do |heating_type|
            output_line_text = ''
            for int in 0..heating_type_cap[heating_type].size - 1
              output_line_text += "#{heating_type},#{heating_type_min_cap[heating_type][int]},#{heating_type_max_cap[heating_type][int]},"
              if efficiency_type[heating_type][int] == 'Seasonal Energy Efficiency Ratio (SEER)'
                actual_unitary_eff[heating_type][int] = (OpenstudioStandards::HVAC.cop_no_fan_to_seer(actual_unitary_cop[heating_type][int].to_f) + 0.001).round(2)
                output_line_text += "#{actual_unitary_eff[heating_type][int]},,\n"
              elsif efficiency_type[heating_type][int] == 'Energy Efficiency Ratio (EER)'
                actual_unitary_eff[heating_type][int] = (OpenstudioStandards::HVAC.cop_no_fan_to_eer(actual_unitary_cop[heating_type][int].to_f) + 0.001).round(2)
                output_line_text += ",#{actual_unitary_eff[heating_type][int]},\n"
              elsif efficiency_type[heating_type][int] == 'Coefficient of Performance (COP)'
                actual_unitary_eff[heating_type][int] = sprintf('%.2f', actual_unitary_cop[heating_type][int].to_f)
                output_line_text += ",,#{actual_unitary_eff[heating_type][int]}\n"
              end
            end
            unitary_res_file_output_text += output_line_text
          end

          # Write actual results file
          test_result_file = File.join(@test_results_folder, "ecm_modify_unitary_#{unitary_ecm.downcase.gsub(' ','_')}-test_results.csv")
          File.open(test_result_file, 'w') {|f| f.write(unitary_res_file_output_text.chomp)}
          # Test that the values are correct by doing a file compare.
          b_result = FileUtils.compare_file(unitary_expected_result_file, test_result_file)
          assert(b_result,
                 "test_unitary_efficiency: Unitary efficiency test results do not match expected results! Compare/diff the output with the stored values here #{unitary_expected_result_file} and #{test_result_file}")

        end
      end
    end
  end

end
