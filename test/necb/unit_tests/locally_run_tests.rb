require_relative '../../helpers/parallel_tests'
TestListFile = Dir.entries(File.join(__dir__, 'tests'))
RelativeOutputFolder = File.join(__dir__, '../../output')

class RunNECBTests < Minitest::Test
  def test_all()
    full_file_list = nil
    # load test files from file.
    full_file_list = TestListFile
    # Select only .rb files that exist
    full_file_list.select! {|item| item.end_with?(".rb") and File.exist?(File.absolute_path(File.join(__dir__, 'tests', "#{item.strip}")))}
    full_file_list = full_file_list.map! {|item| File.absolute_path(File.join(__dir__, 'tests', "#{item.strip}"))}
    puts "Starting Unit Tests"
    start_time = Time.now.to_i
    assert(ParallelTests.new.run(full_file_list, RelativeOutputFolder), "Some tests failed please ensure all test pass and tests have been updated to reflect the changes you expect before issuing a pull request")
    duration = Time.now.to_i - start_time
    puts "Running time: #{duration}s"
  end
end