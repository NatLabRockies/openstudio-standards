require_relative '../../helpers/minitest_helper'

class TestSchedulesCreate < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def test_create_schedule_type_limits
    model = OpenStudio::Model::Model.new

    # test standard schedule type limits
    for type in ['Dimensionless', 'Temperature', 'Humidity Ratio', 'Fraction', 'OnOff', 'Activity']
      schedule_type_limits = @sch.create_schedule_type_limits(model, standard_schedule_type_limit: type)
      name = schedule_type_limits.name.to_s
      unit_type = schedule_type_limits.unitType.to_s
      numeric_type = schedule_type_limits.numericType.to_s
      case type
      when 'Humidity Ratio'
        expected_unit_type = 'Dimensionless'
        expected_numeric_type = 'Continuous'
      when 'Fraction', 'Fractional'
        expected_unit_type = 'Dimensionless'
        expected_numeric_type = 'Continuous'
      when 'OnOff'
        expected_unit_type = 'Availability'
        expected_numeric_type = 'Discrete'
      when 'Activity'
        expected_unit_type = 'ActivityLevel'
        expected_numeric_type = 'Continuous'
      else
        expected_unit_type = type
        expected_numeric_type = 'Continuous'
      end
      assert(name == type, "Expected schedule type limits name #{schedule_type_limits.name} to be #{type}")
      assert(unit_type == expected_unit_type, "Expected schedule type limits unit type #{schedule_type_limits.unitType} to be #{expected_unit_type}")
      assert(numeric_type == expected_numeric_type, "Expected schedule type limits numeric type #{schedule_type_limits.unitType} to be #{expected_numeric_type}")
    end

    # test custom schedule type limits
    schedule_type_limits = @sch.create_schedule_type_limits(model,
                                                            name: 'Infiltration Schedule Type Limits',
                                                            lower_limit_value: 0.0,
                                                            upper_limit_value: 1.0,
                                                            numeric_type: 'Continuous',
                                                            unit_type: 'Dimensionless')
    name = schedule_type_limits.name.to_s
    unit_type = schedule_type_limits.unitType.to_s
    numeric_type = schedule_type_limits.numericType.to_s
    lower_limit = schedule_type_limits.lowerLimitValue.get
    upper_limit = schedule_type_limits.upperLimitValue.get
    assert(name = 'Infiltration Schedule Type Limits')
    assert(unit_type = 'Continuous')
    assert(numeric_type = 'Dimensionless')
    assert(name = 0.0)
    assert(name = 1.0)
  end

  def test_create_constant_schedule_ruleset
    model = OpenStudio::Model::Model.new
    schedule = @sch.create_constant_schedule_ruleset(model, 42.0,
                                                     name: 'Test Schedule',
                                                     schedule_type_limit: 'Temperature')
    result = @sch.schedule_ruleset_get_min_max(schedule)
    assert(result['min'] == 42.0)
    assert(result['max'] == 42.0)
  end

  def test_create_simple_schedule
    model = OpenStudio::Model::Model.new
    test_options = {
      'name' => 'Test Create Simple',
      'winter_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'summer_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'default_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 }
    }
    schedule = @sch.create_simple_schedule(model, test_options)
    assert(schedule.to_ScheduleRuleset.is_initialized)
    assert(schedule.name.to_s == 'Test Create Simple')
  end

  def test_create_complex_schedule
    model = OpenStudio::Model::Model.new
    rules = []
    rules << ['Tuesdays and Thursdays', '1/1-12/31', 'Tue/Thu', [4, 0], [4.33, 1], [18, 0], [18.66, 1], [24, 0]]
    test_options = {
      'name' => 'Test Create Complex',
      'winter_design_day' => [[24, 0]],
      'summer_design_day' => [[24, 1]],
      'default_day' => ['Test Create Complex Default', [11, 0], [11.33, 1], [23, 0], [23.33, 1], [24, 0]],
      'rules' => rules
    }
    schedule = @sch.create_complex_schedule(model, test_options)
    assert(schedule.to_ScheduleRuleset.is_initialized)
    assert(schedule.name.to_s == 'Test Create Complex')
  end

  def test_create_schedule_from_rate_of_change
    model = OpenStudio::Model::Model.new
    test_options = {
      'name' => 'Test Create Rate Of Change',
      'default_time_value_pairs' => { 4.0 => 0.0, 6.0 => 6.0, 8.0 => 15.0, 16 => 7.0, 24 => 0.0 }
    }
    input_schedule = @sch.create_simple_schedule(model, test_options)
    output_schedule = @sch.create_schedule_from_rate_of_change(model, input_schedule)
    assert(output_schedule.to_ScheduleRuleset.is_initialized)
  end

  def test_create_weighted_merge_schedules
    model = OpenStudio::Model::Model.new
    schedule1_options = {
      'name' => 'Schedule1',
      'default_time_value_pairs' => { 8.0 => 0.0, 16.0 => 10.0, 24.0 => 0.0 }
    }
    schedule1 = @sch.create_simple_schedule(model, schedule1_options)

    schedule2_options = {
      'name' => 'Schedule2',
      'default_time_value_pairs' => { 8.0 => 0.0, 16.0 => 20.0, 24.0 => 0.0 }
    }
    schedule2 = @sch.create_simple_schedule(model, schedule2_options)

    schedule_weights_hash = {}
    schedule_weights_hash[schedule1] = 2
    schedule_weights_hash[schedule2] = 8

    schedule = @sch.create_weighted_merge_schedules(model, schedule_weights_hash)
    assert(schedule['mergedSchedule'].to_ScheduleRuleset.is_initialized)
    assert(schedule['mergedSchedule'].name.to_s == 'Merged Schedule')
    assert(schedule['denominator'] == 10.0)
    # the design day setters clone what they are handed; building the day first left it
    # parentless in the model, reaching the IDF with no type limits
    orphans = model.getScheduleDays.reject { |day| day.parent.is_initialized }
    assert_empty(orphans.map { |day| day.name.to_s }, 'day schedules were left with no parent')
  end

  def test_create_inverted_schedule_day
    model = OpenStudio::Model::Model.new
    test_options = {
      'name' => 'Test Create Simple',
      'winter_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'summer_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'default_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 }
    }
    schedule = @sch.create_simple_schedule(model, test_options)
    default_day_schedule = schedule.defaultDaySchedule
    inverted_schedule = @sch.create_inverted_schedule_day(default_day_schedule)
    assert(inverted_schedule.to_ScheduleDay.is_initialized)
    assert_equal(1.0, inverted_schedule.values[0])
    assert_equal(0.0, inverted_schedule.values[1])
    assert_equal(1.0, inverted_schedule.values[2])
  end

  def test_create_inverted_schedule_ruleset
    model = OpenStudio::Model::Model.new
    test_options = {
      'name' => 'Test Create Simple',
      'winter_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'summer_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 },
      'default_time_value_pairs' => { 8.0 => 0.0, 16.0 => 1.0, 24.0 => 0.0 }
    }
    schedule = @sch.create_simple_schedule(model, test_options)
    inverted_schedule = @sch.create_inverted_schedule_ruleset(schedule)
    assert(inverted_schedule.to_ScheduleRuleset.is_initialized)
    assert_equal('Test Create Simple inverted', inverted_schedule.name.to_s)
    # every day of the source is inverted, including the design days, which are filled in
    # place after the setter rather than built first and cloned
    [inverted_schedule.defaultDaySchedule, inverted_schedule.summerDesignDaySchedule, inverted_schedule.winterDesignDaySchedule].each do |day|
      assert_equal([1.0, 0.0, 1.0], day.values, "#{day.name} is not the inversion of its source")
      assert_equal([8.0, 16.0, 24.0], day.times.map(&:totalHours))
    end
    refute_equal(inverted_schedule.defaultDaySchedule.handle, inverted_schedule.summerDesignDaySchedule.handle)

    rules = []
    rules << ['Tuesdays and Thursdays', '1/1-12/31', 'Tue/Thu', [4, 0], [4.33, 1], [18, 0], [18.66, 1], [24, 0]]
    test_options = {
      'name' => 'Test Create Complex',
      'winter_design_day' => [[24, 0]],
      'summer_design_day' => [[24, 1]],
      'default_day' => ['Test Create Complex Default', [11, 0], [11.33, 1], [23, 0], [23.33, 1], [24, 0]],
      'rules' => rules
    }
    schedule = @sch.create_complex_schedule(model, test_options)
    inverted_schedule = @sch.create_inverted_schedule_ruleset(schedule)
    assert(inverted_schedule.to_ScheduleRuleset.is_initialized)
    assert_equal('Test Create Complex inverted', inverted_schedule.name.to_s)
    assert_equal(1, inverted_schedule.scheduleRules.size)
    rule = inverted_schedule.scheduleRules.first
    assert_equal([1.0, 0.0, 1.0, 0.0, 1.0], rule.daySchedule.values)
    assert(rule.applyTuesday && rule.applyThursday && !rule.applyMonday)
    assert_equal([0.0], inverted_schedule.summerDesignDaySchedule.values)
    assert_equal([1.0], inverted_schedule.winterDesignDaySchedule.values)

    # no day schedule is built first and cloned by a setter: nothing is left parentless
    orphans = model.getScheduleDays.reject { |day| day.parent.is_initialized }
    assert_empty(orphans.map { |day| day.name.to_s }, 'day schedules were left with no parent')
  end
end