require_relative 'test_helper'

# P2 gate (parity half): Lights objects + lighting schedules match legacy
# NECB2020 space_type_apply_internal_loads(set_lights: true) +
# space_type_apply_internal_load_schedules across representative space types —
# below/above the sensor threshold, NECB_Default and LED. Repo bundle only.
class TestLightsParity < Minitest::Test
  include FixtureHelper

  PAIRS = [
    ['Space Function', 'Office enclosed > 25 m2'],                  # below threshold
    ['Space Function', 'Conference/Meeting/Multi-purpose room'],    # above -> synthesis
    ['Space Function', 'Corridor/Transition area other-sch-A'],
    ['Space Function', 'Dining area - family dining'],
    ['Space Function', 'Classroom/Lecture hall/Training room other']
  ].freeze

  def self.legacy
    @legacy ||= begin
      require File.expand_path('../../lib/openstudio-standards', __dir__)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy
    skip 'openstudio-standards not loadable — parity gate runs from the monorepo' if std == :unavailable
    std
  end

  def day_values(day)
    (1..24).map { |h| day.getValue(OpenStudio::Time.new(0, h, 0, 0)).round(6) }
  end

  def lights_signature(space_type)
    lights = space_type.lights.sort_by(&:nameString).reject { |l| l.nameString.include?('Additional') }.first
    return nil if lights.nil?

    d = lights.lightsDefinition
    schedule = space_type.defaultScheduleSet.is_initialized ? space_type.defaultScheduleSet.get.lightingSchedule : nil
    sched_sig = nil
    if schedule&.is_initialized
      rs = schedule.get.to_ScheduleRuleset
      sched_sig = rs.empty? ? schedule.get.nameString : {
        name: schedule.get.nameString,
        default: day_values(rs.get.defaultDaySchedule),
        rules: rs.get.scheduleRules.map { |r| day_values(r.daySchedule) }
      }
    end
    { w_m2: d.wattsperSpaceFloorArea.is_initialized ? d.wattsperSpaceFloorArea.get.round(9) : nil,
      w_person: d.wattsperPerson.is_initialized ? d.wattsperPerson.get.round(9) : nil,
      return_air: d.returnAirFraction.round(9), radiant: d.fractionRadiant.round(9),
      visible: d.fractionVisible.round(9), schedule: sched_sig }
  end

  def build(pairs)
    model = OpenStudio::Model::Model.new
    pairs.each { |bt, st| tagged_space_type(model, bt, st) }
    model
  end

  def run_parity(lights_type)
    std = legacy
    gem_model = build(PAIRS)
    OpenStudioLighting.apply_lights(gem_model, vintage: '2020', lights_type: lights_type)

    legacy_model = build(PAIRS)
    legacy_model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      std.space_type_apply_internal_loads(space_type: space_type,
                                          set_people: false, set_electric_equipment: false,
                                          set_gas_equipment: false, set_ventilation: false,
                                          set_infiltration: false, set_lights: true,
                                          lights_type: lights_type, lights_scale: 1.0)
      std.space_type_apply_internal_load_schedules(space_type,
                                                   set_people: false, set_electric_equipment: false,
                                                   set_gas_equipment: false, set_ventilation: false,
                                                   set_lights: true)
    end

    mismatches = []
    PAIRS.each do |bt, st_name|
      full = "#{bt} #{st_name}"
      gem_sig = lights_signature(gem_model.getSpaceTypes.find { |s| s.nameString == full })
      legacy_sig = lights_signature(legacy_model.getSpaceTypes.find { |s| s.nameString == full })
      next if gem_sig == legacy_sig

      keys = gem_sig.keys.select { |k| gem_sig[k] != legacy_sig[k] }
      mismatches << "#{st_name} [#{lights_type}]: #{keys.map { |k| "#{k}: gem=#{gem_sig[k].inspect[0, 80]} legacy=#{legacy_sig[k].inspect[0, 80]}" }.join('; ')}"
    end
    mismatches
  end

  def test_necb_default_parity
    assert_empty run_parity('NECB_Default').join("\n\n"), 'NECB_Default lights parity'
  end

  def test_led_parity
    assert_empty run_parity('LED').join("\n\n"), 'LED lights parity'
  end
end
