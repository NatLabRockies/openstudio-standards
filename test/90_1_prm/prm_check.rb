require_relative './prm_check_helpers'

class AppendixGPRMTests < Minitest::Test
  # Check baseline outdoor air setting
  # @param prototypes_base [Hash] Baseline prototypes
  def check_baseline_oa(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      model_baseline.getDesignSpecificationOutdoorAirs.each do |dsoa|
        if dsoa.name.get == 'Office WholeBuilding - Md Office Ventilation'
          assert((dsoa.outdoorAirFlowperFloorArea - 0.0004).abs < 0.00001, "The baseline design specification outdoor air fail to updated to 0.0004 m3/s-m2, get actual #{dsoa.outdoorAirFlowperFloorArea}")
        end
      end
    end
  end

  def check_building_rotation_exception(prototypes_base, test_string)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      @test_dir = "#{File.dirname(__FILE__)}/output"
      mod_str = mod.flatten.join('_') unless mod.empty?
      model_baseline_file_name = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-Baseline/baseline_final.osm" : "#{building_type}-#{template}-#{climate_zone}-#{user_data_dir}-#{mod.flatten.join('_') unless mod.empty?}-Baseline/baseline_final.osm"
      model_baseline_file_name_90 = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-Baseline/baseline_final_90.osm" : "#{building_type}-#{template}-#{climate_zone}-#{user_data_dir}-#{mod.flatten.join('_') unless mod.empty?}-Baseline/baseline_final_90.osm"
      model_baseline_file_name_180 = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-Baseline/baseline_final_180.osm" : "#{building_type}-#{template}-#{climate_zone}-#{user_data_dir}-#{mod.flatten.join('_') unless mod.empty?}-Baseline/baseline_final_180.osm"
      model_baseline_file_name_270 = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-Baseline/baseline_final_270.osm" : "#{building_type}-#{template}-#{climate_zone}-#{user_data_dir}-#{mod.flatten.join('_') unless mod.empty?}-Baseline/baseline_final_270.osm"
      rotated = File.exist?("#{@test_dir}/#{model_baseline_file_name}") && File.exist?("#{@test_dir}/#{model_baseline_file_name_90}") && File.exist?("#{@test_dir}/#{model_baseline_file_name_180}") && File.exist?("#{@test_dir}/#{model_baseline_file_name_270}")

      if mod.empty?
        # test case 1 - rotation
        assert(rotated == true, 'Small Office with default WWR shall rotate orientations, but it didnt')
      elsif mod == 'change_wwr_model_0.4_0.4_0.4_0.4'
        # test case 2 - true
        assert(rotated == true, 'Small Office with updated WWR (0.4, 0.4, 0.4, 0.4) shall rotate orientations, but it didnt')
      elsif mod == 'change_wwr_model_0.4_0.4_0.6_0.6'
        assert(rotated == false, 'Small Office with updated WWR (0.4, 0.4, 0.6, 0.6) do not need to rotate, but it did rotate')
      end
    end
  end

  def check_computer_rooms_equipment_schedule(model_info)
    model_info.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype

      model.getSpaces.each do |space|
        if prm_get_optional_handler(space, @sizing_run_dir, 'spaceType', 'standardsSpaceType') == 'computer room'
          space.spaceType.get.electricEquipment.each do |elec_equipment|
            assert(elec_equipment.schedule.get.name.to_s == 'ASHRAE 90.1 Appendix G - Computer Room Equipment Schedule')
          end
        end
      end
    end
  end

  # Check that no daylighting controls are modeled in the baseline models
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_daylighting_control(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      # Check the model include daylighting control objects
      model_baseline.getSpaces.sort.each do |space|
        existing_daylighting_controls = space.daylightingControls
        assert(existing_daylighting_controls.empty?, "The baseline model for the #{building_type}-#{template} in #{climate_zone} has daylighting control.")
      end
    end
  end

  def check_dcv(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mods = prototype

      # to simplify testing procedures, for all test cases below, the following are true
      #   - zone area is larger than 500 sqft
      #   - air loop has economizer

      tc_ids = nil
      mods.each do |mod|
        if mod[0] == 'mark_test_case_no'
          tc_ids = mod[1]
        end
      end
      if tc_ids.nil?
        assert(false, 'mark_test_case_no mod not set, cannot proceed with DCV test check_dcv')
      end

      tc_ids.each do |tc_id|
        case tc_id
        when 1
          # test case 1:
          #   - DCV should be in the user model (zone ppl density > 25 ppl/ksqft, no user exception)
          #   - DCV should be in the baseline (air loop oa flow > 3000 cfm && zone ppl density > 100 ppl/ksqft)
          #   - DCV is implemented in user model
          # expected result: baseline implements DCV
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - no user data needed
          #   - zone ppl density 101 [through ppl density modifier]
          #   - DCV implemented in the user model
          #     - at the airloop level [through modifier]
          #     - at the zone level, zone oa spec per person 0.003539605824
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(dcv_is_on(zone, airloop))

        when 2
          # test case 2:
          #   - DCV should not be in the user model (zone ppl density > 25 ppl/ksqft, but has ZONE user exception)
          #   - DCV should be in the baseline (air loop oa flow > 3000 cfm && zone ppl density > 100 ppl/ksqft)
          #   - DCV is implemented in user model
          # expected result: baseline implements DCV but prompts warning (user model has DCV but meet exception)
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - zone ppl density 101 [through ppl density modifier]
          #   - user data specifies ZONE DCV exception is true
          #   - DCV implemented in the user model
          #     - at the airloop level [through modifier]
          #     - at the zone level, zone oa spec per person 0.003539605824
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          # check warning
          assert(dcv_is_on(zone, airloop))

        when 3
          # test case 3:
          #   - DCV should be in the user model (zone ppl density > 25 ppl/ksqft, no user exception)
          #   - DCV should be in the baseline model (air loop oa flow > 3000 cfm && zone ppl density > 100 ppl/ksqft)
          #   - DCV is NOT implemented in user model
          # expected result: error and terminate
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - zone ppl density 101 [through ppl density modifier]
          #   - no user data
          #   - DCV not implemented in the user model
          #     - at the airloop level by default
          #     - at the zone level [through remove_zone_oa_per_person_spec modifier] (optional)
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          # check error and terminate
          assert(!dcv_is_on(zone, airloop))

        when 4
          # test case 4:
          #   - DCV should not be in the user model (zone ppl density > 25 ppl/ksqft, but has AIR LOOP user exception)
          #   - DCV should be in the baseline model (air loop oa flow > 3000 cfm && zone ppl density > 100 ppl/ksqft)
          #   - DCV is NOT implemented in user model
          # expected result: no DCV in baseline model
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - zone ppl density 101 [through ppl density modifier]
          #   - user data specifies AIR LOOP DCV exception is true
          #   - DCV not implemented in the user model
          #     - at the airloop level by default
          #     - at the zone level [through remove_zone_oa_per_person_spec modifier] (optional)
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(!dcv_is_on(zone, airloop))

        when 5
          # test 5
          #   - DCV should be in the user model (zone ppl density > 25 ppl/ksqft, no user exception)
          #   - DCV should NOT be in the baseline model (air loop oa flow < 3000 cfm || zone ppl density < 100 ppl/ksqft)
          #   - DCV is implmented in user model
          # expected result: no DCV in baseline model
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - zone ppl density 99.99
          #   - no user exception
          #   - DCV implemented in the user model
          #     - at the airloop level [through modifier]
          #     - at the zone level, zone oa spec per person 0.003539605824
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(!dcv_is_on(zone, airloop))

        when 6
          # test 6
          #   - DCV should NOT be in the user model (zone ppl density > 25 ppl/ksqft, but has ZONE user exception)
          #   - DCV should NOT be in the baseline model (air loop oa flow < 3000 cfm || zone ppl density < 100 ppl/ksqft)
          #   - DCV is NOT implemented in user model
          # expected result: NO DCV in baseline model
          # test case setting:
          #   - Cafeteria
          #   - user model air loop oa flow 3153 cfm
          #   - zone ppl density 99.99
          #   - user data specifies ZONE DCV exception is true
          #   - DCV NOT implemented in the user model
          #     - at the airloop level by default
          #     - at the zone level [through remove_zone_oa_per_person_spec modifier] (optional)
          zone = model_baseline.getThermalZoneByName('Cafeteria_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(!dcv_is_on(zone, airloop))

        when 7
          # test 7
          #   - DCV should NOT be in the user model (zone ppl density < 25 ppl/ksqft)
          #   - DCV should NOT be in the baseline model (air loop oa flow < 3000 cfm || zone ppl density < 100 ppl/ksqft)
          #   - DCV is implemented in user model
          # expected result: no DCV in baseline model
          # test case setting:
          #   - Kitchen
          #   - user model air loop oa flow 528 cfm
          #   - zone ppl density 14.93
          #   - no user exception
          #   - DCV implemented in the user model
          #     - at the airloop level [through modifier]
          #     - at the zone level, zone oa spec per person 0.003539605824
          zone = model_baseline.getThermalZoneByName('Kitchen_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(!dcv_is_on(zone, airloop))

        when 8
          # test 8
          #   - DCV should NOT be in the user model (zone ppl denstiy < 25 ppl/ksqft)
          #   - DCV should NOT be in the baseline model (air loop oa flow < 3000 cfm || zone ppl density < 100 ppl/ksqft)
          #   - DCV is NOT implemented in user model
          # expected result: no DCV in baseline model
          # test case setting:
          #   - Kitchen
          #   - user model air loop oa flow 528 cfm
          #   - zone ppl density 14.93
          #   - no user exception
          #   - DCV not implemented in the user model
          #     - at the airloop level by default
          #     - at the zone level [through remove_zone_oa_per_person_spec modifier] (optional)
          zone = model_baseline.getThermalZoneByName('Kitchen_ZN_1_FLR_1 ZN').get
          airloop = zone.airLoopHVAC.get
          assert(!dcv_is_on(zone, airloop))
        else
          assert(false, "ERROR! #{tc_id} not a valid test case id for check_dcv")
        end
      end
    end
  end

  def check_economizer_exception(baseline_base)
    baseline_base.each do |baseline, baseline_model|
      building_type, template, climate_zone, user_data_dir, mod = baseline
      baseline_model.getAirLoopHVACs.each do |air_loop|
        economizer_activated_target = false
        temperature_highlimit_target = 23.89
        air_loop_name = air_loop.name.get
        baseline_system_type = air_loop.additionalProperties.getFeatureAsString('baseline_system_type')
        if ['Building Story 3 VAV_PFP_Boxes (Sys8)', 'DataCenter_top_ZN_6 ZN PSZ-VAV', 'DataCenter_basement_ZN_6 ZN PSZ-VAV', 'Basement Story 0 VAV_PFP_Boxes (Sys8)'].include?(air_loop_name) && climate_zone.end_with?('2B')
          economizer_activated_target = true
        end

        economizer_activated_model = false
        temperature_highlimit_model = 23.89
        oa_sys = air_loop.airLoopHVACOutdoorAirSystem
        if oa_sys.is_initialized
          economizer_activated_model = true unless oa_sys.get.getControllerOutdoorAir.getEconomizerControlType == 'NoEconomizer'
          if economizer_activated_model
            temperature_highlimit_model = oa_sys.get.getControllerOutdoorAir.getEconomizerMaximumLimitDryBulbTemperature.get
          end
        end

        assert(economizer_activated_model == economizer_activated_target,
               "#{building_type}_#{template} is in #{climate_zone}. Air loop #{air_loop.name.get} system type is #{baseline_system_type}. The target economizer flag should be #{economizer_activated_target} but get #{economizer_activated_model}")

        temp_diff = temperature_highlimit_model - temperature_highlimit_target
        assert(temp_diff.abs <= 0.01,
               "#{building_type}_#{template} is in #{climate_zone}. Air loop #{air_loop.name.get} system type is #{baseline_system_type}. The target economizer temperature high limit setpoint is #{temperature_highlimit_target} but get #{temperature_highlimit_model}")
      end
    end
    return true
  end

  #
  # testing baseline elevator implementation
  #
  # @param prototypes_base [Hash] Baseline prototypes
  #
  def check_elevators(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      if building_type == 'MediumOffice'
        if user_data_dir.include?('hydraulic')
          elevators = model.getElectricEquipmentByName('2 Elevator Lift Motors').get.electricEquipmentDefinition
          elevators_power = elevators.designLevel.get.round(1)
          assert(elevators_power == 37976.6, "The baseline model elevator power for #{building_type}-#{template}-#{climate_zone} is incorrect, it was  #{elevators_power} instead of 37976.6.")
          elevators_process_loads = model.getElectricEquipmentByName('2 Elevator Lift Motors - Misc Process Loads').get.electricEquipmentDefinition
          elevators_process_loads_power = elevators_process_loads.designLevel.get.round(1)
          assert(elevators_process_loads_power == 408.5, "The baseline model elevator process loads power for #{building_type}-#{template}-#{climate_zone} is incorrect, it was  #{elevators_power} instead of 408.5.")
        else
          elevators = model.getElectricEquipmentByName('2 Elevator Lift Motors').get.electricEquipmentDefinition
          elevators_power = elevators.designLevel.get.round(1)
          assert(elevators_power == 8524.6, "The baseline model elevator power for #{building_type}-#{template}-#{climate_zone} is incorrect, it was  #{elevators_power} instead of 8524.6.")
        end
      end
    end
  end

  # Check envelope requirements lookups
  #
  # @param prototypes_base [Hash] Baseline prototypes
  #
  # TODO: Add residential and semi-heated spaces lookup
  def check_envelope(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      # Define name of surfaces used for verification
      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod_str}"

      opaque_exterior_name = JSON.parse(File.read("#{@@json_dir}/envelope.json"))[run_id]['opaque_exterior_name']
      opaque_interior_name = JSON.parse(File.read("#{@@json_dir}/envelope.json"))[run_id]['opaque_interior_name']
      exterior_fenestration_name = JSON.parse(File.read("#{@@json_dir}/envelope.json"))[run_id]['exterior_fenestration_name']
      exterior_door_name = JSON.parse(File.read("#{@@json_dir}/envelope.json"))[run_id]['exterior_door_name']

      u_value_baseline = {}
      construction_baseline = {}
      opaque_exterior_name.each do |val|
        u_value_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Opaque Exterior', val[0], 'U-Factor with Film', 'W/m2-K').to_f
        construction_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Opaque Exterior', val[0], 'Construction', '').to_s
      end
      # @todo: we've identified an issue with the r-value for air film in EnergyPlus for semi-exterior surfaces:
      # https://github.com/NREL/EnergyPlus/issues/9470
      # todos were added in OpenstudioStandards::Constructions.film_coefficients_r_value() since this is just a reporting issue, we're checking the no film u-value for opaque interior surfaces
      opaque_interior_name.each do |val|
        u_value_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Opaque Interior', val[0], 'U-Factor no Film', 'W/m2-K').to_f
        construction_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Opaque Interior', val[0], 'Construction', '').to_s
      end
      exterior_fenestration_name.each do |val|
        u_value_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Exterior Fenestration', val[0], 'Glass U-Factor', 'W/m2-K').to_f
        construction_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Exterior Fenestration', val[0], 'Construction', '').to_s
      end
      exterior_door_name.each do |val|
        u_value_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Exterior Door', val[0], 'U-Factor with Film', 'W/m2-K').to_f
        construction_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'EnvelopeSummary', 'Exterior Door', val[0], 'Construction', '').to_s
      end

      # Check U-value against expected U-value
      u_value_goal = opaque_exterior_name + opaque_interior_name + exterior_fenestration_name + exterior_door_name
      u_value_goal.each do |key, value|
        value_si = OpenStudio.convert(value, 'Btu/ft^2*hr*R', 'W/m^2*K').get
        assert(((u_value_baseline[key] - value_si).abs < 0.0015 || (u_value_baseline[key] - 5.835).abs < 0.01), "Baseline U-value for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The U-value of the #{key} is #{u_value_baseline[key]} but should be #{value_si.round(3)}.")
        # assert((construction_baseline[key].include? 'PRM'), "Baseline U-value for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The construction of the #{key} is #{construction_baseline[key]}, which is not from PRM_Construction tab.")
      end
    end
  end

  #
  # testing for exhaust air energy recovery requirement: general requirement and one exception
  #
  # @param prototypes_base [Hash] Baseline prototypes
  #
  def check_exhaust_air_energy(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      hxs = model.getHeatExchangerAirToAirSensibleAndLatents
      if !hxs.empty?
        assert(false, "The baseline model for #{building_type}-#{template}-#{climate_zone} should not contain ERVs.") unless user_data_dir == 'userdata_default_test'
        hxs.each do |hx|
          if climate_zone.include?('4A')
            assert(hx.sensibleEffectivenessat100HeatingAirFlow.round(2) == 0.67, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.sensibleEffectivenessat100CoolingAirFlow.round(2) == 0.66, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.latentEffectivenessat75HeatingAirFlow.round(2) == 0.50, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.latentEffectivenessat75CoolingAirFlow.round(2) == 0.45, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
          elsif climate_zone.include?('8A')
            assert(hx.sensibleEffectivenessat100HeatingAirFlow.round(2) == 0.50, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.sensibleEffectivenessat100CoolingAirFlow.round(2) == 0.50, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.latentEffectivenessat75HeatingAirFlow.round(2) == 0.0, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
            assert(hx.latentEffectivenessat75CoolingAirFlow.round(2) == 0.0, "The baseline model for #{building_type}-#{template} does not have the correct effectiveness values.")
          end
        end
      else
        assert(false, "The baseline model for #{building_type}-#{template}-#{climate_zone} should contain ERVs.") unless user_data_dir == 'userdata_erv_except_01'
      end
    end
  end

  # Check exterior lighting via userdata
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_exterior_lighting(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype

      if building_type == 'RetailStandalone'
        model.getExteriorLightss.each do |exterior_lights|
          ext_lights_def = exterior_lights.exteriorLightsDefinition
          if exterior_lights.name.get == 'NonDimming Exterior Lights Def'
            design_power = ext_lights_def.designLevel.round(0)
            assert(design_power == 700, "The exterior lighting for 'NonDimming Exterior Lights Def' in #{building_type}-#{template} has incorrect power. Found: #{design_power}; expected 700.")
          end
          if exterior_lights.name.get == 'Occ Sensing Exterior Lights Def'
            design_power = ext_lights_def.designLevel.round(0)
            assert(design_power == 4328, "The exterior lighting for 'Occ Sensing Exterior Lights Def' #{building_type}-#{template} has incorrect power. Found: #{design_power}; expected 4328.")
          end
        end

      end
    end
  end

  # Check fan power credits calculations
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_fan_power_credits(prototypes_base)
    standard = Standard.build('90.1-PRM-2019')
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype
      std = Standard.build('90.1-PRM-2019')

      if building_type == 'SmallOffice'
        model.getFanVariableVolumes.sort.each do |fan|
          fan_power_si = std.fan_fanpower(fan) / std.fan_design_air_flow(fan)
          fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
          fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
          assert(fan_bhp_ip.round(4) == 0.0017, "Fan power for #{fan.name} fan in #{building_type} #{template} #{climate_zone} #{mod} is #{fan_bhp_ip.round(4)} instead of 0.0017.")
        end
      end

      if building_type == 'RetailStandalone'
        model.getFanOnOffs.sort.each do |fan|
          if fan.name.to_s.include?('Front_Entry ZN')
            fan_power_si = std.fan_fanpower(fan) / std.fan_design_air_flow(fan)
            fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
            fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
            assert(fan_bhp_ip.round(4) == 0.0012, "Fan power for  #{fan.name} fan in #{building_type} #{template} #{climate_zone} #{mod} is #{fan_bhp_ip.round(4)} instead of 0.0012.")
          end
        end
      end
    end
  end

  def check_f_c_factors(baseline_base)
    baseline_base.each do |baseline, baseline_model|
      building_type, template, climate_zone, user_data_dir, mod = baseline
      # Check that the appropriate ground temperature profile object has been added to the model
      assert(!baseline_model.getSiteGroundTemperatureFCfactorMethod.nil?, "No FCfactorMethod ground temperature profile were found in the #{building_type} baseline model.")

      if building_type == 'LargeOffice'
        # Check ground temperature profile temperatures
        assert(baseline_model.getSiteGroundTemperatureFCfactorMethod.januaryGroundTemperature.to_f.round(1) == 24.2, "Wrong temperature in the FCfactorMethod ground temperature profile for the  #{building_type} baseline model.")
        assert(baseline_model.getSiteGroundTemperatureFCfactorMethod.julyGroundTemperature.to_f.round(1) == 21.2, "Wrong temperature in the FCfactorMethod ground temperature profile for the  #{building_type} baseline model.")

        # F-factor
        # Check outside boundary condition
        surface = baseline_model.getSurfaceByName('Basement_Floor').get
        assert(surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct outside boundary condition for the slab on grade.")
        # Check construction type
        construction = surface.construction.get.to_FFactorGroundFloorConstruction.get
        assert(construction.iddObjectType.valueName.to_s == 'OS_Construction_FfactorGroundFloor', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct construction type for the slab on grade.")
        # Check F-factor abd other params
        assert(construction.fFactor.round(2) == 1.26, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct F-factor type for the slab on grade.")
        assert(construction.area.round(2) == 2779.43, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct area for the slab on grade.")
        assert(construction.perimeterExposed == 0, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct exposed perimeter for the slab on grade.")
        # C-factor
        # Check outside boundary condition
        surface = baseline_model.getSurfaceByName('Basement_Wall_East').get
        assert(surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct outside boundary condition for the basement walls.")
        # Check construction type
        construction = surface.construction.get.to_CFactorUndergroundWallConstruction.get
        assert(construction.iddObjectType.valueName.to_s == 'OS_Construction_CfactorUndergroundWall', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct construction type for the basement walls.")
        # Check F-factor abd other params
        assert(construction.cFactor.round(2) == 6.47, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct C-factor type for the basement walls.")
        assert(construction.height.round(2) == 2.44, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct height for the basement walls.")
      elsif building_type == 'SmallOffice'
        # F-factor
        # Check outside boundary condition
        surface = baseline_model.getSurfaceByName('Core_ZN_floor').get
        assert(surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct outside boundary condition for the core slab on grade.")
        # Check construction type
        construction = surface.construction.get.to_FFactorGroundFloorConstruction.get
        assert(construction.iddObjectType.valueName.to_s == 'OS_Construction_FfactorGroundFloor', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct construction type for the core slab on grade.")
        # Check F-factor abd other params
        assert(construction.fFactor.round(2) == 1.26, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct F-factor type for the core slab on grade.")
        assert(construction.area.round(2) == 149.66, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct area for the core slab on grade.")
        assert(construction.perimeterExposed == 0, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct exposed perimeter for the core slab on grade.")
        # Check outside boundary condition
        surface = baseline_model.getSurfaceByName('Perimeter_ZN_1_floor').get
        assert(surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct outside boundary condition for the perimeter slab on grade.")
        # Check construction type
        construction = surface.construction.get.to_FFactorGroundFloorConstruction.get
        assert(construction.iddObjectType.valueName.to_s == 'OS_Construction_FfactorGroundFloor', "The #{building_type} baseline model created for check_f_c_factors() does not use the correct construction type for the perimeter slab on grade.")
        # Check F-factor abd other params
        assert(construction.fFactor.round(2) == 1.26, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct F-factor type for the perimeter slab on grade.")
        assert(construction.area.round(2) == 113.45, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct area for the perimeter slab on grade.")
        assert(construction.perimeterExposed.round(2) == 27.69, "The #{building_type} baseline model created for check_f_c_factors() does not use the correct exposed perimeter for the perimeter slab on grade.")
      end
    end
  end

  # Check hvac baseline system type selections
  # Expected outcome depends on prototype name and 'mod' variation defined with
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_hvac(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod_str}"
      @bldg_type_alt_now = @bldg_type_alt[prototype]
      if ['0A', '0B', '1A', '1B', '2A', '2B', '3A'].include?(climate_zone.sub('ASHRAE 169-2013-', ''))
        energy_type = 'Electric'
      else
        energy_type = 'Fuel'
      end

      if building_type == 'MidriseApartment' && mod_str.nil?
        # Residential model should be ptac or pthp, depending on climate
        check_if_pkg_terminal(model, climate_zone, 'MidriseApartment')
      elsif @bldg_type_alt_now == 'Assembly' && building_type == 'MediumOffice'
        # This is a public assembly < 120 ksf, should be PSZ
        check_if_psz(model, 'Assembly < 120,000 sq ft.')
        check_heat_type(model, climate_zone, 'SZ', 'HeatPump')
      elsif @bldg_type_alt_now == 'Assembly' && building_type == 'LargeHotel'
        # This is a public assembly > 120 ksf, should be SZ-CV
        check_if_sz_cv(model, climate_zone, 'Assembly < 120,000 sq ft.')
      elsif building_type == 'RetailStripmall' && mod_str.nil?
        # System type should be PSZ
        check_if_psz(model, 'RetailStripmall, one story, any area')
      elsif @bldg_type_alt_now == 'Retail' && building_type == 'PrimarySchool'
        # Single story retail is PSZ, regardless of floor area
        check_if_psz(model, 'retail, one story, floor area > 25 ksf.')
      elsif building_type == 'RetailStripmall' && mod_str == 'set_zone_multiplier_3'
        # System type should be PVAV with 10 zones
        check_if_pvav(model, 'retail > 25,000 sq ft, 3 stories')
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'SmallOffice' && mod_str.nil?
        # System type should be PSZ
        check_if_psz(model, 'non-res, one story, < 25 ksf')
        check_heat_type(model, climate_zone, 'SZ', 'HeatPump')
      elsif building_type == 'PrimarySchool' && mod_str == 'remove_transformer'
        # System type should be PVAV, some zones may be on PSZ systems
        check_if_pvav(model, 'nonres > 25,000 sq ft, < 150 ksf , 1 story')
        check_heat_type(model, climate_zone, 'MZ', energy_type)
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'SecondarySchool' && mod_str == 'remove_transformer'
        # System type should be VAV/chiller
        check_if_vav_chiller(model, 'nonres > 150 ksf , 1 to 3 stories')
        check_heat_type(model, climate_zone, 'MZ', energy_type)
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'MediumOffice' && mod_str == 'remove_transformer_return_relief_fan'
        # Check if baseline has return and relief fan and if fan power
        # distribution is correct
        check_return_reflief_fan_pwr_dist(model)
      elsif building_type == 'SmallOffice' && mod_str == 'set_zone_multiplier_4'
        # nonresidential, 4 to 5 stories, <= 25 ksf --> PVAV
        # System type should be PVAV with 10 zones, area is 22,012 sf
        check_if_pvav(model, 'other nonres > 4 to 5 stories, <= 25 ksf')
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'SmallOffice' && mod_str == 'set_zone_multiplier_5'
        # nonresidential, 4 to 5 stories, <= 150 ksf --> PVAV
        # System type should be PVAV with 10 zones, area is 27,515 sf
        check_if_pvav(model, 'other nonres > 4 to 5 stories, <= 150 ksf')
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'PrimarySchool' && mod_str.include?('set_zone_multiplier_4')
        # nonresidential, 4 to 5 stories, > 150 ksf --> VAV/chiller
        # System type should be PVAV with 10 zones, area is 22,012 sf
        check_if_vav_chiller(model, 'other nonres > 4 to 5 stories, > 150 ksf')
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'SmallOffice' && mod_str == 'set_zone_multiplier_6'
        # 6+ stories, any floor area --> VAV/chiller
        # This test has floor area 33,018 sf
        check_if_vav_chiller(model, ' other nonres > 6 stories')
        check_terminal_type(model, energy_type, run_id)
      elsif @bldg_type_alt_now == 'Hospital' && building_type == 'SmallOffice'
        energy_type = 'Fuel' # Table G3.1.1-3 Note 4
        # Hospital < 25 ksf is PVAV; different rule than non-res
        check_if_pvav(model, 'hospital, floor area < 25 ksf.')
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'Hospital' && mod_str.nil?
        energy_type = 'Fuel' # Table G3.1.1-3 Note 4
        # System type should be VAV/chiller, area is 241 ksf
        check_if_vav_chiller(model, 'hospital > 4 to 5 stories, > 150 ksf')
        check_heat_type(model, climate_zone, 'MZ', energy_type)
        check_terminal_type(model, energy_type, run_id)
      elsif building_type == 'Warehouse'
        # System type should be system 9, 10 but with no mechanical cooling
        check_if_heat_only(model, climate_zone, building_type)
      elsif mod_str == 'make_lab_high_distrib_zone_exh' || mod_str == 'make_lab_high_system_exh'
        # All labs on a given floor of the building should be on a separate MZ system
        model.getAirLoopHVACs.each do |air_loop|
          # identify hours of operation
          has_lab = false
          has_nonlab = false
          air_loop.thermalZones.each do |thermal_zone|
            thermal_zone.spaces.each do |space|
              space_type = space.spaceType.get.standardsSpaceType.get
              if space_type == 'laboratory'
                has_lab = true
              else
                has_nonlab = true
              end
            end
          end
          assert(!(has_lab == true && has_nonlab == true), "System #{air_loop.name} has lab and nonlab spaces and lab exhaust > 15,000 cfm.")
        end
      elsif mod_str == 'make_lab_low_distrib_zone_exh'
        # Labs on a given floor of the building should be mixed with other space types on the main MZ system
        model.getAirLoopHVACs.each do |air_loop|
          # identify hours of operation
          has_lab = false
          has_nonlab = false
          air_loop.thermalZones.each do |thermal_zone|
            thermal_zone.spaces.each do |space|
              space_type = space.spaceType.get.standardsSpaceType.get
              if space_type == 'laboratory'
                has_lab = true
              else
                has_nonlab = true
              end
            end
          end
          assert(!(has_lab == true && has_nonlab == false), "System #{air_loop.name} has only lab spaces and lab exhaust < 15,000 cfm.")
        end
      elsif building_type == 'LargeOffice' || building_type == 'MediumOffice'
        # Check that the datacenter basement is assigned to system 11, PSZ-VAV
        check_cmp_dtctr_system_type(model)
      end
    end
  end

  # Check hvac baseline system efficiencies
  def check_hvac_efficiency(prototypes_base)
    # No.1 PTAC
    # cooling: CoilCoolingDXSingleSpeed
    # heating: CoilHeatingWater
    # hash = {capacity:cop}
    capacity_cop_cool = { 100000 => 3.2 }
    capacity_cop_cool.each do |key_cool, value_cool|
      std = Standard.build('90.1-PRM-2019')
      prototypes_base.each do |prototype, model_base|
        building_type, template, climate_zone, user_data_dir, mod = prototype
        if building_type == 'SmallOffice' && climate_zone == 'ASHRAE 169-2013-2A'
          # Create a deep copy of the proposed model
          model_ptac = BTAP::FileIO.deep_copy(model_base)
          # Remove all HVAC from model, excluding service water heating
          std.model_remove_prm_hvac(model_ptac)
          hot_water_loop = std.model_add_hw_loop(model_ptac, 'DistrictHeating')
          model_ptac.getPumpVariableSpeeds.each do |pump|
            pump.setRatedFlowRate(100)
          end
          zones = model_ptac.getThermalZones.select { |z| !OpenstudioStandards::ThermalZone.thermal_zone_plenum?(z) }
          zones.each do |zone|
            zone.additionalProperties.setFeature('baseline_system_type', 'PTAC')
          end
          std.model_add_ptac(model_ptac,
                             zones,
                             cooling_type: 'Single Speed DX AC',
                             heating_type: 'Water',
                             hot_water_loop: hot_water_loop,
                             fan_type: 'ConstantVolume')
          zones.each do |zone|
            zone.equipment.each do |zone_equipment|
              ptac = zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
              ptac.supplyAirFan.to_FanOnOff.get.setMaximumFlowRate(100)
              clg_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get
              capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
              clg_coil.setRatedTotalCoolingCapacity(capacity_cool_w)
            end
          end
          std.model_apply_hvac_efficiency_standard(model_ptac, climate_zone)
          assert((model_ptac.getCoilCoolingDXSingleSpeeds[0].ratedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX single coil (PTAC).')
        end
      end
    end

    # No.2 PTHP
    # cooling: CoilCoolingDXSingleSpeed
    # heating: CoilHeatingDXSingleSpeed
    # hash = {capacity:cop}
    capacity_cop_cool = { 100000 => 3.1 }
    capacity_eff_heat = { 100000 => 3.1 }
    capacity_cop_cool.each do |key_cool, value_cool|
      capacity_eff_heat.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'SmallOffice' && climate_zone == 'ASHRAE 169-2013-2A'
            # Create a deep copy of the proposed model
            model_pthp = BTAP::FileIO.deep_copy(model_base)
            # Remove all HVAC from model, excluding service water heating
            std.model_remove_prm_hvac(model_pthp)
            zones = model_pthp.getThermalZones
            zones.each do |zone|
              zone.additionalProperties.setFeature('baseline_system_type', 'PTHP')
            end
            std.model_add_pthp(model_pthp,
                               zones,
                               fan_type: 'ConstantVolume')
            zones.each do |zone|
              zone.equipment.each do |zone_equipment|
                pthp = zone_equipment.to_ZoneHVACPackagedTerminalHeatPump.get
                pthp.supplyAirFan.to_FanOnOff.get.setMaximumFlowRate(100)
                clg_coil = pthp.coolingCoil.to_CoilCoolingDXSingleSpeed.get
                capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
                clg_coil.setRatedTotalCoolingCapacity(capacity_cool_w)
                htg_coil = pthp.heatingCoil.to_CoilHeatingDXSingleSpeed.get
                capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
                htg_coil.setRatedTotalHeatingCapacity(capacity_heat_w)
              end
            end
            std.model_apply_hvac_efficiency_standard(model_pthp, climate_zone)
            assert((model_pthp.getCoilCoolingDXSingleSpeeds[0].ratedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX single coil (PTHP).')
            assert((model_pthp.getCoilHeatingDXSingleSpeeds[0].ratedCOP.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for heating DX single coil (PTHP).')
          end
        end
      end
    end

    # No.3 PSZ_AC
    # cooling: CoilCoolingDXSingleSpeed
    # heating: CoilHeatingGas
    # hash = {capacity:cop}
    capacity_cop_cool = { 10000 => 3.0,
                          300000 => 3.5 }
    capacity_cop_heat = { 10000 => 0.8,
                          300000 => 0.793 }
    capacity_cop_cool.each do |key_cool, value_cool|
      capacity_cop_heat.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'SmallOffice' && climate_zone == 'ASHRAE 169-2013-8A'
            # Create a deep copy of the proposed model
            model_psz_ac = BTAP::FileIO.deep_copy(model_base)
            # Remove all HVAC from model, excluding service water heating
            std.model_remove_prm_hvac(model_psz_ac)
            # Remove all EMS objects from the model
            std.model_remove_prm_ems_objects(model_psz_ac)
            zones = model_psz_ac.getThermalZones
            std.model_add_psz_ac(model_psz_ac,
                                 zones,
                                 cooling_type: 'Single Speed DX AC',
                                 chilled_water_loop: nil,
                                 heating_type: 'Gas',
                                 supplemental_heating_type: nil,
                                 hot_water_loop: nil,
                                 fan_location: 'DrawThrough',
                                 fan_type: 'ConstantVolume')
            capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
            model_psz_ac.getCoilCoolingDXSingleSpeeds.sort.each do |clg_coil|
              clg_coil.setRatedTotalCoolingCapacity(capacity_cool_w)
            end
            capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
            model_psz_ac.getCoilHeatingGass.sort.each do |htg_coil|
              htg_coil.setNominalCapacity(capacity_heat_w)
            end
            model_psz_ac.getAirLoopHVACs.each do |air_loop_hvac|
              air_loop_hvac.additionalProperties.setFeature('baseline_system_type', 'PSZ_AC')
              air_loop_hvac.setDesignSupplyAirFlowRate(0.01)
            end
            model_psz_ac.getFanOnOffs.each do |fan_on_off|
              fan_on_off.setMaximumFlowRate(0.01)
            end
            std.model_apply_hvac_efficiency_standard(model_psz_ac, climate_zone)
            assert((model_psz_ac.getCoilCoolingDXSingleSpeeds[0].ratedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX single coil (PSZ-AC).')
            assert((model_psz_ac.getCoilHeatingGass[0].gasBurnerEfficiency.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for heating gas coil (PSZ-AC).')
          end
        end
      end
    end

    # No.4 PSZ_HP
    # cooling: CoilCoolingDXSingleSpeed
    # heating: CoilHeatingDXSingleSpeed
    # hash = {capacity:cop}
    capacity_cop_cool = { 10000 => 3.0,
                          300000 => 3.1 }
    capacity_cop_heat = { 10000 => 3.4,
                          300000 => 3.4 }
    capacity_cop_cool.each do |key_cool, value_cool|
      capacity_cop_heat.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'SmallOffice' && climate_zone == 'ASHRAE 169-2013-2A'
            # Create a deep copy of the proposed model
            model_psz_hp = BTAP::FileIO.deep_copy(model_base)
            capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
            model_psz_hp.getCoilCoolingDXSingleSpeeds.sort.each do |clg_coil|
              clg_coil.setRatedTotalCoolingCapacity(capacity_cool_w)
            end
            capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
            model_psz_hp.getCoilHeatingDXSingleSpeeds.sort.each do |htg_coil|
              htg_coil.setRatedTotalHeatingCapacity(capacity_heat_w)
            end
            std.model_apply_hvac_efficiency_standard(model_psz_hp, climate_zone)
            assert((model_psz_hp.getCoilCoolingDXSingleSpeeds[0].ratedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX single coil (PSZ-HP).')
            assert((model_psz_hp.getCoilHeatingDXSingleSpeeds[0].ratedCOP.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for heating DX single coil (PSZ-HP).')
          end
        end
      end
    end

    # No.5 PVAV_Reheat
    # cooling: CoilCoolingDXTwoSpeed
    # heating: Boiler
    # hash = {capacity:cop}
    capacity_cop_cool = { 10000 => 3.0,
                          300000 => 3.5 }
    boiler_capacity_eff = { 100000 => 0.8,
                            1000000 => 0.75 }
    capacity_cop_cool.each do |key_cool, value_cool|
      boiler_capacity_eff.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'MediumOffice' && template == '90.1-2013' && climate_zone == 'ASHRAE 169-2013-8A'
            # Create a deep copy of the proposed model
            model_pvav_reheat = BTAP::FileIO.deep_copy(model_base)
            capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
            model_pvav_reheat.getCoilCoolingDXTwoSpeeds.sort.each do |clg_coil|
              clg_coil.setRatedHighSpeedTotalCoolingCapacity(capacity_cool_w)
              clg_coil.setRatedLowSpeedTotalCoolingCapacity(capacity_cool_w)
            end
            capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
            model_pvav_reheat.getBoilerHotWaters.sort.each do |boiler|
              boiler.setNominalCapacity(capacity_heat_w)
            end
            std.model_apply_hvac_efficiency_standard(model_pvav_reheat, climate_zone)
            assert((model_pvav_reheat.getCoilCoolingDXTwoSpeeds[0].ratedHighSpeedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX two speed coil (PVAV_Reheat).')
            assert((model_pvav_reheat.getCoilCoolingDXTwoSpeeds[0].ratedLowSpeedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX two speed coil (PVAV_Reheat).')
            assert((model_pvav_reheat.getBoilerHotWaters[0].nominalThermalEfficiency.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for boiler (PVAV_Reheat).')
          end
        end
      end
    end

    # No.6 PVAV_PFP_Boxes
    # cooling: CoilCoolingDXTwoSpeed
    # heating: CoilHeatingElectric
    # hash = {capacity:cop}
    capacity_cop_cool = { 10000 => 3.0,
                          300000 => 3.5 }
    capacity_cop_cool.each do |key_cool, value_cool|
      boiler_capacity_eff.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'MediumOffice' && template == '90.1-2013' && climate_zone == 'ASHRAE 169-2013-2A'
            # Create a deep copy of the proposed model
            model_pvav_pfp_boxes = BTAP::FileIO.deep_copy(model_base)
            capacity_cool_w = OpenStudio.convert(key_cool, 'Btu/hr', 'W'). get
            model_pvav_pfp_boxes.getCoilCoolingDXTwoSpeeds.sort.each do |clg_coil|
              clg_coil.setRatedHighSpeedTotalCoolingCapacity(capacity_cool_w)
              clg_coil.setRatedLowSpeedTotalCoolingCapacity(capacity_cool_w)
            end
            std.model_apply_hvac_efficiency_standard(model_pvav_pfp_boxes, climate_zone)
            assert((model_pvav_pfp_boxes.getCoilCoolingDXTwoSpeeds[0].ratedHighSpeedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX two speed coil (PVAV_PFP_Boxes).')
            assert((model_pvav_pfp_boxes.getCoilCoolingDXTwoSpeeds[0].ratedLowSpeedCOP.to_f - value_cool).abs < 0.001, 'Error in efficiency setting for cooling DX two speed coil (PVAV_PFP_Boxes).')
          end
        end
      end
    end

    # No.7 VAV_Reheat
    # cooling: Chiller/CoolingTower
    # heating: Boiler
    # hash = {capacity:cop}
    chiller_capacity_eff = { 100 => 0.79,
                             200 => 0.718 }
    boiler_capacity_eff = { 100000 => 0.8,
                            1000000 => 0.75 }
    chiller_capacity_eff.each do |key_cool, value_cool|
      boiler_capacity_eff.each do |key_heat, value_heat|
        std = Standard.build('90.1-PRM-2019')
        prototypes_base.each do |prototype, model_base|
          building_type, template, climate_zone, user_data_dir, mod = prototype
          if building_type == 'MediumOffice' && template == '90.1-2004'
            # Create a deep copy of the proposed model
            model_vav_reheat = BTAP::FileIO.deep_copy(model_base)
            capacity_cool_w = OpenStudio.convert(key_cool, 'ton', 'W'). get
            model_vav_reheat.getChillerElectricEIRs.sort.each do |chiller|
              chiller.setReferenceCapacity(capacity_cool_w)
            end
            capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
            model_vav_reheat.getBoilerHotWaters.sort.each do |boiler|
              boiler.setNominalCapacity(capacity_heat_w)
            end
            std.model_apply_hvac_efficiency_standard(model_vav_reheat, climate_zone)
            assert((model_vav_reheat.getChillerElectricEIRs[0].referenceCOP.to_f - 3.517 / value_cool).abs < 0.001, 'Error in efficiency setting for chiller (VAV_Reheat).')
            assert((model_vav_reheat.getBoilerHotWaters[0].nominalThermalEfficiency.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for boiler (VAV_Reheat).')
          end
        end
      end
    end

    # check cooling tower heat rejection
    std = Standard.build('90.1-PRM-2019')
    prototypes_base.each do |prototype, model_base|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      if building_type == 'MediumOffice' && template == '90.1-2004'
        # Create a deep copy of the proposed model
        model_vav_reheat_coolingtower = BTAP::FileIO.deep_copy(model_base)
        design_water_flow_gpm = 1000
        design_water_flow_m3_per_s = OpenStudio.convert(design_water_flow_gpm, 'gal/min', 'm^3/s').get
        model_vav_reheat_coolingtower.getCoolingTowerVariableSpeeds[0].setDesignWaterFlowRate(design_water_flow_m3_per_s)
        design_water_flow_gpm = OpenStudio.convert(design_water_flow_m3_per_s, 'm^3/s', 'gal/min').get
        fan_motor_nameplate_hp = design_water_flow_gpm / 38.2
        fan_bhp = 0.9 * fan_motor_nameplate_hp
        fan_motor_eff = 0.924
        fan_motor_actual_power_hp = fan_bhp / fan_motor_eff
        fan_motor_actual_power_w = fan_motor_actual_power_hp * 745.7
        std.model_apply_hvac_efficiency_standard(model_vav_reheat_coolingtower, climate_zone)
        assert((model_vav_reheat_coolingtower.getCoolingTowerVariableSpeeds[0].designFanPower.to_f - fan_motor_actual_power_w).abs < 0.001, 'Error in setting for cooling tower heat rejection (VAV_Reheat).')
      end
    end

    # No.8 VAV_PFP_Boxes
    # cooling: Chiller/CoolingTower
    # heating: Boiler
    # hash = {capacity:cop}
    chiller_capacity_eff = { 100 => 0.703,
                             200 => 0.634 }
    chiller_capacity_eff.each do |key_cool, value_cool|
      std = Standard.build('90.1-PRM-2019')
      prototypes_base.each do |prototype, model_base|
        building_type, template, climate_zone, user_data_dir, mod = prototype
        if building_type == 'LargeOffice' && template == '90.1-2004'
          # Create a deep copy of the proposed model
          model_vav_pfp = BTAP::FileIO.deep_copy(model_base)
          capacity_cool_w = OpenStudio.convert(key_cool, 'ton', 'W'). get
          model_vav_pfp.getChillerElectricEIRs.sort.each do |chiller|
            chiller.setReferenceCapacity(capacity_cool_w)
          end
          std.model_apply_hvac_efficiency_standard(model_vav_pfp, climate_zone)
          assert((model_vav_pfp.getChillerElectricEIRs[0].referenceCOP.to_f - 3.517 / value_cool).abs < 0.001, 'Error in efficiency setting for chiller (VAV_Reheat).')
        end
      end
    end

    # No.9 Gas_Furnace
    # heating: CoilHeatingGas
    # hash = {capacity:cop}
    capacity_cop_heat = { 10000 => 0.793 }
    capacity_cop_heat.each do |key_heat, value_heat|
      std = Standard.build('90.1-PRM-2019')
      prototypes_base.each do |prototype, model_base|
        building_type, template, climate_zone, user_data_dir, mod = prototype
        if building_type == 'SmallOffice' && climate_zone == 'ASHRAE 169-2013-2A'
          # Create a deep copy of the proposed model
          model_gas_furnace = BTAP::FileIO.deep_copy(model_base)
          # Remove all HVAC from model, excluding service water heating
          std.model_remove_prm_hvac(model_gas_furnace)
          # Remove all EMS objects from the model
          std.model_remove_prm_ems_objects(model_gas_furnace)
          zones = model_gas_furnace.getThermalZones
          zones.each do |zone|
            zone.additionalProperties.setFeature('baseline_system_type', 'Gas_Furnace')
          end
          std.model_add_unitheater(model_gas_furnace,
                                   zones,
                                   fan_control_type: 'ConstantVolume',
                                   fan_pressure_rise: 0.2,
                                   heating_type: 'Gas',
                                   hot_water_loop: nil)
          capacity_heat_w = OpenStudio.convert(key_heat, 'Btu/hr', 'W'). get
          model_gas_furnace.getCoilHeatingGass.sort.each do |htg_coil|
            htg_coil.setNominalCapacity(capacity_heat_w)
          end
          model_gas_furnace.getFanConstantVolumes.each do |fan_constant_volume|
            fan_constant_volume.setMaximumFlowRate(0.01)
          end
          std.model_apply_hvac_efficiency_standard(model_gas_furnace, climate_zone)
          assert((model_gas_furnace.getCoilHeatingGass[0].gasBurnerEfficiency.to_f - value_heat).abs < 0.001, 'Error in efficiency setting for gas furnace (Gas Furnace).')
        end
      end
    end
  end
  # Check if split of zones to PSZ from multizone baselines is working correctly

  def check_psz_split_from_mz(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod_str}"
      @bldg_type_alt_now = @bldg_type_alt[prototype]

      if building_type == 'MediumOffice' && mod_str == 'remove_transformer_change_zone_epd_Perimeter_bot_ZN_1 ZN_70'
        # This mod should isolate Perimeter_bot_ZN_1 ZN to PSZ
        # Fan schedule for the PSZ should be same as the MZ system fan schedule (92 hrs/wk)
        # MZ system will have the zone Core_bottom ZN on it
        # Review all air loops and check zones and fan schedules
        num_zones_target = 0
        num_zones_mz = 0
        fan_hrs_per_week_target = 0
        fan_hrs_per_week_mz = 0
        model.getAirLoopHVACs.each do |air_loop|
          air_loop.thermalZones.each do |zone|
            zone_name = zone.name.get
            if zone.name.get == 'Perimeter_bot_ZN_1 ZN'
              # Get fan hours and num zones
              num_zones_target = air_loop.thermalZones.size
              fan_hrs_per_week_target = get_fan_hours_per_week(model, air_loop)
            elsif zone.name.get == 'Core_bottom ZN'
              num_zones_mz = air_loop.thermalZones.size
              fan_hrs_per_week_mz = get_fan_hours_per_week(model, air_loop)
            end
          end
        end
        assert(num_zones_target == 1, "Split PSZ from MZ system fails for high internal gain zone. Expected 'Perimeter_bot_ZN_1 ZN' to be isolated as one zone, but num_zones_target is #{num_zones_target}")
        assert(num_zones_mz > 1, 'Split PSZ from MZ system fails for high internal gain zone. Expected multiple zones to be on multiple zone system.')
        assert((fan_hrs_per_week_target - fan_hrs_per_week_mz).abs < 5, "Split PSZ from MZ system fails for high internal gain zone. Expected fan schedule on the PSZ system with #{fan_hrs_per_week_target} system hours to be roughly the same as the MZ system with #{fan_hrs_per_week_mz} system hours.")
      elsif building_type == 'MediumOffice' && mod_str == 'remove_transformer_change_to_long_occ_sch_Perimeter_bot_ZN_1 ZN'
        # This mod should isolate Perimeter_bot_ZN_1 ZN to PSZ
        # Fan schedule for the PSZ should be 24/7, while fan schedule for MZ system should be 92 hrs/wk
        num_zones_target = 0
        num_zones_mz = 0
        fan_hrs_per_week_target = 0
        fan_hrs_per_week_mz = 0
        model.getAirLoopHVACs.each do |air_loop|
          air_loop.thermalZones.each do |zone|
            if zone.name.get == 'Perimeter_bot_ZN_1 ZN'
              # Get fan hours and num zones
              num_zones_target = air_loop.thermalZones.size
              fan_hrs_per_week_target = get_fan_hours_per_week(model, air_loop)
            elsif zone.name.get == 'Core_bottom ZN'
              num_zones_mz = air_loop.thermalZones.size
              fan_hrs_per_week_mz = get_fan_hours_per_week(model, air_loop)
            end
          end
        end
        assert(num_zones_target == 1, "Split PSZ from MZ system fails for high internal gain zone. Expected 'Perimeter_bot_ZN_1 ZN' to be isolated as one zone, but num_zones_target is #{num_zones_target}")
        assert(num_zones_mz > 1, 'Split PSZ from MZ system fails for high internal gain zone. Expected multiple zones to be on multiple zone system.')
        assert(fan_hrs_per_week_target > fan_hrs_per_week_mz, "Split PSZ from MZ system fails for high internal gain zone. Target zone fan hrs/wk = #{fan_hrs_per_week_target}; MZ fan hrs/wk = #{fan_hrs_per_week_mz}.")
      end
    end
  end

  #
  # testing method for PRM 2019 baseline HVAC sizing, specific testing objectives are commented inline
  #
  # @param prototypes_base [Hash] Baseline prototypes
  #
  def check_hvac_sizing(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # check sizing parameters (G3.1.2.2)
      sizing_parameters = model_baseline.getSizingParameters
      assert((sizing_parameters.coolingSizingFactor - 1.15).abs < 0.001, "Baseline cooling sizing parameters for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The cooling sizing parameter is #{sizing_parameters.coolingSizingFactor} but should be 1.15")
      assert((sizing_parameters.heatingSizingFactor - 1.25).abs < 0.001, "Baseline cooling sizing parameters for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The heating sizing parameter is #{sizing_parameters.heatingSizingFactor} but should be 1.25")

      # check sizing schedules for loads are correct (min/max) (G3.1.2.2.1 and exception)
      check_sizing_values(model_baseline, building_type, template, climate_zone)

      # check delta t between supply air temperature set point and room temperature set point are 20 deg (exception of 17 deg for laboratory spaces) (G3.1.2.8.1 and exception)
      # including checking unit heater supply air temperature set point of 105 deg (G3.1.2.8.2)
      check_sizing_delta_t(model_baseline, building_type, template, climate_zone)
    end
  end

  # Check baseline infiltration calculations
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_infiltration(prototypes, prototypes_base, baseline_or_proposed)
    std = Standard.build('90.1-PRM-2019')
    space_env_areas = JSON.parse(File.read("#{@@json_dir}/space_envelope_areas.json"))

    # Check that the model_get_infiltration_method and
    # model_get_infiltration_coefficients method retrieve
    # the correct information
    model_blank = OpenStudio::Model::Model.new
    infil_object = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model_blank)
    infil_object.setFlowperExteriorWallArea(0.001)
    infil_object.setConstantTermCoefficient(0.002)
    infil_object.setTemperatureTermCoefficient(0.003)
    infil_object.setVelocityTermCoefficient(0.004)
    infil_object.setVelocitySquaredTermCoefficient(0.005)
    new_space = OpenStudio::Model::Space.new(model_blank)
    infil_object.setSpace(new_space)
    assert(infil_object.designFlowRateCalculationMethod.to_s == std.model_get_infiltration_method(model_blank), 'Error in infiltration method retrieval.')
    assert(std.model_get_infiltration_coefficients(model_blank) == [infil_object.constantTermCoefficient,
                                                                    infil_object.temperatureTermCoefficient,
                                                                    infil_object.velocityTermCoefficient,
                                                                    infil_object.velocitySquaredTermCoefficient], 'Error in infiltration coeffcient retrieval.')

    # Retrieve space envelope area for input prototypes
    prototypes_spc_area_calc = {}
    prototypes.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod}"

      # At this step, model simulations shall be successful.
      # Otherwise, we should handle the simulation failure in the PRM method
      sql = model.sqlFile.get
      unless sql.connectionOpen
        sql.reopen
      end

      # Get space envelope area
      spc_env_area = 0
      model.getSpaces.sort.each do |spc|
        spc_env_area += OpenstudioStandards::Geometry.space_get_envelope_area(spc)
      end
      # close the sql
      sql.close
      prototypes_spc_area_calc[prototype] = spc_env_area
    end

    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod_str}"

      # At this step, model simulations shall be successful.
      # Otherwise, we should handle the simulation failure in the PRM method
      sql = model.sqlFile.get
      unless sql.connectionOpen
        sql.reopen
      end

      # Check if the space envelope area calculations
      spc_env_area = 0
      model.getSpaces.sort.each do |spc|
        spc_env_area += OpenstudioStandards::Geometry.space_get_envelope_area(spc)
      end
      assert((space_env_areas[run_id].to_f - spc_env_area.round(2)).abs < 0.001, "Space envelope calculation is incorrect for the #{building_type}, #{template}, #{climate_zone} model: #{spc_env_area.round(2)} (model) vs. #{space_env_areas[run_id]} (expected).")

      # Check that infiltrations are not assigned at
      # the space type level
      model.getSpaceTypes.sort.each do |spc|
        assert(false, "The #{baseline_or_proposed} for the #{building_type}, #{template}, #{climate_zone} model has infiltration specified at the space type level.") unless spc.spaceInfiltrationDesignFlowRates.empty?
      end
      # close SQL
      sql.close

      # Back calculate the I_75 (cfm/ft2), expected value is 1 cfm/ft2 in 90.1-PRM-2019
      # Use input prototype's space envelope area because, even though the baseline model space
      # conditioning can be different, 90.1-2019 Appendix G specified that:
      # "The baseline building design shall be modeled with the same number of floors and
      # identical conditioned floor area as the proposed design."
      # So it is assumed that the baseline space conditioning category shall be the same as the proposed.
      if baseline_or_proposed == 'baseline'
        infil_rate = 1.0
      else
        # if building_type == 'SmallOffice'
        #   infil_rate = 0.22
        # elsif building_type == 'LargeHotel'
        #   infil_rate = 0.50
        # elsif building_type == 'Warehouse'
        #   infil_rate = 0.61
        # end
        infil_rate = 1.0
      end

      conv_fact = OpenStudio.convert(1, 'm^3/s', 'ft^3/min').to_f / OpenStudio.convert(1, 'm^2', 'ft^2').to_f
      model_infil_rate = (std.model_current_building_envelope_infiltration_at_75pa(model, prototypes_spc_area_calc[prototype]) * conv_fact).round(2)
      assert(model_infil_rate == infil_rate, "The #{baseline_or_proposed} air leakage rate of the building envelope (#{building_type}) at a fixed building pressure of 75 Pa (#{model_infil_rate} cfm/ft2) is different than the requirement (#{infil_rate} cfm/ft2).")
    end
  end

  # Check if the IsResidential flag used by the PRM works as intended (i.e. should be false for commercial spaces)
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_residential_flag(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      # Determine whether any space is residential
      has_res = 'false'
      std = Standard.build("#{template}_#{building_type}")
      model_baseline.getSpaces.sort.each do |space|
        if OpenstudioStandards::Space.space_residential?(space)
          has_res = 'true'
        end
      end
      # Check whether space_residential? function is working
      has_res_goal = @@hasres_values[building_type]
      assert(has_res == has_res_goal, "Failure to set space_residential? for #{building_type}, #{template}, #{climate_zone}.")
    end
  end

  def check_lighting_exceptions(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      if building_type == 'RetailStripmall'
        # check if nonregulate lights objects still exist
        found_obj_1 = false
        found_obj_2 = false
        model.getLightss.each do |lights|
          lights_def = lights.lightsDefinition
          actual_w_area = lights_def.wattsperSpaceFloorArea.to_f
          # Check if non-regulated lights objects have been removed
          if lights.name.get == 'StripMall Strip mall - type 1 Additional Lights'
            found_obj_1 = true
          end
          if lights.name.get == 'StripMall Strip mall - type 2 Additional Lights'
            found_obj_2 = true
          end

          # Check power level of regulated lights objects
          if lights.name.get == 'StripMall Strip mall - type 1 Lights'
            expected_w_area = 16.1458656250646
            assert(expected_w_area.round(3) == actual_w_area.round(3), "The incorrect lighting power for #{lights.name.get} in #{building_type}-#{template}.")
          end
          if lights.name.get == 'StripMall Strip mall - type 1 Lights'
            expected_w_area = 16.1458656250646
            assert(expected_w_area.round(3) == actual_w_area.round(3), "The incorrect lighting power for #{lights.name.get} in #{building_type}-#{template}.")
          end
          if lights.name.get == 'StripMall Strip mall - type 2 Lights'
            expected_w_area = 16.1458656250646
            assert(expected_w_area.round(3) == actual_w_area.round(3), "The incorrect lighting power for #{lights.name.get} in #{building_type}-#{template}.")
          end
          if lights.name.get == 'StripMall Strip mall - type 3 Lights'
            expected_w_area = 16.1458656250646
            assert(expected_w_area.round(3) == actual_w_area.round(3), "The incorrect lighting power for #{lights.name.get} in #{building_type}-#{template}.")
          end
        end
        assert(found_obj_1 == true, "The retail display lighting exception user data for in #{building_type}-#{template} has failed to preserve the lights object.")
        assert(found_obj_2 == true, "The unregulated lighting exception user data for in #{building_type}-#{template} has failed to preserve the lights object.")
      end
    end
  end

  # Check lighting occ sensor
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_light_occ_sensor(prototypes, prototypes_base)
    light_sch = {}
    prototypes.each do |prototype, model_proto|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod}"
      # Define name of spaces used for verification
      space_name = JSON.parse(File.read("#{@@json_dir}/light_occ_sensor.json"))[run_id]

      # Get lighting schedule in prototype model
      light_sch_model = {}
      model_proto.getLightss.sort.each do |lgts|
        light_sch_model_lgts = {}

        # get default schedule
        day_rule = lgts.schedule.get.to_ScheduleRuleset.get.defaultDaySchedule
        times = day_rule.times()
        light_sch_model_default_rule = {}
        times.each do |time|
          light_sch_model_default_rule[time.to_s] = day_rule.getValue(time)
        end
        light_sch_model_lgts['default schedule'] = light_sch_model_default_rule

        # get daily schedule
        lgts.schedule.get.to_ScheduleRuleset.get.scheduleRules.each do |week_rule|
          light_sch_model_week_rule = {}
          day_rule = week_rule.daySchedule
          times = day_rule.times()
          times.each do |time|
            light_sch_model_week_rule[time.to_s] = day_rule.getValue(time)
          end
          light_sch_model_lgts[week_rule.name.to_s] = light_sch_model_week_rule
        end
        light_sch_model[lgts.name.to_s] = light_sch_model_lgts
      end
      light_sch[run_id] = light_sch_model
    end

    light_sch_base = {}
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod}"
      # Define name of spaces used for verification
      space_name = JSON.parse(File.read("#{@@json_dir}/light_occ_sensor.json"))[run_id]

      # Get lighting schedule in baseline model
      model_baseline.getSpaceTypes.sort.each do |space_type|
        light_sch_model_base = {}
        space_type.lights.sort.each do |lgts|
          if lgts.schedule.get.to_ScheduleRuleset.is_initialized
            light_sch_model_lgts_base = {}
            light_sch_model_lgts_base['space_type'] = space_type.standardsSpaceType.to_s

            # get default schedule
            day_rule = lgts.schedule.get.to_ScheduleRuleset.get.defaultDaySchedule
            times = day_rule.times()
            light_sch_model_default_rule = {}
            times.each do |time|
              light_sch_model_default_rule[time.to_s] = day_rule.getValue(time)
            end
            light_sch_model_lgts_base['default schedule'] = light_sch_model_default_rule

            # get daily schedule
            lgts.schedule.get.to_ScheduleRuleset.get.scheduleRules.each do |week_rule|
              light_sch_model_week_rule_base = {}
              day_rule = week_rule.daySchedule
              times = day_rule.times()
              times.each do |time|
                light_sch_model_week_rule_base[time.to_s] = day_rule.getValue(time)
              end
              light_sch_model_lgts_base[week_rule.name.to_s] = light_sch_model_week_rule_base
            end
            light_sch_model_base[lgts.name.to_s] = light_sch_model_lgts_base
          end
        end

        # Check light schedule against expected light schedule
        light_sch_model_base.each do |key, value|
          value.each do |key1, value1|
            if key1 != 'space_type'
              value1.each do |key2, value2|
                space_type_var = 0
                # get the lpd for the space type from preset values
                space_name.each do |key3, value3|
                  if value['space_type'] == key3
                    space_type_var = value3
                  end
                end
                if value2 < 0
                  assert(((light_sch[run_id][key][key1][key2] - value2 * (1.0 - space_type_var)).abs < 0.001), "Lighting schedule for the #{building_type}, #{template}, #{climate_zone} model is incorrect.")
                end
              end
            end
          end
        end
      end
    end
  end

  # Check LPD requirements lookups
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_lpd(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      # Define name of spaces used for verification
      run_id = "#{building_type}_#{template}_#{climate_zone}_#{mod_str}"
      space_name = JSON.parse(File.read("#{@@json_dir}/lpd.json"))[run_id]

      sql = model_baseline.sqlFile.get
      unless sql.connectionOpen
        sql.reopen
      end
      # Get LPD in baseline model
      lpd_baseline = {}
      space_name.each do |val|
        lpd_baseline[val[0]] = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'LightingSummary', 'Interior Lighting', val[0], 'Lighting Power Density', 'W/m2').to_f
      end
      sql.close

      # Check LPD against expected LPD
      space_name.each do |key, value|
        value_si = OpenStudio.convert(value, 'W/ft^2', 'W/m^2').get
        assert(((lpd_baseline[key] - value_si).abs < 0.001), "Baseline LPD the #{building_type}, #{template}, #{climate_zone} model is incorrect. The LPD of #{key} is #{lpd_baseline[key]} but should be #{value_si}.")
      end
    end
  end

  # Implement multiple LPD handling from userdata by space, space type and default space_type
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_multi_lpd_handling(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      if user_data_dir == 'no_user_data'
        sub_prototypes_base = {}
        sub_prototypes_base[prototype] = model_baseline
        check_lpd(sub_prototypes_base)
      else
        if user_data_dir == 'userdata_lpd_01'
          space_name_to_lpd_target = {}
          space_name_to_lpd_target['Attic'] = 15.06948107
          space_name_to_lpd_target['Perimeter_ZN_2'] = 14.83267494
          space_name_to_lpd_target['Perimeter_ZN_1'] = 15.26323154
          space_name_to_lpd_target['Perimeter_ZN_4'] = 12.91669806

          model_baseline.getSpaces.each do |space|
            space_name = space.name.get
            target_lpd = 10.7639
            if space_name_to_lpd_target.key?(space_name)
              target_lpd = space_name_to_lpd_target[space_name]
            end
            lights_name = space.spaceType.get.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
            lights_obj = model_baseline.getLightsByName(lights_name).get
            model_lpd = lights_obj.lightsDefinition.wattsperSpaceFloorArea.get
            # model_lpd = space.spaceType.get.lights[0].lightsDefinition.wattsperSpaceFloorArea.get
            assert((target_lpd - model_lpd).abs < 0.001, "Baseline LPD for #{building_type}, #{template}, #{climate_zone} model with user data #{user_data_dir} is incorrect. The LPD of #{space_name} is #{target_lpd} but should be #{model_lpd}.")
          end
        elsif user_data_dir == 'userdata_lpd_02'
          space_name_to_lpd_target = {}
          space_name_to_lpd_target['Attic'] = 0.0
          space_name_to_lpd_target['Perimeter_ZN_2'] = 10.255
          space_name_to_lpd_target['Perimeter_ZN_4'] = 10.2557
          space_name_to_lpd_target['Core_ZN'] = 10.2392

          model_baseline.getSpaces.each do |space|
            space_name = space.name.get
            target_lpd = 10.2435
            if space_name_to_lpd_target.key?(space_name)
              target_lpd = space_name_to_lpd_target[space_name]
            end
            lights_name = space.spaceType.get.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
            lights_obj = model_baseline.getLightsByName(lights_name).get
            model_lpd = lights_obj.lightsDefinition.wattsperSpaceFloorArea.get
            assert((target_lpd - model_lpd).abs < 0.001, "Baseline LPD for #{building_type}, #{template}, #{climate_zone} model with user data #{user_data_dir} is incorrect. The LPD of #{space_name} is #{target_lpd} but should be #{model_lpd}.")
          end
        end
      end
    end
  end

  def check_multi_bldg_handling(baseline_base)
    baseline_base.each do |baseline, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = baseline
      if building_type == 'SmallOffice'
        # Get WWR of baseline model
        wwr_baseline = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'InputVerificationandResultsSummary', 'Conditioned Window-Wall Ratio', 'Gross Window-Wall Ratio', 'Total', '%').to_f
        # Check WWR against expected WWR
        wwr_goal = 100 * @@wwr_values[building_type].to_f
        assert(wwr_baseline > wwr_goal, "Baseline WWR for the #{building_type}, #{template}, #{climate_zone} model with user data is incorrect. The WWR of the baseline model is #{wwr_baseline} but should be greater than the WWR goal #{wwr_goal}")
      end
      # TODO: adding more tests to check if zones are assigned correctly
      if building_type == 'LargeHotel'
        model_baseline.getThermalZones.each do |thermal_zone|
          thermal_zone_name = thermal_zone.name.get
          # assert(thermal_zone.additionalProperties.hasFeature('building_type_for_hvac'), "Baseline zone #{thermal_zone_name} does not have building_type_for_hvac assigned.")
          if thermal_zone.additionalProperties.hasFeature('building_type_for_hvac')
            bldg_hvac_type = thermal_zone.additionalProperties.getFeatureAsString('building_type_for_hvac').get
            if /_1 ZN/i =~ thermal_zone_name
              # first floor hvac type shall be "retail"
              assert(bldg_hvac_type == 'retail', "Baseline zone #{thermal_zone_name} has incorrect building_type_for_hvac. It should be retail but get #{bldg_hvac_type}")
            else
              # other floors hvac type shall be "residential"
              assert(bldg_hvac_type == 'residential', "Baseline zone #{thermal_zone_name} has incorrect building_type_for_hvac. It should be residential but get #{bldg_hvac_type}")
            end
          end
        end
      end
    end
  end

  #
  # testing method for night cycling control exceptions
  #
  # @param prototypes_base [Hash] Baseline prototypes
  #
  def check_nightcycle_exception(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      if building_type == 'MediumOffice'
        # check for night cycle on lower level
        thermal_zone = model.getThermalZoneByName('Core_bottom ZN').get
        air_loop = thermal_zone.airLoopHVAC.get
        fan_schedule_name = air_loop.availabilitySchedule.name.get
        assert(fan_schedule_name.include?('Always'), "Night cycle exception failed for #{building_type}-#{template}.")
      end
    end
  end

  # Check if number of boilers is correct
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_number_of_boilers(prototypes_base)
    # Find plant loops with boilers and ensure the meet the requirement laid out by G3.1.3.2 of Appendix G 2019
    #
    # G3.1.3.2 Type and Number of Boilers (Systems 1, 5, 7, 11, and 12)
    # The boiler plant shall be natural draft, except as noted in Section G3.1.1.1. The baseline
    # building design boiler plant shall be modeled as having a single boiler if the baseline
    # building design plant serves a conditioned floor area of 15,000 ft2 or less, and as having
    # two equally sized boilers for plants serving more than 15,000 ft2.

    prototypes_base.each do |prototype, model|
      model.getPlantLoops.each do |plant_loop|
        n_boilers = plant_loop.supplyComponents(OpenStudio::Model::BoilerHotWater.iddObjectType).length

        # Skip plant loops with no boilers
        next if n_boilers == 0

        # Find area served by this loop
        standard = Standard.build('90.1-PRM-2019')
        area_served_m2 = standard.plant_loop_total_floor_area_served(plant_loop)
        area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

        # check that the number of boilers equals the amount specified by the standard based on the conditioned floor area
        n_expected_boilers = area_served_ft2 < 15000 ? 1 : 2

        assert(n_boilers == n_expected_boilers,
               msg = "Baseline system failed. Number of boilers equaled #{n_boilers} when it should be #{n_expected_boilers}.
                    Please review section G3.1.3.2 of Appendix G for guidance.")
      end
    end
  end

  # Check if number of chillers is correct
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_number_of_chillers(prototypes_base)
    # Find plant loops with chillers and ensure the meet the requirement laid out by G3.1.3.7 of Appendix G 2019
    #
    # Electric chillers shall be used in the baseline building design regardless of the cooling
    # energy source, e.g. direct-fired absorption or absorption from purchased steam. The
    # baseline building design’s chiller plant shall be modeled with chillers having the number
    # and type as indicated in Table G3.1.3.7 as a function of building peak cooling load.
    #
    # Building Peak Cooling Load Number and Type of Chillers
    # <=300 tons: 1 water-cooled screw chiller
    # >300 tons, <600 tons:  2 water-cooled screw chillers sized equally
    # >=600 tons:  2 water-cooled centrifugal chillers minimum with chillers added so that no chiller is larger than 800 tons, all sized equally

    prototypes_base.each do |prototype, model|
      model.getPlantLoops.each do |plant_loop|
        n_chillers = plant_loop.supplyComponents(OpenStudio::Model::ChillerElectricEIR.iddObjectType).length

        # Skip plant loops with no chillers
        next if n_chillers == 0

        # Check for Autosized chillers. Chillers should have had their capacity set already. Faile
        plant_loop.supplyComponents.each do |sc|
          # ChillerElectricEIR
          if sc.to_ChillerElectricEIR.is_initialized
            chiller = sc.to_ChillerElectricEIR.get

            # Check to make sure chiller is not autosized
            assert(!chiller.isReferenceCapacityAutosized,
                   "Chiller named #{chiller.name} is autosized. The 90.1 PRM model should not have any autosized chillers
                        as this causes issues when finding a chilled plant loop's capacity. Check if the cooling plant sizing run failed.")
          end
        end

        # Initialize Standard class
        standard = Standard.build('90.1-PRM-2019')
        cap_w = standard.plant_loop_total_cooling_capacity(plant_loop)
        cap_tons = OpenStudio.convert(cap_w, 'W', 'ton').get

        if cap_tons <= 300
          n_expected_chillers = 1
        elsif cap_tons > 300 && cap_tons < 600
          n_expected_chillers = 2
        else
          # Max capacity of a single chiller
          max_cap_ton = 800.0
          n_expected_chillers = (cap_tons / max_cap_ton).floor + 1
          # Must be at least 2 chillers
          n_expected_chillers += 1 if n_expected_chillers == 1
        end

        assert(n_chillers == n_expected_chillers,
               msg = "Baseline system failed. Number of chillers equaled #{n_chillers} when it should be #{n_expected_chillers}.
                    Please review section G3.1.3.7 of Appendix G for guidance.")
      end
    end
  end

  # Check if number of towers is correct
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_number_of_cooling_towers(prototypes_base)
    # Find plant loops with chillers + cooling towers and ensure the meet the requirement laid out by Appendix G 2019
    #
    # 3.7.3 Cooling Towers;
    # Only one tower in baseline, regardless of number of chillers
    prototypes_base.each do |prototype, model|
      n_chillers = model.getChillerElectricEIRs.size

      n_cooling_towers = model.getCoolingTowerSingleSpeeds.size
      n_cooling_towers += model.getCoolingTowerTwoSpeeds.size
      n_cooling_towers += model.getCoolingTowerVariableSpeeds.size

      if n_cooling_towers > 0
        assert(n_cooling_towers == 1,
               msg = "Baseline system failed for Appendix G 2019 requirements. Number of cooling towers > 1.
                        The number of chillers equaled #{n_chillers} and the number of cooling towers equaled #{n_cooling_towers}.")
      end
    end
  end

  def check_num_systems_in_zone(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      model_baseline.getAirLoopHVACs.each do |air_loop|
        if air_loop.name.get.downcase == 'core_retail'
          # Normally core retail is > 65 kbtuh
          # With number_of_systems = 30, it will be < 65 kbtuh
          air_loop.supplyComponents.each do |sc|
            # CoilCoolingDXSingleSpeed
            if sc.to_CoilCoolingDXSingleSpeed.is_initialized
              coil = sc.to_CoilCoolingDXSingleSpeed.get
              cop = coil.ratedCOP.to_f
              diff = (cop - 3.0).abs
              assert(diff < 0.1, "Cooling COP for the #{building_type}, #{template}, #{climate_zone} model is incorrect. Expected: 3.0, got: #{cop}.")
            end
          end
        end
      end
    end
  end

  def check_power_equipment_handling(prototypes_base)
    prototypes_base.each do |prototype_base, baseline_model|
      base_building_type, base_template, base_climate_Zone, base_user_data_dir, base_mod = prototype_base
      # user_data_dir match to identify matched propose and baseline
      if base_user_data_dir == 'userdata_pe_01'
        # test case 1, apply 5% RPC (0.5 * 0.1) to Office WholeBuilding -Sm Offie Elec Equip
        base_electric_equipment_schedule = baseline_model.getElectricEquipments[0].schedule.get.to_ScheduleRuleset.get
        receptacle_power_credits = base_electric_equipment_schedule.name.get.split('_')[3].to_f
        assert((0.05 - receptacle_power_credits).abs < 0.0001, "Building: #{base_building_type}; Template: #{base_template}; Climate: #{base_climate_Zone}. The receptacle_power_credits shall be 0.05 (5%) but get #{receptacle_power_credits}")
      elsif base_user_data_dir == 'userdata_pe_02'
        # test case 2, apply 15% RPC (0.15) to Office WholeBuilding -Sm Offie Elec Equip
        base_electric_equipment_schedule = baseline_model.getElectricEquipments[0].schedule.get.to_ScheduleRuleset.get
        receptacle_power_credits = base_electric_equipment_schedule.name.get.split('_')[3].to_f
        assert((0.15 - receptacle_power_credits).abs < 0.0001, "Building: #{base_building_type}; Template: #{base_template}; Climate: #{base_climate_Zone}. The receptacle_power_credits shall be 0.15 (15%) but get #{receptacle_power_credits}")
      elsif base_user_data_dir == 'userdata_pe_03'
        # test case 3, record motor horsepower, efficiency and whether it is exempt
        base_electric_equipment = baseline_model.getElectricEquipments[0]
        base_electric_equipment_ap = base_electric_equipment.additionalProperties
        assert(base_electric_equipment_ap.hasFeature('motor_horsepower') && base_electric_equipment_ap.getFeatureAsDouble('motor_horsepower').get == 10.0,
               'motor_horsepower data is missing or incorrect. The motor_horsepower for test case 3 shall be 10.0')
        assert(base_electric_equipment_ap.hasFeature('motor_efficiency') && base_electric_equipment_ap.getFeatureAsDouble('motor_efficiency').get == 0.72,
               'motor_efficiency data is missing or incorrect. The motor_efficiency for test case 3 shall be 0.72')
        assert(base_electric_equipment_ap.hasFeature('motor_is_exempt') && base_electric_equipment_ap.getFeatureAsBoolean('motor_is_exempt').get == false,
               'motor_is_exempt data is missing or incorrect. The motor_is_exempt for test case 3 shall be False')
      elsif base_user_data_dir == 'userdata_pe_04'
        baseline_equipments = baseline_model.getElectricEquipments
        baseline_equipments.each do |equipment|
          baseline_equipment_name = equipment.name.get
          if baseline_equipment_name == 'Office WholeBuilding - Sm Office Elec Equip'
            base_electric_equipment_schedule = equipment.schedule.get.to_ScheduleRuleset.get
            receptacle_power_credits = base_electric_equipment_schedule.name.get.split('_')[3].to_f
            assert((0.025 - receptacle_power_credits).abs < 0.0001, "Building: #{base_building_type}; Template: #{base_template}; Climate: #{base_climate_Zone}. The receptacle_power_credits shall be 0.025 (5%) but get #{receptacle_power_credits}")          end
        end
      end
    end
  end

  # Check that no pipe insulation is modeled in the baseline models
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_pipe_insulation(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype
      # Check if the model include PipeIndoor or PipeOutdoor objects
      model_baseline.getPlantLoops.each do |plant_loop|
        existing_pipe_insulation = ''
        a = plant_loop.supplyComponents
        b = plant_loop.demandComponents
        plantloop_components = a += b
        plantloop_components.each do |component|
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          next if !['OS_Pipe_Indoor', 'OS_Pipe_Outdoor'].include?(obj_type)

          existing_pipe_insulation = component.name.get
        end
        assert(existing_pipe_insulation.empty?, "The baseline model for the #{building_type}-#{template} in #{climate_zone} has no pipe insulation.")
      end
    end
  end

  # Check if the hvac baseline system from 5 to 13 has the HW and CHW reset control
  # Expected outcome
  # @param prototypes_base[Hash] Baseline prototypes
  def check_hw_chw_reset(prototypes_base)
    # check if the numbers are correct
    chw_low_temp = 15.5
    chw_low_temp_reset = 12.2
    chw_high_temp = 26.7
    chw_high_temp_reset = 6.6
    hw_low_temp = -6.7
    hw_low_temp_reset = 82.2
    hw_high_temp = 10.0
    hw_high_temp_reset = 65.5

    prototypes_base.each do |prototype, baseline_model|
      building_type, template, climate_zone, user_data_dir, mode = prototype

      if baseline_model.getPlantLoops.empty?
        assert(building_type != 'SmallOffice', "No Plant Loop found in the baseline model #{building_type}, #{template}, #{climate_zone}, failure to generate plant loop")
      end

      # first check if the baseline_model has water loops or not (SHW is not included)
      baseline_model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if Standard.new.plant_loop_swh_loop?(plant_loop)

        baseline_model.getSetpointManagerOutdoorAirResets.each do |oa_reset|
          name = oa_reset.name.to_s
          if name.end_with?('CHW Temp Reset')
            low_temp = oa_reset.outdoorLowTemperature
            assert(((low_temp - chw_low_temp).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The outdoor low temperature for the loop #{name} shall be #{chw_low_temp}, but this value is #{low_temp}")
            low_temp_reset = oa_reset.setpointatOutdoorLowTemperature
            assert(((low_temp_reset - chw_low_temp_reset).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The setpoint at outdoor low temperature for the loop #{name} shall be #{chw_low_temp_reset}, but this value is #{low_temp_reset}")
            high_temp = oa_reset.outdoorHighTemperature
            assert(((high_temp - chw_high_temp).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The outdoor high temperature for the loop #{name} shall be #{chw_high_temp}, but this value is #{high_temp}")
            high_temp_reset = oa_reset.setpointatOutdoorHighTemperature
            assert(((high_temp_reset - chw_high_temp_reset).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The setpoint at outdoor high temperature for the loop #{name} shall be #{chw_high_temp_reset}, but this value is #{high_temp_reset}")
          elsif name.end_with?('HW Temp Reset')
            low_temp = oa_reset.outdoorLowTemperature
            assert(((low_temp - hw_low_temp).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The outdoor low temperature for the loop #{name} shall be #{hw_low_temp}, but this value is #{low_temp}")
            low_temp_reset = oa_reset.setpointatOutdoorLowTemperature
            assert(((low_temp_reset - hw_low_temp_reset).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The setpoint at outdoor low temperature for the loop #{name} shall be #{hw_low_temp_reset}, but this value is #{low_temp_reset}")
            high_temp = oa_reset.outdoorHighTemperature
            assert(((high_temp - hw_high_temp).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The outdoor high temperature for the loop #{name} shall be #{hw_high_temp}, but this value is #{high_temp}")
            high_temp_reset = oa_reset.setpointatOutdoorHighTemperature
            assert(((high_temp_reset - hw_high_temp_reset).abs < 0.1), "Baseline #{building_type}, #{template}, #{climate_zone} has incorrect temperature reset value. The setpoint at outdoor high temperature for the loop #{name} shall be #{hw_high_temp_reset}, but this value is #{high_temp_reset}")
          end
        end
      end
    end
  end

  # Check if preheat coil control for system 5 through 8 are implemented
  #
  # @param baseline_base [Hash] Baseline
  def check_preheat_coil_ctrl(baseline_base)
    baseline_base.each do |baseline, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = baseline

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      htg_coil_node_list = []
      model_baseline.getAirLoopHVACs.each do |airloop|
        # Baseline system type identified based on airloop HVAC name
        system_type = airloop.additionalProperties.getFeatureAsString('baseline_system_type').get
        if system_type == 'PVAV_Reheat' || system_type == 'PVAV_PFP_Boxes' || system_type == 'VAV_Reheat' || system_type == 'VAV_PFP_Boxes'
          # Get all Heating Coil in the airloop.
          heating_coil_outlet_node = nil
          airloop.supplyComponents.each do |equip|
            if equip.to_CoilHeatingWater.is_initialized
              htg_coil = equip.to_CoilHeatingWater.get
              heating_coil_outlet_node = htg_coil.airOutletModelObject.get.to_Node.get
            elsif equip.to_CoilHeatingElectric.is_initialized
              htg_coil = equip.to_CoilHeatingElectric.get
              heating_coil_outlet_node = htg_coil.outletModelObject.get.to_Node.get
            elsif equip.to_CoilHeatingGas.is_initialized
              # in this case the test should failed because preheat coil should be either hydronic or eletric
              assert(false, 'Preheat coil shall only be hydronic or electric coils. Coil type: Natural gas')
            else
              next
            end
            # get heating coil spm
            spms = heating_coil_outlet_node.setpointManagers

            # Report if multiple setpoint managers have been assigned to the air loop supply outlet node
            assert(false, 'Multiple setpoint manager have been assigned to the heating coil outlet node.') unless spms.size == 1

            spms.each do |spm|
              if spm.to_SetpointManagerScheduled.is_initialized
                # Get SPM
                spm_s = spm.to_SetpointManagerScheduled.get
                schedule_name = spm_s.schedule.name.to_s
                setpoint_temp_str = schedule_name.split('-')[-1].strip
                # remove the F unit
                setpoint_temp = setpoint_temp_str[0, -1].to_f
                assert((setpoint_temp - 50).abs > 1, "The scheduled temperature is not equal to 50F, instead it is #{setpoint_temp}F")
              else
                assert(false, 'The sepoint manager for preheat coil is not setpointManager:Scheduled.')
              end
            end
          end
        end
      end
    end
  end

  def check_residential_lpd(prototypes_info)
    prototypes_info.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype

      space = model.getSpaceByName('Room_1_Flr_3').get
      lpd_w_per_m2 = space.lightingPowerPerFloorArea
      assert(lpd_w_per_m2 == 2) # 2

      space = model.getSpaceByName('Room_4_Mult19_Flr_3').get
      lpd_w_per_m2 = space.lightingPowerPerFloorArea
      assert(lpd_w_per_m2.round(2) == 4.41)

      space = model.getSpaceByName('Room_3_Mult9_Flr_6').get
      lpd_w_per_m2 = space.lightingPowerPerFloorArea
      assert(lpd_w_per_m2.round(2) == 9.80)
    end
  end

  # Verify if return air plenums are generated
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_return_air_type(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype

      if building_type == 'LargeOffice'
        assert(model.getAirLoopHVACReturnPlenums.length == 3, 'The expected return air plenums in the large office baseline model have not been created.')
      end

      if building_type == 'PrimarySchool'
        assert(model.getAirLoopHVACReturnPlenums.empty?, 'Return air plenums are being modeled in the primary school baseline model, they are not expected.')
      end
    end
  end

  # Check if SAT requirements for system 5 through 8 are implemented
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_sat_ctrl(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      model_baseline.getAirLoopHVACs.each do |airloop|
        # Baseline system type identified based on airloop HVAC name
        if airloop.name.to_s.include?('Sys5') ||
          airloop.name.to_s.include?('Sys6') ||
          airloop.name.to_s.include?('Sys7') ||
          airloop.name.to_s.include?('Sys8')
          # Get all SPM assigned to supply outlet node of the airloop
          spms = airloop.supplyOutletNode.setpointManagers
          spm_check = false

          # Report if multiple setpoint managers have been assigned to the air loop supply outlet node
          assert(false, 'Multiple setpoint manager have been assigned to the air loop supply outlet node.') unless spms.size == 1

          spms.each do |spm|
            if spm.to_SetpointManagerWarmest.is_initialized

              # Get SPM
              spm_w = spm.to_SetpointManagerWarmest.get

              # Retrieve SAT and SAT reset
              max = spm_w.maximumSetpointTemperature
              min = spm_w.minimumSetpointTemperature

              # Calculate difference
              dt_ip = max - min

              # Convert to dT F
              dt_si = OpenStudio.convert(dt_ip, 'K', 'R').get

              # Check if requirement is met for SPM
              spm_check = true if dt_si.round(0) == 5.0
              puts dt_si
            end
          end

          # Check if requirement is met for airloop
          assert(spm_check)
        end
      end
    end
  end

  # Check Skylight-to-Roof Ratio (SRR) for the baseline models
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_srr(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Get srr of baseline model
      srr_baseline = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'InputVerificationandResultsSummary', 'Skylight-Roof Ratio', 'Skylight-Roof Ratio', 'Total', '%').to_f

      # Check WWR against expected WWR
      srr_goal = 3
      assert((srr_baseline - srr_goal).abs < 0.1, "Baseline SRR for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The SRR of the baseline model is #{srr_baseline} but should be #{srr_goal}.")
    end
  end

  def check_unenclosed_spaces(baseline_base)
    baseline_base.each do |baseline, baseline_model|
      building_type, template, climate_zone, user_data_dir, mod = baseline
      if building_type == 'SmallOffice'
        cons_name = baseline_model.getSurfaceByName('Core_ZN_ceiling').get.construction.get.name.to_s
        assert(cons_name == 'PRM IEAD Roof R-15.87', "The #{building_type} baseline model created for check_unenclosed_spaces() does not contain the expected constructions for surface adjacent to an unconditioned space. Expected: PRM IEAD Roof R-15.87; In the model #{cons_name}.")
        cons_name = baseline_model.getSurfaceByName('Core_ZN_ceiling').get.construction.get.name.to_s
        assert(cons_name == 'PRM IEAD Roof R-15.87', "The #{building_type} baseline model created for check_unenclosed_spaces() does not contain the expected constructions for surface adjacent to an unconditioned space. Expected: PRM IEAD Roof R-15.87; In the model #{cons_name}.")
      end
    end
    return true
  end

  # Check model unmet load hours
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_unmet_load_hours(prototypes_base)
    standard = Standard.build('90.1-PRM-2019')
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype

      umlh = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(model)
      assert(umlh < 300, "The #{building_type} prototype building model has more than 300 unmet load hours.")
    end
  end

  # Set ZoneMultiplier to passed value for all zones
  # Check if coefficients of part-load power curve is correct per G3.1.3.15
  def check_variable_speed_fan_power(prototypes_base)
    prototypes_base.each do |prototype, model|
      model.getFanVariableVolumes.each do |supply_fan|
        supply_fan_name = supply_fan.name.get.to_s
        # check fan curves
        # Skip single-zone VAV fans
        next if supply_fan.airLoopHVAC.get.thermalZones.size == 1

        # coefficient 1
        if supply_fan.fanPowerCoefficient1.is_initialized
          expected_coefficient = 0.0013
          coefficient = supply_fan.fanPowerCoefficient1.get
          assert(((coefficient - expected_coefficient) / expected_coefficient).abs < 0.01, "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead")
        end
        # coefficient 2
        if supply_fan.fanPowerCoefficient2.is_initialized
          expected_coefficient = 0.1470
          coefficient = supply_fan.fanPowerCoefficient2.get
          assert(((coefficient - expected_coefficient) / expected_coefficient).abs < 0.01, "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead")
        end
        # coefficient 3
        if supply_fan.fanPowerCoefficient4.is_initialized
          expected_coefficient = 0.9506
          coefficient = supply_fan.fanPowerCoefficient3.get
          assert(((coefficient - expected_coefficient) / expected_coefficient).abs < 0.01, "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead")
        end
        # coefficient 4
        if supply_fan.fanPowerCoefficient4.is_initialized
          expected_coefficient = -0.0998
          coefficient = supply_fan.fanPowerCoefficient4.get
          assert(((coefficient - expected_coefficient) / expected_coefficient).abs < 0.01, "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead")
        end
        # coefficient 5
        if supply_fan.fanPowerCoefficient5.is_initialized
          expected_coefficient = 0
          coefficient = supply_fan.fanPowerCoefficient5.get
          assert((coefficient - expected_coefficient).abs < 0.01, "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead")
        end
      end
    end
  end

  # Check if the VAV box minimum flow setpoint are
  # assigned following the rules in Appendix G
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_vav_min_sp(prototypes_base)
    prototypes_base.each do |prototype, model|
      building_type, template, climate_zone, mod = prototype
      model.getAirLoopHVACs.each do |air_loop|
        air_loop.thermalZones.each do |zone|
          zone.equipment.each do |equip|
            if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
              zone_oa = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
              vav_terminal = equip.to_AirTerminalSingleDuctVAVReheat.get
              expected_mdp = [zone_oa / vav_terminal.autosizedMaximumAirFlowRate.get, 0.3].max.round(2)
              actual_mdp = vav_terminal.constantMinimumAirFlowFraction.get.round(2)
              assert(expected_mdp == actual_mdp, "Minimum MDP for #{building_type} for #{template} in #{climate_zone} should be #{expected_mdp} but #{actual_mdp} is used in the model.")
            elsif equip.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized
              zone_oa = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
              fp_vav_terminal = equip.to_AirTerminalSingleDuctParallelPIUReheat.get
              expected_prim_frac = [zone_oa / fp_vav_terminal.autosizedMaximumPrimaryAirFlowRate.get, 0.3].max.round(2)
              actual_prim_frac = fp_vav_terminal.minimumPrimaryAirFlowFraction.get
              assert(expected_prim_frac == actual_prim_frac, "Minimum primary air flow fraction for #{building_type} for #{template} in #{climate_zone} should be #{expected_prim_frac} but #{actual_prim_frac} is used in the model.")
            end
          end
        end
      end
    end
  end

  # Check Window-to-Wall Ratio (WWR) for the baseline models
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_wwr(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      building_type, template, climate_zone, user_data_dir, mod = prototype

      # Get WWR of baseline model
      wwr_baseline = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'InputVerificationandResultsSummary', 'Conditioned Window-Wall Ratio', 'Gross Window-Wall Ratio', 'Total', '%').to_f
      if building_type == 'MediumOffice'
        # In 3.5 the conditioned window-wall ratio table does not consider plenum as indirectly conditioned space, so we need to take out the value from window-wall ratio table.
        wwr_baseline = OpenstudioStandards::SqlFile.model_tabular_data_query(model_baseline, 'InputVerificationandResultsSummary', 'Window-Wall Ratio', 'Gross Window-Wall Ratio', 'Total', '%').to_f
      end
      # Check WWR against expected WWR
      wwr_goal = 100 * @@wwr_values[building_type].to_f
      if building_type == 'MidriseApartment' && climate_zone == 'ASHRAE 169-2013-3A'
        assert(((wwr_baseline - 40.0) / 40.0).abs < 0.01, "Baseline WWR for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The WWR of the baseline model is #{wwr_baseline} but should be #{wwr_goal}.")
      else
        assert(((wwr_baseline - wwr_goal) / wwr_goal).abs < 0.01, "Baseline WWR for the #{building_type}, #{template}, #{climate_zone} model is incorrect. The WWR of the baseline model is #{wwr_baseline} but should be #{wwr_goal}.")
      end
    end
  end

  def check_swh_single_building_type(prototypes_base)
    prototypes_base.each do |prototype, model_baseline|
      # set the fuel type according to the building area type (Small Office)
      new_fuel = "Electricity"
      water_heater_efficiency = 1.0
      ua_w_per_k = 0.9647
      model_baseline.getWaterHeaterMixeds.sort.each do |water_heater|
        assert(water_heater.heaterFuelType == new_fuel, "New fuel type is not the expected value.")
        assert((water_heater.heaterThermalEfficiency.get - water_heater_efficiency)/water_heater_efficiency < 0.01, "New efficiency is not the expected value.")
        assert((water_heater.offCycleLossCoefficienttoAmbientTemperature.get - ua_w_per_k)/ua_w_per_k < 0.01, "New surface loss coefficient is not the expected value.")
      end
    end
  end

  # Check primary/secondary chilled water loop for the baseline models
  #
  # @param prototypes_base [Hash] Baseline prototypes
  def check_pri_sec_loop(prototypes_base)

    prototypes_base.each do |prototype, model_baseline|

      building_type, template, climate_zone, user_data_dir, mod = prototype

      has_primary_chilled_water_loop = false
      has_secondary_chilled_water_loop = false

      # Check primary and secondary chilled water loops
      model_baseline.getPlantLoops.each do |plant_loop|

        sizing_plant = plant_loop.sizingPlant

        next if sizing_plant.loopType != 'Cooling'

        # Check primary loop for components
        if plant_loop.name.to_s.include? 'Chilled Water Loop_Primary'

          has_primary_chilled_water_loop = true

          n_chillers = 0

          # Count chillers
          plant_loop.supplyComponents.each do |sc|
            if sc.to_ChillerElectricEIR.is_initialized
              n_chillers += 1
            end
          end

          assert(n_chillers == 2, "The number of chillers in the primary loop is incorrect. The test results in #{n_chillers} when it should be 2.")

          has_heat_exchanger = false

          # Check for heat exchanger on demand side
          plant_loop.demandComponents.each do |dc|
            if dc.to_HeatExchangerFluidToFluid.is_initialized
              has_heat_exchanger = true
            end
          end

          assert(has_heat_exchanger, "The primary chilled water loop should have a HeatExchangerFluidToFluid on the demand side but it does not.")

        # Check secondary loop for components
        elsif plant_loop.name.to_s.include? 'Chilled Water Loop'

          has_secondary_chilled_water_loop = true
          has_heat_exchanger = false

          # Check for heat exchanger on supply side
          plant_loop.supplyComponents.each do |sc|
            if sc.to_HeatExchangerFluidToFluid.is_initialized
              has_heat_exchanger = true
            end
          end

          assert(has_heat_exchanger, "The secondary chilled water loop should have a HeatExchangerFluidToFluid on the supply side but it does not.")

        end

      end

      assert(has_primary_chilled_water_loop, "The primary/secondary test did not find a primary chilled water loop for #{building_type}, #{template}, #{climate_zone}.")
      assert(has_secondary_chilled_water_loop, "The primary/secondary test did not find a secondary chilled water loop for #{building_type}, #{template}, #{climate_zone}.")

    end
  end
end