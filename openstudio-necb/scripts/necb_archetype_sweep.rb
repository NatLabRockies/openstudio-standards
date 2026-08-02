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
#   [SWEEP_MODE=annual] [FUEL=NaturalGas] [LOC=edmonton|yellowknife] \
#     ruby openstudio-necb/scripts/necb_archetype_sweep.rb [types...]
#
# FUEL (default Electricity) is the legacy generator's primary_heating_fuel —
# NaturalGas flips the whole Table 8.4.4.7.-B gas column (boilers, HW
# baseboards, gas coils, boiler staging). LOC picks the EPW/DDY + Table C-1
# HDD — edmonton (zone 7A) / yellowknife (zone 8) exercise the HDD-dependent
# envelope and ERV rows. VINTAGE (2020 default | 2025) picks the PIPELINE
# edition only — the proposed is ALWAYS the legacy NECB2020 archetype (legacy
# has no 2025 generator), so the generated-OSM cache is shared across
# vintages while run dirs and result files fork. Cache keys include
# fuel/loc(/vintage), so variants coexist.

require 'fileutils'
require 'json'
require 'openstudio'

ROOT = File.expand_path('../..', __dir__)
require File.join(ROOT, 'openstudio-necb', 'lib', 'openstudio_necb')

TYPES = ARGV.empty? ? %w[Warehouse FullServiceRestaurant HighriseApartment PrimarySchool RetailStandalone] : ARGV
CACHE_DIR = '/tmp/openstudio_necb_legacy_archetype_e2e'
FUEL = ENV.fetch('FUEL', 'Electricity')
LOC = ENV.fetch('LOC', 'toronto')
LOCATIONS = {
  # HDD18 from the gem's Table C-1 (table_c1.json) — the same source the pipeline resolves from
  'toronto' => { epw: File.join(ROOT, 'openstudio-hvac', 'test', 'fixtures', 'weather',
                                'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'), hdd: 3890 },
  'edmonton' => { epw: File.join(ROOT, 'data', 'weather', 'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw'), hdd: 5120 },
  'yellowknife' => { epw: File.join(ROOT, 'data', 'weather', 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'), hdd: 8170 }
}.freeze
raise(ArgumentError, "unknown LOC '#{LOC}' (#{LOCATIONS.keys.join('/')})") unless LOCATIONS.key?(LOC)

EPW = LOCATIONS[LOC][:epw]
DDY = EPW.sub('.epw', '.ddy')
HDD = LOCATIONS[LOC][:hdd]
VINTAGE = ENV.fetch('VINTAGE', '2020')
raise(ArgumentError, "unknown VINTAGE '#{VINTAGE}' (2020/2025)") unless %w[2020 2025].include?(VINTAGE)

# The proposed-OSM cache is vintage-independent (always the legacy NECB2020
# archetype); run dirs and result files carry the vintage.
GEN_VARIANT = [FUEL == 'Electricity' ? nil : FUEL.downcase, LOC == 'toronto' ? nil : LOC].compact.join('_')
SUFFIX = GEN_VARIANT.empty? ? '' : "_#{GEN_VARIANT}"
RUN_VARIANT = [GEN_VARIANT.empty? ? nil : GEN_VARIANT, VINTAGE == '2020' ? nil : "v#{VINTAGE}"].compact.join('_')
RUN_SUFFIX = RUN_VARIANT.empty? ? '' : "_#{RUN_VARIANT}"
FileUtils.mkdir_p(CACHE_DIR)

def generate!(type)
  osm = File.join(CACHE_DIR, "sweep_necb2020_#{type.downcase}#{SUFFIX}.osm")
  return osm if File.exist?(osm)

  gen = File.join(CACHE_DIR, "gen_#{type}#{SUFFIX}.rb")
  File.write(gen, <<~RUBY)
    require File.join('#{ROOT}', 'lib', 'openstudio-standards')
    std = Standard.build('NECB2020')
    model = std.model_create_prototype_model(
      template: 'NECB2020', building_type: '#{type}',
      primary_heating_fuel: '#{FUEL}',
      epw_file: '#{File.basename(EPW)}',
      sizing_run_dir: File.join('#{CACHE_DIR}', 'gen_sizing_#{type}#{SUFFIX}'))
    (warn('GENERATION FAILED'); exit 1) if model.nil? || model.is_a?(FalseClass)
    model.save(OpenStudio::Path.new('#{osm}'), true)
    puts 'OK'
  RUBY
  ok = system('bundle', 'exec', 'ruby', gen, chdir: ROOT, out: File.join(CACHE_DIR, "gen_#{type}#{SUFFIX}.log"),
                                              err: File.join(CACHE_DIR, "gen_#{type}#{SUFFIX}.err"))
  ok && File.exist?(osm) ? osm : nil
end

def sweep_one(type)
  osm = generate!(type)
  return { type: type, verdict: 'GEN-FAIL', detail: "see #{CACHE_DIR}/gen_#{type}.err" } if osm.nil?

  # SWEEP_MODE: 'sizing' (default) | 'annual' (January-week shortcut — fast,
  # flagged not-code-compliant by the pipeline) | 'full' (true 8760 h annual —
  # the code-compliant 8.4.1.2 determination). Full mode keeps its own run
  # dirs/result files so week-run artifacts survive side by side.
  mode = ENV.fetch('SWEEP_MODE', 'sizing')
  annual = %w[annual full].include?(mode)
  run_dir = File.join(CACHE_DIR, "sweep_run#{mode == 'full' ? '_full' : ''}_#{type.downcase}#{RUN_SUFFIX}")
  FileUtils.rm_rf(run_dir)
  FileUtils.mkdir_p(run_dir)
  result = OpenStudioNECB.performance_compliance(
    osm, vintage: VINTAGE, simulate: annual ? :annual : :sizing, hdd: HDD,
    weather: { epw: EPW, ddy: DDY }, run_dir: run_dir,
    run_period: mode == 'annual' ? { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 } : nil)
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

RESULT_TAG = ENV.fetch('SWEEP_MODE', 'sizing') == 'full' ? "_full#{RUN_SUFFIX}" : RUN_SUFFIX
pids = TYPES.to_h do |type|
  [Process.fork do
    result = sweep_one(type)
    File.write(File.join(CACHE_DIR, "result_#{type}#{RESULT_TAG}.json"), JSON.generate(result))
    exit!(result[:verdict] == 'PASS' ? 0 : 1)
  end, type]
end
pids.each_key { |pid| Process.wait(pid) }
results = TYPES.map { |t| JSON.parse(File.read(File.join(CACHE_DIR, "result_#{t}#{RESULT_TAG}.json")), symbolize_names: true) }

puts
mode_label = { 'annual' => 'annual/week-run', 'full' => 'FULL ANNUAL (8760 h)' }.fetch(ENV.fetch('SWEEP_MODE', 'sizing'), 'sizing')
puts "necb_archetype_sweep results (#{mode_label} mode, vintage=#{VINTAGE}, fuel=#{FUEL}, loc=#{LOC}, #{TYPES.size} parallel):"
results.each { |r| puts format('  %-22s %-18s %s', r[:type], r[:verdict], r[:detail]) }
exit(results.all? { |r| r[:verdict] == 'PASS' } ? 0 : 1)
