require_relative 'regression_helper'

=begin

Parametric Regression Helper

Helper functions used to facilitate tests for the parametric test creator

=end

class ParametricRegressionHelper < NECBRegressionHelper
  def setup()
    # Setup variables are inherited from regression_helper.rb
    super
  end

  def create_model_and_regression_test(model_name, model_params)

    self.create_model_from_hash(model_name, model_params)

    result, diff = self.osm_regression(expected_results_folder: @expected_results_folder)
    if run_simulation
      self.run_simulation()
      #self.qaqc_regression()
      end
    return result, diff
  end

  def create_model_from_hash(model_name, model_params)

    @model_name = model_name

    @run_dir = "#{@test_dir}/#{@model_name}"

    # Create a key/value pair for the run directory to include it as an argument
    model_params[:sizing_run_dir] = @run_dir

    #create folders
    if !Dir.exist?(@test_dir)
      Dir.mkdir(@test_dir)
    end
    if !Dir.exist?(@run_dir)
      Dir.mkdir(@run_dir)
    end

    puts "========================model_name =================== #{@model_name}"
    puts "Parameters for the current model:"
    puts
    model_params.each do |key, value|
      puts("#{key.to_s.ljust(30)}: #{value}")
    end
    puts
    @model = Standard.build("#{model_params[:template]}").model_create_prototype_model(**model_params)
    unless @model.instance_of?(OpenStudio::Model::Model)
      puts "Creation of Model for #{@model_name} failed. Please check output for errors."
    end
    return self
  end
end

