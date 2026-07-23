#!/usr/bin/env ruby
# frozen_string_literal: true

# Breadth cross-validation sweep: generate legacy NECB2020 archetypes (same
# out-of-process recipe as openstudio-necb/test/test_legacy_archetype_e2e.rb,
# same cache dir) and run each through the NEW gem pipeline — proving
# preflight, system selection, reference transforms, the sizing run, and the
# post-sizing determinations (ERV 5.2.10.1, pump 8.4.4.14) on real whole
# buildings. SWEEP_MODE=annual adds January-week annual runs for both models
# and reports the 8.4.1.2 verdict + tier (the pipeline flags the shortened
# period as not-annual-compliant by itself). Preflight refusals are reported
# as FINDINGS (the unresolved space types), not crashes.
#
# Buildings are independent, so each runs in its OWN forked process (the
# stages within one building stay sequential by necessity: proposed sizing ->
# reference sizing -> annual runs). Usage:
#   [SWEEP_MODE=annual] ruby openstudio-necb/scripts/necb_archetype_sweep.rb [types...]

require 'fileutils'
require 'json'
require 'openstudio'

ROOT = File.expand_path('../..', __dir__)
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

def sweep_one(type)
  osm = generate!(type)
  return { type: type, verdict: 'GEN-FAIL', detail: "see #{CACHE_DIR}/gen_#{type}.err" } if osm.nil?

  annual = ENV['SWEEP_MODE'] == 'annual'
  run_dir = File.join(CACHE_DIR, "sweep_run_#{type.downcase}")
  FileUtils.rm_rf(run_dir)
  FileUtils.mkdir_p(run_dir)
  result = OpenStudioNECB.performance_compliance(
    osm, vintage: '2020', simulate: annual ? :annual : :sizing, hdd: 3890,
    weather: { epw: EPW, ddy: DDY }, run_dir: run_dir,
    run_period: annual ? { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 } : nil)
  ref = result.reference_model
  detail = "zones=#{ref.getThermalZones.size} air_loops=#{ref.getAirLoopHVACs.size} " \
           "plant_loops=#{ref.getPlantLoops.size} ervs=#{ref.getHeatExchangerAirToAirSensibleAndLatents.size} " \
           "warnings=#{result.audit.warnings.size}"
  if annual
    rep = result.report
    detail += format(' | proposed=%.0f ref=%.0f kWh wk compliant=%s tier=%s (%.0f%% of target)',
                     rep.dig('proposed', 'total_site_kwh').to_f, rep.dig('reference', 'total_site_kwh').to_f,
                     rep['compliant'].inspect, rep['tier'].inspect, rep['percent_of_target'].to_f)
  end
  { type: type, verdict: 'PASS', detail: detail }
rescue ArgumentError => e
  if e.message.include?('pre-flight')
    { type: type, verdict: 'PREFLIGHT-REFUSAL', detail: e.message.lines.first(4).join(' ').strip[0, 300] }
  else
    { type: type, verdict: 'ERROR', detail: "#{e.class}: #{e.message[0, 200]}" }
  end
rescue StandardError => e
  { type: type, verdict: 'ERROR', detail: "#{e.class}: #{e.message[0, 200]}" }
end

pids = TYPES.to_h do |type|
  [Process.fork do
    result = sweep_one(type)
    File.write(File.join(CACHE_DIR, "result_#{type}.json"), JSON.generate(result))
    exit!(result[:verdict] == 'PASS' ? 0 : 1)
  end, type]
end
pids.each_key { |pid| Process.wait(pid) }
results = TYPES.map { |t| JSON.parse(File.read(File.join(CACHE_DIR, "result_#{t}.json")), symbolize_names: true) }

puts
puts "necb_archetype_sweep results (#{ENV['SWEEP_MODE'] == 'annual' ? 'annual/week-run' : 'sizing'} mode, #{TYPES.size} parallel):"
results.each { |r| puts format('  %-22s %-18s %s', r[:type], r[:verdict], r[:detail]) }
exit(results.all? { |r| r[:verdict] == 'PASS' } ? 0 : 1)
