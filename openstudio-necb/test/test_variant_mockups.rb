require_relative 'test_helper'
require 'json'

# D-33 gate: the reference-system routes the archetype fleet never exercises
# (Systems 2/5, hp override, residential copy/through-the-wall, kitchen-hood
# route, 8.4.4.6 purchased energy), each driven through the FULL umbrella
# pipeline by a synthetic mockup from test/fixtures/variant_mockups/
# (regenerate with scripts/generate_variant_mockups.rb).
#
# With the openstudio CLI present each mockup runs simulate: :sizing (proposed
# + reference sizing runs, post-sizing efficiency/ERV passes); without it the
# selection/build assertions still run via simulate: :none.
class TestVariantMockups < Minitest::Test
  include FixtureHelper

  DIR = File.expand_path('fixtures/variant_mockups', __dir__)
  MANIFEST = JSON.parse(File.read(File.join(DIR, 'manifest.json')))

  def run_mockup(name)
    spec = MANIFEST.fetch(name)
    building = spec['building']&.transform_keys(&:to_sym)
    mode = openstudio_cli? ? :sizing : :none
    run_dir = File.join(Dir.mktmpdir("mockup_#{name}_"))
    result = OpenStudioNECB.performance_compliance(
      File.join(DIR, spec['osm']), vintage: '2020', simulate: mode, hdd: 3890,
      weather: { epw: EPW, ddy: DDY }, building: building, run_dir: run_dir
    )
    [result, spec['expect'], mode]
  end

  def entry_values(audit, action)
    audit.entries.select { |e| e[:action].to_s == action }.map { |e| e[:value].to_s }
  end

  def assert_expectations(result, expect, name)
    audit = result.audit
    if expect['selected']
      selected = entry_values(audit, 'reference system selected')
      assert(selected.any? { |v| v.include?(expect['selected']) },
             "#{name}: expected selection #{expect['selected'].inspect}, got #{selected.uniq.inspect}")
    end
    if expect['built']
      built = entry_values(audit, 'reference system built')
      assert(built.any? { |v| v.include?(expect['built']) },
             "#{name}: expected build #{expect['built'].inspect}, got #{built.uniq.inspect}")
    end
    %w[decision decision2].each do |key|
      next unless expect[key]

      assert(audit.entries.any? { |e| e[:action].to_s.include?(expect[key]) },
             "#{name}: expected audit decision #{expect[key].inspect}")
    end
    return unless expect['article']

    assert(audit.entries.any? { |e| e[:article].to_s.include?(expect['article']) || e[:action].to_s.include?(expect['article']) },
           "#{name}: expected article citation #{expect['article'].inspect}")
  end

  MANIFEST.each_key do |name|
    define_method("test_#{name}") do
      result, expect, mode = run_mockup(name)
      assert_expectations(result, expect, name)
      next unless mode == :sizing

      # the sizing gate: both models actually sized without E+ fatals
      refute_nil result.reference_model, "#{name}: reference model present"
      fatals = result.audit.entries.select { |e| e[:level] == :error }
      assert_empty fatals, "#{name}: no error-level audit entries after sizing"
    end
  end

  def test_sys5_is_a_first_build_not_just_a_selection
    result, = run_mockup('sys5_refrigerated')
    ref = result.reference_model
    fan_coils = ref.getZoneHVACFourPipeFanCoils.size + ref.getZoneHVACUnitVentilators.size +
                ref.getZoneHVACTerminalUnitVariableRefrigerantFlows.size
    chillers = ref.getChillerElectricEIRs.size
    assert_operator chillers, :>=, 1, 'sys 5 reference carries a chiller plant'
    assert_operator fan_coils + ref.getZoneHVACBaseboardConvectiveWaters.size, :>=, 1,
                    'sys 5 reference carries zone hydronic equipment'
  end
end
