require_relative 'necb_helper'
require_relative '../necb/regression_tests/resources/regression_helper'

class CreateNECBPrototypeBuildingTest < NECBRegressionHelper
  def self.create_run_model_tests(headers)
    NecbHelper.test_case_matrix(headers).each do |args|
      building_type        = args.fetch(:building_type)
      template             = args.fetch(:template)
      primary_heating_fuel = args.fetch(:primary_heating_fuel)
      epw_file             = args.fetch(:epw_file, 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw')
      run_simulation       = args.fetch(:run_simulation, false)

      method_name = "test_#{template}_#{building_type}_regression_#{primary_heating_fuel}".gsub(/[^0-9A-Za-z_]/, '_')

      define_method(method_name) do
        result, diff = create_model_and_regression_test(
          building_type:        building_type,
          primary_heating_fuel: primary_heating_fuel,
          epw_file:             epw_file,
          template:             template,
          run_simulation:       run_simulation
        )

        if result == false
          puts "JSON terse listing of diff-errors."
          puts diff
          puts "Pretty listing of diff-errors for readability."
          puts JSON.pretty_generate(diff)
          puts "You can find the saved json diff file here test/necb/regression_tests/expected/#{building_type}-#{template}-#{primary_heating_fuel}_diffs.json"
          puts 'outputing errors here. '
          puts diff['diffs-errors']
        end

        assert(result, diff)
      end
    end
  end
end
