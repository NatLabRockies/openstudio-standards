#!/usr/bin/env ruby
# frozen_string_literal: true

# Breadth cross-validation sweep: generate legacy NECB2020 archetypes (same
# out-of-process recipe as openstudio-necb/test/test_legacy_archetype_e2e.rb,
# same cache dir) and run each through the NEW gem pipeline in :sizing mode —
# proving preflight, system selection, reference transforms, the sizing run,
# and the post-sizing determinations (ERV 5.2.10.1, pump 8.4.4.14) on real
# whole buildings. Preflight refusals are reported as FINDINGS (the unresolved
# space types), not crashes. Usage: ruby scripts/necb_archetype_sweep.rb [types...]

require 'fileutils'
require 'openstudio'

ROOT = File.expand_path('..', __dir__)
require File.join(ROOT, 'openstudio-necb', 'lib', 'openstudio_necb')

TYPES = ARGV.empty? ? %w[Warehouse FullServiceRestaurant HighriseApartment PrimarySchool RetailStandalone] : ARGV
CACHE_DIR = '/tmp/openstudio_necb_legacy_archetype_e2e'
EPW = File.join(ROOT, 'openstudio-hvac', 'test', 'fixtures', 'weather', 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
DDY = EPW.sub('.epw', '.ddy')
FileUtils.mkdir_p(CACHE_DIR)

def generate!(type)
  osm = File.join(CACHE_DIR, "sweep_necb2020_#{type.downcase}.osm")
  return osm if File.exist?(osm)

  gen = File.join(CACHE_DIR, "gen_#{type}.rb")
  File.write(gen, <<~RUBY)
    require File.join('#{ROOT}', 'lib', 'openstudio-standards')
    std = Standard.build('NECB2020')
    model = std.model_create_prototype_model(
      template: 'NECB2020', building_type: '#{type}',
      epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      sizing_run_dir: File.join('#{CACHE_DIR}', 'gen_sizing_#{type}'))
    (warn('GENERATION FAILED'); exit 1) if model.nil? || model.is_a?(FalseClass)
    model.save(OpenStudio::Path.new('#{osm}'), true)
    puts 'OK'
  RUBY
  ok = system('bundle', 'exec', 'ruby', gen, chdir: ROOT, out: File.join(CACHE_DIR, "gen_#{type}.log"),
                                              err: File.join(CACHE_DIR, "gen_#{type}.err"))
  ok && File.exist?(osm) ? osm : nil
end

results = TYPES.map do |type|
  print "#{type}: generating... "
  osm = generate!(type)
  next { type: type, verdict: 'GEN-FAIL', detail: "see #{CACHE_DIR}/gen_#{type}.err" } if osm.nil?

  print "pipeline... "
  run_dir = File.join(CACHE_DIR, "sweep_run_#{type.downcase}")
  FileUtils.rm_rf(run_dir)
  FileUtils.mkdir_p(run_dir)
  begin
    result = OpenStudioNECB.performance_compliance(
      osm, vintage: '2020', simulate: :sizing, hdd: 3890,
      weather: { epw: EPW, ddy: DDY }, run_dir: run_dir)
    warns = result.audit.warnings.size
    ref = result.reference_model
    { type: type, verdict: 'PASS',
      detail: "zones=#{ref.getThermalZones.size} air_loops=#{ref.getAirLoopHVACs.size} " \
              "plant_loops=#{ref.getPlantLoops.size} ervs=#{ref.getHeatExchangerAirToAirSensibleAndLatents.size} " \
              "warnings=#{warns}" }
  rescue ArgumentError => e
    if e.message.include?('pre-flight')
      { type: type, verdict: 'PREFLIGHT-REFUSAL', detail: e.message.lines.first(4).join(' ').strip[0, 300] }
    else
      { type: type, verdict: 'ERROR', detail: "#{e.class}: #{e.message[0, 200]}" }
    end
  rescue StandardError => e
    { type: type, verdict: 'ERROR', detail: "#{e.class}: #{e.message[0, 200]}" }
  end.tap { |r| puts r[:verdict] }
end

puts
puts 'necb_archetype_sweep results:'
results.each { |r| puts format('  %-22s %-18s %s', r[:type], r[:verdict], r[:detail]) }
exit(results.all? { |r| r[:verdict] == 'PASS' } ? 0 : 1)
