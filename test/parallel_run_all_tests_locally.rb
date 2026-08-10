require_relative './helpers/parallel_tests'
TestListFile = File.join(File.dirname(__FILE__), 'ci_tests.txt')

class RunAllTests < Minitest::Test
  def test_all()
    full_file_list = nil
    if File.exist?(TestListFile)
      # load test files from file.
      full_file_list = File.readlines(TestListFile).shuffle
      # Select only .rb files that exist
      full_file_list.select! {|item| item.include?('rb')  && File.exist?(File.absolute_path(File.join(File.dirname(__FILE__),"#{item.strip}")))}
      full_file_list = full_file_list.map! {|item| File.absolute_path(File.join(File.dirname(__FILE__),"#{item.strip}")) }
    else
      puts "Could not find list of files to test at #{TestListFile}"
      return false
    end
    cpus = ENV.key?( "CPUS" )? ENV['CPUS'].to_i : nil

    assert(ParallelTestHelper.new.run( full_file_list,"#{__dir__}/output",cpus),
                                  "Some tests failed please ensure all test pass and tests have been updated to reflect the changes you expect before issuing a pull request")
  end
end
