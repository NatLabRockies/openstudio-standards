require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# *** Needs a re-write to use std paths etc ***

class NECB_LED_Lighting_Tests < Minitest::Test

  def test_led_lighting()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_led_lighting')
    @expected_results_file = File.join(__dir__, '../expected_results/led_lighting_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/led_lighting-test_results.json')

    # Intial test condition
    @test_passed = true

    #Range of test options.
    @templates = [
        'NECB2011',
        'NECB2015',
        'NECB2017'
    ]
    @building_types = [
        'FullServiceRestaurant',
        'HighriseApartment',
        'Hospital',
        'LargeHotel',
        'LargeOffice',
        'MediumOffice',
        'MidriseApartment',
        'Outpatient',
        'PrimarySchool',
        'QuickServiceRestaurant',
        'RetailStandalone',
        'SecondarySchool',
        'SmallHotel',
        'Warehouse'
    ]
    @epw_files = ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw']
    @primary_heating_fuels = ['DefaultFuel']
    @dcv_types = ['No DCV']
    @lighting_types = ['LED'] #LED  #NECB_Default

    # Test results storage array.
    @test_results_array = []

    @templates.sort.each do |template|
      @epw_files.sort.each do |epw_file|
        @building_types.sort.each do |building_type|
          @primary_heating_fuels.sort.each do |primary_heating_fuel|
            @dcv_types.sort.each do |dcv_type|
              @lighting_types.sort.each do |lighting_type|

                result = {}
                result['template'] = template
                result['epw_file'] = epw_file
                result['building_type'] = building_type
                result['primary_heating_fuel'] = primary_heating_fuel
                result['dcv_type'] = dcv_type
                result['lighting_type'] = lighting_type

                # make an empty model
                model = OpenStudio::Model::Model.new
                #set up basic model.
                standard = Standard.build(template)

                #loads osm geometry and spactypes from library.
                model = standard.load_building_type_from_library(building_type: building_type)

                # this runs the step in the model. You can remove steps after what you want to test if you wish to make the test run faster.
                standard.apply_weather_data(model: model, epw_file: epw_file)
                standard.apply_loads(model: model, lights_type: lighting_type, lights_scale: 1.0)

                # # comment out for regular tests
                # BTAP::FileIO.save_osm(model, File.join(@output_folder, "#{template}-#{building_type}-led_lighting.osm"))
                # puts File.join(@output_folder, "#{template}-#{building_type}-led_lighting.osm")

                model.getSpaceTypes.sort.each do |space_type|
                  #   puts model

                  ##### Calculate height of spaces, as this is required for the calculation of atriums' LPD
                  space_type_spaces = space_type.spaces()
                  # puts space_type
                  # puts space_type_spaces
                  # puts space_type_spaces.class
                  # puts space_type_spaces.length
                  # puts space_type_spaces[0]
                  space_walls_vertices = []
                  for i in 0..space_type_spaces.length - 1
                    space_type_spaces[i].surfaces.sort.each do |surface|
                      if surface.surfaceType == "Wall"
                        space_walls_vertices << surface.vertices
                      end
                    end
                  end
                  for i in 0..space_walls_vertices.length - 1
                    if i == 0
                      space_height = [space_walls_vertices[i][0].z, space_walls_vertices[i][1].z, space_walls_vertices[i][2].z, space_walls_vertices[i][3].z,].max
                    end
                    if space_height < [space_walls_vertices[i][0].z, space_walls_vertices[i][1].z, space_walls_vertices[i][2].z, space_walls_vertices[i][3].z,].max
                      space_height = [space_walls_vertices[i][0].z, space_walls_vertices[i][1].z, space_walls_vertices[i][2].z, space_walls_vertices[i][3].z,].max
                    else
                      space_height = space_height
                    end
                  end
                  if space_type_spaces.length > 0
                    space_height = space_height
                  else
                    space_height = 0
                  end
                  # puts space_type.name()
                  result["#{space_type.name.to_s} - space_height"] = space_height.to_s

                  if !space_type.lights().empty?
                    space_type_lights = space_type.lights()
                    # puts space_type_lights
                    space_type.lights.sort.each do |inst|
                      space_type_lights_definition = inst.lightsDefinition
                      # puts space_type_lights_definition
                      # puts space_type_lights_definition.name()
                      # puts space_type_lights_definition.designLevelCalculationMethod()
                      # puts space_type_lights_definition.wattsperSpaceFloorArea()
                      # puts space_type_lights_definition.fractionRadiant()
                      # puts space_type_lights_definition.fractionVisible()
                      # puts space_type_lights_definition.returnAirFraction()

                      ##### Gather information about lights definitions of spaces/space types
                      result["#{space_type.name.to_s} - space_type_lights_definition - name"] = space_type_lights_definition.name().to_s
                      result["#{space_type.name.to_s} - space_type_lights_definition - designLevelCalculationMethod"] = space_type_lights_definition.designLevelCalculationMethod()
                      result["#{space_type.name.to_s} - space_type_lights_definition - wattsperSpaceFloorArea"] = space_type_lights_definition.wattsperSpaceFloorArea().to_s
                      result["#{space_type.name.to_s} - space_type_lights_definition - fractionRadiant"] = space_type_lights_definition.fractionRadiant().to_s
                      result["#{space_type.name.to_s} - space_type_lights_definition - fractionVisible"] = space_type_lights_definition.fractionVisible().to_s
                      result["#{space_type.name.to_s} - space_type_lights_definition - returnAirFraction"] = space_type_lights_definition.returnAirFraction().to_s
                    end
                    # puts result
                    # raise('check space_type_spaces')
                  end


                end #model.getSpaces.each do |space|

                #then store results into the array that contains all the scenario results.
                @test_results_array << result
              end #@lighting_types.sort.each do |lighting_type|
            end #@dcv_types.sort.each do |dcv_type|
          end #@primary_heating_fuels.sort.each do |primary_heating_fuel|
        end #@building_types.sort.each do |building_type|
      end #@epw_files.sort.each do |epw_file|
    end #@templates.sort.each do |template|
    # puts @test_results_array

    # Save test results to file.
    File.open(@test_results_file, 'w') {|f| f.write(JSON.pretty_generate(@test_results_array))}

    # Compare results
    compare_message = ''
    # Check if expected file exists.
    if File.exist?(@expected_results_file)
      # Load expected results from file.
      @expected_results = JSON.parse(File.read(@expected_results_file))
      if @expected_results.size == @test_results_array.size
        # Iterate through each test result.
        @expected_results.each_with_index do |expected, row|
          # Compare if row /hash is exactly the same.
          if expected != @test_results_array[row]
            #if not set test flag to false
            @test_passed = false
            compare_message << "\nERROR: This row was different expected/result\n"
            compare_message << "EXPECTED:#{expected.to_s}\n"
            compare_message << "TEST:    #{@test_results_array[row].to_s}\n\n"
          end
        end
      else
        assert(false, "#{@expected_results_file} # of rows do not match the #{@test_results_array}..cannot compare")
      end
    else
      assert(false, "#{@expected_results_file} does not exist..cannot compare")
    end
    puts compare_message
    assert(@test_passed, "Error: This test failed to produce the same result as in the #{@expected_results_file}\n")
  end

end
