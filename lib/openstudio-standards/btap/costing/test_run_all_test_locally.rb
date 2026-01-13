require 'fileutils'
require 'parallel'
require 'open3'
require 'minitest/autorun'
require 'json'
require_relative './parallel_tests'
require_relative './btap_results/tests/BtapResults_test_helper' # Required for the cached switch

# NOTE: Runs are cached automatically. To run this test with an annual
# simulation and update the cache, pass the RERUN_CACHED=true environment
# variable pair to the test file, for example:
# RERUN_CACHED=true bundle exec ruby [test_file]
class RunAllTests < Minitest::Test
  def test_all()
    full_file_list = nil
    test_list_file = File.expand_path(File.join(__dir__, 'test_list.txt'))
    root_dir       = File.expand_path("../../../../", __dir__)
    if File.exist?(test_list_file)
      puts test_list_file
      # load test files from file.
      full_file_list = File.readlines(test_list_file).shuffle
      full_file_list.map! {|file| "#{root_dir}/#{file.strip}"}
      # Select only .rb files that exist
      full_file_list.select! {|file| file.include?('rb') && File.exist?(file)}
    else
      puts "Could not find list of files to test at #{test_list_file}"
      return false
    end
    assert(ParallelTests.new.run(full_file_list), "Some tests failed please ensure all test pass and tests have been updated to reflect the changes you expect before issuing a pull request")
  end
end
