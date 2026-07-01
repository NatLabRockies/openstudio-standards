module OpenStudio
  def self.logFree(*); end
  Error = :error
  Warn  = :warn
  Info  = :info
  Debug = :debug
end

require 'sinatra'
require 'json'
require 'rack/cors'

REPO_ROOT = File.expand_path('../../', __dir__)

SPACE_TYPES_PATH          = File.join(REPO_ROOT, 'lib/openstudio-standards/space_type/data/level_1_space_types.json')
PARAMETRIC_SCHEDULES_PATH = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_parametric_schedules.json')
SCHEDULE_SET_PATH         = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_parametric_schedule_set.json')
LIGHTING_PARAMS_PATH     = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_lighting_parameters.json')
ELEC_EQUIP_PARAMS_PATH   = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_electric_equipment_parameters.json')
GAS_EQUIP_PARAMS_PATH    = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_gas_equipment_parameters.json')
HOT_WATER_PARAMS_PATH    = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_hot_water_equipment_parameters.json')
ASHRAE_SCHEDULES_PATH    = File.join(REPO_ROOT, 'lib/openstudio-standards/standards/ashrae_90_1/data/ashrae_90_1.schedules.json')
CBES_SCHEDULES_PATH      = File.join(REPO_ROOT, 'lib/openstudio-standards/standards/cbes/data/cbes.schedules.json')
DEER_SCHEDULES_PATH      = File.join(REPO_ROOT, 'lib/openstudio-standards/standards/deer/data/deer.schedules.json')

require_relative File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/create_parametric_schedule.rb')

set :port, 4567
set :bind, '0.0.0.0'

use Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource '*', headers: :any, methods: [:get, :post, :options]
  end
end

before do
  content_type :json
end

get '/api/data' do
  space_types          = JSON.parse(File.read(SPACE_TYPES_PATH))
  parametric_schedules = JSON.parse(File.read(PARAMETRIC_SCHEDULES_PATH))
  schedule_sets        = JSON.parse(File.read(SCHEDULE_SET_PATH))
  lighting_params     = JSON.parse(File.read(LIGHTING_PARAMS_PATH))
  elec_equip_params   = JSON.parse(File.read(ELEC_EQUIP_PARAMS_PATH))
  gas_equip_params    = JSON.parse(File.read(GAS_EQUIP_PARAMS_PATH))
  hot_water_params    = JSON.parse(File.read(HOT_WATER_PARAMS_PATH))

  ashrae_raw       = JSON.parse(File.read(ASHRAE_SCHEDULES_PATH))
  ashrae_schedules = ashrae_raw.is_a?(Hash) ? (ashrae_raw['schedules'] || []) : ashrae_raw

  cbes_raw       = JSON.parse(File.read(CBES_SCHEDULES_PATH))
  cbes_schedules = cbes_raw.is_a?(Hash) ? (cbes_raw['schedules'] || []) : cbes_raw

  deer_raw       = JSON.parse(File.read(DEER_SCHEDULES_PATH))
  deer_schedules = deer_raw.is_a?(Hash) ? (deer_raw['schedules'] || []) : deer_raw

  {
    space_types:          space_types,
    parametric_schedules: parametric_schedules,
    schedule_sets:        schedule_sets,
    lighting_params:     lighting_params,
    elec_equip_params:   elec_equip_params,
    gas_equip_params:    gas_equip_params,
    hot_water_params:    hot_water_params,
    ashrae_schedules:    ashrae_schedules,
    cbes_schedules:      cbes_schedules,
    deer_schedules:      deer_schedules
  }.to_json
end

# Returns the space type entries for a given template, with only schedule-relevant fields.
# :template param must match a key in ASHRAE_TEMPLATES (URL-encoded).
get '/api/spc_typ/:template' do
  label = params[:template]
  dir_name = ASHRAE_TEMPLATES[label]
  halt 404, { error: "Unknown template '#{label}'" }.to_json unless dir_name

  path = File.join(REPO_ROOT, 'lib/openstudio-standards/standards/ashrae_90_1', dir_name, 'data', "#{dir_name}.spc_typ.json")
  halt 404, { error: "File not found for template '#{label}'" }.to_json unless File.exist?(path)

  raw = JSON.parse(File.read(path))
  entries = (raw.is_a?(Hash) ? raw['space_types'] : raw) || []

  result = entries
    .select { |e| e['building_type'] && e['space_type'] }
    .map do |e|
      {
        key:                      "#{e['building_type']} - #{e['space_type']}",
        building_type:            e['building_type'],
        space_type:               e['space_type'],
        occupancy_schedule:       e['occupancy_schedule'],
        lighting_schedule:        e['lighting_schedule'],
        electric_equipment_schedule: e['electric_equipment_schedule'],
        gas_equipment_schedule:   e['gas_equipment_schedule']
      }
    end

  result.to_json
