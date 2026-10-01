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
  DERIVATION_TYPES = %w[linear exponential exponential-inverse up_down logistic saturating first_order].freeze
  DIURNAL_MODES = %w[off_when_asleep on_when_asleep].freeze

  # One file per category. Each load file holds both forms a schedule can take: a
  # control-point profile (direct) and a derivation parameter set (derived from occupancy).
  DATA_FILES = {
    occupancy: 'default_occupancy_schedules.json',
    Lighting: 'default_lighting_schedules.json',
    electric_equipment: 'default_electric_equipment_schedules.json',
    gas_equipment: 'default_gas_equipment_schedules.json',
    hot_water_equipment: 'default_hot_water_equipment_schedules.json',
    diurnal: 'default_diurnal_schedules.json'
  }.freeze

  LOAD_SLOTS = %i[Lighting electric_equipment gas_equipment hot_water_equipment].freeze

  # control-point expression grammar: an anchor with an optional +/-/* numeric modifier
  TIME_EXPR = /\A(st|et)([+\-*]\d+(\.\d+)?)?\z/.freeze
  # 'range*f' places a point f of the way from base to peak (see reanchor_control_points.rb)
  VALUE_EXPR = /\A(base|peak|range)([+\-*]\d+(\.\d+)?)?\z/.freeze

  def setup
    @files = DATA_FILES.transform_values { |f| load_json(f) }
    @schedule_sets = load_json('default_parametric_schedule_set.json')
    # A record's form, not its file, says which rules apply to it: a profile carries
    # day_types, a derivation carries derivation_type.
    @schedules = @files.values.flatten.select { |o| o.key?('day_types') }
    @load_param_files = LOAD_SLOTS.to_h { |slot| [slot, @files[slot].reject { |o| o.key?('day_types') }] }
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
    diurnal_names = @files[:diurnal].map { |o| o['name'] }

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

  # A linear derivation is base + (peak - base) x presence x response, so its reachable
  # maximum is base + (peak - base) x response. The grid search that fit these parameters
  # tied on a flat occupancy trace and kept its first candidate, a response of 0.05, on 53
  # lighting records: a classroom whose peak is 0.657 could not rise above 0.149 whatever
  # the occupancy. A derivation whose peak cannot be reached is a broken fit, not a
  # calibration choice, so every linear record must reach at least half of its peak.
  def test_linear_derivations_can_reach_their_peak
    errors = []
    @load_param_files.each do |label, entries|
      entries.each do |obj|
        next unless obj['derivation_type'] == 'linear' && numeric?(obj['base']) && numeric?(obj['peak']) && numeric?(obj['response'])

        peak = obj['peak'].to_f
        next if peak < 0.2

        reachable = obj['base'].to_f + ((peak - obj['base'].to_f) * obj['response'].to_f)
        next if reachable >= 0.5 * peak

        errors << format("%s/%s: linear response %.3f reaches only %.3f of a %.3f peak", label, obj['name'], obj['response'].to_f, reachable, peak)
      end
    end
    assert_no_errors(errors)
  end

  # ---------------------------------------------------------------------------
  # default_parametric_schedule_set.json — structure + cross-file references
  # ---------------------------------------------------------------------------

  # Mirrors resolve_load_schedule: a load reference resolves if the category's own file
  # holds a record of that name, in either form.
  def load_reference_resolves?(name, slot)
    @files[slot].any? { |o| o['name'] == name }
  end

  def test_schedule_set_references
    errors = []
    occ_names = @files[:occupancy].map { |o| o['name'] }

    load_columns = {
      'interior_lighting_schedule' => :Lighting,
      'electric_equipment_schedule' => :electric_equipment,
      'gas_equipment_schedule' => :gas_equipment,
      'hot_water_equipment_schedule' => :hot_water_equipment
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

      load_columns.each do |column, slot|
        name = set[column]
        next if name.nil?

        unless load_reference_resolves?(name, slot)
          errors << "#{id}: #{column} '#{name}' has no record in #{DATA_FILES[slot]}"
        end
      end
    end

    assert_no_errors(errors)
  end
end
