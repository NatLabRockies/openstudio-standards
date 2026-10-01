require_relative '../../helpers/minitest_helper'

class TestSchedulesDerivation < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules

    # load schedules data
    @schedule_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/test_schedules_data.json"), symbolize_names: true)
  end

  def test_schedule_derivation_basic
    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # test a range of derivation params
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, @schedule_data, 'conference occupancy', {})
    [0.5, 0.75, 1.0].each do |peak|
      [0.5, 1.0, 5.0].each do |response|
        params = {
          "name": "conference equipment",
          "category": "Equipment",
          "derivation_type": "linear",
          "base": 0.3,
          "peak": peak,
          "response": response,
          "winter_design_day_base": 0.0,
          "winter_design_day_peak": 0.0,
          "winter_design_day_response": 0.0,
          "summer_design_day_base": 1.0,
          "summer_design_day_peak": 1.0,
          "summer_design_day_response": 1.0
        }
        equip_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)
        equip_sch.setName("equipment_peak:#{peak}_resp:#{response}")
      end
    end

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation_basic.osm', true)
  end

  def test_linear_response_above_one_saturates_at_peak
    # A linear response above 1 reaches the peak before full presence; unclamped it kept
    # climbing past it - 'retail - supermarket lighting' (base 0.05, peak 0.9, response
    # 1.15) reached 1.00125 on its default day and EnergyPlus refused the Fractional
    # schedule before the simulation started.
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, @schedule_data, 'conference occupancy', {})
    params = {
      "name": "conference lighting",
      "category": "Lighting",
      "derivation_type": "linear",
      "base": 0.05,
      "peak": 0.9,
      "response": 1.15
    }
    lighting = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)
    days = [lighting.defaultDaySchedule] + lighting.scheduleRules.map(&:daySchedule)
    values = days.flat_map(&:values)
    assert_operator(values.max, :<=, 0.9, 'a derived value passed the peak')
    assert_operator(values.min, :>=, 0.05, 'a derived value fell below the base')
    assert_in_delta(0.9, lighting.defaultDaySchedule.values.max, 1e-9, 'the default day never reaches the peak')

    pairs = OpenstudioStandards::Schedules.derive_values('linear', 0.05, 0.9, 1.15, [[8.0, 0.0], [12.0, 0.5], [18.0, 1.0]])
    assert_equal([0.05, 0.05 + (0.85 * 0.5 * 1.15), 0.9], pairs.map { |_, v| v.round(9) })
  end

  def test_supermarket_lighting_stays_within_its_fractional_limits
    # the shipped definition that reached EnergyPlus at 1.00125 and stopped the grocery's
    # sizing run: built through the same path create_typical uses
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('retail - supermarket')
    space_type.setStandardsSpaceType('retail - supermarket')
    space_type.additionalProperties.setFeature('standards_space_type', 'retail - supermarket')
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties', reset_standards_space_type: true)
    OpenstudioStandards::Schedules.space_type_apply_parametric_internal_load_schedules(space_type)

    lighting = space_type.defaultScheduleSet.get.lightingSchedule
    assert(lighting.is_initialized, 'no lighting schedule was applied')
    ruleset = lighting.get.to_ScheduleRuleset.get
    days = [ruleset.defaultDaySchedule, ruleset.summerDesignDaySchedule, ruleset.winterDesignDaySchedule] + ruleset.scheduleRules.map(&:daySchedule)
    days.each do |day|
      assert_operator(day.values.max, :<=, 1.0, "#{day.name} exceeds 1")
      assert_operator(day.values.min, :>=, 0.0, "#{day.name} is below 0")
    end
    assert_in_delta(0.9, ruleset.defaultDaySchedule.values.max, 1e-9, 'the default day does not reach its 0.9 peak')
  end

  def test_schedule_derivation_slope
    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # test a range of derivation params
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, @schedule_data, 'slope occupancy', {})
    params = {
      "name": "slope lighting",
      "category": "Lighting",
      "derivation_type": "exponential",
      "base": 0.05,
      "peak": 0.9,
      "response": 0.5,
      "winter_design_day_peak": 0.0,
      "summer_design_day_base": 1.0
    }
    light_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation_slope.osm', true)
  end

  def test_schedule_derivation_up_down
    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # create occupancy schedule and derive with up_down methodology
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, @schedule_data, 'slope occupancy', {})
    params = {
      "name": "up_down lighting",
      "category": "Lighting",
      "derivation_type": "up_down",
      "base": 0.1,
      "peak": 0.85,
      "response": 1.0,
      "start_slope": 0.4,
      "end_slope": 0.6,
      "winter_design_day_peak": 0.0,
      "summer_design_day_base": 1.0
    }

    light_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)

    refute_nil(light_sch)
    default_vals = light_sch.defaultDaySchedule.values
    assert(default_vals.size.positive?)
    assert_operator(default_vals.max, :<=, params[:peak] + 0.001)
    assert_operator(default_vals.min, :>=, params[:base] - 0.001)

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation_up_down.osm', true)
  end

  def test_derivation_school
    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # test derivation for school classroom occupancy
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, @schedule_data, 'school classroom occupancy', {})
    params = {
      "name": "school classroom lighting",
      "category": "Lighting",
      "derivation_type": "exponential",
      "base": 0.05,
      "peak": 0.9,
      "response": 0.5,
      "winter_design_day_peak": 0.0,
      "summer_design_day_base": 1.0
    }
    light_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation_school.osm', true)
  end

  def test_space_type_apply_parametric_internal_load_schedules
    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('classroom')
    space_type.setStandardsSpaceType('classroom')
    space_type.additionalProperties.setFeature('standards_space_type', 'classroom/lecture/training')
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties', reset_standards_space_type: true)

    # set default scedules data
    OpenstudioStandards::Schedules.space_type_apply_parametric_internal_load_schedules(space_type)

    model.save(File.dirname(__FILE__) + '/output/test_parametric_space_type_schedules.osm', true)
  end
end
