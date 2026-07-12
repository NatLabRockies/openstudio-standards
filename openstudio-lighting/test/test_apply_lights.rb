require_relative 'test_helper'

# P2 gate (standalone half): LPD application, sensor-schedule synthesis above the
# 8.6 W/m2 threshold, LED path with the fixed atrium height rule, coverage.
class TestApplyLights < Minitest::Test
  include FixtureHelper

  OFFICE = ['Space Function', 'Office enclosed > 25 m2'].freeze         # 6.9 W/m2 < threshold
  CONFERENCE = ['Space Function', 'Conference/Meeting/Multi-purpose room'].freeze # 10.5 W/m2 > threshold

  def test_plain_lpd_below_threshold
    model = OpenStudio::Model::Model.new
    st = tagged_space_type(model, *OFFICE)
    audit = OpenStudioLighting.apply_lights(model, vintage: '2020', audit: OpenStudioLighting::AuditLog.new)

    record = OpenStudioLoads::NECB::SpaceTypes.record(building_type: OFFICE[0], space_type: OFFICE[1])
    lights = st.lights.first
    refute_nil lights
    expected = OpenStudio.convert(record['lighting_per_area'].to_f, 'W/ft^2', 'W/m^2').get
    assert_in_delta expected, lights.lightsDefinition.wattsperSpaceFloorArea.get, 1e-9
    assert_in_delta record['lighting_fraction_radiant'].to_f, lights.lightsDefinition.fractionRadiant, 1e-9

    schedule = st.defaultScheduleSet.get.lightingSchedule
    assert schedule.is_initialized
    assert_equal record['lighting_schedule'], schedule.get.nameString, 'plain schedule below 8.6 W/m2'
  end

  def test_sensor_schedule_synthesis_above_threshold
    model = OpenStudio::Model::Model.new
    st = tagged_space_type(model, *CONFERENCE)
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.apply_lights(model, vintage: '2020', audit: audit)

    record = OpenStudioLoads::NECB::SpaceTypes.record(building_type: CONFERENCE[0], space_type: CONFERENCE[1])
    assert_operator record['lighting_per_area'].to_f, :>, 0.799256505, 'fixture premise: above threshold'

    schedule = st.defaultScheduleSet.get.lightingSchedule.get
    assert_match(/-Light Ruleset\z/, schedule.nameString, 'synthesized sensor ruleset wired')

    # occupied-hour value == original; deep-night value == original x occ_control
    ruleset = schedule.to_ScheduleRuleset.get
    default = ruleset.defaultDaySchedule
    rel = record['rel_absence_occ'].to_f
    control = 1 - (rel * record['occ_sense'].to_f) - record['personal_control'].to_f
    lighting_rows = OpenStudioLoads::NECB.table('2020', 'schedules')
                                         .select { |r| r['name'] == record['lighting_schedule'] }
    occupancy_rows = OpenStudioLoads::NECB.table('2020', 'schedules')
                                          .select { |r| r['name'] == record['occupancy_schedule'] }
    base = lighting_rows.find { |r| r['day_types'].include?('Default') }['values']
    occ = occupancy_rows.find { |r| r['day_types'].include?('Default') }['values']
    (0..23).each do |hour|
      expected = occ[hour].to_f < rel ? base[hour].to_f * control : base[hour].to_f
      actual = default.getValue(OpenStudio::Time.new(0, hour + 1, 0, 0))
      assert_in_delta expected, actual, 1e-6, "hour #{hour + 1}"
    end
    assert(audit.entries.any? { |e| e[:action].include?('occupancy-sensor lighting schedule synthesized') })
  end

  def test_led_path_and_atrium_height_fix
    model = OpenStudio::Model::Model.new
    st = tagged_space_type(model, *OFFICE)
    OpenStudioLighting.apply_lights(model, vintage: '2020', lights_type: 'LED',
                                    audit: OpenStudioLighting::AuditLog.new)
    led = OpenStudioLighting::NECB.led_record(building_type: OFFICE[0], space_type: OFFICE[1])
    lights = st.lights.first
    expected = OpenStudio.convert(led['lighting_per_area'].to_f, 'W/ft^2', 'W/m^2').get
    assert_in_delta expected, lights.lightsDefinition.wattsperSpaceFloorArea.get, 1e-9
    assert_match(/LED lighting/, lights.lightsDefinition.nameString)

    # atrium: a 9 m-tall space drives the below-12m equation (legacy raises NameError here)
    atrium_model = OpenStudio::Model::Model.new
    atrium_st = tagged_space_type(atrium_model, 'Space Function', 'Atrium (height < 6m)-sch-A')
    space = OpenStudio::Model::Space.new(atrium_model)
    space.setSpaceType(atrium_st)
    points = OpenStudio::Point3dVector.new
    [[0, 0, 0], [0, 10, 0], [10, 10, 0], [10, 0, 0]].each { |x, y, z| points << OpenStudio::Point3d.new(x, y, z) }
    wall_points = OpenStudio::Point3dVector.new
    [[0, 0, 9], [0, 0, 0], [10, 0, 0], [10, 0, 9]].each { |x, y, z| wall_points << OpenStudio::Point3d.new(x, y, z) }
    OpenStudio::Model::Surface.new(wall_points, atrium_model).setSpace(space)
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.apply_lights(atrium_model, vintage: '2020', lights_type: 'LED', audit: audit)

    atrium_decision = audit.entries.find { |e| e[:action].include?('LED atrium LPD') }
    refute_nil atrium_decision, 'atrium equation exercised (legacy NameError path)'
    assert_in_delta 9.0, atrium_decision[:inputs][:height_m], 0.01
    expected_w_ft2 = (0.0 + 1.06 * 9.0) * 0.092903
    lights = atrium_st.lights.first
    assert_in_delta OpenStudio.convert(expected_w_ft2, 'W/ft^2', 'W/m^2').get,
                    lights.lightsDefinition.wattsperSpaceFloorArea.get, 1e-6
  end

  def test_scale_and_coverage
    model = OpenStudio::Model::Model.new
    st = tagged_space_type(model, *OFFICE)
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.apply_lights(model, vintage: '2020', lights_scale: 0.5, audit: audit)
    record = OpenStudioLoads::NECB::SpaceTypes.record(building_type: OFFICE[0], space_type: OFFICE[1])
    expected = OpenStudio.convert(record['lighting_per_area'].to_f * 0.5, 'W/ft^2', 'W/m^2').get
    assert_in_delta expected, st.lights.first.lightsDefinition.wattsperSpaceFloorArea.get, 1e-9

    coverage = audit.entries.select { |e| e[:step] == :coverage }
    assert_operator coverage.size, :>=, 7
    assert(coverage.any? { |e| e[:level] == :warning }, 'not_implemented/partial articles warn')
  end
end
