require_relative '../../helpers/minitest_helper'

# Tests to compare prototype vs parametric schedules across ComStock building types.
# Generates an HTML report with interactive charts for visual comparison.
class TestScheduleComparison < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @geo = OpenstudioStandards::Geometry
    @sch = OpenstudioStandards::Schedules

    FileUtils.mkdir_p "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"

    # suppress most logging to keep test output readable
    OpenStudio::Logger.instance.standardOutLogger.setLogLevel(OpenStudio::Warn)
  end

  # ---------------------------------------------------------------------------
  # Main test
  # ---------------------------------------------------------------------------

  # Generates two sets of models – one with 'prototype' schedules and one with
  # 'parametric' schedules – for each ComStock building type listed below.
  # Extracts ScheduleRuleset objects from both models, labels them by building
  # type and space type, then writes an HTML file with side-by-side charts so
  # you can visually compare the two schedule methods.
  #
  # Output: test/modules/create_typical/output/test_compare_prototype_vs_parametric_schedules/schedule_comparison.html
  def test_compare_prototype_vs_parametric_schedules
    template = 'ComStock 90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'

    # Building type => floor area (ft^2).
    # Smaller buildings use 10 000 ft^2; larger use 100 000 ft^2.
    small_types = %w[QuickServiceRestaurant FullServiceRestaurant SmallOffice Warehouse SmallHotel]
    building_types = %w[
      SecondarySchool
      PrimarySchool
      SmallOffice
      MediumOffice
      LargeOffice
      SmallHotel
      LargeHotel
      Warehouse
      RetailStandalone
      RetailStripmall
      QuickServiceRestaurant
      FullServiceRestaurant
      Hospital
      Outpatient
      SuperMarket
    ]

    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir_p output_dir unless Dir.exist? output_dir

    # collected data structure:
    #   all_data[bldg_type]['prototype'|'parametric'][space_type_label][schedule_label][day_type] = [24 hourly values]
    all_data = {}

    building_types.each do |bldg_type|
      floor_area = small_types.include?(bldg_type) ? 10_000 : 100_000
      all_data[bldg_type] = {}

      %w[prototype parametric].each do |schedule_method|
        puts "Building: #{bldg_type}, schedule_method: #{schedule_method}"

        model = build_comstock_model(bldg_type, floor_area, template, climate_zone,
                                     schedule_method, output_dir)
        next if model.nil?

        all_data[bldg_type][schedule_method] = extract_schedule_data(model, bldg_type)
      end
    end

    # Write the HTML comparison report
    html_path = File.join(output_dir, 'schedule_comparison.html')
    write_html_report(all_data, html_path)

    assert File.exist?(html_path),
           "Expected HTML report at #{html_path} but file was not found."
    puts "Schedule comparison report written to: #{html_path}"
  end

  # ---------------------------------------------------------------------------
  # Model-building helpers
  # ---------------------------------------------------------------------------

  # Creates and fully populates a single ComStock model for one combination of
  # building type / schedule method.
  #
  # @param bldg_type      [String] e.g. 'MediumOffice'
  # @param floor_area     [Numeric] total building floor area in ft^2
  # @param template       [String] e.g. 'ComStock 90.1-2013'
  # @param climate_zone   [String] e.g. 'ASHRAE 169-2013-4A'
  # @param schedule_method [String] 'prototype' or 'parametric'
  # @param base_output_dir [String] parent output directory for sizing runs
  # @return [OpenStudio::Model::Model, nil]
  def build_comstock_model(bldg_type, floor_area, template, climate_zone,
                           schedule_method, base_output_dir)
    model = OpenStudio::Model::Model.new
    model.getYearDescription.setCalendarYear(2018)
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # --- Step 1: geometry ---
    bar_args = {
      climate_zone: climate_zone,
      bldg_type_a: bldg_type,
      bldg_type_a_num_units: 1,
      bldg_type_b: 'SecondarySchool',
      bldg_subtype_b: 'NA',
      bldg_type_b_fract_bldg_area: 0,
      bldg_type_b_num_units: 1,
      bldg_type_c: 'SecondarySchool',
      bldg_subtype_c: 'NA',
      bldg_type_c_fract_bldg_area: 0,
      bldg_type_c_num_units: 1,
      bldg_type_d: 'SecondarySchool',
      bldg_subtype_d: 'NA',
      bldg_type_d_fract_bldg_area: 0,
      bldg_type_d_num_units: 1,
      num_stories_below_grade: 0,
      num_stories_above_grade: 1,
      story_multiplier: 'None',
      bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
      bottom_story_ground_exposed_floor: true,
      top_story_exterior_exposed_roof: true,
      make_mid_story_surfaces_adiabatic: true,
      total_bldg_floor_area: floor_area,
      wwr: 0.38,
      ns_to_ew_ratio: 3,
      perim_mult: 0.0,
      bar_width: 0.0,
      bar_sep_dist_mult: 10.0,
      building_rotation: 0.0,
      template: template,
      custom_height_bar: true,
      floor_height: 0.0,
      party_wall_fraction: 0.0,
      party_wall_stories_north: 0,
      party_wall_stories_south: 0,
      party_wall_stories_east: 0,
      party_wall_stories_west: 0,
      double_loaded_corridor: 'Primary Space Type',
      space_type_sort_logic: 'Building Type > Size',
      single_floor_area: 0
    }

    result = @geo.create_bar_from_building_type_ratios(model, bar_args)
    unless result
      puts "  WARN: create_bar_from_building_type_ratios failed for #{bldg_type}"
      return nil
    end

    # --- Step 2: weather / location ---
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # --- Step 3: create typical (no HVAC – schedules only) ---
    sizing_dir = File.join(base_output_dir, "#{bldg_type}_#{schedule_method}_sizing")
    FileUtils.mkdir_p sizing_dir unless Dir.exist? sizing_dir

    begin
      @create.create_typical_building_from_model(
        model, template,
        climate_zone: climate_zone,
        schedule_method: schedule_method,
        add_hvac: false,
        add_elevators: false,
        sizing_run_directory: sizing_dir
      )
    rescue StandardError => e
      puts "  ERROR: create_typical_building_from_model failed for #{bldg_type}/#{schedule_method}: #{e.message}"
      return nil
    end

    model
  end

  # ---------------------------------------------------------------------------
  # Schedule-extraction helpers
  # ---------------------------------------------------------------------------

  # Extracts every ScheduleRuleset associated with space-type loads and
  # thermostats in the model.
  #
  # @param model     [OpenStudio::Model::Model]
  # @param bldg_type [String] used only as a label fallback
  # @return [Hash] { space_type_label => { schedule_label => { day_type => [24 values] } } }
  def extract_schedule_data(model, bldg_type)
    data = {}

    # --- space-type schedules ---
    model.getSpaceTypes.each do |space_type|
      st_name = space_type.name.get
      # Use standardsBuildingType + standardsSpaceType when available
      std_bt = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : bldg_type
      std_st = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : st_name
      label = "#{std_bt} | #{std_st}"

      data[label] ||= {}

      # helper to register one ScheduleRuleset
      register = lambda do |schedule, load_label|
        next if schedule.nil? || !schedule.to_ScheduleRuleset.is_initialized

        rs = schedule.to_ScheduleRuleset.get
        sch_label = "#{load_label}: #{rs.name.get}"
        data[label][sch_label] = ruleset_day_profiles(rs)
      end

      # People
      space_type.people.each do |load|
        register.call(load.numberofPeopleSchedule.is_initialized ? load.numberofPeopleSchedule.get : nil, 'People - Occ')
        register.call(load.activityLevelSchedule.is_initialized ? load.activityLevelSchedule.get : nil, 'People - Activity')
      end

      # Lights
      space_type.lights.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'Lights')
      end

      # Luminaires
      space_type.luminaires.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'Luminaire')
      end

      # ElectricEquipment
      space_type.electricEquipment.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'ElecEquip')
      end

      # GasEquipment
      space_type.gasEquipment.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'GasEquip')
      end

      # OtherEquipment
      space_type.otherEquipment.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'OtherEquip')
      end

      # Infiltration
      space_type.spaceInfiltrationDesignFlowRates.each do |load|
        register.call(load.schedule.is_initialized ? load.schedule.get : nil, 'Infiltration')
      end
    end

    # --- thermostat schedules (one entry per unique thermostat) ---
    seen_tstats = []
    model.getThermalZones.each do |zone|
      tstat = zone.thermostatSetpointDualSetpoint
      next if tstat.empty?

      tstat = tstat.get
      next if seen_tstats.include?(tstat.handle.to_s)

      seen_tstats << tstat.handle.to_s

      # find an associated space type name via the zone's spaces
      zone_label = zone.name.get
      st_label = "Thermostat | #{zone_label}"
      data[st_label] ||= {}

      if tstat.coolingSetpointTemperatureSchedule.is_initialized
        sch = tstat.coolingSetpointTemperatureSchedule.get
        if sch.to_ScheduleRuleset.is_initialized
          rs = sch.to_ScheduleRuleset.get
          data[st_label]["Cooling: #{rs.name.get}"] = ruleset_day_profiles(rs)
        end
      end

      if tstat.heatingSetpointTemperatureSchedule.is_initialized
        sch = tstat.heatingSetpointTemperatureSchedule.get
        if sch.to_ScheduleRuleset.is_initialized
          rs = sch.to_ScheduleRuleset.get
          data[st_label]["Heating: #{rs.name.get}"] = ruleset_day_profiles(rs)
        end
      end
    end

    data
  end

  # Returns a hash of day-type label => 24-element array of hourly averages
  # for every unique profile in the ScheduleRuleset.
  #
  # @param rs [OpenStudio::Model::ScheduleRuleset]
  # @return [Hash<String, Array<Float>>]
  def ruleset_day_profiles(rs)
    profiles = {}

    # Default day
    vals = @sch.schedule_day_get_hourly_values(rs.defaultDaySchedule)
    profiles['Default'] = vals if vals && vals.size == 24

    # Rule-based day schedules
    rs.scheduleRules.each do |rule|
      day_sch = rule.daySchedule

      # build a label from the applicable days
      days = []
      days << 'Mon' if rule.applyMonday
      days << 'Tue' if rule.applyTuesday
      days << 'Wed' if rule.applyWednesday
      days << 'Thu' if rule.applyThursday
      days << 'Fri' if rule.applyFriday
      days << 'Sat' if rule.applySaturday
      days << 'Sun' if rule.applySunday
      day_label = days.empty? ? day_sch.name.get : days.join('/')

      # collect weekday / weekend shorthand labels
      if rule.applyWeekdays && rule.applyWeekends
        day_label = 'All Days'
      elsif rule.applyWeekdays
        day_label = 'Weekday'
      elsif rule.applyWeekends
        day_label = 'Weekend'
      end

      vals = @sch.schedule_day_get_hourly_values(day_sch)
      profiles[day_label] = vals if vals && vals.size == 24
    end

    profiles
  end

  # ---------------------------------------------------------------------------
  # HTML / Chart.js report generator
  # ---------------------------------------------------------------------------

  # Writes a self-contained HTML file that displays side-by-side Chart.js line
  # charts comparing prototype vs. parametric schedules for every building type
  # and space type.
  #
  # @param all_data [Hash] nested hash from #extract_schedule_data
  # @param path     [String] output file path
  def write_html_report(all_data, path)
    # Colour palette for day-type lines
    day_colors = {
      'Default'  => '#2196F3',
      'Weekday'  => '#4CAF50',
      'Weekend'  => '#FF9800',
      'All Days' => '#9C27B0',
      'Mon'      => '#00BCD4',
      'Tue'      => '#009688',
      'Wed'      => '#8BC34A',
      'Thu'      => '#CDDC39',
      'Fri'      => '#FFC107',
      'Sat'      => '#FF5722',
      'Sun'      => '#795548'
    }
    default_color = '#607D8B'

    # Build collection of unique (bldg_type, space_type, schedule) combinations
    # We key on (space_type, schedule_base_label) to pair prototype vs parametric
    hour_labels = Array.new(24) { |i| "#{i}:00" }.to_json

    html = []
    html << '<!DOCTYPE html>'
    html << '<html lang="en">'
    html << '<head>'
    html << '  <meta charset="UTF-8">'
    html << '  <meta name="viewport" content="width=device-width, initial-scale=1.0">'
    html << '  <title>Schedule Comparison: Prototype vs Parametric</title>'
    html << '  <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>'
    html << '  <style>'
    html << '    body { font-family: Arial, sans-serif; margin: 0; padding: 16px; background: #f5f5f5; color: #333; }'
    html << '    h1 { margin-bottom: 4px; }'
    html << '    h2 { color: #1565C0; margin-top: 32px; margin-bottom: 4px; border-bottom: 2px solid #1565C0; padding-bottom: 4px; }'
    html << '    h3 { color: #555; font-size: 0.95em; margin: 16px 0 4px 0; }'
    html << '    .bldg-section { margin-bottom: 40px; }'
    html << '    .space-type-section { margin-left: 12px; }'
    html << '    .chart-grid { display: flex; flex-wrap: wrap; gap: 16px; }'
    html << '    .chart-card { background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 12px;'
    html << '                  box-shadow: 0 1px 3px rgba(0,0,0,0.1); width: 480px; }'
    html << '    .chart-title { font-size: 0.85em; font-weight: bold; margin-bottom: 8px; color: #444;'
    html << '                   word-break: break-all; }'
    html << '    .method-label { display: inline-block; padding: 2px 8px; border-radius: 3px;'
    html << '                    font-size: 0.75em; font-weight: bold; margin-bottom: 4px; }'
    html << '    .method-prototype  { background: #E3F2FD; color: #0D47A1; }'
    html << '    .method-parametric { background: #E8F5E9; color: #1B5E20; }'
    html << '    canvas { max-width: 100%; }'
    html << '    .toc { background:#fff; border:1px solid #ddd; border-radius:6px; padding:12px 20px; display:inline-block; margin-bottom:24px; }'
    html << '    .toc a { color:#1565C0; text-decoration:none; display:block; margin:3px 0; font-size:0.9em; }'
    html << '    .toc a:hover { text-decoration:underline; }'
    html << '  </style>'
    html << '</head>'
    html << '<body>'
    html << '  <h1>Schedule Comparison: Prototype vs Parametric</h1>'
    html << "  <p>Template: <strong>ComStock 90.1-2013</strong> &nbsp;|&nbsp; Climate Zone: <strong>ASHRAE 169-2013-4A</strong></p>"
    html << "  <p>Generated: <strong>#{Time.now.strftime('%Y-%m-%d %H:%M')}</strong></p>"

    # Table of contents
    html << '  <div class="toc"><strong>Building Types</strong>'
    all_data.each_key do |bldg_type|
      html << "    <a href=\"#bldg-#{bldg_type.gsub(/\s+/, '-')}\">#{bldg_type}</a>"
    end
    html << '  </div>'

    chart_id = 0

    all_data.each do |bldg_type, method_data|
      anchor = "bldg-#{bldg_type.gsub(/\s+/, '-')}"
      html << "  <div class=\"bldg-section\" id=\"#{anchor}\">"
      html << "    <h2>#{bldg_type}</h2>"

      proto_data = method_data['prototype'] || {}
      param_data = method_data['parametric'] || {}

      # Collect all space-type labels present in either method
      all_space_types = (proto_data.keys + param_data.keys).uniq.sort

      if all_space_types.empty?
        html << '    <p><em>No schedule data collected for this building type.</em></p>'
        html << '  </div>'
        next
      end

      all_space_types.each do |st_label|
        proto_scheds = proto_data[st_label] || {}
        param_scheds = param_data[st_label] || {}

        # Group schedules from each method by load-type prefix (the part before
        # the first ':' in the schedule key, e.g. "Lights", "ElecEquip").
        # This ensures prototype and parametric profiles land on the same chart.
        load_type_groups = {}

        proto_scheds.each do |sch_key, profiles|
          load_type = sch_key.split(':').first.strip
          load_type_groups[load_type] ||= { 'prototype' => {}, 'parametric' => {} }
          # If multiple schedule objects share a load type, disambiguate day labels
          existing = load_type_groups[load_type]['prototype']
          profiles.each do |day_type, vals|
            key = existing.key?(day_type) ? "#{day_type} (#{sch_key.split(':').last.strip})" : day_type
            existing[key] = vals
          end
        end

        param_scheds.each do |sch_key, profiles|
          load_type = sch_key.split(':').first.strip
          load_type_groups[load_type] ||= { 'prototype' => {}, 'parametric' => {} }
          existing = load_type_groups[load_type]['parametric']
          profiles.each do |day_type, vals|
            key = existing.key?(day_type) ? "#{day_type} (#{sch_key.split(':').last.strip})" : day_type
            existing[key] = vals
          end
        end

        next if load_type_groups.empty?

        html << "    <div class=\"space-type-section\">"
        html << "      <h3>Space Type / Zone: #{html_escape(st_label)}</h3>"
        html << "      <div class=\"chart-grid\">"

        load_type_groups.sort.each do |load_type, method_profiles|
          chart_id += 1
          canvas_id = "chart_#{chart_id}"

          proto_profiles = method_profiles['prototype']
          param_profiles = method_profiles['parametric']

          # Union of all day-type labels across both methods
          all_day_types = (proto_profiles.keys + param_profiles.keys).uniq

          datasets = []

          # Prototype datasets – solid lines
          all_day_types.each do |day_type|
            vals = proto_profiles[day_type]
            next if vals.nil?

            color = day_colors.fetch(day_type.split(' ').first, default_color)
            datasets << {
              label: "Proto - #{day_type}",
              data: vals,
              borderColor: color,
              backgroundColor: 'transparent',
              borderWidth: 2,
              borderDash: [],
              pointRadius: 0,
              tension: 0.3
            }
          end

          # Parametric datasets – dashed lines, same colours as prototype
          all_day_types.each do |day_type|
            vals = param_profiles[day_type]
            next if vals.nil?

            color = day_colors.fetch(day_type.split(' ').first, default_color)
            datasets << {
              label: "Param - #{day_type}",
              data: vals,
              borderColor: color,
              backgroundColor: 'transparent',
              borderWidth: 2,
              borderDash: [6, 3],
              pointRadius: 0,
              tension: 0.3
            }
          end

          next if datasets.empty?

          datasets_json = datasets.map do |ds|
            %Q({
              label: #{ds[:label].to_json},
              data: #{ds[:data].to_json},
              borderColor: #{ds[:borderColor].to_json},
              backgroundColor: #{ds[:backgroundColor].to_json},
              borderWidth: #{ds[:borderWidth]},
              borderDash: #{ds[:borderDash].to_json},
              pointRadius: #{ds[:pointRadius]},
              tension: #{ds[:tension]}
            })
          end.join(",\n")

          html << "        <div class=\"chart-card\">"
          html << "          <div class=\"chart-title\">"
          html << "            #{html_escape(load_type)}"
          html << "            &nbsp;<span class=\"method-label method-prototype\">— Prototype</span>"
          html << "            <span class=\"method-label method-parametric\">- - Parametric</span>"
          html << "          </div>"
          html << "          <canvas id=\"#{canvas_id}\" height=\"180\"></canvas>"
          html << "          <script>"
          html << "            (function() {"
          html << "              var ctx = document.getElementById(#{canvas_id.to_json}).getContext('2d');"
          html << "              new Chart(ctx, {"
          html << "                type: 'line',"
          html << "                data: {"
          html << "                  labels: #{hour_labels},"
          html << "                  datasets: [#{datasets_json}]"
          html << "                },"
          html << "                options: {"
          html << "                  animation: false,"
          html << "                  plugins: {"
          html << "                    legend: { display: true, position: 'bottom', labels: { boxWidth: 12, font: { size: 10 } } },"
          html << "                    tooltip: { mode: 'index', intersect: false }"
          html << "                  },"
          html << "                  scales: {"
          html << "                    x: { ticks: { font: { size: 9 }, maxTicksLimit: 12 } },"
          html << "                    y: { ticks: { font: { size: 9 } }, beginAtZero: true }"
          html << "                  }"
          html << "                }"
          html << "              });"
          html << "            })();"
          html << "          </script>"
          html << "        </div>"
        end

        html << "      </div>" # .chart-grid
        html << "    </div>" # .space-type-section
      end

      html << '  </div>' # .bldg-section
    end

    html << '</body>'
    html << '</html>'

    File.write(path, html.join("\n"))
  end

  # ---------------------------------------------------------------------------
  # Utility
  # ---------------------------------------------------------------------------

  # Escapes HTML special characters in a string.
  def html_escape(str)
    str.to_s
       .gsub('&', '&amp;')
       .gsub('<', '&lt;')
       .gsub('>', '&gt;')
       .gsub('"', '&quot;')
  end
end
