require 'fileutils'

# BTAPResultsHelper
#   Helper methods for the BtapResults suite of tests.
class BTAPResultsHelper
  @@cached = !(ENV["RERUN_CACHED"] == "true")
  puts "BTAP Results caching #{@@cached ? "enabled" : "disabled"}."
  attr_reader :model_cached_path
  attr_reader :sql_cached_path

  def initialize(test_path)
    cached_folder      = "#{__dir__}/cache/#{File.basename(test_path, '.rb')}"
    @model_cached_path = cached_folder + "/output.osm"
    @sql_cached_path   = cached_folder + "/eplusout.sql"
  end

  def cache_osm_and_sql(model_path:, sql_path:)
    FileUtils.cp(model_path, model_cached_path)
    FileUtils.cp(sql_path, sql_cached_path)
  end

  def get_analysis(output_folder:, template:)
    return BTAPNoSimAnalysis.new(
      model_path:    @model_cached_path, 
      sql_file_path: @sql_cached_path,
      output_folder: output_folder,
      template:      template,
      datapoint_id:  'test_run')
  end

  class << self
    def cached
      return @@cached
    end
  end
end
