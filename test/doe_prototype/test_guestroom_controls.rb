require_relative '../helpers/minitest_helper'

class TestGuestroomControls < Minitest::Test
  def annual_days(schedule)
    [schedule.defaultDaySchedule] + schedule.scheduleRules.map(&:daySchedule)
  end

  def day_values(day)
    [day.times.map(&:totalSeconds), day.values.to_a]
  end

  def guestroom_model(building_type, occupied: false)
    model = OpenStudio::Model::Model.new
    schedules = [18.889, 23.333].each_with_index.map do |temperature, index|
      schedule = OpenStudio::Model::ScheduleRuleset.new(model)
      schedule.setName("GuestRoom #{occupied ? 'Occ' : 'Vac'} #{index}")
      weekend = OpenStudio::Model::ScheduleRule.new(schedule)
      weekend.setApplySaturday(true)
      weekend.setApplySunday(true)
      seasonal = OpenStudio::Model::ScheduleRule.new(schedule)
      seasonal.setApplyMonday(true)
      seasonal.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(7), 1))
      seasonal.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(8), 31))
      annual_days(schedule).each_with_index do |day, day_index|
        if occupied
          off_value = temperature + day_index
          on_value = index.zero? ? off_value + 2.0 : off_value - 2.0
          day.addValue(OpenStudio::Time.new(0, 8, 0, 0), on_value)
          day.addValue(OpenStudio::Time.new(0, 18, 0, 0), off_value)
          day.addValue(OpenStudio::Time.new(0, 24, 0, 0), on_value)
        else
          day.addValue(OpenStudio::Time.new(0, 24, 0, 0), temperature)
        end
      end
      design_day = OpenStudio::Model::ScheduleDay.new(model)
      if occupied
        design_day.addValue(OpenStudio::Time.new(0, 8, 0, 0), index.zero? ? temperature + 2.0 : temperature - 2.0)
        design_day.addValue(OpenStudio::Time.new(0, 18, 0, 0), temperature)
      end
      design_day.addValue(OpenStudio::Time.new(0, 24, 0, 0), occupied ? annual_days(schedule).first.values.last : temperature)
      schedule.setSummerDesignDaySchedule(design_day)
      schedule.setWinterDesignDaySchedule(design_day)
      design_day.remove
      schedule
    end
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType(building_type)
    space_type.setStandardsSpaceType('GuestRoom')
    names = building_type == 'SmallHotel' ? ['GuestRoom101', 'GuestRoom102'] : ['Room_3_Mult19_Flr_3']
    names.each do |name|
      space = OpenStudio::Model::Space.new(model)
      space.setName(name)
      space.setSpaceType(space_type)
      zone = OpenStudio::Model::ThermalZone.new(model)
      space.setThermalZone(zone)
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setName("#{name} GuestRoom Thermostat")
      thermostat.setHeatingSetpointTemperatureSchedule(schedules[0])
      thermostat.setCoolingSetpointTemperatureSchedule(schedules[1])
      zone.setThermostatSetpointDualSetpoint(thermostat)
    end
    [model, schedules]
  end

  def test_vacancy_controls_adjust_all_annual_days_only
    ['SmallHotel', 'LargeHotel'].each do |building_type|
      ['90.1-2016', '90.1-2019'].each do |template|
        model, schedules = guestroom_model(building_type)
        design_values = schedules.map { |s| [day_values(s.summerDesignDaySchedule), day_values(s.winterDesignDaySchedule)] }
        Standard.build(template).model_add_guestroom_vacancy_controls(model, building_type)
        schedules.each_with_index do |schedule, index|
          expected = index.zero? ? 15.556 : 26.667
          annual_days(schedule).each do |day|
            assert_in_delta(expected, day.values.first, 0.000001, "#{building_type} #{template} #{day.name}")
          end
          assert_equal(design_values[index], [day_values(schedule.summerDesignDaySchedule), day_values(schedule.winterDesignDaySchedule)])
        end
      end
    end
  end

  def test_setback_delay_adjusts_all_annual_days_only
    ['SmallHotel', 'LargeHotel'].each do |building_type|
      model, schedules = guestroom_model(building_type, occupied: true)
      values_before = schedules.map { |s| annual_days(s).map { |day| day.values.to_a } }
      design_values = schedules.map { |s| [day_values(s.summerDesignDaySchedule), day_values(s.winterDesignDaySchedule)] }
      Standard.build('90.1-2019').model_reduce_setback_sch_delay(model, building_type)
      schedules.each_with_index do |schedule, index|
        annual_days(schedule).each_with_index do |day, day_index|
          assert_equal([28_200, 64_800, 86_400], day.times.map(&:totalSeconds))
          assert_equal(values_before[index][day_index], day.values.to_a)
        end
        assert_equal(design_values[index], [day_values(schedule.summerDesignDaySchedule), day_values(schedule.winterDesignDaySchedule)])
      end
    end
  end

  def test_controls_preserve_vintage_restrictions
    ['SmallHotel', 'LargeHotel'].each do |building_type|
      model, schedules = guestroom_model(building_type)
      before = schedules.map { |s| annual_days(s).map { |day| day_values(day) } }
      Standard.build('90.1-2013').model_add_guestroom_vacancy_controls(model, building_type)
      assert_equal(before, schedules.map { |s| annual_days(s).map { |day| day_values(day) } })

      model, schedules = guestroom_model(building_type, occupied: true)
      before = schedules.map { |s| annual_days(s).map { |day| day_values(day) } }
      Standard.build('90.1-2016').model_reduce_setback_sch_delay(model, building_type)
      assert_equal(before, schedules.map { |s| annual_days(s).map { |day| day_values(day) } })
    end
  end

  def test_controls_preserve_default_only_schedule_behavior
    [false, true].each do |occupied|
      model, schedules = guestroom_model('SmallHotel', occupied: occupied)
      schedules.each { |schedule| schedule.scheduleRules.each(&:remove) }
      standard = Standard.build('90.1-2019')
      if occupied
        standard.model_reduce_setback_sch_delay(model, 'SmallHotel')
        schedules.each do |schedule|
          assert_equal([28_200, 64_800, 86_400], schedule.defaultDaySchedule.times.map(&:totalSeconds))
        end
      else
        standard.model_add_guestroom_vacancy_controls(model, 'SmallHotel')
        assert_in_delta(15.556, schedules[0].defaultDaySchedule.values.first, 0.000001)
        assert_in_delta(26.667, schedules[1].defaultDaySchedule.values.first, 0.000001)
      end
    end
  end
end
