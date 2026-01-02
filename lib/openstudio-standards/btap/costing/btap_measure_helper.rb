module BTAPMeasureHelper
  ###################Helper functions

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    if true == @use_json_package
      #Set up package version of input.
      json_default = {}
      @measure_interface_detailed.each do |argument|
        json_default[argument['name']] = argument["default_value"]
      end
      default = JSON.pretty_generate(json_default)
      arg = OpenStudio::Ruleset::OSArgument.makeStringArgument('json_input', true)
      arg.setDisplayName('Contains a json version of the input as a single package.')
      arg.setDefaultValue(default)
      args << arg
    else
      # Conductances for all surfaces and subsurfaces.
      @measure_interface_detailed.each do |argument|
        arg = nil
        statement = nil
        case argument['type']
          when "String"
            arg = OpenStudio::Ruleset::OSArgument.makeStringArgument(argument['name'], argument['is_required'])
            arg.setDisplayName(argument['display_name'])
            arg.setDefaultValue(argument['default_value'].to_s)

          when "Double"
            arg = OpenStudio::Ruleset::OSArgument.makeDoubleArgument(argument['name'], argument['is_required'])
            arg.setDisplayName("#{argument['display_name']}")
            arg.setDefaultValue("#{argument['default_value']}".to_f)

          when "Choice"
            arg = OpenStudio::Measure::OSArgument.makeChoiceArgument(argument['name'], argument['choices'], argument['is_required'])
            arg.setDisplayName(argument['display_name'])
            arg.setDefaultValue(argument['default_value'].to_s)
            puts arg.defaultValueAsString

          when "Bool"
            arg = OpenStudio::Measure::OSArgument.makeBoolArgument(argument['name'], argument['is_required'])
            arg.setDisplayName(argument['display_name'])
            arg.setDefaultValue(argument['default_value'])


          when "StringDouble"
            if @use_string_double == false
              arg = OpenStudio::Ruleset::OSArgument.makeDoubleArgument(argument['name'], argument['is_required'])
              arg.setDefaultValue(argument['default_value'].to_f)
            else
              arg = OpenStudio::Ruleset::OSArgument.makeStringArgument(argument['name'], argument['is_required'])
              arg.setDefaultValue(argument['default_value'].to_s)
            end
            arg.setDisplayName(argument['display_name'])
        end
        args << arg
      end
    end
    return args
  end

  #returns a hash of the user inputs for you to use in your measure.
  def get_hash_of_arguments(user_arguments, runner)
    values = {}
    if @use_json_package
      return JSON.parse(runner.getStringArgumentValue('json_input', user_arguments))
    else

      @measure_interface_detailed.each do |argument|

        case argument['type']
          when "String", "Choice"
            values[argument['name']] = runner.getStringArgumentValue(argument['name'], user_arguments)
          when "Double"
            values[argument['name']] = runner.getDoubleArgumentValue(argument['name'], user_arguments)
          when "Bool"
            values[argument['name']] = runner.getBoolArgumentValue(argument['name'], user_arguments)
          when "StringDouble"
            value = nil
            if @use_string_double == false
              value = (runner.getDoubleArgumentValue(argument['name'], user_arguments).to_f)
            else
              value = runner.getStringArgumentValue(argument['name'], user_arguments)
              if valid_float?(value)
                value = value.to_f
              end
            end
            values[argument['name']] = value
        end
      end
    end
    return values
  end

  # boilerplate that validated ranges of inputs.
  def validate_and_get_arguments_in_hash(model, runner, user_arguments)
    return_value = true
    values = get_hash_of_arguments(user_arguments, runner)
    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      runner_register(runner, 'Error', "validateUserArguments failed... Check the argument definition for errors.")
      return_value = false
    end

    # Validate arguments
    errors = ""
    @measure_interface_detailed.each do |argument|
      case argument['type']
        when "Double"
          value = values[argument['name']]
          if (not argument["max_double_value"].nil? and value.to_f > argument["max_double_value"].to_f) or
              (not argument["min_double_value"].nil? and value.to_f < argument["min_double_value"].to_f)
            error = "#{argument['name']} must be between #{argument["min_double_value"]} and #{argument["max_double_value"]}. You entered #{value.to_f} for this #{argument['name']}.\n Please enter a value withing the expected range.\n"
            errors << error
          end
        when "StringDouble"
          value = values[argument['name']]
          if (not argument["valid_strings"].include?(value)) and (not valid_float?(value))
            error = "#{argument['name']} must be a string that can be converted to a float, or one of these #{argument["valid_strings"]}. You have entered #{value}\n"
            errors << error
          elsif (not argument["max_double_value"].nil? and value.to_f > argument["max_double_value"]) or
              (not argument["min_double_value"].nil? and value.to_f < argument["min_double_value"])
            error = "#{argument['name']} must be between #{argument["min_double_value"]} and #{argument["max_double_value"]}. You entered #{value} for #{argument['name']}. Please enter a stringdouble value in the expected range.\n"
            errors << error
          end
      end
    end
    #If any errors return false, else return the hash of argument values for user to use in measure.
    if errors != ""
      runner.registerError(errors)
      return false
    end
    return values
  end

  # Helper method to see if str is a valid float.
  def valid_float?(str)
    !!Float(str) rescue false
  end

