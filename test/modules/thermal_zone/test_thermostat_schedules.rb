require_relative '../../helpers/minitest_helper'

class TestThermalZoneThermostatSchedules < Minitest::Test
  def setup
    @zone = OpenstudioStandards::ThermalZone
    @sch = OpenstudioStandards::Schedules
  end

  def test_thermal_zones_set_thermostat_schedules_primary_school
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: false))

    # test assigning thermostat schedules
    assert(@zone.thermal_zones_set_thermostat_schedules(model.getThermalZones))
    test_zone = model.getThermalZoneByName('TZ-Mult_Class_1_Pod_1_ZN_1_FLR_1').get
    thermostat = test_zone.thermostatSetpointDualSetpoint.get

  end

  def test_thermal_zones_set_thermostat_schedules_ese
    # load a model and set up weather file
    template = 'DEER 2011'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_ESe.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: false))

    # test assigning thermostat schedules
    assert(@zone.thermal_zones_set_thermostat_schedules(model.getThermalZones))
    test_zone = model.getThermalZoneByName('E1 West Perim Spc (G.W1) ZN').get
    thermostat = test_zone.thermostatSetpointDualSetpoint.get
    assert_equal('D_ESe_All_HTemp_Yr', thermostat.heatingSetpointTemperatureSchedule.get.name.to_s)
  end

  def test_thermal_zone_set_unconditioned_thermostat
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
    @zone.thermal_zone_set_unconditioned_thermostat(thermal_zone)
    assert(thermal_zone.thermostatSetpointDualSetpoint.is_initialized)
    assert_equal(false, @zone.thermal_zone_heated?(thermal_zone))
    assert_equal(false, @zone.thermal_zone_cooled?(thermal_zone))
  end
end
