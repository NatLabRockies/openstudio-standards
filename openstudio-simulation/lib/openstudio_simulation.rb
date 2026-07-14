require 'openstudio'

require_relative 'openstudio_simulation/version'
require_relative 'openstudio_simulation/backends'
require_relative 'openstudio_simulation/runner'

# OpenStudioSimulation is the LOWEST-level family gem: run EnergyPlus on an
# OpenStudio model and get results back, WITHOUT any compliance layer. It depends
# on nothing else in the family — only the OpenStudio SDK (and, by default, the
# `openstudio` CLI on PATH for local execution).
#
# Two entry points:
#   * OpenStudioSimulation.run — the low-friction "just run a model" facade.
#   * OpenStudioSimulation::Runner — the granular steps (attach_weather!,
#     run_energyplus!, clean_run?, energy_results, unmet_occupied_hours).
#
# Execution is pluggable via a Backend: Local (the `openstudio` CLI, default) or
# Remote (a documented seam for a remote/AWS EnergyPlus service). See backends.rb.
module OpenStudioSimulation
  # Result of a run. `clean` mirrors Runner.clean_run?; energy/unmet_hours are
  # nil for a sizing-only run (no annual results to parse).
  Result = Struct.new(:run_dir, :clean, :energy, :unmet_hours, keyword_init: true) do
    def clean?
      clean
    end
  end

  # Run a model end to end and return a Result.
  #
  # @param model [OpenStudio::Model::Model]
  # @param run_dir [String] directory to run in (created if needed)
  # @param weather [Hash, nil] { epw:, ddy: } — attached first if given
  # @param sizing_only [Boolean] design-day sizing run only (no annual results)
  # @param run_period [Hash, nil] { begin_month:, begin_day:, end_month:, end_day: }
  # @param backend [Backend] execution backend (Local by default)
  # @return [Result]
  def self.run(model, run_dir:, weather: nil, sizing_only: false, run_period: nil, backend: Local.new)
    Runner.attach_weather!(model, epw: weather[:epw], ddy: weather[:ddy]) if weather
    dir = Runner.run_energyplus!(model, run_dir, sizing_only: sizing_only, run_period: run_period, backend: backend)
    Result.new(
      run_dir: dir,
      clean: Runner.clean_run?(dir),
      energy: sizing_only ? nil : Runner.energy_results(model),
      unmet_hours: sizing_only ? nil : Runner.unmet_occupied_hours(model)
    )
  end
end
