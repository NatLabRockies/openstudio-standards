require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# *** Needs a re-write to use std paths etc ***

class NECB_Daylighting_Sensor_Control_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  def test_daylighting_sensor_control()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_daylight_sensor')
    @expected_results_file = File.join(__dir__, '../expected_results/daylighting_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/daylighting-test_results.json')

    # Initial test condition
    @test_passed = true

    #Range of test options.
    @templates = [  #expected results are for 'NECB2011', 'NECB2015', 'NECB2017'
        'NECB2011',
        'NECB2015',
        'NECB2017'
    ]
    @building_types = [         #expected results are for 'Hospital', 'LargeOffice', 'Outpatient', 'Warehouse'
        # # 'FullServiceRestaurant',
        # # 'HighriseApartment',
        # 'Hospital',
        # # 'LargeHotel',
        'LargeOffice',
        # # 'MediumOffice',
        # # 'MidriseApartment',
        'Outpatient',
        # # 'PrimarySchool',
        # # 'QuickServiceRestaurant',
        # # 'RetailStandalone',
        'SecondarySchool',
        # # 'SmallHotel',
        'Warehouse'
    ]
    @epw_files = ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw']
    @primary_heating_fuels = ['DefaultFuel']
    @dcv_types = ['No DCV']
    @lighting_types = ['NECB_Default'] #LED  #NECB_Default
    @daylighting_types = [
      'NECB_Default',
      'add_daylighting_controls'
    ]

    # Test results storage array.
    @test_results_array = []

    @templates.sort.each do |template|
      @epw_files.sort.each do |epw_file|
        @building_types.sort.each do |building_type|
          @primary_heating_fuels.sort.each do |primary_heating_fuel|
            @dcv_types.sort.each do |dcv_type|
              @lighting_types.sort.each do |lighting_type|
                @daylighting_types.sort.each do |daylighting_type|

                  result = {}
                  result['template'] = template
                  result['epw_file'] = epw_file
                  result['building_type'] = building_type
                  result['primary_heating_fuel'] = primary_heating_fuel
                  result['daylighting_type'] = daylighting_type

                  # make an empty model
                  model = OpenStudio::Model::Model.new
                  #set up basic model.
                  standard = Standard.build(template)

                  #loads osm geometry and spactypes from library.
                  model = standard.load_building_type_from_library(building_type: building_type)

                  # this runs the step in the model.
                  standard.assign_building_activity(model: model)
                  standard.assign_building_structure(model: model, activity: @activity, massive: false)
                  standard.apply_weather_data(model: model, epw_file: epw_file)
                  standard.assign_building_activity(model: model)
                  standard.assign_building_structure(model: model, activity: @activity)
                  standard.apply_loads(model: model, lights_type: lighting_type, lights_scale: 1.0)
                  standard.apply_envelope(model: model)
                  standard.apply_fdwr_srr_daylighting(model: model)
                  standard.model_add_daylighting_controls(model: model, daylighting_type: daylighting_type)

                  # # comment out for regular tests
                  # BTAP::FileIO.save_osm(model, File.join(@output_folder,"#{template}-#{building_type}-daylighting_type-#{daylighting_type}.osm"))
                  # puts File.join(@output_folder,"#{template}-#{building_type}-daylighting_type-#{daylighting_type}.osm")

                  ##### gather daylighting sensor controls once this measure is applied to the model

                  ##### Find spaces with exterior fenestration including fixed window, operable window, and skylight.
                  daylight_spaces = []
                  model.getSpaces.sort.each do |space|
                    space.surfaces.sort.each do |surface|
                      surface.subSurfaces.sort.each do |subsurface|
                        if subsurface.outsideBoundaryCondition == "Outdoors" &&
                          (subsurface.subSurfaceType == "FixedWindow" ||
                            subsurface.subSurfaceType == "OperableWindow" ||
                            subsurface.subSurfaceType == "Skylight")
                          daylight_spaces << space
                        end #subsurface.outsideBoundaryCondition == "Outdoors" && (subsurface.subSurfaceType == "FixedWindow" || "OperableWindow")
                      end #surface.subSurfaces.each do |subsurface|
                    end #space.surfaces.each do |surface|
                  end #model.getSpaces.each do |space|

                  ##### Remove duplicate spaces from the "daylight_spaces" array, as a daylighted space may have various fenestration types.
                  daylight_spaces = daylight_spaces.uniq

                  if daylighting_type == 'NECB_Default'

                    ##### Create hashes for "Primary Sidelighted Areas", "Sidelighting Effective Aperture", "Daylighted Area Under Skylights",
                    ##### and "Skylight Effective Aperture" for the whole model.
                    ##### Each of these hashes will be used later in this function (i.e. model_add_daylighting_controls)
                    ##### to provide a dictionary of daylighted space names and the associated value (i.e. daylighted area or effective aperture).
                    primary_sidelighted_area_hash = {}
                    sidelighting_effective_aperture_hash = {}
                    daylighted_area_under_skylights_hash = {}
                    skylight_effective_aperture_hash = {}

                    ##### Calculate "Primary Sidelighted Areas" AND "Sidelighting Effective Aperture" as per NECB2011.
                    # @todo consider removing overlapped sidelighted area
                    daylight_spaces.sort.each do |daylight_space|
                      primary_sidelighted_area = 0.0
                      area_weighted_vt_handle = 0.0
                      area_weighted_vt = 0.0
                      window_area_sum = 0.0

                      ##### Calculate floor area of the daylight_space and get floor vertices of the daylight_space (to be used for the calculation of daylight_space depth)
                      floor_surface = nil
                      floor_area = 0.0
                      floor_vertices = []
                      daylight_space.surfaces.sort.each do |surface|
                        if surface.surfaceType == "Floor"
                          floor_surface = surface
                          floor_area += surface.netArea
                          floor_vertices << surface.vertices
                        end
                      end

                      ##### Loop through the surfaces of each daylight_space to calculate primary_sidelighted_area and
                      ##### area-weighted visible transmittance and window_area_sum which are used to calculate sidelighting_effective_aperture
                      primary_sidelighted_area, area_weighted_vt_handle, window_area_sum =
                        standard.get_parameters_sidelighting(daylight_space: daylight_space,
                                                             floor_surface: floor_surface,
                                                             floor_vertices: floor_vertices,
                                                             floor_area: floor_area,
                                                             primary_sidelighted_area: primary_sidelighted_area,
                                                             area_weighted_vt_handle: area_weighted_vt_handle,
                                                             window_area_sum: window_area_sum)

                      primary_sidelighted_area_hash[daylight_space.name.to_s] = primary_sidelighted_area

                      ##### Calculate area-weighted VT of glazing (this is used to calculate sidelighting effective aperture; see NECB2011: 4.2.2.10.).
                      area_weighted_vt = area_weighted_vt_handle / window_area_sum
                      sidelighting_effective_aperture_hash[daylight_space.name.to_s] = window_area_sum * area_weighted_vt / primary_sidelighted_area

                    end #daylight_spaces.each do |daylight_space|


                    ##### Calculate "Daylighted Area Under Skylights" AND "Skylight Effective Aperture"
                    daylight_spaces.sort.each do |daylight_space|
                      skylight_area_weighted_vt_handle = 0.0
                      skylight_area_weighted_vt = 0.0
                      skylight_area_sum = 0.0
                      daylighted_under_skylight_area = 0.0

                      ##### Loop through the surfaces of each daylight_space to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
                      daylighted_under_skylight_area, skylight_area_weighted_vt_handle, skylight_area_sum =
                        standard.get_parameters_skylight(daylight_space: daylight_space,
                                                         skylight_area_weighted_vt_handle: skylight_area_weighted_vt_handle,
                                                         skylight_area_sum: skylight_area_sum,
                                                         daylighted_under_skylight_area: daylighted_under_skylight_area)
                      daylighted_area_under_skylights_hash[daylight_space.name.to_s] = daylighted_under_skylight_area

                      ##### Calculate skylight_effective_aperture as per NECB2011: 4.2.2.7.
                      ##### Note that it was assumed that the skylight is flush with the ceiling. Therefore, area-weighted average well factor (WF) was set to 0.9 in the below Equation.
                      skylight_area_weighted_vt = skylight_area_weighted_vt_handle / skylight_area_sum
                      skylight_effective_aperture_hash[daylight_space.name.to_s] = 0.85 * skylight_area_sum * skylight_area_weighted_vt * 0.9 / daylighted_under_skylight_area

                    end #daylight_spaces.each do |daylight_space|


                    ##### Find office spaces >= 25m2 among daylight_spaces
                    offices_larger_25m2 = []
                    daylight_spaces.sort.each do |daylight_space|
                      office_area = nil
                      daylight_space.surfaces.sort.each do |surface|
                        if surface.surfaceType == "Floor"
                          office_area = surface.netArea
                        end
                      end
                      if daylight_space.spaceType.get.standardsSpaceType.get.to_s == "Office - enclosed" && office_area >= 25.0
                        offices_larger_25m2 << daylight_space.name.to_s
                      end
                    end

                    ##### find daylight_spaces which do not need daylight sensor controls based on the primary_sidelighted_area as per NECB2011: 4.2.2.8.
                    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their primary_sidelighted_area <= 100m2), as per NECB2011: 4.2.2.2.
                    daylight_spaces_exception = []
                    primary_sidelighted_area_hash.sort.each do |key_daylight_space_name, value_primary_sidelighted_area|
                      if value_primary_sidelighted_area <= 100.0 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
                        daylight_spaces_exception << key_daylight_space_name
                      end
                    end

                    ##### find daylight_spaces which do not need daylight sensor controls based on the sidelighting_effective_aperture as per NECB2011: 4.2.2.8.
                    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their sidelighting_effective_aperture <= 10%), as per NECB2011: 4.2.2.2.
                    sidelighting_effective_aperture_hash.sort.each do |key_daylight_space_name, value_sidelighting_effective_aperture|
                      if value_sidelighting_effective_aperture <= 0.1 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
                        daylight_spaces_exception << key_daylight_space_name
                      end
                    end

                    ##### find daylight_spaces which do not need daylight sensor controls based on the daylighted_area_under_skylights as per NECB2011: 4.2.2.4.
                    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their daylighted_area_under_skylights <= 400m2), as per NECB2011: 4.2.2.2.
                    daylighted_area_under_skylights_hash.sort.each do |key_daylight_space_name, value_daylighted_area_under_skylights|
                      if value_daylighted_area_under_skylights <= 400.0 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
                        daylight_spaces_exception << key_daylight_space_name
                      end
                    end

                    ##### find daylight_spaces which do not need daylight sensor controls based on the skylight_effective_aperture criterion as per NECB2011: 4.2.2.4.
                    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their skylight_effective_aperture <= 0.6%), as per NECB2011: 4.2.2.2.
                    skylight_effective_aperture_hash.sort.each do |key_daylight_space_name, value_skylight_effective_aperture|
                      if value_skylight_effective_aperture <= 0.006 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
                        daylight_spaces_exception << key_daylight_space_name
                      end
                    end

                    ##### Loop through the daylight_spaces and exclude the daylight_spaces that do not meet the criteria (see above) as per NECB2011: 4.2.2.4. and 4.2.2.8.
                    daylight_spaces_exception.sort.each do |daylight_space_exception|
                      daylight_spaces.sort.each do |daylight_space|
                        if daylight_space.name.to_s == daylight_space_exception
                          daylight_spaces.delete(daylight_space)
                        end
                      end
                    end

                  end #END if daylighting_type == 'NECB_Default'

                  ##### Gather daylighting sensors specifications in the model for the daylight_spaces that should have daylighting sensor
                  daylight_spaces.sort.each do |daylight_space|
                    ##### 1. Calculate number of floors of each daylight_space
                    ##### 2. Find the lowest z among all floors of each daylight_space
                    ##### 3. Find lowest floors of each daylight_space (these floors are at the same level)
                    ##### 4. Calculate 'daylight_space_area' as sum of area of all the lowest floors of each daylight_space, and gather the vertices of all the lowest floors of each daylight_space
                    ##### 5. Find min and max of x and y among vertices of all the lowest floors of each daylight_space (these vertices are required for boundingBox to find the location of daylighting sensor(s))

                    ##### Calculate number of floors of daylight_space
                    floor_vertices = []
                    number_floor = 0
                    daylight_space.surfaces.sort.each do |surface|
                      if surface.surfaceType == 'Floor'
                        floor_vertices << surface.vertices
                        number_floor += 1
                      end
                    end

                    ##### Loop through all floors of daylight_space, and find the lowest z among all floors of daylight_space
                    lowest_floor_z = []
                    highest_floor_z = []
                    for i in 0..number_floor - 1
                      if i == 0
                        lowest_floor_z = floor_vertices[i][0].z
                        highest_floor_z = floor_vertices[i][0].z
                      else
                        if lowest_floor_z > floor_vertices[i][0].z
                          lowest_floor_z = floor_vertices[i][0].z
                        else
                          lowest_floor_z = lowest_floor_z
                        end
                        if highest_floor_z < floor_vertices[i][0].z
                          highest_floor_z = floor_vertices[i][0].z
                        else
                          highest_floor_z = highest_floor_z
                        end
                      end
                    end

                    ##### Loop through all floors of daylight_space, and calculate the sum of area of all the lowest floors of daylight_space,
                    ##### and gather the vertices of all the lowest floors of daylight_space
                    daylight_space_area = 0
                    lowest_floors_vertices = []
                    floor_vertices = []
                    daylight_space.surfaces.sort.each do |surface|
                      if surface.surfaceType == 'Floor'
                        floor_vertices = surface.vertices
                        if floor_vertices[0].z == lowest_floor_z
                          lowest_floors_vertices << floor_vertices
                          daylight_space_area = daylight_space_area + surface.netArea
                        end
                      end
                    end

                    ##### Get the thermal zone of daylight_space (this is used later to assign daylighting sensor)
                    zone = daylight_space.thermalZone
                    if !zone.empty?
                      zone = daylight_space.thermalZone.get
                      # puts zone

                      if !zone.primaryDaylightingControl.empty?
                        zone_daylighting_control_primary = zone.primaryDaylightingControl.get
                        primary_daylighting_control_fraction_of_zone_controlled = zone.fractionofZoneControlledbyPrimaryDaylightingControl()
                        primary_daylighting_control_illuminance_setpoint = zone_daylighting_control_primary.illuminanceSetpoint()
                        primary_daylighting_control_lighting_control_type = zone_daylighting_control_primary.lightingControlType()
                        primary_daylighting_control_number_of_stepped_control_steps = zone_daylighting_control_primary.numberofSteppedControlSteps()
                        primary_daylighting_x_pos = zone_daylighting_control_primary.positionXCoordinate()
                        primary_daylighting_y_pos = zone_daylighting_control_primary.positionYCoordinate()
                        primary_daylighting_z_pos = zone_daylighting_control_primary.positionZCoordinate()

                        ##### Gather results from this iteration and store it into the test_result_array.
                        result["#{daylight_space.name.to_s} - area"] = daylight_space_area
                        result["#{daylight_space.name.to_s} - primary_daylighting_control_fraction_of_zone_controlled"] = primary_daylighting_control_fraction_of_zone_controlled
                        result["#{daylight_space.name.to_s} - primary_daylighting_control_illuminance_setpoint"] = primary_daylighting_control_illuminance_setpoint
                        result["#{daylight_space.name.to_s} - primary_daylighting_control_lighting_control_type"] = primary_daylighting_control_lighting_control_type
                        result["#{daylight_space.name.to_s} - primary_daylighting_control_number_of_stepped_control_steps"] = primary_daylighting_control_number_of_stepped_control_steps
                        result["#{daylight_space.name.to_s} - primary_daylighting_x_pos"] = primary_daylighting_x_pos
                        result["#{daylight_space.name.to_s} - primary_daylighting_y_pos"] = primary_daylighting_y_pos
                        result["#{daylight_space.name.to_s} - primary_daylighting_z_pos"] = primary_daylighting_z_pos

                      end
                    end #!zone.empty?

                  end #daylight_spaces.each do |daylight_space|

                  #then store result into the array that contains all the scenario results.
                  @test_results_array << result



                end #@daylighting_types.sort.each do |daylighting_type|
              end #@lighting_types.sort.each do |lighting_type|
            end #@dcv_types.sort.each do |dcv_type|
          end #@primary_heating_fuels.sort.each do |primary_heating_fuel|
        end #@building_types.sort.each do |building_type|
      end #@epw_files.sort.each do |epw_file|
    end #@templates.sort.each do |template|


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
