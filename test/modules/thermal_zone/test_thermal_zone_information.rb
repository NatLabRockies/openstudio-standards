require_relative '../../helpers/minitest_helper'

class TestThermalZone < Minitest::Test
  def setup
    @zone = OpenstudioStandards::ThermalZone
    @sch = OpenstudioStandards::Schedules
  end

  def test_thermal_zone_plenum?
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    space.setName('some space')
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    assert_equal(false, @zone.thermal_zone_plenum?(thermal_zone))

    space.setPartofTotalFloorArea(false)
    assert_equal(true, @zone.thermal_zone_plenum?(thermal_zone))

    space.setPartofTotalFloorArea(true)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Plenum')
    space.setSpaceType(space_type)
    assert_equal(true, @zone.thermal_zone_plenum?(thermal_zone))
  end

  def test_thermal_zone_residential?
    model = OpenStudio::Model::Model.new
    # from plenum
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)

    # from space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('MidriseApartment Apartment')
    space.setSpaceType(space_type)
    assert_equal(true, @zone.thermal_zone_residential?(thermal_zone))

    apt_ofc = OpenStudio::Model::SpaceType.new(model)
    apt_ofc.setName('MidriseApartment Office')
    ofc = OpenStudio::Model::Space.new(model)
    ofc.setSpaceType(apt_ofc)
    ofc_thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    ofc.setThermalZone(ofc_thermal_zone)
    assert_equal(false, @zone.thermal_zone_residential?(ofc_thermal_zone))
  end

  def test_thermal_zone_vestibule?
    model = OpenStudio::Model::Model.new
    # from plenum
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 3.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(3.0, 3.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(3.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    assert_equal(false, @zone.thermal_zone_vestibule?(thermal_zone))

    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration.setDesignFlowRate(1.0)
    infiltration.setSpace(space)
    assert_equal(true, @zone.thermal_zone_vestibule?(thermal_zone))
  end

  def test_thermal_zone_heated?
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 20.0,
                                                         name: 'Heating Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 24.0,
                                                         name: 'Cooling Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(true, @zone.thermal_zone_heated?(thermal_zone))

    # test unconditioned (<41F)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 4.0,
                                                         name: 'Unconditioned Heating Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    assert_equal(false, @zone.thermal_zone_heated?(thermal_zone))
  end

  def test_thermal_zone_cooled?
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 20.0,
                                                         name: 'Heating Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 24.0,
                                                         name: 'Cooling Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(true, @zone.thermal_zone_cooled?(thermal_zone))

    # test unconditioned (>91F)
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 35.0,
                                                         name: 'Unconditioned Cooling Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(false, @zone.thermal_zone_cooled?(thermal_zone))
  end

  def test_thermal_zone_electric_heat?
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    std.model_add_hvac_system(model, 'VAV Reheat', ht = 'Electricity', znht = 'Electricity', cl = 'Electricity', model.getThermalZones,
                              chilled_water_loop_cooling_type: 'AirCooled')
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    assert_equal(true, @zone.thermal_zone_electric_heat?(thermal_zone))

    # test a mixed system
    OpenstudioStandards::HVAC.remove_hvac(model)
    std.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', model.getThermalZones,
                              air_loop_cooling_type: 'DX')
    std.model_add_hvac_system(model, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', model.getThermalZones)
    assert_equal(true, @zone.thermal_zone_electric_heat?(thermal_zone))
  end

  def test_thermal_zone_fossil_heat?
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    std.model_add_hvac_system(model, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', model.getThermalZones,
                              chilled_water_loop_cooling_type: 'AirCooled')
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    assert_equal(true, @zone.thermal_zone_fossil_heat?(thermal_zone))
  end

  def test_thermal_zone_district_heat?
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    std.model_add_hvac_system(model, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', model.getThermalZones,
                              chilled_water_loop_cooling_type: 'AirCooled')
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    assert_equal(true, @zone.thermal_zone_district_heat?(thermal_zone))
  end

  def test_thermal_zone_mixed_heat?
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    std.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', model.getThermalZones,
                              air_loop_cooling_type: 'DX')
    assert_equal(false, @zone.thermal_zone_mixed_heat?(thermal_zone))
    std.model_add_hvac_system(model, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', model.getThermalZones)
    assert_equal(true, @zone.thermal_zone_mixed_heat?(thermal_zone))
  end

  def test_thermal_zone_get_design_internal_load
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    assert_equal(0.0, @zone.thermal_zone_get_design_internal_load(thermal_zone))

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.setStandardsSpaceType('Classroom')
    space.setSpaceType(space_type)

    # add loads
    std = Standard.build('90.1-2013')
    std.model_add_loads(model)
    assert_in_delta(708.67, @zone.thermal_zone_get_design_internal_load(thermal_zone), 0.1)
  end

  def test_thermal_zone_get_space_type
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    space_type = @zone.thermal_zone_get_space_type(thermal_zone)
    assert_equal('SecondarySchool Gym', space_type.get.name.get)
  end

  def test_thermal_zone_get_building_type
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    assert_equal('SecondarySchool', @zone.thermal_zone_get_building_type(thermal_zone))
  end

  def test_thermal_zone_get_occupancy_schedule
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    thermal_zone = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    occ_sch = @zone.thermal_zone_get_occupancy_schedule(thermal_zone)
    assert_in_delta(0.95, occ_sch.defaultDaySchedule.values.max, 0.0001)
  end

  def test_thermal_zones_get_occupancy_schedule
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
    std.model_add_loads(model)
    thermal_zone1 = model.getThermalZoneByName('TZ-Aux_Gym_ZN_1_FLR_1').get
    thermal_zone2 = model.getThermalZoneByName('TZ-Mult_Class_1_Pod_1_ZN_1_FLR_1').get
    occ_sch = @zone.thermal_zones_get_occupancy_schedule([thermal_zone1, thermal_zone2])
    assert_in_delta(0.70328, occ_sch.defaultDaySchedule.values.max, 0.0001)
  end

  def test_thermal_zone_get_outdoor_airflow_rate
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    assert_equal(0.0, @zone.thermal_zone_get_outdoor_airflow_rate(thermal_zone))

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.setStandardsSpaceType('Classroom')
    space.setSpaceType(space_type)

    # add loads
    std = Standard.build('90.1-2013')
    std.model_add_loads(model)
    assert_in_delta(0.047, @zone.thermal_zone_get_outdoor_airflow_rate(thermal_zone), 0.001)
  end

  def test_thermal_zone_get_outdoor_airflow_rate_per_area
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    assert_equal(0.0, @zone.thermal_zone_get_outdoor_airflow_rate_per_area(thermal_zone))

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.setStandardsSpaceType('Classroom')
    space.setSpaceType(space_type)

    # add loads
    std = Standard.build('90.1-2013')
    std.model_add_loads(model)
    assert_in_delta(0.00188, @zone.thermal_zone_get_outdoor_airflow_rate_per_area(thermal_zone), 0.0001)
  end

  def test_thermal_zone_convert_outdoor_air_to_per_area
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.setStandardsSpaceType('Classroom')
    space.setSpaceType(space_type)

    # add loads
    std = Standard.build('90.1-2013')
    std.model_add_loads(model)

    # get outdoor air and check per person values specified
    oa = space.designSpecificationOutdoorAir.get
    initial_oa_per_person = oa.outdoorAirFlowperPerson
    intial_oa_per_area = oa.outdoorAirFlowperFloorArea
    assert(initial_oa_per_person > 0)
    assert(intial_oa_per_area > 0)

    # check that outdoor air spec has been converted to per area
    @zone.thermal_zone_convert_outdoor_air_to_per_area(thermal_zone)
    oa = space.designSpecificationOutdoorAir.get
    final_oa_per_person = oa.outdoorAirFlowperPerson
    final_oa_per_area = oa.outdoorAirFlowperFloorArea
    assert_equal(0.0, final_oa_per_person)
    assert(final_oa_per_area > intial_oa_per_area)
  end
end
