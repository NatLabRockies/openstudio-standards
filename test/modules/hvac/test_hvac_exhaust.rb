require_relative '../../helpers/minitest_helper'

class TestHVACExhaust < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_create_exhaust_fan
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create exhaust fan
    exhaust_zone = model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get
    makeup_zone = model.getThermalZoneByName('TZ-Cafeteria_ZN_1_FLR_1').get
    assert(0, model.getZoneMixings.size)
    zone_exhaust_fan = @hvac.create_exhaust_fan(exhaust_zone, make_up_air_source_zone: makeup_zone)

    # set fan pressure rise
    std.fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)

    # update efficiency and pressure rise
    std.prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)

    assert(1, model.getZoneMixings.size)
    assert(2, model.getFanZoneExhausts.size)
    # model.save("#{output_dir}/out.osm", true)
  end

  def test_create_exhaust_fan_comstock
    # load model and set up weather file
    template = 'ComStock DOE Ref 1980-2004'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEOutpatient.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # apply create exhaust fan
    exhaust_zone = model.getThermalZoneByName('TZ-Floor 1 Anesthesia').get
    zone_exhaust_fan = @hvac.create_exhaust_fan(exhaust_zone)

    # set fan pressure rise
    std.fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)

    # update efficiency and pressure rise
    std.prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)

    assert(1, model.getFanZoneExhausts.size)
    # model.save("#{output_dir}/out.osm", true)
  end
end