require_relative '../helpers/minitest_helper'

class ACM179dASHRAE9012007Test < Minitest::Test

  @@logSink = nil

  def suite_init
    OpenStudio::Logger.instance.standardOutLogger.disable
    sink = OpenStudio::StringStreamLogSink.new
    sink.setLogLevel(OpenStudio::Warn)
    sink
  end

  attr_accessor :template, :standard, :model
  def setup
    @@logSink ||= suite_init
    @@logSink.resetStringStream

    @template = '179D 90.1-2007'
    @standard = Standard.build(@template)

    model = OpenStudio::Model::exampleModel
    model.getSpaceTypes.map(&:remove)

    spaces = model.getSpaces.sort_by(&:nameString)

    wh_bulk = OpenStudio::Model::SpaceType.new(model)
    wh_bulk.setName("Warehouse Bulk")
    wh_bulk.setStandardsBuildingType('Warehouse')
    wh_bulk.setStandardsSpaceType('Bulk')
    spaces[0].setSpaceType(wh_bulk)
    spaces[1].setSpaceType(wh_bulk)

    wh_office = OpenStudio::Model::SpaceType.new(model)
    wh_office.setName("Warehouse Office")
    wh_office.setStandardsBuildingType('Warehouse')
    wh_office.setStandardsSpaceType('Office')
    spaces[2].setSpaceType(wh_bulk)

    retail_pt_sale = OpenStudio::Model::SpaceType.new(model)
    retail_pt_sale.setName("Retail POS")
    retail_pt_sale.setStandardsBuildingType('Retail')
    retail_pt_sale.setStandardsSpaceType('Point_of_Sale')
    spaces[3].setSpaceType(retail_pt_sale)
    @model = model
  end

  def log_errors
    @@logSink.logMessages.select{ |l| l.logLevel == OpenStudio::Error }.map(&:logMessage)
  end

  def log_warnings
    @@logSink.logMessages.select{ |l| l.logLevel == OpenStudio::Warn }.map(&:logMessage)
  end


  def test_model_get_primary_building_type
    assert_equal('Warehouse', @standard.model_get_primary_building_type(@model))

    # Avoid the memoization by calling the static method instead
    # Space Type area method is prefered
    @model.getBuilding.setStandardsBuildingType("Office")
    assert_equal('Warehouse', @standard.__model_get_primary_building_type(@model))
    assert_equal(0, log_errors.size)
    assert_equal(1, log_warnings.size)
    assert_match(
      /The Building has standardsBuildingType 'Office' while the area determination based on space types has 'Warehouse'. Preferring the Space Type one/,
      log_warnings.first,
    )
    @@logSink.resetStringStream


    # When Space Type area not found, use building
    @model.getSpaceTypes.each(&:resetStandardsBuildingType)
    assert_equal('Office', @standard.__model_get_primary_building_type(@model))

    # When neither: it throws
    @model.getBuilding.resetStandardsBuildingType
    assert_raises(RuntimeError, 'No Primary Building Type found') { @standard.__model_get_primary_building_type(@model) }
    assert_equal(1, log_errors.size)
    assert_equal(0, log_warnings.size)
    assert_equal("Cannot identify a single building type in model, none of your 3 SpaceTypes have a standardsBuildingType assigned and neither does the Building",
                 log_errors.first)
  end

  def test_model_get_standards_data
    assert_equal('Warehouse', standard.model_get_primary_building_type(model))

    data = standard.model_get_standards_data(model)
    assert_equal('179d-90.1-2007', data['template'])
    assert_equal('Warehouse', data['building_type'])
    assert_equal('WholeBuilding', data['space_type'])
    assert_equal('ASHRAE 90.1-2007', data['lighting_standard'])
    assert_equal('WholeBuilding', data['lighting_primary_space_type'])
    assert_equal('Warehouse', data['lighting_secondary_space_type'])
    assert_equal('Nonres_HVAC_Sch', data['hvac_operation_schedule'])
  end

  def test_space_type_get_standards_data
    assert_equal('Warehouse', standard.model_get_primary_building_type(model))

    model.getSpaceTypes.each do |space_type|
      data = standard.space_type_get_standards_data(space_type)
      assert_equal('179d-90.1-2007', data['template'])
      assert_equal('Warehouse', data['building_type'])
      assert_equal('WholeBuilding', data['space_type'])
      assert_equal('ASHRAE 90.1-2007', data['lighting_standard'])
      assert_equal('WholeBuilding', data['lighting_primary_space_type'])
      assert_equal('Warehouse', data['lighting_secondary_space_type'])
    end

    space_type = model.getSpaceTypes.select { |sp| sp.standardsSpaceType.get == 'Bulk' }.first

    data_only_179d = standard.space_type_get_standards_data(space_type, extend_with_2007: false)
    assert_empty(data_only_179d.select{|k, _| ['ventilation', 'exhaust'].any? { |x| k.include?(x) } })

    std_2007 = Standard.build('90.1-2007')
    data2007 = std_2007.space_type_get_standards_data(space_type)
    refute_empty(data2007.select{|k, _| ['ventilation', 'exhaust'].any? { |x| k.include?(x) } })

    # This is the merged data
    data = standard.space_type_get_standards_data(space_type)
    refute_empty(data.select{|k, _| ['ventilation', 'exhaust'].any? { |x| k.include?(x) } })

    # All keys from 2007 and in our
    assert_empty(data2007.keys - data.keys)

    assert_includes(data.keys, 'space_type_2007')
    enhanced_keys = data.keys - data_only_179d.keys - ['space_type_2007']
    refute_empty(enhanced_keys)
    assert_equal(25, enhanced_keys.size)

    # Ensure all keys defined specifically in 179D are left untouched
    data_only_179d.keys.each do |k|
      if data_only_179d[k].nil?
        assert_nil(data[k])
      else
        assert_equal(data_only_179d[k], data[k])
      end
    end
    # Ensure all enhanced keys are directly from 2007
    enhanced_keys.each do |k|
      if data2007[k].nil?
        assert_nil(data[k])
      else
        assert_equal(data2007[k], data[k])
      end
    end

    assert_equal('179d-90.1-2007', data['template'])
    assert_equal('Warehouse', data['building_type'])
    assert_equal('WholeBuilding', data['space_type'])
    assert_equal('Bulk', data['space_type_2007'])

    assert_equal('ASHRAE 90.1-2007', data['lighting_standard'])
    assert_equal('WholeBuilding', data['lighting_primary_space_type'])
    assert_equal('Warehouse', data['lighting_secondary_space_type'])
    assert_in_delta(0.8, data['lighting_per_area'])
    assert_nil(data['rcr_threshold'])
    assert_nil(data['lighting_per_person'])
    assert_nil(data['additional_lighting_per_area'])
    assert_in_delta(0.0, data['lighting_fraction_to_return_air'])
    assert_in_delta(0.42, data['lighting_fraction_radiant'])
    assert_in_delta(0.18, data['lighting_fraction_visible'])
    assert_in_delta(1.0, data['lighting_fraction_replaceable'])
    assert_in_delta(1.0, data['lpd_fraction_linear_fluorescent'])
    assert_nil(data['lpd_fraction_compact_fluorescent'])
    assert_nil(data['lpd_fraction_high_bay'])
    assert_nil(data['lpd_fraction_specialty_lighting'])
    assert_nil(data['lpd_fraction_exit_lighting'])
    assert_equal('Nonres_Light_Sch', data['lighting_schedule'])
    assert_nil(data['compact_fluorescent_lighting_schedule'])
    assert_nil(data['high_bay_lighting_schedule'])
    assert_nil(data['specialty_lighting_schedule'])
    assert_nil(data['exit_lighting_schedule'])
    assert_nil(data['target_illuminance_setpoint'])
    assert_nil(data['psa_nongeometry_fraction'])
    assert_nil(data['ssa_nongeometry_fraction'])
    assert_nil(data['notes'])
    assert_nil(data['gas_equipment_per_area'])
    assert_nil(data['gas_equipment_fraction_latent'])
    assert_nil(data['gas_equipment_fraction_radiant'])
    assert_nil(data['gas_equipment_fraction_lost'])
    assert_nil(data['gas_equipment_schedule'])
    assert_in_delta(0.43, data['electric_equipment_per_area'])
    assert_in_delta(0.0, data['electric_equipment_fraction_latent'])
    assert_in_delta(0.5, data['electric_equipment_fraction_radiant'])
    assert_in_delta(0.0, data['electric_equipment_fraction_lost'])
    assert_equal('Nonres_Equip_Sch', data['electric_equipment_schedule'])
    assert_nil(data['additional_electric_equipment_schedule'])
    assert_nil(data['additional_gas_equipment_schedule'])
    assert_in_delta(5.0, data['occupancy_per_area'])
    assert_equal('Nonres_Occ_Sch', data['occupancy_schedule'])
    assert_equal('ACM_Warehouse_ACTIVITY_SCH', data['occupancy_activity_schedule'])
    assert_nil(data['is_residential'])

    assert_nil(data['infiltration_per_exterior_area'])
    assert_in_delta(0.038, data['infiltration_per_exterior_wall_area'])
    assert_nil(data['infiltration_air_changes'])
    assert_equal('Nonres_Infil_Sch', data['infiltration_schedule'])
    assert_nil(data['infiltration_schedule_perimeter'])
    assert_equal('Nonres_Heat_Sch', data['heating_setpoint_schedule'])
    assert_equal('Warehouse_Cool_Sch', data['cooling_setpoint_schedule'])
    assert_nil(data['service_water_heating_peak_flow_rate'])
    assert_nil(data['service_water_heating_area'])
    assert_in_delta(0.0007, data['service_water_heating_peak_flow_per_area'])
    assert_equal("Shared", data['service_water_heating_system_type'])
    assert_nil(data['booster_water_heater_fraction'])
    assert_in_delta(140.0, data['service_water_heating_target_temperature'])
    assert_nil(data['booster_water_heating_target_temperature'])
    assert_equal(0.2, data['service_water_heating_fraction_sensible'])
    assert_equal(0.05, data['service_water_heating_fraction_latent'])
    assert_equal('Nonres_SWH_Sch', data['service_water_heating_schedule'])

    # Enhanced from 2007, based on actual Space Type
    assert_equal('ASHRAE 62.1-2004', data['ventilation_standard'])
    assert_equal('Miscellaneous Spaces', data['ventilation_primary_space_type'])
    assert_equal('Warehouses', data['ventilation_secondary_space_type'])
    assert_in_delta(0.06, data['ventilation_per_area'])
    assert_nil(data['ventilation_per_person'])
    assert_nil(data['ventilation_air_changes'])
    assert_nil(data['minimum_total_air_changes'])

    assert_nil(data['manual_continuous_dimming'])
    assert_nil(data['programmable_multilevel_dimming'])
    assert_nil(data['multilevel_occupancy_sensors'])
    assert_nil(data['occupancy_sensors'])
    assert_nil(data['occupancy_sensors_with_personal_continuous_dimming'])
    assert_nil(data['automatic_multilevel_switching_in_primary_sidelighted_areas'])
    assert_nil(data['automatic_continuous_daylight_dimming_in_primary_sidelighted_areas'])
    assert_nil(data['automatic_continuous_daylight_dimming_in_secondary_sidelighted_areas'])
    assert_nil(data['automatic_continuous_daylight_dimming_in_daylighted_areas_under_skylights'])
    assert_nil(data['exhaust_per_area'])
    assert_nil(data['exhaust_fan_efficiency'])
    assert_nil(data['exhaust_fan_power'])
    assert_nil(data['exhaust_fan_pressure_rise'])
    assert_nil(data['exhaust_fan_maximum_flow_rate'])
    assert_nil(data['exhaust_availability_schedule'])
    assert_nil(data['exhaust_flow_fraction_schedule'])
    assert_nil(data['balanced_exhaust_fraction_schedule'])
    assert_equal('41_31_169', data['rgb'])
  end

  TEST_BASELINE_SYS_NUM_DATA = [
      # area_type, area_ft2, num_stories, expected
      ['residential', 24_999, 1, '1_or_2'],
      ['residential', 24_999, 10, '1_or_2'],

      ['nonresidential', 24_900, 3, '3_or_4'],

      ['nonresidential', 24_900, 4, '5_or_6'],
      ['nonresidential', 24_900, 5, '5_or_6'],
      ['nonresidential', 75_000, 4, '5_or_6'],
      ['nonresidential', 75_900, 5, '5_or_6'],

      ['nonresidential', 24_900, 10, '7_or_8'],
      ['nonresidential', 150_001, 1, '7_or_8'],
      ['nonresidential', 150_001, 10, '7_or_8'],

      ['heatedonly', 24_900, 1, '9_or_10'],
      ['heatedonly', 150_001, 1, '9_or_10'],
      ['heatedonly', 150_001, 10, '9_or_10'],
  ]
  TEST_BASELINE_SYS_NUM_DATA.each do |area_type, area_ft2, num_stories, expected_system_number|
    define_method("test_model_prm_baseline_system_number_#{area_type}_#{area_ft2.to_i}sqft_#{num_stories}floors") do
      _model = nil
      _climate_zone = nil
      _fuel_type = nil
      custom = ''

      assert_equal(expected_system_number, @standard.model_prm_baseline_system_number(_model, _climate_zone, area_type, _fuel_type, area_ft2, num_stories, custom))
    end
  end

  def test_zone_hvac_component_apply_standard_controls
    fan = OpenStudio::Model::FanSystemModel.new(model)
    heating_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    cooling_coil = OpenStudio::Model::CoilCoolingWater.new(model)
    four_pipe_fan_coil = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, model.alwaysOnDiscreteSchedule, fan, cooling_coil, heating_coil)
    four_pipe_fan_coil.addToThermalZone(model.getThermalZones.first)

    assert_empty(four_pipe_fan_coil.supplyAirFanOperatingModeSchedule)

    four_pipe_fan_coil.setMaximumOutdoorAirFlowRate(0.0)
    standard.zone_hvac_component_apply_standard_controls(four_pipe_fan_coil.to_ZoneHVACComponent.get)
    assert_empty(four_pipe_fan_coil.supplyAirFanOperatingModeSchedule)

    four_pipe_fan_coil.autosizeMaximumOutdoorAirFlowRate
    assert_empty(four_pipe_fan_coil.maximumOutdoorAirFlowRate)
    assert four_pipe_fan_coil.isMaximumOutdoorAirFlowRateAutosized
    standard.zone_hvac_component_apply_standard_controls(four_pipe_fan_coil.to_ZoneHVACComponent.get)
    refute_empty(four_pipe_fan_coil.supplyAirFanOperatingModeSchedule)

    four_pipe_fan_coil.resetSupplyAirFanOperatingModeSchedule
    four_pipe_fan_coil.setMaximumOutdoorAirFlowRate(0.1)
    standard.zone_hvac_component_apply_standard_controls(four_pipe_fan_coil.to_ZoneHVACComponent.get)
    refute_empty(four_pipe_fan_coil.supplyAirFanOperatingModeSchedule)
  end

  def test_model_apply_acm_hvac_availability_schedule
    model = OpenStudio::Model.exampleModel

    building = model.getBuilding
    building.setStandardsBuildingType('PrimarySchool')

    _airloophvac = OpenStudio::Model::AirLoopHVAC.new(model)

    _baseboardconvectiveelectric = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)

    baseboardconvectivewater_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
    _baseboardconvectivewater = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model, model.alwaysOnDiscreteSchedule, baseboardconvectivewater_coil)

    _baseboardradiantconvectiveelectric = OpenStudio::Model::ZoneHVACBaseboardRadiantConvectiveElectric.new(model)

    _baseboardradiantconvectivewater = OpenStudio::Model::ZoneHVACBaseboardRadiantConvectiveWater.new(model)

    _coolingpanelradiantconvectivewater = OpenStudio::Model::ZoneHVACCoolingPanelRadiantConvectiveWater.new(model)

    _dehumidifierdx = OpenStudio::Model::ZoneHVACDehumidifierDX.new(model)

    _energyrecoveryventilator = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator.new(model)

    fourPipeFan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
    fourPipeHeat = OpenStudio::Model::CoilHeatingWater.new(model, model.alwaysOnDiscreteSchedule)
    fourPipeCool = OpenStudio::Model::CoilCoolingWater.new(model, model.alwaysOnDiscreteSchedule)
    _fourPipeFanCoil = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, model.alwaysOnDiscreteSchedule,
                                                                     fourPipeFan, fourPipeCool, fourPipeHeat)

    _hightemperatureradiant = OpenStudio::Model::ZoneHVACHighTemperatureRadiant.new(model)

    _idealloadsairsystem = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)

    lowtemperatureradiantelectric_tempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtemperatureradiantelectric_tempSched.setValue(10.0)
    _lowtemperatureradiantelectric = OpenStudio::Model::ZoneHVACLowTemperatureRadiantElectric.new(model, model.alwaysOnDiscreteSchedule, lowtemperatureradiantelectric_tempSched)

    lowtempradiantconstflow_coolingHighWaterTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_coolingLowWaterTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_coolingHighControlTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_coolingLowControlTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_heatingHighWaterTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_heatingLowWaterTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_heatingHighControlTempSched = OpenStudio::Model::ScheduleConstant.new(model)
    lowtempradiantconstflow_heatingLowControlTempSched = OpenStudio::Model::ScheduleConstant.new(model)

    lowtempradiantconstflow_coolingHighWaterTempSched.setValue(15.0)
    lowtempradiantconstflow_coolingLowWaterTempSched.setValue(10.0)
    lowtempradiantconstflow_coolingHighControlTempSched.setValue(25.0)
    lowtempradiantconstflow_coolingLowControlTempSched.setValue(21.0)
    lowtempradiantconstflow_heatingHighWaterTempSched.setValue(50.0)
    lowtempradiantconstflow_heatingLowWaterTempSched.setValue(30.0)
    lowtempradiantconstflow_heatingHighControlTempSched.setValue(20.0)
    lowtempradiantconstflow_heatingLowControlTempSched.setValue(17.0)
    lowtempradiantconstflow_heat_coil = OpenStudio::Model::CoilHeatingLowTempRadiantConstFlow.new(model, lowtempradiantconstflow_heatingHighWaterTempSched, lowtempradiantconstflow_heatingLowWaterTempSched, lowtempradiantconstflow_heatingHighControlTempSched, lowtempradiantconstflow_heatingLowControlTempSched)
    lowtempradiantconstflow_cool_coil = OpenStudio::Model::CoilCoolingLowTempRadiantConstFlow.new(model, lowtempradiantconstflow_coolingHighWaterTempSched, lowtempradiantconstflow_coolingLowWaterTempSched, lowtempradiantconstflow_coolingHighControlTempSched, lowtempradiantconstflow_coolingLowControlTempSched)
    _lowtempradiantconstflow = OpenStudio::Model::ZoneHVACLowTempRadiantConstFlow.new(model, model.alwaysOnDiscreteSchedule, lowtempradiantconstflow_heat_coil, lowtempradiantconstflow_cool_coil, 200.0)

    _lowtempradiantvarflow = OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow.new(model)

    ptac_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    ptac_clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    ptac_fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
    _ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model, model.alwaysOffDiscreteSchedule, ptac_fan, ptac_htg_coil, ptac_clg_coil)

    pthp_htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    pthp_clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    pthp_fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
    pthp_supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    _pthp = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(model, model.alwaysOffDiscreteSchedule, pthp_fan, pthp_htg_coil, pthp_clg_coil, pthp_supp_htg_coil)

    unitheater_fan = OpenStudio::Model::FanConstantVolume.new(model, model.alwaysOnDiscreteSchedule)
    unitheater_coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOnDiscreteSchedule)
    _unitheater = OpenStudio::Model::ZoneHVACUnitHeater.new(model, model.alwaysOnDiscreteSchedule, unitheater_fan, unitheater_coil)

    _unitventilator = OpenStudio::Model::ZoneHVACUnitVentilator.new(model)

    wtahp_fan = OpenStudio::Model::FanOnOff.new(model)
    wtahp_DXHC = OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit.new(model)
    wtahp_DXCC = OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit.new(model)
    wtahp_supplementalHC = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOnDiscreteSchedule)
    _wtahp = OpenStudio::Model::ZoneHVACWaterToAirHeatPump.new(model, model.alwaysOnDiscreteSchedule, wtahp_fan, wtahp_DXHC, wtahp_DXCC, wtahp_supplementalHC)

    _airloophvacunitarysystem = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)

    avail_sch = OpenStudio::Model::ScheduleConstant.new(model)

    ACM179dASHRAE9012007::HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      objects = model.send("get#{hvac_type}s")
      refute_empty objects, "Missing object of type #{hvac_type} in model"
      obj = objects.first
      methods.each do |getter, setter|
        assert obj.respond_to?(getter)
        assert obj.respond_to?(setter)
        assert obj.send(setter, avail_sch)
      end
    end

    assert standard.model_apply_acm_hvac_availability_schedule(model)

    ACM179dASHRAE9012007::HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      objects = model.send("get#{hvac_type}s")
      refute_empty objects, "Missing object of type #{hvac_type} in model"
      objects.each do |obj|
        methods.each do |getter, _|
          new_avail_sch = obj.send(getter)
          # if new_avail_sch.class.name.include?('OptionalSchedule')
          if new_avail_sch.respond_to?(:get)
            new_avail_sch = new_avail_sch.get
          end
          refute_equal(avail_sch, new_avail_sch, "#{obj.briefDescription}: #{getter}")
          assert_equal('SchoolPrimary_HVAC_Sch', new_avail_sch.nameString, "#{obj.briefDescription}: #{getter}")
        end
      end
    end
  end

  def test_space_type_apply_internal_loads_also_sets_people_fraction_sensible

    set_people = true
    set_lights = false
    set_electric_equipment = false
    set_gas_equipment = false
    set_ventilation = false
    set_infiltration = false

    data = standard.model_get_standards_data(model)
    assert_equal(0.399, data['occupancy_fraction_sensible'])

    model.getSpaceTypes.each do |space_type|
      standard.space_type_apply_internal_loads(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration)
      assert_equal(1, space_type.people.size)
      p = space_type.people.first
      pd = p.peopleDefinition
      refute_empty(pd.sensibleHeatFraction)
      assert_equal(data['occupancy_fraction_sensible'],  pd.sensibleHeatFraction.get)
    end
  end

  def test_179d_extending_materials_and_constructions
    std_2007 = Standard.build('90.1-2007')

    assert_equal(standard.standards_data['materials'].size,
                 std_2007.standards_data['materials'].size + 3)

    assert_equal(standard.standards_data['constructions'].size,
                 std_2007.standards_data['constructions'].size + 3)
  end

  def test_all_windows_have_a_construction_and_material

    intended_surface_types = ["ExteriorWindow"] #, "GlassDoor", "Skylight"]
    standard.standards_data['construction_properties'].each do |construction_props|

      next if intended_surface_types.none?{|t| construction_props['intended_surface_type'] == t}

      construction_name = construction_props['construction']

      construction = standard.standards_data['constructions'].find { |x| x['name'] == construction_name }
      refute_nil(construction, "Construction '#{construction_name}' not found: #{construction_props}")

      # assert_equal(1, construction['materials'].size, "Construction '#{construction_name}' has more than one layer: #{construction_props}")

      construction['materials'].each do |material_name|
        material = standard.standards_data['materials'].find { |x| x['name'] == material_name }
        refute_nil(material, "Material '#{material_name}' not found")
      end
    end
  end

  def test_space_type_apply_internal_load_schedules_override
    set_people = false
    set_lights = false
    set_electric_equipment = false
    set_gas_equipment = false
    set_ventilation = false
    set_infiltration = false
    make_thermostat = true

    @model.getThermostatSetpointDualSetpoints.each(&:remove)

    assert_equal(0, @model.getThermostatSetpointDualSetpoints.size)

    @model.getSpaceTypes.each do |space_type|
      @standard.space_type_apply_internal_load_schedules(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration, make_thermostat)
    end

    assert_equal(3, @model.getThermostatSetpointDualSetpoints.size)

    expected_tstats = {
      'Warehouse Office Thermostat' => {
        'heating_sch' => 'Nonres_Heat_Sch',
        'cooling_sch' => 'Nonres_Cool_Sch'  # <----
      },
      'Warehouse Bulk Thermostat' => {
        'heating_sch' => 'Nonres_Heat_Sch',
        'cooling_sch' => 'Warehouse_Cool_Sch'
      },
      'Retail POS Thermostat' => {
        'heating_sch' => 'Nonres_Heat_Sch',
        'cooling_sch' => 'Warehouse_Cool_Sch'
      }
    }

    expected_tstats.each do |tstat_name, tstat_info|
      refute_empty(@model.getThermostatSetpointDualSetpointByName(tstat_name))
      tstat = @model.getThermostatSetpointDualSetpointByName(tstat_name).get
      refute_empty(tstat.heatingSetpointTemperatureSchedule)
      assert_equal(tstat_info['heating_sch'], tstat.heatingSetpointTemperatureSchedule.get.nameString)

      refute_empty(tstat.coolingSetpointTemperatureSchedule)
      assert_equal(tstat_info['cooling_sch'], tstat.coolingSetpointTemperatureSchedule.get.nameString)
    end
  end

  def test_airloop_hvac_dcv
    a = @model.getAirLoopHVACs.first
    assert_equal(1, a.thermalZones.size)
    z = @model.getThermalZones.first
    refute(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z))
    refute(@standard.baseline_air_loop_hvac_demand_control_ventilation_required?(a))
    z.additionalProperties.setFeature("apxg no need to have DCV", true)
    z.additionalProperties.setFeature("zone DCV implemented in user model", true)
    refute(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z))
    refute(@standard.baseline_air_loop_hvac_demand_control_ventilation_required?(a))
    z.additionalProperties.setFeature("apxg no need to have DCV", false)
    z.additionalProperties.setFeature("zone DCV implemented in user model", false)
    refute(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z))
    refute(@standard.baseline_air_loop_hvac_demand_control_ventilation_required?(a))
    z.additionalProperties.setFeature("apxg no need to have DCV", false)
    z.additionalProperties.setFeature("zone DCV implemented in user model", true)
    assert(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z))
    assert(@standard.baseline_air_loop_hvac_demand_control_ventilation_required?(a))

    refute_empty(a.airLoopHVACOutdoorAirSystem)
    oa_sys = a.airLoopHVACOutdoorAirSystem.get
    controller_oa = oa_sys.getControllerOutdoorAir
    controller_mv = controller_oa.controllerMechanicalVentilation
    refute(controller_mv.demandControlledVentilation)

    climate_zone = 'ASHRAE 169-2013-5A'
    @standard.model_set_baseline_demand_control_ventilation(@model, climate_zone)
    assert(controller_mv.demandControlledVentilation)

    # To produce the original crash, we need a second thermal zone on the
    # AirLoopHVAC that does NOT need DCV
    s2 = z.spaces.last
    z2 = OpenStudio::Model::ThermalZone.new(@model)
    s2.setThermalZone(z2)
    a.addBranchForZone(z2)
    # Assign a  DSOA that is not per floor area
    dsoa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(@model)
    dsoa.setName("DSOA ACH")
    dsoa.setOutdoorAirFlowAirChangesperHour(0.5)
    @model.getSpaces.each {|s| s.setDesignSpecificationOutdoorAir(dsoa) }

    assert(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z))
    refute(@standard.baseline_thermal_zone_demand_control_ventilation_required?(z2))
    assert(@standard.baseline_air_loop_hvac_demand_control_ventilation_required?(a))
    assert_equal(1, @model.getDesignSpecificationOutdoorAirs.size)
    @standard.model_set_baseline_demand_control_ventilation(@model, climate_zone)
    # One regular, one per area
    assert_equal(2, @model.getDesignSpecificationOutdoorAirs.size)

    refute_empty(s2.designSpecificationOutdoorAir)
    refute_equal(dsoa, s2.designSpecificationOutdoorAir.get)
    assert_equal("DSOA ACH to per-area", s2.designSpecificationOutdoorAir.get.nameString)
    refute_equal(dsoa, s2.designSpecificationOutdoorAir.get)
    assert_equal(0.0, s2.designSpecificationOutdoorAir.get.outdoorAirFlowAirChangesperHour)
    assert_equal(0.0, s2.designSpecificationOutdoorAir.get.outdoorAirFlowperPerson)
    assert_equal(0.0, s2.designSpecificationOutdoorAir.get.outdoorAirFlowRate)
    assert(s2.designSpecificationOutdoorAir.get.outdoorAirFlowperFloorArea > 0)

    z.spaces.each do |s|
      assert_equal(dsoa, s.designSpecificationOutdoorAir.get)
      assert_equal("DSOA ACH", s.designSpecificationOutdoorAir.get.nameString)
      assert_equal(dsoa, s.designSpecificationOutdoorAir.get)
      assert_equal(0.5, s.designSpecificationOutdoorAir.get.outdoorAirFlowAirChangesperHour)
      assert_equal(0.0, s.designSpecificationOutdoorAir.get.outdoorAirFlowperFloorArea)
      assert_equal(0.0, s.designSpecificationOutdoorAir.get.outdoorAirFlowperPerson)
      assert_equal(0.0, s.designSpecificationOutdoorAir.get.outdoorAirFlowRate)
    end

  end
end
