require_relative '../helpers/minitest_helper'

class TestPrmBaselineZoneHvacFanOperation < Minitest::Test
  # Returns a model and its one zone, which is occupied from 08:00 to 18:00.
  def model_with_occupied_zone
    model = OpenStudio::Model::Model.new
    floor = OpenStudio::Point3dVector.new
    [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| floor << OpenStudio::Point3d.new(x, y, 0) }
    space = OpenStudio::Model::Space.fromFloorPrint(floor, 3.0, model).get
    zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(zone)

    occupancy = OpenStudio::Model::ScheduleRuleset.new(model)
    [[8, 0.0], [18, 1.0], [24, 0.0]].each { |hour, value| occupancy.defaultDaySchedule.addValue(OpenStudio::Time.new(0, hour, 0, 0), value) }
    people_definition = OpenStudio::Model::PeopleDefinition.new(model)
    people_definition.setNumberofPeople(10)
    people = OpenStudio::Model::People.new(people_definition)
    people.setSpace(space)
    people.setNumberofPeopleSchedule(occupancy)
    [model, zone]
  end

  def fan_mode_value(model, schedule, hour)
    date = model.getYearDescription.makeDate(1, 8)
    schedule.to_ScheduleRuleset.get.getDaySchedules(date, date).first.getValue(OpenStudio::Time.new(0, hour, 30, 0))
  end

  # G3.1.2.4: fans run continuously when the zone is occupied and cycle when it is unoccupied.
  def test_system_1_and_2_fans_cycle_when_zone_is_unoccupied
    ['90.1-PRM-2019', '90.1-2013'].product(['PTAC', 'PTHP']).each do |template, system_type|
      model, zone = model_with_occupied_zone
      std = Standard.build(template)
      std.model_add_prm_baseline_system(model, system_type, 'NaturalGas', 'NaturalGas', 'Electricity', [zone], {})
      unit = model.getZoneHVACComponents.first
      unit = system_type == 'PTAC' ? unit.to_ZoneHVACPackagedTerminalAirConditioner.get : unit.to_ZoneHVACPackagedTerminalHeatPump.get

      std.zone_hvac_component_apply_standard_controls(unit)

      fan_mode = unit.supplyAirFanOperatingModeSchedule
      label = "#{template} #{system_type}"
      assert(unit.supplyAirFan.to_FanOnOff.is_initialized, "#{label} supply fan must be able to cycle")
      refute_equal('Always On Discrete', fan_mode.nameString, "#{label} fan must not run continuously all year")
      assert_equal(0.0, fan_mode_value(model, fan_mode, 3), "#{label} fan must cycle when the zone is unoccupied")
      assert_equal(1.0, fan_mode_value(model, fan_mode, 12), "#{label} fan must run continuously when the zone is occupied")
    end
  end
end
