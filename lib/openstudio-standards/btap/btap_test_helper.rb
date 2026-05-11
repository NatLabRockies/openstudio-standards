require 'fileutils'
require 'minitest'

# BTAPResultsHelper
#   Helper methods for the BtapResults suite of tests.
class BTAPResultsHelper < Minitest::Test
  @@cached = false

  def initialize(test_path:, model_name:, run_dir:)
    @test_path             = File.expand_path(test_path) 
    @test_filename         = File.basename(test_path, '.rb')
    @model_name            = model_name
    @run_dir               = File.expand_path(run_dir)
    cached_folder          = ""
    @model_cached_path     = cached_folder + "/output.osm"
    @sql_cached_path       = cached_folder + "/eplusout.sql"
  end

  class << self
    def cached
      return @@cached
    end
  end

  def cache_osm_and_sql(model_path:, sql_path:)
    FileUtils.cp(model_path, @model_cached_path)
    FileUtils.cp(sql_path, @sql_cached_path)
  end

  def get_analysis(output_folder:, template:)
    return BTAPNoSimAnalysis.new(
      model_path:    @model_cached_path, 
      sql_file_path: @sql_cached_path,
      output_folder: output_folder,
      template:      template,
      datapoint_id:  'test_run')
  end

  def evaluate_regression_files(test_instance:, cost_result:)
    cost_result_json_path = "#{@run_dir}/cost_results.json"
    cost_list_json_path   = "#{@run_dir}/btap_items.json"
    test_instance.assert(File.exist?(cost_result_json_path), "Could not find costing json at this path:#{cost_result_json_path}")
    regression_files_folder = "#{File.dirname(@test_path)}/regression_files"
    expected_result_filename = "#{regression_files_folder}/#{@model_name}_expected_result.cost.json"
    test_result_filename = "#{regression_files_folder}/#{@model_name}_test_result.cost.json"

    FileUtils.rm(test_result_filename) if File.exist?(test_result_filename)
    if File.exist?(expected_result_filename)
      unless FileUtils.compare_file(cost_result_json_path, expected_result_filename)
        FileUtils.cp(cost_result_json_path, test_result_filename)
        test_instance.assert(false, "Regression test for #{@model_name} produces differences. Examine expected and test result differences in the #{File.dirname(@test_filename)}/regression_files folder ")
      end
    else
      puts "No expected test file...Generating expected file #{expected_result_filename}. Please verify."
      FileUtils.cp(cost_result_json_path, expected_result_filename)
    end
    puts "Regression test for #{@model_name} passed."

    # Do comparison of direct btap_costing results and those derived from the itemized cost list
    # Check if an itemized cost list file exists.  If it exists, do the comparison.  If not, Ignore the comparison.
    if File.exist?(cost_list_json_path)
      # Get the itemized cost list file.
      cost_list = JSON.parse(File.read(cost_list_json_path))
      # Cost the building based on the itemized cost list.
      cost_list_output = BTAPCosting.new().cost_list_items(btap_items: cost_list)
      # Get the detailed btap_costing result file:
      cost_result = JSON.parse(File.read(cost_result_json_path))
      cost_sum = cost_result['totals']
      # Compare the results and let the user know if there are differences.  Do not fail test if there are.
      puts("")
      puts("Comparing BTAP_Costing results and itemized costing list cost results:")
      puts("Envelope Cost Difference: #{cost_sum['envelope'].to_f - cost_list_output['envelope'].to_f}")
      puts("Lighting Cost Difference: #{cost_sum['lighting'].to_f - cost_list_output['lighting'].to_f}")
      puts("Heating and Cooling Cost Difference: #{cost_sum['heating_and_cooling'].to_f - cost_list_output['heating_and_cooling'].to_f}")
      puts("SHW Cost Difference: #{cost_sum['shw'].to_f - cost_list_output['shw'].to_f}")
      puts("Ventilation Cost Difference: #{cost_sum['ventilation'].to_f - cost_list_output['ventilation'].to_f}")
      cost_sum['renewables'].nil? ? sum_renew = 0.00 : sum_renew = cost_sum['renewables'].to_f
      puts("Renewables Cost Difference: #{sum_renew - cost_list_output['renewables'].to_f}")
      if cost_sum['grand_total'] == cost_list_output['grand_total']
        puts("No difference in costing between BTAP_Costing results and itemized cost list results.")
      else
        puts("Total Cost Difference: #{cost_sum['grand_total'].to_f - cost_list_output['grand_total'].to_f}")
      end
    end
  end
end
