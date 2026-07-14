require_relative 'test_helper'

# Proves the execution abstraction / local-vs-cloud seam WITHOUT EnergyPlus:
# the runner prepares the dir, then delegates to an injected backend.
class TestBackends < Minitest::Test
  include FixtureHelper

  Runner = OpenStudioSimulation::Runner
  Backend = OpenStudioSimulation::Backend
  Local = OpenStudioSimulation::Local
  Remote = OpenStudioSimulation::Remote

  # A test backend: asserts the runner prepared the dir, records the call, and
  # lands the two artifacts the contract requires (canned, no E+).
  class FakeBackend < Backend
    attr_reader :called_with

    def initialize(test)
      super()
      @test = test
      @called_with = nil
    end

    def execute(dir)
      # Contract precondition: the runner must have written in.osm + in.osw
      # BEFORE handing the dir to the backend.
      @test.assert File.exist?("#{dir}/in.osm"), 'backend called before in.osm written'
      @test.assert File.exist?("#{dir}/in.osw"), 'backend called before in.osw written'
      @called_with = dir
      FileUtils.mkdir_p("#{dir}/run")
      File.write("#{dir}/run/eplusout.err", "EnergyPlus Completed Successfully\n")
      File.write("#{dir}/run/eplusout.sql", '') # placeholder — no results parsed here
      nil
    end
  end

  def run_dir(name)
    File.join('/tmp/claude-1000/-workspaces-openstudio-standards/14d4ffe0-7e76-41d2-9609-bba51763b608/scratchpad',
              'sim_backends', name)
  end

  def setup
    FileUtils.rm_rf(run_dir(''))
  end

  # Dependency injection: a custom backend is invoked, and only after the runner
  # has written in.osm + in.osw into the prepared dir.
  def test_custom_backend_is_invoked_with_prepared_dir
    model = load_fixture
    dir = run_dir('custom')
    fake = FakeBackend.new(self)

    result = Runner.run_energyplus!(model, dir, sizing_only: true, backend: fake)

    assert_equal dir, fake.called_with, 'backend.execute was not called with the run dir'
    assert File.exist?("#{dir}/in.osm"), 'runner did not write in.osm'
    assert File.exist?("#{dir}/in.osw"), 'runner did not write in.osw'
    assert_equal "#{dir}/run", result
    assert Runner.clean_run?(result), 'clean_run? should read the canned err'
  end

  # The facade uses the injected backend too, and returns a Result.
  def test_facade_uses_injected_backend
    model = load_fixture
    dir = run_dir('facade')
    fake = FakeBackend.new(self)

    result = OpenStudioSimulation.run(model, run_dir: dir, sizing_only: true, backend: fake)

    assert_equal dir, fake.called_with
    assert_instance_of OpenStudioSimulation::Result, result
    assert result.clean?
    assert_nil result.energy, 'sizing_only run has no energy results'
    assert_nil result.unmet_hours, 'sizing_only run has no unmet hours'
  end

  # Local is the DEFAULT backend when none is injected. Stub Local#execute to
  # observe it without needing the CLI.
  def test_local_is_the_default_backend
    model = load_fixture
    dir = run_dir('default')
    called = false
    test = self

    Local.class_eval do
      alias_method :__orig_execute, :execute
      define_method(:execute) do |d|
        called = true
        test.assert File.exist?("#{d}/in.osw"), 'default backend called before in.osw written'
        FileUtils.mkdir_p("#{d}/run")
        File.write("#{d}/run/eplusout.err", "EnergyPlus Completed Successfully\n")
        File.write("#{d}/run/eplusout.sql", '')
        nil
      end
    end
    begin
      Runner.run_energyplus!(model, dir, sizing_only: true) # no backend: arg
    ensure
      Local.class_eval do
        alias_method :execute, :__orig_execute
        remove_method :__orig_execute
      end
    end

    assert called, 'default backend was not an OpenStudioSimulation::Local instance'
  end

  # The abstraction's base class documents the interface by raising.
  def test_backend_base_execute_raises_not_implemented
    err = assert_raises(NotImplementedError) { Backend.new.execute('/nope') }
    assert_match(/execute/, err.message)
  end

  # Remote is a documented stub — it raises with the contract to implement.
  def test_remote_execute_raises_with_contract
    remote = Remote.new(endpoint: 'https://example.test', api_key: 'k')
    err = assert_raises(NotImplementedError) { remote.execute('/nope') }
    assert_match(/documented stub/i, err.message)
    assert_match(/UPLOAD/,   err.message)
    assert_match(/DOWNLOAD/, err.message)
    assert_match(/eplusout\.sql/, err.message)
  end

  # Sanity: Local and Remote really are Backends (the seam is polymorphic).
  def test_backends_share_the_interface
    assert Local.new.is_a?(Backend)
    assert Remote.new.is_a?(Backend)
    assert_respond_to Local.new, :execute
    assert_respond_to Remote.new, :execute
  end
end