end

ASHRAE_TEMPLATES = {
  '90.1-2004'        => 'ashrae_90_1_2004',
  '90.1-2007'        => 'ashrae_90_1_2007',
  '90.1-2010'        => 'ashrae_90_1_2010',
  '90.1-2013'        => 'ashrae_90_1_2013',
  '90.1-2016'        => 'ashrae_90_1_2016',
  '90.1-2019'        => 'ashrae_90_1_2019',
  'DOE Ref 1980-2004' => 'doe_ref_1980_2004',
  'DOE Ref Pre-1980'  => 'doe_ref_pre_1980'
}.freeze

SAVE_TARGETS = {
  'parametric_schedules' => PARAMETRIC_SCHEDULES_PATH,
  'schedule_sets'        => SCHEDULE_SET_PATH,
  'lighting_params'     => LIGHTING_PARAMS_PATH,
  'elec_equip_params'   => ELEC_EQUIP_PARAMS_PATH,
  'gas_equip_params'    => GAS_EQUIP_PARAMS_PATH,
  'hot_water_params'    => HOT_WATER_PARAMS_PATH
}.freeze

post '/api/expand_parametric' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  sch  = body[:schedule_data]
  p    = body[:params] || {}
  tph  = (p[:timesteps_per_hour] || sch[:timesteps_per_hour] || 1).to_i
  base = (p[:base]  || sch[:base_std]).to_f
  peak = (p[:peak]  || sch[:peak_std]).to_f
  st   = (p[:st]    || sch[:st_std]).to_f
  et   = (p[:et]    || sch[:et_std]).to_f
  pairs = OpenstudioStandards::Schedules.expand_schedule_control_points(sch, base, peak, st, et, tph)
  { time_value_pairs: pairs }.to_json
end

post '/api/expand_slope' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  sch  = body[:schedule_data]
  p    = body[:params] || {}
  tph  = (p[:timesteps_per_hour] || sch[:timesteps_per_hour] || 1).to_i
  base = (p[:base]  || sch[:base_std]).to_f
  peak = (p[:peak]  || sch[:peak_std]).to_f
  st   = (p[:st]    || sch[:st_std]).to_f
  et   = (p[:et]    || sch[:et_std]).to_f
  pairs = OpenstudioStandards::Schedules.expand_schedule_start_end_slope(sch, base, peak, st, et, tph)
  { time_value_pairs: pairs }.to_json
end

# Returns the RAW, un-smoothed control-point anchors so the editor can place
# draggable markers exactly on the schedule's control points. Mirrors the
# /api/expand_parametric request shape but calls evaluate_schedule_control_points
# (no wrap, no smoothing). Used by the control-point editor in standard-coordinate mode.
post '/api/evaluate_control_points' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  sch  = body[:schedule_data]
  p    = body[:params] || {}
  tph  = (p[:timesteps_per_hour] || sch[:timesteps_per_hour] || 1).to_i
  base = (p[:base]  || sch[:base_std]).to_f
  peak = (p[:peak]  || sch[:peak_std]).to_f
  st   = (p[:st]    || sch[:st_std]).to_f
  et   = (p[:et]    || sch[:et_std]).to_f
  anchors = OpenstudioStandards::Schedules.evaluate_schedule_control_points(sch, base, peak, st, et, tph)
  { anchors: anchors }.to_json
end

