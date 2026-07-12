require 'minitest/autorun'
require 'fileutils'
require 'json'
require_relative '../lib/openstudio_loads'

module FixtureHelper
  # Fixtures shared with the sibling gems (monorepo incubation).
  HVAC_FIXTURES = File.expand_path('../../openstudio-hvac/test/fixtures', __dir__)
  FIXTURE = File.join(HVAC_FIXTURES, '5ZoneNoHVAC.osm')
  EPW = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  DDY = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.ddy')

  def load_fixture
    OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  end

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

  def assert_clean_energyplus_run(run_dir, context)
    err = File.read("#{run_dir}/eplusout.err")
    refute_match(/\*\*\s*Fatal\s*\*\*/, err, "#{context}: E+ fatal error")
    severe = err.scan(/\*\* Severe  \*\*(.*)$/).flatten
    assert_empty severe, "#{context}: E+ severe errors:\n#{severe.join("\n")}"
    assert_match(/EnergyPlus Completed Successfully/, err, "#{context}: E+ did not complete")
  end
end
