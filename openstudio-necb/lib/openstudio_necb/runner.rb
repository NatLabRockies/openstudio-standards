require 'fileutils'

module OpenStudioNECB
  # Simulation execution — the SDK+CLI recipe (pure `openstudio` gem + the
  # `openstudio` CLI; no measures, no openstudio-standards). Promoted to library
  # code from the recipe proven in the domain gems' E2E suites and READMEs.
  module Runner
    module_function

    def openstudio_cli?
      @openstudio_cli = system('openstudio openstudio_version > /dev/null 2>&1') if @openstudio_cli.nil?
      @openstudio_cli
    end

    # Attach an EPW + its design days (required before any sizing run).
    def attach_weather!(model, epw:, ddy:)
      epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw))
      OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
      workspace = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy)
      raise(ArgumentError, "could not parse design days from #{ddy}") if workspace.empty?

      workspace.get.getDesignDays.each { |dd| model.addObject(dd.clone) }
      model
    end

    # Run EnergyPlus via the CLI and attach the result SQL to the model.
    #
    # @param sizing_only [Boolean] design-day sizing run only
    # @param run_period [Hash, nil] { begin_month:, begin_day:, end_month:, end_day: }
    #   override for the weather run (tests use one week; code compliance is annual)
    # @return [String] the run directory (contains eplusout.err / eplusout.sql)
    def run_energyplus!(model, dir, sizing_only: false, run_period: nil)
      raise('openstudio CLI not available on PATH') unless openstudio_cli?

      FileUtils.mkdir_p(dir)
      sim = model.getSimulationControl
      sim.setDoZoneSizingCalculation(true)
      sim.setDoSystemSizingCalculation(true)
      sim.setDoPlantSizingCalculation(true)
      sim.setRunSimulationforSizingPeriods(true)
      sim.setRunSimulationforWeatherFileRunPeriods(!sizing_only)
      if !sizing_only && run_period
        rp = model.getRunPeriod
        rp.setBeginMonth(run_period[:begin_month])
        rp.setBeginDayOfMonth(run_period[:begin_day])
        rp.setEndMonth(run_period[:end_month])
        rp.setEndDayOfMonth(run_period[:end_day])
      end
      model.save("#{dir}/in.osm", true)
      osw = OpenStudio::WorkflowJSON.new
      osw.setSeedFile("#{dir}/in.osm")
      osw.saveAs("#{dir}/in.osw")
      ok = system("openstudio run -w #{dir}/in.osw > #{dir}/cli.log 2>&1")
      err_path = "#{dir}/run/eplusout.err"
      err = File.exist?(err_path) ? File.read(err_path) : '(no eplusout.err)'
      raise("EnergyPlus run failed in #{dir}:\n#{err[/^.*Fatal.*$/] || err[-800..] || err}") unless ok

      model.setSqlFile(OpenStudio::SqlFile.new(OpenStudio::Path.new("#{dir}/run/eplusout.sql")))
      "#{dir}/run"
    end

    # @return [Boolean] completed with no Fatal and no Severe errors
    def clean_run?(run_dir)
      err = File.read("#{run_dir}/eplusout.err")
      err.include?('EnergyPlus Completed Successfully') &&
        !err.match?(/\*\*\s*Fatal\s*\*\*/) && !err.match?(/\*\* Severe  \*\*/)
    end

    # Annual (or run-period) site energy results from an attached SQL.
    # @return [Hash] kWh totals + end-use breakdown + floor area
    def energy_results(model)
      sql = model.sqlFile
      raise('no SQL attached — run run_energyplus! first') if sql.empty?

      sql = sql.get
      gj_to_kwh = 277.777778
      total_gj = optional(sql.totalSiteEnergy)
      results = {
        'total_site_kwh' => total_gj ? (total_gj * gj_to_kwh).round(1) : nil,
        'electricity_kwh' => scaled(sql.electricityTotalEndUses, gj_to_kwh),
        'natural_gas_kwh' => scaled(sql.naturalGasTotalEndUses, gj_to_kwh),
        'district_heating_kwh' => district(sql, %i[districtHeatingTotalEndUses districtHeatingWaterTotalEndUses], gj_to_kwh),
        'district_cooling_kwh' => district(sql, %i[districtCoolingTotalEndUses], gj_to_kwh),
        'end_uses_kwh' => {
          'heating' => end_use(sql, 'Heating', gj_to_kwh),
          'cooling' => end_use(sql, 'Cooling', gj_to_kwh),
          'fans' => end_use(sql, 'Fans', gj_to_kwh),
          'pumps' => end_use(sql, 'Pumps', gj_to_kwh),
          'interior_lighting' => end_use(sql, 'InteriorLighting', gj_to_kwh),
          'interior_equipment' => end_use(sql, 'InteriorEquipment', gj_to_kwh),
          'water_systems' => end_use(sql, 'WaterSystems', gj_to_kwh)
        }
      }
      area = model.getBuilding.floorArea
      results['floor_area_m2'] = area.round(1)
      results['eui_kwh_per_m2'] = (results['total_site_kwh'] / area).round(1) if results['total_site_kwh'] && area.positive?
      results
    end

    # Facility 'Time Setpoint Not Met During Occupied' hours (SystemSummary).
    # @return [Hash] { 'heating' => Float|nil, 'cooling' => Float|nil }
    def unmet_occupied_hours(model)
      sql = model.sqlFile
      return { 'heating' => nil, 'cooling' => nil } if sql.empty?

      sql = sql.get
      query = lambda do |column|
        value = sql.execAndReturnFirstDouble(
          "SELECT Value FROM TabularDataWithStrings WHERE ReportName='SystemSummary' " \
          "AND TableName='Time Setpoint Not Met' AND RowName='Facility' AND ColumnName='#{column}'"
        )
        value.is_initialized ? value.get : nil
      end
      { 'heating' => query.call('During Occupied Heating'),
        'cooling' => query.call('During Occupied Cooling') }
    end

    def optional(value)
      value.is_initialized ? value.get : nil
    end

    def scaled(value, factor)
      v = optional(value)
      v.nil? ? nil : (v * factor).round(1)
    end

    # District end-use SqlFile accessors were renamed across OpenStudio versions.
    def district(sql, method_names, factor)
      name = method_names.find { |m| sql.respond_to?(m) }
      name ? scaled(sql.public_send(name), factor) : nil
    end

    # SqlFile end-use accessors are per-fuel (electricityHeating, naturalGasHeating,
    # ...) — sum the category across every fuel from the tabular End Uses table.
    def end_use(sql, category, factor)
      value = sql.execAndReturnFirstDouble(
        "SELECT SUM(Value) FROM TabularDataWithStrings " \
        "WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND TableName='End Uses' " \
        "AND RowName='#{end_use_row(category)}' AND Units='GJ'"
      )
      value.is_initialized ? (value.get * factor).round(1) : nil
    end

    def end_use_row(category)
      { 'Heating' => 'Heating', 'Cooling' => 'Cooling', 'Fans' => 'Fans', 'Pumps' => 'Pumps',
        'InteriorLighting' => 'Interior Lighting', 'InteriorEquipment' => 'Interior Equipment',
        'WaterSystems' => 'Water Systems' }.fetch(category)
    end
  end
end
