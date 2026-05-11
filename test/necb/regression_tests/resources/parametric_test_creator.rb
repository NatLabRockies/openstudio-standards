require_relative '../resources/parametric_regression_helper'

=begin

Parametric Regression Test Creator

This class supports the testing of a combination of models created with a pre-defined set of parameters.

Currently, it supports the creation of models with these parameters:
  *building type
  *epw_file
  *template
  *primary_heating_fuel
  ecm_system_name

The parameters marked with * are minimum requirements for a test to run. These will be defaulted if none are specified.

The remaining ones are optional and are defaulted as specified by the class corresponding to the chosen template.

Although this class should support each parameter outlined in the template files, this restriction is due to how the
naming conventions are currently handled.

=end

class ParametricTestCreator < ParametricRegressionHelper

  # These are the default parameters which will be passed to Standards
  # Stored in singleton lists--this is for the combinations
  # Ideally these would be inherited from regression_helper.rb but those are nested inside function scope
  $params_default =
    {
      building_type:        ['FullServiceRestaurant'],
      epw_file:             ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'],
      template:             ['NECB2011'],
      primary_heating_fuel: ['Electricity']
    }

  $unitary_cop_args =
    [
      {
        unitary_cop_arg:  'NECB_Default',
        untiary_cop_short: 'NECB_Default'
      },
      {
        unitary_cop_arg:  'Carrier WeatherExpert',
        unitary_cop_short: 'unitary_Carrier_WE'
      },
      {
        unitary_cop_arg:  'Lennox Model L Ultra High Efficiency',
        unitary_cop_short: 'unitary_Lennox_HE'
      }
    ]

  $boiler_eff_args =
    [
      {
        boiler_eff_arg: 'NECB_Default',
        boiler_eff_short: 'NECB_Default'
      },
      {
        boiler_eff_arg: 'NECB 85% Efficient Condensing Boiler',
        boiler_eff_short: 'NECB_boiler_85'
      },
      {
        boiler_eff_arg: 'NECB 88% Efficient Condensing Boiler',
        boiler_eff_short: 'NECB_boiler_88'
      },
      {
        boiler_eff_arg: 'NECB 91% Efficient Condensing Boiler',
        boiler_eff_short: 'NECB_boiler_91'
      },
      {
        boiler_eff_arg: 'NECB 94% Efficient Condensing Boiler',
        boiler_eff_short: 'NECB_boiler_94'
      },
      {
        boiler_eff_arg: 'Viessmann Vitocrossal 300 CT3-17 96.2% Efficient Condensing Gas Boiler',
        boiler_eff_short: 'Viessmann_V300_boiler'
      }
    ]

  $furnace_eff_args =
    [
      {
        furnace_eff_arg: 'NECB_Default',
        furnace_eff_short: 'NECB_Default'
      },
      {
        furnace_eff_arg: 'NECB 85% Efficient Condensing Gas Furnace',
        furnace_eff_short: 'NECB_furnace_85'
      },
      {
        furnace_eff_arg: 'NECB 88% Efficient Condensing Gas Furnace',
        furnace_eff_short: 'NECB_furnace_88'
      },
      {
        furnace_eff_arg: 'NECB 91% Efficient Condensing Gas Furnace',
        furnace_eff_short: 'NECB_furnace_91'
      },
      {
        furnace_eff_arg: 'NECB 94% Efficient Condensing Gas Furnace',
        furnace_eff_short: 'NECB_furnace_94'
      }
    ]

  $shw_eff_args =
    [
      {
        shw_eff_arg: 'NECB_Default',
        shw_eff_short: 'NECB_Default'
      },
      {
        shw_eff_arg: 'Natural Gas 85% Efficient SHW',
        shw_eff_short: 'NECB_shw_85'
      },
      {
        shw_eff_arg: 'Natural Gas 88% Efficient SHW',
        shw_eff_short: 'NECB_shw_88'
      },
      {
        shw_eff_arg: 'Natural Gas Direct Vent with Electric Ignition',
        shw_eff_short: 'NECB_shw_91'
      },
      {
        shw_eff_arg: 'Natural Gas Power Vent with Electric Ignition',
        shw_eff_short: 'NECB_shw_94'
      },
      {
        shw_eff_arg: 'Natural Gas Power Vent with Electric Ignition 97% Efficient',
        shw_eff_short: 'NECB_shw_97'
      },
    ]

  # The generation of test methods has to be at the class level so Minitest doesn't skip them before they initialize
  class << self
    def generate_tests(params)

      # Additional parameters provided by this method will be merged into the default ones
      params = $params_default.merge(params)

      # Variable-nested for-loop to create and test each combination of models
      # From https://stackoverflow.com/a/20577981

      pos           = 0                      # Position of the current index
      num_params    = params.length          # Number of attributes
      curr_indicies = [0] * (num_params + 1) # Current index of each list
      max_indicies  = [0] * (num_params + 1) # Max length of each list

      # Set each max index to the correct length
      0.upto num_params - 1 do |i|
        max_indicies[i] = params.values[i].length
      end

      while curr_indicies[num_params] == 0

        # Main control flow
        # This is where the models are created

        # Combination of parameters unique to this iteration
        model_params = {}

        # Gets and stores the parameters
        0.upto num_params - 1 do |i|
          model_params[params.keys[i]] = params.values[i][curr_indicies[i]]
        end

        # Generates the file name to compare the expected result
        model_name = generate_model_name(model_params)
        
        # Create the test method to be run by Minitest
        create_test_method(model_name, model_params)
          
        # Iteration logic
        curr_indicies[0] += 1
        while curr_indicies[pos] == max_indicies[pos]

          curr_indicies[pos] = 0
          pos += 1
          curr_indicies[pos] += 1

          if curr_indicies[pos] != max_indicies[pos]
            pos = 0
          end
        end
      end
    end

    # Metaprogramming method to generate test methods for each combination of parameters
    # Minitest requires each test to be a method starting with "test_"
    def create_test_method(model_name, model_params)

      define_method("test_#{model_name}") do

        result, diff = create_model_and_regression_test(model_name, model_params)
        if result == false
          puts "JSON terse listing of diff-errors."
          puts diff
          puts "Pretty listing of diff-errors for readability."
          puts JSON.pretty_generate( diff )
          puts "You can find the saved json diff file here: #{model_name}_diffs.json"
          puts "outputting errors here. "
          puts diff["diffs-errors"] if result == false
        end
        assert(result, diff)
      end
    end

    # Generates the name of the model from the set of parameters provided
    def generate_model_name(params)
      # TODO Currently, this function only supports these 5 parameters until a different naming convention is proposed.

      building_type        = params[:building_type]
      epw_file             = params[:epw_file]
      template             = params[:template]
      primary_heating_fuel = params[:primary_heating_fuel]
      ecm_system_name      = params[:ecm_system_name]
      unitary_cop          = params[:unitary_cop]
      airloop_economizer_type = params[:airloop_economizer_type]
      boiler_eff = params[:boiler_eff]
      furnace_eff = params[:furnace_eff]
      shw_eff = params[:shw_eff]

      if !(params.key?(:ecm_system_name)) && !(params.key?(:unitary_cop)) && !(params.key?(:airloop_economizer_type)) && !(params.key?(:boiler_eff)) && !(params.key?(:furnace_eff)) && !(params.key?(:shw_eff))
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:ecm_system_name)
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{ecm_system_name}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:unitary_cop)
        unitary_cop_out = $unitary_cop_args.select{ |unitary_cop_item| unitary_cop_item[:unitary_cop_arg] == unitary_cop }.first
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{unitary_cop_out[:unitary_cop_short]}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:airloop_economizer_type)
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{airloop_economizer_type}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:boiler_eff)
        boiler_eff_out = $boiler_eff_args.select{ |boiler_eff_item| boiler_eff_item[:boiler_eff_arg] == boiler_eff }.first
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{boiler_eff_out[:boiler_eff_short]}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:furnace_eff)
        furnace_eff_out = $furnace_eff_args.select{ |furnace_eff_item| furnace_eff_item[:furnace_eff_arg] == furnace_eff }.first
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{furnace_eff_out[:furnace_eff_short]}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      elsif params.key?(:shw_eff)
        shw_eff_out = $shw_eff_args.select{ |shw_eff_item| shw_eff_item[:shw_eff_arg] == shw_eff }.first
        return "#{building_type}-#{template}-#{primary_heating_fuel}-#{shw_eff_out[:shw_eff_short]}-#{File.basename(epw_file, '.epw').split('.')[0]}"
      end
    end
  end
end