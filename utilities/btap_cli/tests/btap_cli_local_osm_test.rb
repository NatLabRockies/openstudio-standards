require_relative '../libs'
class BTAPCLITest < Minitest::Test
  def test_cli_local_osm
    input_folder = File.join(__dir__, '..', 'input')
    input_folder_cache = File.join(__dir__, '..', 'input_cache')
    output_folder = File.join(__dir__, '..', 'output')
    weather_folder = File.join(__dir__, ['..', 'weather'])
    # Make sure temp folder is always clean.
    FileUtils.rm_rf(input_folder)
    FileUtils.rm_rf(input_folder_cache)
    FileUtils.rm_rf(output_folder)
    FileUtils.mkdir_p(input_folder)
    # If there are custom databases for custom costing and/or factors, decide if they should be copied
    # to the input folder or not.
    costs_filename   = 'costs.csv'
    factors_filename = 'local_cost_factors.csv'
    costs_path       = File.join(__dir__, costs_filename)
    factors_path     = File.join(__dir__, factors_filename)

    if File.exist?(costs_path)
      FileUtils.cp(factors_path, File.join(input_folder, costs_filename))
    end

    if File.exist?(factors_path)
      FileUtils.cp(factors_path, File.join(input_folder, factors_filename))
    end
    # Run options and local osm file locations
    FileUtils.cp(File.join(__dir__, 'run_options_local_osm.yml'), File.join(input_folder, 'run_options.yml'))
    FileUtils.cp(File.join(__dir__, 'LocalCompleteModel.osm'), File.join(input_folder, 'LocalCompleteModel.osm'))
    BTAPDatapoint.new(input_folder: input_folder, output_folder: output_folder, weather_folder: weather_folder, input_folder_cache: File.join(__dir__, 'input_cache'))
  end
end
