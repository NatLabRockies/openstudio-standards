require_relative 'test_helper'

# P4 gate: lighting fixture costing on real spaces — set matching, height bins,
# zone multipliers, loud daylighting note, and legacy parity where callable.
class TestCosting < Minitest::Test
  include FixtureHelper

  CITY = 'TORONTO'.freeze
  PROVINCE = 'ONTARIO'.freeze
  OFFICE = ['Space Function', 'Office enclosed > 25 m2'].freeze

  def costed_fixture_model(lights_type: 'NECB_Default')
    model = load_fixture
    map = model.getSpaces.to_h { |s| [s.nameString, OFFICE] }
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020')
    OpenStudioLighting.apply_lights(model, vintage: '2020', lights_type: lights_type)
    model
  end

  def test_fixture_costing_end_to_end
    audit = OpenStudioLighting::AuditLog.new
    report = OpenStudioLighting.cost(costed_fixture_model, vintage: '2020',
                                     city: CITY, province_state: PROVINCE, audit: audit)
    assert_operator report.total, :>, 0
    assert_equal 5, report.lighting['space_report'].size, 'all five fixture spaces costed'
    report.lighting['space_report'].each do |line|
      assert_operator line['cost'], :>, 0, line['space']
      assert line['fixture_type']
      assert_operator line['height_avg_ft'], :>, 0
    end
    total_from_lines = report.lighting['space_report'].sum { |l| l['cost'] }
    assert_in_delta report.total, total_from_lines, 0.1
    assert(audit.entries.any? { |e| e[:action].include?('no daylighting controls') })
    assert_equal 0, report.warnings.count { |w| w.include?('regional adjustment') }
  end

  def test_zone_multiplier_scales
    base = OpenStudioLighting.cost(costed_fixture_model, vintage: '2020',
                                   city: CITY, province_state: PROVINCE)
    scaled_model = costed_fixture_model
    scaled_model.getThermalZones.each { |z| z.setMultiplier(2) }
    scaled = OpenStudioLighting.cost(scaled_model, vintage: '2020',
                                     city: CITY, province_state: PROVINCE)
    assert_in_delta base.total * 2.0, scaled.total, base.total * 0.01
  end

  def test_cfl_request_falls_back_to_led_only_2020_catalog
    audit = OpenStudioLighting::AuditLog.new
    cfl = OpenStudioLighting.cost(costed_fixture_model(lights_type: 'NECB_Default'),
                                  vintage: '2020', city: CITY, province_state: PROVINCE, audit: audit)
    led = OpenStudioLighting.cost(costed_fixture_model(lights_type: 'LED'),
                                  vintage: '2020', city: CITY, province_state: PROVINCE)
    assert_in_delta led.total, cfl.total, 0.05,
                    'NECB2020 sets are LED-only; CFL-modeled lights cost through the same LED sets (why legacy forces LED)'
    assert(audit.entries.any? { |e| e[:action].include?('carries only LED') })
  end

  def test_daylighting_controls_warn_loudly
    model = costed_fixture_model
    control = OpenStudio::Model::DaylightingControl.new(model)
    control.setSpace(model.getSpaces.first)
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.cost(model, vintage: '2020', city: CITY, province_state: PROVINCE, audit: audit)
    assert(audit.warnings.any? { |w| w[:action].include?('UNCOSTED') },
           'daylighting sensors present but unported costing warns')
  end

  def test_legacy_parity_led_2020
    legacy_root = File.expand_path('../../lib/openstudio-standards', __dir__)
    skip 'openstudio-standards not present' unless File.exist?("#{legacy_root}.rb")
    begin
      require legacy_root
      legacy_dir = File.expand_path('../../lib/openstudio-standards/btap', __dir__)
      require File.join(legacy_dir, 'common_paths')
      require File.join(legacy_dir, 'costing/btap_database')
      require File.join(legacy_dir, 'costing/btap_costing')
      require File.join(legacy_dir, 'costing/lighting_costing')
      require File.join(legacy_dir, 'costing/led_lighting_costing')
      require File.join(legacy_dir, 'costing/daylighting_sensor_control_costing')
    rescue LoadError, StandardError => e
      skip "legacy not loadable: #{e.message[0, 60]}"
    end

    # legacy needs the sorted-accessor monkeypatches from attributes.rb
    OpenStudio::Model::Model.class_eval do
      define_method(:getThermalZonesSorted) { getThermalZones.sort_by { |z| z.name.get } }
    end
    OpenStudio::Model::ThermalZone.class_eval do
      define_method(:getSpacesSorted) { spaces.sort_by { |s| s.name.get } }
    end

    model = costed_fixture_model(lights_type: 'LED') # NECB2020 template => legacy forces LED
    model.getBuilding.setStandardsTemplate('NECB2020')

    coster = BTAPCosting.allocate
    coster.instance_variable_set(:@costing_database, BTAPDatabase.instance)
    coster.instance_variable_set(:@costing_report,
                                 { 'province_state' => PROVINCE, 'city' => CITY,
                                   'lighting' => {} })
    coster.instance_variable_set(:@cost_items, [])
    def coster.add_costed_item(**_kwargs); end
    def coster.cost_audit_daylighting_sensor_control(model:, prototype_creator:); 0.0; end
    def coster.cost_audit_led_lighting(model:, prototype_creator:); 0.0; end

    prototype = Standard.build('NECB2020')
    legacy_total = coster.cost_audit_lighting(model, prototype)

    gem_report = OpenStudioLighting.cost(model, vintage: '2020', city: CITY, province_state: PROVINCE)
    assert_in_delta legacy_total, gem_report.total, [legacy_total.abs * 0.001, 0.05].max,
                    'fixture-costing dollar parity vs legacy cost_audit_lighting (LED/NECB2020 path)'
  end
end
