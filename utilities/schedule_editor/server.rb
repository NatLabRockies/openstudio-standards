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

SPACE_TYPES_PATH         = File.join(REPO_ROOT, 'lib/openstudio-standards/space_type/data/level_1_space_types.json')
OCCUPANCY_SCHEDULES_PATH = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_parametric_occupancy_schedules.json')
SCHEDULE_SET_PATH        = File.join(REPO_ROOT, 'lib/openstudio-standards/schedules/data/default_parametric_schedule_set.json')
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
  space_types         = JSON.parse(File.read(SPACE_TYPES_PATH))
  occupancy_schedules = JSON.parse(File.read(OCCUPANCY_SCHEDULES_PATH))
  schedule_sets       = JSON.parse(File.read(SCHEDULE_SET_PATH))
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
    space_types:         space_types,
    occupancy_schedules: occupancy_schedules,
    schedule_sets:       schedule_sets,
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
  'occupancy_schedules' => OCCUPANCY_SCHEDULES_PATH,
  'schedule_sets'       => SCHEDULE_SET_PATH,
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

post '/api/derive' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  pairs = OpenstudioStandards::Schedules.derive_values(
    body[:derivation_type],
    body[:base].to_f,
    body[:peak].to_f,
    body[:response].to_f,
    body[:initial_values],
    start_slope:       body[:start_slope],
    end_slope:         body[:end_slope],
    start_time:        body[:start_time],
    end_time:          body[:end_time],
    timesteps_per_hour: (body[:timesteps_per_hour] || 1).to_i
  )
  { time_value_pairs: pairs }.to_json
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
  File.write(tmp, JSON.pretty_generate(body['data']))
  File.rename(tmp, path)
  { saved: true }.to_json
end

error do
  status 500
  { error: env['sinatra.error'].message }.to_json
end
