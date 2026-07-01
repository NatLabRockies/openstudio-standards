require_relative '../../helpers/minitest_helper'

# Data-integrity checks for the parametric schedule data files. These run at author/CI
# time (not per model build) and catch the failures the runtime schedule code handles
# silently or late: missing/typo'd fields, malformed control-point expressions, bad
# enums/ranges, ambiguous duplicate day types, and broken cross-file references.
#
# Each test accumulates every problem and asserts the list is empty, so one run surfaces
# all issues at once with the offending entry named.
class TestSchedulesDataIntegrity < Minitest::Test
  DATA_DIR = File.expand_path('../../../lib/openstudio-standards/schedules/data', __dir__)

  CATEGORIES = %w[Occupancy Lighting Equipment Diurnal].freeze
  # day-type tokens the schedule builder understands (create_complex_schedule + design days)
  DAY_TYPES = %w[Default Wkdy Wknd Mon Tue Wed Thu Fri Sat Sun SmrDsn WntrDsn Hol].freeze
  EXPANSIONS = %w[control_points slope].freeze
  ADJUSTMENT_MODES = %w[stretch truncate].freeze
  DERIVATION_TYPES = %w[linear exponential exponential-inverse up_down].freeze
  DIURNAL_MODES = %w[off_when_asleep on_when_asleep].freeze

  # control-point expression grammar: an anchor with an optional +/-/* numeric modifier
  TIME_EXPR = /\A(st|et)([+\-*]\d+(\.\d+)?)?\z/.freeze
  VALUE_EXPR = /\A(base|peak)([+\-*]\d+(\.\d+)?)?\z/.freeze

  def setup
    @schedules = load_json('default_parametric_schedules.json')
    @schedule_sets = load_json('default_parametric_schedule_set.json')
    @load_param_files = {
      'Lighting' => load_json('default_lighting_parameters.json'),
      'electric_equipment' => load_json('default_electric_equipment_parameters.json'),
      'gas_equipment' => load_json('default_gas_equipment_parameters.json'),
      'hot_water_equipment' => load_json('default_hot_water_equipment_parameters.json')
    }
  end

  def load_json(name)
    JSON.parse(File.read(File.join(DATA_DIR, name)))
  end

  def numeric?(value)
    value.is_a?(Numeric)
  end

  def assert_no_errors(errors)
    assert errors.empty?, "#{errors.size} data integrity issue(s):\n  - #{errors.join("\n  - ")}"
  end

  # ---------------------------------------------------------------------------
  # default_parametric_schedules.json — structure + control-point grammar
  # ---------------------------------------------------------------------------

  def test_parametric_schedules_structure
    errors = []
    @schedules.each_with_index do |obj, i|
      id = obj['name'] ? "#{obj['name']} (#{obj['category']})" : "entry ##{i}"

      %w[name day_types start_date end_date category type base_std peak_std st_std et_std].each do |k|
        errors << "#{id}: missing required field '#{k}'" unless obj.key?(k)
      end
      next unless obj['name'] && obj['day_types'] && obj['category']

      errors << "#{id}: invalid category '#{obj['category']}'" unless CATEGORIES.include?(obj['category'])
      errors << "#{id}: type must be 'parametric'" unless obj['type'] == 'parametric'

      obj['day_types'].split('|').each do |dt|
        errors << "#{id}: invalid day_type '#{dt}'" unless DAY_TYPES.include?(dt)
      end

      %w[base_std peak_std st_std et_std].each do |k|
        errors << "#{id}: '#{k}' must be numeric" if obj.key?(k) && !numeric?(obj[k])
      end
      [obj['base_std'], obj['peak_std']].each do |v|
        errors << "#{id}: base/peak #{v} outside [0, 1]" if numeric?(v) && (v < 0.0 || v > 1.0)
      end
      errors << "#{id}: st_std/et_std out of range" if numeric?(obj['st_std']) && numeric?(obj['et_std']) &&
                                                       (obj['st_std'].negative? || obj['et_std'] > 48.0)

      if obj.key?('expansion') && !EXPANSIONS.include?(obj['expansion'])
        errors << "#{id}: invalid expansion '#{obj['expansion']}'"
      end
      if obj.key?('adjustment_mode') && !ADJUSTMENT_MODES.include?(obj['adjustment_mode'])
        errors << "#{id}: invalid adjustment_mode '#{obj['adjustment_mode']}'"
      end

      %w[start_slope end_slope].each do |k|
        errors << "#{id}: '#{k}' must be numeric" if obj.key?(k) && !numeric?(obj[k])
      end

      # must be expandable: control points OR both slopes, consistent with `expansion`
      has_cp = obj['control_points'].is_a?(Array) && !obj['control_points'].empty?
      has_slopes = obj.key?('start_slope') && obj.key?('end_slope')
      case obj['expansion']
      when 'slope'
        errors << "#{id}: expansion 'slope' requires start_slope and end_slope" unless has_slopes
      when 'control_points'
        errors << "#{id}: expansion 'control_points' requires control_points" unless has_cp
      else
        errors << "#{id}: needs control_points or both slopes" unless has_cp || has_slopes
      end

      # control-point grammar
      if has_cp
        obj['control_points'].each_with_index do |cp, j|
          unless cp.is_a?(Array) && cp.size == 2 && cp.all? { |s| s.is_a?(String) }
            errors << "#{id}: control_point ##{j} must be a [time, value] pair of strings"
            next
          end
          errors << "#{id}: bad time expr '#{cp[0]}'" unless cp[0] =~ TIME_EXPR
          errors << "#{id}: bad value expr '#{cp[1]}'" unless cp[1] =~ VALUE_EXPR
        end
      end

      %w[start_date end_date].each do |k|
        next unless obj[k].is_a?(String)

        begin
          DateTime.strptime(obj[k])
        rescue ArgumentError
          errors << "#{id}: unparseable #{k} '#{obj[k]}'"
        end
      end
    end

    assert_no_errors(errors)
  end

  # A (name, category) groups one ruleset. The same day-type token may legitimately
  # repeat across objects with different date ranges (e.g. seasonal Wkdy rules), so the
  # ambiguity to flag is an exact duplicate: the same day type AND the same date range.
  def test_parametric_schedules_no_duplicate_day_rules
    errors = []
    @schedules.group_by { |o| [o['name'], o['category']] }.each do |(name, category), group|
      seen = {}
      group.each do |obj|
        next unless obj['day_types']

        obj['day_types'].split('|').each do |dt|
          key = [dt, obj['start_date'], obj['end_date']]
          if seen[key]
            errors << "#{name} (#{category}): duplicate '#{dt}' rule for #{obj['start_date']}..#{obj['end_date']}"
          else
            seen[key] = true
          end
        end
      end
    end
    assert_no_errors(errors)
  end

  # ---------------------------------------------------------------------------
  # derived-load parameter files — structure
  # ---------------------------------------------------------------------------

  def test_load_parameter_files_structure
    errors = []
    diurnal_names = @schedules.select { |o| o['category'] == 'Diurnal' }.map { |o| o['name'] }

    @load_param_files.each do |label, entries|
      entries.each_with_index do |obj, i|
        id = obj['name'] ? "#{label}/#{obj['name']}" : "#{label} entry ##{i}"

        %w[name category derivation_type base peak].each do |k|
          errors << "#{id}: missing required field '#{k}'" unless obj.key?(k)
        end
        next unless obj['name']

        errors << "#{id}: category must be Lighting or Equipment" unless %w[Lighting Equipment].include?(obj['category'])
        errors << "#{id}: invalid derivation_type '#{obj['derivation_type']}'" unless DERIVATION_TYPES.include?(obj['derivation_type'])

        %w[base peak response].each do |k|
          errors << "#{id}: '#{k}' must be numeric" if obj.key?(k) && !numeric?(obj[k])
        end
        errors << "#{id}: derivation_type '#{obj['derivation_type']}' needs response" if !obj['derivation_type'].nil? &&
                                                                                         obj['derivation_type'] != 'up_down' && !obj.key?('response')
        if obj['derivation_type'] == 'up_down' && !(obj.key?('start_slope') && obj.key?('end_slope'))
          errors << "#{id}: derivation_type 'up_down' needs start_slope and end_slope"
        end

        # optional diurnal modifier fields
        if obj.key?('diurnal_profile') && !obj['diurnal_profile'].nil?
          errors << "#{id}: diurnal_profile '#{obj['diurnal_profile']}' has no Diurnal curve" unless diurnal_names.include?(obj['diurnal_profile'])
        end
        if obj.key?('diurnal_mode') && !DIURNAL_MODES.include?(obj['diurnal_mode'])
          errors << "#{id}: invalid diurnal_mode '#{obj['diurnal_mode']}'"
        end
        if obj.key?('diurnal_weight') && (!numeric?(obj['diurnal_weight']) || obj['diurnal_weight'] < 0.0 || obj['diurnal_weight'] > 1.0)
          errors << "#{id}: diurnal_weight must be a number in [0, 1]"
        end
      end
    end
    assert_no_errors(errors)
  end

  # ---------------------------------------------------------------------------
  # default_parametric_schedule_set.json — structure + cross-file references
  # ---------------------------------------------------------------------------

  # Mirrors resolve_load_schedule: a load reference resolves if it names a direct
  # parametric schedule of the load's category, OR a derivation parameter set.
  def load_reference_resolves?(name, direct_category, param_file_label)
    return true if @schedules.any? { |o| o['name'] == name && o['category'] == direct_category }

    @load_param_files[param_file_label].any? { |o| o['name'] == name }
  end

  def test_schedule_set_references
    errors = []
    occ_names = @schedules.select { |o| o['category'] == 'Occupancy' }.map { |o| o['name'] }

    load_columns = {
      'derived_interior_lighting_parameters' => ['Lighting', 'Lighting'],
      'derived_electric_equipment_parameters' => ['Equipment', 'electric_equipment'],
      'derived_gas_equipment_parameters' => ['Equipment', 'gas_equipment'],
      'derived_hot_water_equipment_parameters' => ['Equipment', 'hot_water_equipment']
    }

    @schedule_sets.each_with_index do |set, i|
      id = set['schedule_set_name'] || "set ##{i}"
      errors << "#{id}: missing schedule_set_name" unless set.key?('schedule_set_name')

      %w[start_time_offset end_time_offset].each do |k|
        errors << "#{id}: '#{k}' must be numeric" if set.key?(k) && !set[k].nil? && !numeric?(set[k])
      end

      occ = set['occupancy_schedule']
      if !occ.nil? && !occ_names.include?(occ)
        errors << "#{id}: occupancy_schedule '#{occ}' has no Occupancy definition"
      end

      load_columns.each do |column, (direct_category, param_label)|
        name = set[column]
        next if name.nil?

        unless load_reference_resolves?(name, direct_category, param_label)
          errors << "#{id}: #{column} '#{name}' resolves to neither a direct #{direct_category} schedule nor a #{param_label} parameter set"
        end
      end
    end

    assert_no_errors(errors)
  end
end
