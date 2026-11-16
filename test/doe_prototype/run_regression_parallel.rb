require_relative '../helpers/parallel_tests'

# Runs every dynamically-generated test in test_regression.rb as a separate
# process, in parallel across local CPUs, instead of sequentially in one process.
class RunDOEPrototypeRegressionTests < Minitest::Test
  def test_all
    test_file = File.absolute_path(File.join(__dir__, 'test_regression.rb'))
    cpus = ENV.key?('CPUS') ? ENV['CPUS'].to_i : nil

    assert(ParallelTestHelper.new.run([test_file], "#{__dir__}/output", cpus),
           'Some regression tests failed please ensure all tests pass before issuing a pull request')
  end
end