# Apply a diurnal gate to occupancy presence pairs before derivation, mirroring
# OpenstudioStandards::Schedules.build_diurnal_gate without the OpenStudio SDK objects:
# expand the Diurnal profile's control points, then scale each presence value by
# gate = on_when_asleep ? (weight * d) : (1 - weight * d), clamped to [0, 1].
def apply_diurnal_gate(initial_values, diurnal_sd, diurnal_mode, diurnal_weight, tph)
  return initial_values if diurnal_sd.nil?

  dpairs = OpenstudioStandards::Schedules.expand_schedule_control_points(
    diurnal_sd,
    diurnal_sd[:base_std].to_f, diurnal_sd[:peak_std].to_f,
    diurnal_sd[:st_std].to_f, diurnal_sd[:et_std].to_f, tph
  )
  on_when_asleep = diurnal_mode.to_s == 'on_when_asleep'
  weight = diurnal_weight.nil? ? 1.0 : diurnal_weight.to_f

  initial_values.map do |t, v|
    d = OpenstudioStandards::Schedules.profile_value_at(dpairs, t)
    g = on_when_asleep ? (weight * d) : (1.0 - (weight * d))
    g = g.clamp(0.0, 1.0)
    [t, v * g]
  end
end

post '/api/derive' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  tph  = (body[:timesteps_per_hour] || 1).to_i

  # Occupancy base/peak for absolute-mode normalization is taken from the UNGATED
  # presence (matching the library, which uses the occupancy schedule's own base/peak),
  # so the diurnal gate does not shift the normalization range.
  occ_vals = (body[:initial_values] || []).map { |p| p[1] }
  occupancy_base = occ_vals.empty? ? nil : occ_vals.min
  occupancy_peak = occ_vals.empty? ? nil : occ_vals.max

  initial_values = apply_diurnal_gate(
    body[:initial_values], body[:diurnal_schedule_data],
    body[:diurnal_mode], body[:diurnal_weight], tph
  )
  pairs = OpenstudioStandards::Schedules.derive_values(
    body[:derivation_type],
    body[:base].to_f,
    body[:peak].to_f,
    body[:response].to_f,
    initial_values,
    start_slope:        body[:start_slope],
    end_slope:          body[:end_slope],
    start_time:         body[:start_time],
    end_time:           body[:end_time],
    timesteps_per_hour: tph,
    base_peak_mode:     body[:base_peak_mode] || 'absolute',
    occupancy_base:     occupancy_base,
    occupancy_peak:     occupancy_peak
  )
  { time_value_pairs: pairs }.to_json
end

# Custom pretty-printer matching the committed default_parametric_schedules.json /
# *_parameters.json style: 2-space indent, one space after the colon, but arrays of
# scalars (the control-point [time, value] pairs) render inline. This keeps a no-op
# save byte-stable (no spurious whitespace diffs), preserving the standalone-expansion
# invariant at the file level.
def scalar_for_json?(v)
  v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false || v.nil?
end

def format_parametric_json(obj, indent = 0)
  sp  = '  ' * indent
  sp1 = '  ' * (indent + 1)
  case obj
  when Hash
    return '{}' if obj.empty?
    inner = obj.map { |k, v| "#{sp1}#{k.to_s.to_json}: #{format_parametric_json(v, indent + 1)}" }.join(",\n")
    "{\n#{inner}\n#{sp}}"
  when Array
    return '[]' if obj.empty?
    if obj.all? { |e| scalar_for_json?(e) }
      '[' + obj.map(&:to_json).join(', ') + ']'
    else
      inner = obj.map { |e| "#{sp1}#{format_parametric_json(e, indent + 1)}" }.join(",\n")
      "[\n#{inner}\n#{sp}]"
    end
  else
    obj.to_json
  end
end

# Serialize each target in the exact committed style so unchanged records stay byte-identical.
def serialize_save(target, data)
  if target == 'schedule_sets'
    # 4-space indent, two spaces after the colon, trailing newline
    JSON.pretty_generate(data, indent: '    ', space: '  ') + "\n"
  else
    # parametric_schedules + *_params: inline control-point pairs, no trailing newline
    format_parametric_json(data)
  end
end

post '/api/save' do
  body   = JSON.parse(request.body.read)
  target = body['target']
  unless SAVE_TARGETS.key?(target)
    status 400
    return { error: "Unknown target '#{target}'. Allowed: #{SAVE_TARGETS.keys.join(', ')}" }.to_json
  end
  path    = SAVE_TARGETS[target]
  tmp     = "#{path}.tmp"
  File.write(tmp, serialize_save(target, body['data']))
  File.rename(tmp, path)
  { saved: true }.to_json
end

error do
  status 500
  { error: env['sinatra.error'].message }.to_json
end
