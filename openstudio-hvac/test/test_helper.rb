require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/openstudio_hvac'

module FixtureHelper
  FIXTURE = File.expand_path('fixtures/5ZoneNoHVAC.osm', __dir__)
  EPW = File.expand_path('fixtures/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw', __dir__)
  DDY = File.expand_path('fixtures/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.ddy', __dir__)

  # A 5-zone model with thermostats and NO standardsSpaceType tags and NO HVAC —
  # proving the gem needs neither standards metadata nor pre-existing systems.
  def load_fixture
    OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  end

  # ---- E2E simulation support (pure SDK + openstudio CLI; the README recipe) ----

  def openstudio_cli?
    @openstudio_cli = system('openstudio openstudio_version > /dev/null 2>&1') if @openstudio_cli.nil?
    @openstudio_cli
  end

  def attach_weather!(model)
    epw = OpenStudio::EpwFile.new(OpenStudio::Path.new(EPW))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw)
    ddy = OpenStudio::EnergyPlus.loadAndTranslateIdf(DDY).get
    ddy.getDesignDays.each { |dd| model.addObject(dd.clone) }
    model
  end

  # Run E+ via the CLI. sizing_only: design-day sizing run; otherwise a short
  # weather-period run (first week of January) to exercise runtime controls.
  # @return [String] the run directory
  def run_energyplus!(model, dir, sizing_only: true)
    FileUtils.mkdir_p(dir)
    sim = model.getSimulationControl
    sim.setDoZoneSizingCalculation(true)
    sim.setDoSystemSizingCalculation(true)
    sim.setDoPlantSizingCalculation(true)
    sim.setRunSimulationforSizingPeriods(true)
    sim.setRunSimulationforWeatherFileRunPeriods(!sizing_only)
    unless sizing_only
      run_period = model.getRunPeriod
      run_period.setBeginMonth(1)
      run_period.setBeginDayOfMonth(1)
      run_period.setEndMonth(1)
      run_period.setEndDayOfMonth(7)
    end
    model.save("#{dir}/in.osm", true)
    osw = OpenStudio::WorkflowJSON.new
    osw.setSeedFile("#{dir}/in.osm")
    osw.saveAs("#{dir}/in.osw")
    ok = system("openstudio run -w #{dir}/in.osw > #{dir}/cli.log 2>&1")
    err = File.exist?("#{dir}/run/eplusout.err") ? File.read("#{dir}/run/eplusout.err") : '(no eplusout.err)'
    raise("E+ run failed in #{dir}:\n#{err[/^.*Fatal.*$/] || err[-800..] || err}") unless ok

    model.setSqlFile(OpenStudio::SqlFile.new(OpenStudio::Path.new("#{dir}/run/eplusout.sql")))
    "#{dir}/run"
  end

  # A clean run: completed, no Fatal, no Severe errors.
  def assert_clean_energyplus_run(run_dir, context)
    err = File.read("#{run_dir}/eplusout.err")
    refute_match(/\*\*\s*Fatal\s*\*\*/, err, "#{context}: E+ fatal error")
    severe = err.scan(/\*\* Severe  \*\*(.*)$/).flatten
    assert_empty severe, "#{context}: E+ severe errors:\n#{severe.join("\n")}"
    assert_match(/EnergyPlus Completed Successfully/, err, "#{context}: E+ did not complete")
  end

  # Facility 'Time Setpoint Not Met During Occupied' hours from the run's SQL.
  # @return [Hash] { heating: Float, cooling: Float }
  def unmet_occupied_hours(sql)
    query = lambda do |column|
      value = sql.execAndReturnFirstDouble(
        "SELECT Value FROM TabularDataWithStrings WHERE ReportName='SystemSummary' " \
        "AND TableName='Time Setpoint Not Met' AND RowName='Facility' AND ColumnName='#{column}'"
      )
      value.is_initialized ? value.get : nil
    end
    { heating: query.call('During Occupied Heating'), cooling: query.call('During Occupied Cooling') }
  end

  # The comfort gate: the generated system must actually CONDITION the zones, not just
  # simulate cleanly. Thresholds are for the simulated period (a broken system shows up
  # as ~every occupied hour unmet, not a handful).
  def assert_zones_conditioned(sql, context, max_heating_hours:, max_cooling_hours:)
    unmet = unmet_occupied_hours(sql)
    refute_nil unmet[:heating], "#{context}: no unmet-hours data in SQL"
    assert_operator unmet[:heating], :<=, max_heating_hours,
                    "#{context}: #{unmet[:heating]} occupied heating hours unmet (limit #{max_heating_hours}) — system not conditioning"
    assert_operator unmet[:cooling], :<=, max_cooling_hours,
                    "#{context}: #{unmet[:cooling]} occupied cooling hours unmet (limit #{max_cooling_hours})"
  end
end