end

module BTAPMeasureTestHelper
  ##### Helper methods Do notouch unless you know the consequences.

  #Boiler plate to default values and number of arguments against what is in your test's setup method.
  def test_arguments_and_defaults
    [true, false].each do |json_input|
      [true, false].each do |string_double|
        @use_json_package = json_input
        @use_string_double = string_double

        # Create an instance of the measure
        measure = get_measure_object()
        measure.use_json_package = @use_json_package
        measure.use_string_double = @use_string_double
        model = OpenStudio::Model::Model.new

        # Create an instance of a runner
        runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

        # Test arguments and defaults
        arguments = measure.arguments(model)
        #convert whatever the input was into a hash. Then test.

        #check number of arguments.
        if @use_json_package
          assert_equal(@measure_interface_detailed.size, JSON.parse(arguments[0].defaultValueAsString).size, "The measure should have #{@measure_interface_detailed.size} but actually has #{arguments.size}. Here the the arguement expected #{@measure_interface_detailed} and this is the actual #{arguments}")
        else
          assert_equal(@measure_interface_detailed.size, arguments.size, "The measure should have #{@measure_interface_detailed.size} but actually has #{arguments.size}. Here the the arguement expected #{@measure_interface_detailed} and this is the actual #{arguments}")
          (@measure_interface_detailed).each_with_index do |argument_expected, index|
            assert_equal(argument_expected['name'], arguments[index].name, "Measure argument name of #{argument_expected['name']} was expected, but got #{arguments[index].name} instead.")
            assert_equal(argument_expected['display_name'], arguments[index].displayName, "Display name for argument #{argument_expected['name']} was expected to be #{argument_expected['display_name']}, but got #{arguments[index].displayName} instead.")
            case argument_type(arguments[index])
              when "String", "Choice"
                assert_equal(argument_expected['default_value'].to_s, arguments[index].defaultValueAsString, "The default value for argument #{argument_expected['name']} was #{argument_expected['default_value']}, but actual was #{arguments[index].defaultValueAsString}")
              when "Double", "Integer"
                assert_equal(argument_expected['default_value'].to_f, arguments[index].defaultValueAsDouble.to_f, "The default value for argument #{argument_expected['name']} was #{argument_expected['default_value']}, but actual was #{arguments[index].defaultValueAsString}")
              when "Bool"
                assert_equal(argument_expected['default_value'], arguments[index].defaultValueAsBool, "The default value for argument #{argument_expected['name']} was #{argument_expected['default_value']}, but actual was #{arguments[index].defaultValueAsString}")
            end
          end
        end
      end
    end
  end

  # Test argument ranges.
  def test_argument_ranges
    [true, false].each do |json_input|
      [true, false].each do |string_double|
        @use_json_package = json_input
        @use_string_double = string_double
        (@measure_interface_detailed).each_with_index do |argument|
          if argument['type'] == 'Double' or argument['type'] == 'StringDouble'
            puts "testing range for #{argument['name']} "
            #Check over max
            if not argument['max_double_value'].nil?
              puts "testing max limit"
              model = OpenStudio::Model::Model.new
              input_arguments = @good_input_arguments.clone
              over_max_value = argument['max_double_value'].to_f + 1.0
              over_max_value = over_max_value.to_s if argument['type'].downcase == "StringDouble".downcase
              input_arguments[argument['name']] = over_max_value
              puts "Testing argument #{argument['name']} max limit of #{argument['max_double_value']}"
              input_arguments = {'json_input' => JSON.pretty_generate(input_arguments)} if @use_json_package
              run_measure(input_arguments, model)
              runner = run_measure(input_arguments, model)
              assert(runner.result.value.valueName != 'Success', "Checks did not stop a lower than limit value of #{over_max_value} for #{argument['name']}")
              puts "Success: Testing argument #{argument['name']} max limit of #{argument['max_double_value']}"
            end
            #Check over max
            if not argument['min_double_value'].nil?
              puts "testing min limit"
              model = OpenStudio::Model::Model.new
              input_arguments = @good_input_arguments.clone
              over_min_value = argument['min_double_value'].to_f - 1.0
              over_min_value = over_max_value.to_s if argument['type'].downcase == "StringDouble".downcase
              input_arguments[argument['name']] = over_min_value
              puts "Testing argument #{argument['name']} min limit of #{argument['min_double_value']}"
              input_arguments = {'json_input' => JSON.pretty_generate(input_arguments)} if @use_json_package
              runner = run_measure(input_arguments, model)
              assert(runner.result.value.valueName != 'Success', "Checks did not stop a lower than limit value of #{over_min_value} for #{argument['name']}")
              puts "Success:Testing argument #{argument['name']} min limit of #{argument['min_double_value']}"
            end

          end
          if (argument['type'] == 'StringDouble') and (not argument["valid_strings"].nil?) and @use_string_double
            model = OpenStudio::Model::Model.new
            input_arguments = @good_input_arguments.clone
            input_arguments[argument['name']] = SecureRandom.uuid.to_s
            puts "Testing argument #{argument['name']} min limit of #{argument['min_double_value']}"
            input_arguments = {'json_input' => JSON.pretty_generate(input_arguments)} if @use_json_package
            runner = run_measure(input_arguments, model)
            assert(runner.result.value.valueName != 'Success', "Checks did not stop a lower than limit value of #{over_min_value} for #{argument['name']}")
          end
        end
      end
    end
  end

  # helper method to create necb archetype as a starting point for testing.
  def create_necb_protype_model(building_type, climate_zone, epw_file, template)

    osm_directory = "#{Dir.pwd}/output/#{building_type}-#{template}-#{climate_zone}-#{epw_file}"
    FileUtils.mkdir_p (osm_directory) unless Dir.exist?(osm_directory)
    #Get Weather climate zone from lookup
    weather = BTAP::Environment::WeatherFile.new(epw_file)
    #create model
    building_name = "#{template}_#{building_type}"

    prototype_creator = Standard.build(template)
    model = prototype_creator.model_create_prototype_model(
        epw_file: epw_file,
        sizing_run_dir: osm_directory,
        debug: @debug,
        template: template,
        building_type: building_type)

    #set weather file to epw_file passed to model.
    weather.set_weather_file(model)
    return model
  end

  # Custom way to run the measure in the test.
  def run_measure(input_arguments, model)

    # This will create a instance of the measure you wish to test. It does this based on the test class name.
    measure = get_measure_object()
    measure.use_json_package = @use_json_package
    measure.use_string_double = @use_string_double
    # Return false if can't
    return false if false == measure
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    #Check if

    # Set the arguements in the argument map use json or real arguments.
    if @use_json_package
      argument = arguments[0].clone
      assert(argument.setValue(input_arguments['json_input']), "Could not set value for 'json_input' to #{input_arguments['json_input']}")
      argument_map['json_input'] = argument
    else
      input_arguments.each_with_index do |(key, value), index|
        argument = arguments[index].clone
        if argument_type(argument) == "Double"
          #forces it to a double if it is a double.
          assert(argument.setValue(value.to_f), "Could not set value for #{key} to #{value}")
        else
          assert(argument.setValue(value.to_s), "Could not set value for #{key} to #{value}")
        end
        argument_map[key] = argument
      end
    end
    #run the measure
    measure.run(model, runner, argument_map)
    runner.result
    return runner
  end


  #Fancy way of getting the measure object automatically.
  def get_measure_object()
    measure_class_name = self.class.name.to_s.match(/(BTAP.*)(\_Test)/i).captures[0]
    measure = nil
    eval "measure = #{measure_class_name}.new"
    if measure.nil?
      puts "Measure class #{measure_class_name} is invalid. Please ensure the test class name is of the form 'MeasureName_Test' "
      return false
    end
    return measure
  end

  #Determines the OS argument type dynamically.
  def argument_type(argument)
    case argument.type.value
      when 0
        return "Bool"
      when 1 #Double
        return "Double"
      when 2 #Quantity
        return "Quantity"
      when 3 #Integer
        return "Integer"
      when 4
        return "String"
      when 5 #Choice
        return "Choice"
      when 6 #Path
        return "Path"
      when 7 #Separator
        return "Separator"
      else
        return "Blah"
    end
  end

  # Valid float helper.
  def valid_float?(str)
    !!Float(str) rescue false
  end

  #Method does a deep copy of a model.
  def copy_model(model)
    copy_model = OpenStudio::Model::Model.new
    # remove existing objects from model
    handles = OpenStudio::UUIDVector.new
    copy_model.objects.each do |obj|
      handles << obj.handle
    end
    copy_model.removeObjects(handles)
    # put contents of new_model into model_to_replace
    copy_model.addObjects(model.toIdfFile.objects)
    return copy_model
  end

end
