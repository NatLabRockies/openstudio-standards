require_relative '../../helpers/minitest_helper'

# Every schedule that reaches EnergyPlus needs a Schedule Type Limits Name.
#
# Without one EnergyPlus reports, per schedule and per day profile inside it:
#   ** Warning ** ProcessScheduleInput: Schedule:Day:Interval = <name>
#   **   ~~~   ** Schedule Type Limits Name is empty.
#   **   ~~~   ** Schedule will not be validated.
# and then does not range-check the values, so an out-of-range fraction or a temperature in
# the wrong units passes silently.
#
# Most schedules get their limits stamped by the OpenStudio SDK when they are assigned to a
# typed slot -- setLightingSchedule, setNumberofPeopleSchedule and so on -- which is why the
# parametric load schedules were never affected. The ones that need stating explicitly are
# those used standalone: the occupancy schedule built for hours-of-operation inference and
# elevator schedules, the economizer maximum OA fraction schedule, and the NIST infiltration
# on/off pair. A hospital model showed 24 such warnings across 12 distinct schedules, all
# tracing to those three creation sites.
class TestScheduleTypeLimits < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  def fractional?(schedule)
    return false unless schedule.scheduleTypeLimits.is_initialized

    %w[Fraction Fractional].include?(schedule.scheduleTypeLimits.get.name.to_s)
  end

  # Schedule objects EnergyPlus will read, with the type limits field it will see.
  def idf_schedules_without_type_limits(model)
    idf = OpenStudio::EnergyPlus::ForwardTranslator.new.translateModel(model).to_s
    missing = []
    idf.scan(/Schedule:(?:Day:Interval|Day:List|Constant|Compact),\n(.*?)\n\n/m).flatten.each do |block|
      lines = block.lines
      name = lines[0].to_s.split(',').first.to_s.strip
      limits = lines[1].to_s.split(',').first.to_s.strip
      missing << name if limits.empty?
    end
    missing
  end

  # The occupancy schedule and every day profile it builds, including its rule days, which
  # are the unnamed "Schedule Day N" objects in the warning list.
  def test_spaces_occupancy_schedule_carries_type_limits
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(
      model, { 'total_bldg_floor_area' => 20_000.0, 'bldg_type_a' => 'MediumOffice' }
    )
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')
    OpenstudioStandards::CreateTypical.create_typical_building_from_model(
      model, '90.1-2013', climate_zone: 'ASHRAE 169-2013-4A',
      add_hvac: false, add_refrigeration: false, add_exterior_lights: false,
      sizing_run_directory: "#{__dir__}/output/#{__method__}"
    )

    schedule = OpenstudioStandards::Space.spaces_get_occupancy_schedule(model.getSpaces.to_a)
    assert(fractional?(schedule), "the occupancy schedule has no fractional type limits: #{schedule.name}")

    days = [schedule.defaultDaySchedule, schedule.summerDesignDaySchedule, schedule.winterDesignDaySchedule] +
           schedule.scheduleRules.map(&:daySchedule)
    without = days.reject { |day| day.scheduleTypeLimits.is_initialized }
    assert_empty(without.map { |d| d.name.to_s },
                 'day schedules inside the occupancy schedule have no type limits')
  end

  # The zero-occupancy branch returns a different object and needs the limits too.
  def test_zero_occupancy_schedule_carries_type_limits
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)
    schedule = OpenstudioStandards::Space.spaces_get_occupancy_schedule([space])
    refute_equal(false, schedule, 'no schedule was returned for a space with no occupancy')
    assert(fractional?(schedule), 'the zero-occupancy schedule has no fractional type limits')
  end

  # Four branches build these, and only one of them needed fixing: where the HVAC schedule is
  # a ScheduleRuleset the pair is a clone and an inversion of it, and they inherit its limits.
  # Where there is no HVAC schedule, or a constant one, they are fresh ScheduleConstants with
  # nothing to inherit from. Both branches are asserted so the passing one cannot be mistaken
  # for coverage of the other.
  def test_nist_infiltration_schedules_carry_type_limits_with_no_hvac_schedule
    model = OpenStudio::Model::Model.new
    OpenStudio::Model::Space.new(model)
    OpenstudioStandards::Infiltration.model_set_nist_infiltration_schedules(model)

    ['Infiltration HVAC On Schedule', 'Infiltration HVAC Off Schedule'].each do |name|
      schedule = model.getScheduleByName(name)
      refute(schedule.empty?, "#{name} was not created")
      refute(schedule.get.to_ScheduleConstant.empty?,
             "#{name} is not a ScheduleConstant, so this test no longer covers that branch")
      assert(fractional?(schedule.get), "#{name} has no fractional type limits")
    end
  end

  def test_nist_infiltration_schedules_carry_type_limits_with_an_hvac_schedule
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(
      model, { 'total_bldg_floor_area' => 20_000.0, 'bldg_type_a' => 'MediumOffice' }
    )
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')
    OpenstudioStandards::CreateTypical.create_typical_building_from_model(
      model, '90.1-2013', climate_zone: 'ASHRAE 169-2013-4A',
      add_refrigeration: false, add_exterior_lights: false,
      sizing_run_directory: "#{__dir__}/output/#{__method__}"
    )
    OpenstudioStandards::Infiltration.model_set_nist_infiltration_schedules(model)

    ['Infiltration HVAC On Schedule', 'Infiltration HVAC Off Schedule'].each do |name|
      schedule = model.getScheduleByName(name)
      refute(schedule.empty?, "#{name} was not created")
      assert(fractional?(schedule.get), "#{name} has no fractional type limits")
    end

    # Asserting the ruleset alone passed while the IDF still carried three schedules with
    # no type limits, which is how this branch stayed broken through a validation run. The
    # inversion built standalone day schedules, the design day and rule setters cloned
    # them, and the originals were left parentless - reaching the IDF with no limits,
    # because limits set on a ruleset only reach its actual children.
    orphans = model.getScheduleDays.reject { |day| day.parent.is_initialized }
    assert_empty(orphans.map { |day| day.name.to_s },
                 'day schedules were left in the model with no parent')
  end

  def test_model_add_schedule_leaves_no_parentless_design_days
    # model_add_schedule built each design day as a standalone ScheduleDay and handed it to
    # a setter that clones, leaving the original in the model with no parent - two empty
    # "Schedule Day N" objects per legacy schedule with design-day rows, reaching the IDF
    # with no type limits (36 lines across the 18 kitchen buildings of a validation run).
    model = OpenStudio::Model::Model.new
    standard = Standard.build('90.1-2013')
    schedule = standard.model_add_schedule(model, 'ApartmentHighRise CLGSETP_APT_SCH')
    ruleset = schedule.to_ScheduleRuleset.get

    orphans = model.getScheduleDays.reject { |day| day.parent.is_initialized }
    assert_empty(orphans.map { |day| day.name.to_s }, 'day schedules were left with no parent')

    # the design days are real children with the data's values, not the default day
    assert_equal([24.4], ruleset.defaultDaySchedule.values)
    assert_equal([24.4], ruleset.summerDesignDaySchedule.values)
    assert_equal([21.7], ruleset.winterDesignDaySchedule.values)
    assert_equal('ApartmentHighRise CLGSETP_APT_SCH Winter Design Day', ruleset.winterDesignDaySchedule.name.to_s)
    refute_equal(ruleset.defaultDaySchedule.handle, ruleset.winterDesignDaySchedule.handle)
    refute_equal(ruleset.summerDesignDaySchedule.handle, ruleset.winterDesignDaySchedule.handle)
  end

  def test_economizer_max_oa_fraction_schedule_carries_type_limits
    model = OpenStudio::Model::Model.new
    standard = Standard.build('90.1-2013')
    standard.apply_economizers('ASHRAE 169-2013-4A', model)

    schedule = model.getScheduleRulesetByName('Economizer Max OA Fraction 70 pct')
    refute(schedule.empty?, 'the economizer maximum OA fraction schedule was not created')
    assert(fractional?(schedule.get), 'the economizer maximum OA fraction schedule has no fractional type limits')
    assert(schedule.get.defaultDaySchedule.scheduleTypeLimits.is_initialized,
           'the economizer schedule default day has no type limits')
  end

  # The regression as EnergyPlus sees it: nothing in the translated model may leave the field
  # blank. This is what the 24 warnings on the hospital model were.
  def test_no_translated_schedule_leaves_type_limits_blank
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(
      model, { 'total_bldg_floor_area' => 20_000.0, 'bldg_type_a' => 'MediumOffice' }
    )
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')
    OpenstudioStandards::CreateTypical.create_typical_building_from_model(
      model, '90.1-2013', climate_zone: 'ASHRAE 169-2013-4A',
      add_refrigeration: false, add_exterior_lights: false,
      sizing_run_directory: "#{__dir__}/output/#{__method__}"
    )
    # the standalone schedules are built on demand, so build them before checking
    OpenstudioStandards::Space.spaces_get_occupancy_schedule(model.getSpaces.to_a)

    missing = idf_schedules_without_type_limits(model)
    assert_empty(missing, "#{missing.size} translated schedule object(s) have an empty Schedule Type Limits Name")
  end
end
