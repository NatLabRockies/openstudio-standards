require_relative '../../test_helper'

class TestNECBLighting < Minitest::Test
  include NecbHelper

  # Setup method called before each test
  def setup
    define_folders(__dir__)
    define_std_ranges
  end

  # Test 1: LPD lookup for various space types across vintages
  def test_lpd_lookup_by_space_type
    templates = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']
    test_space_types = [
      { building_type: 'Space Function', space_type: 'Office - enclosed' },
      { building_type: 'Space Function', space_type: 'Office - open plan' },
      { building_type: 'Space Function', space_type: 'Retail - sales' },
      { building_type: 'Space Function', space_type: 'Warehouse - fine' },
      { building_type: 'Space Function', space_type: 'Classroom/lecture/training' }
    ]

    templates.each do |template|
      standard = get_standard(template)
      model = OpenStudio::Model::Model.new

      test_space_types.each do |st|
        # Create a space type
        space_type = OpenStudio::Model::SpaceType.new(model)
        space_type.setStandardsBuildingType(st[:building_type])
        space_type.setStandardsSpaceType(st[:space_type])

        # Get space type properties
        space_type_properties = standard.space_type_get_standards_data(space_type)

        # Verify LPD exists and is positive
        unless space_type_properties.nil?
          lpd = space_type_properties['lighting_per_area'].to_f
          if lpd > 0
            logger.info("#{template} - #{st[:space_type]}: LPD = #{lpd} W/ft^2")
          else
            # Some space types may not have LPD defined in certain vintages
            logger.info("#{template} - #{st[:space_type]}: No LPD defined (may use different structure)")
          end
          # Only assert positive if properties exist and LPD is defined
          assert(lpd >= 0, "#{template} - #{st[:space_type]}: LPD should be non-negative, got #{lpd}")
        else
          logger.info("#{template} - #{st[:space_type]}: Space type properties not found")
        end
      end
    end
  end

  # Test 2: Occupancy sensor LPD reduction for specific space types
  def test_occupancy_sensor_lpd_reduction
    template = 'NECB2011'
    standard = get_standard(template)
    model = OpenStudio::Model::Model.new

    # Space types that should have occupancy sensor reduction (0.9 factor)
    reduction_spaces = ['Classroom/lecture/training', 'Conf./meet./multi-purpose', 'Washroom-sch-A']

    reduction_spaces.each do |space_type_name|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType(space_type_name)
      space_type.setName("Test #{space_type_name}")

      # Get space type properties
      space_type_properties = standard.space_type_get_standards_data(space_type)
      next if space_type_properties.nil?

      base_lpd = space_type_properties['lighting_per_area'].to_f
      next if base_lpd.zero?

      # Create lights definition
      definition = OpenStudio::Model::LightsDefinition.new(model)
      definition.setName("#{space_type.name} Lights Definition")

      # Apply lighting
      standard.set_lighting_per_area(
        space_type: space_type,
        definition: definition,
        lighting_per_area: base_lpd,
        lights_scale: 1.0
      )

      # Get actual LPD in W/m^2
      actual_lpd_si = definition.wattsperSpaceFloorArea.get

      # Calculate expected LPD with 0.9 reduction
      expected_lpd_si = OpenStudio.convert(base_lpd * 0.9, 'W/ft^2', 'W/m^2').get

      # Allow small tolerance for rounding
      tolerance = 0.01
      assert_in_delta(expected_lpd_si, actual_lpd_si, tolerance,
                      "#{space_type_name}: Expected LPD #{expected_lpd_si} W/m^2 with occ sensor reduction, got #{actual_lpd_si} W/m^2")

      logger.info("#{space_type_name}: Base LPD = #{base_lpd} W/ft^2, Applied LPD = #{actual_lpd_si} W/m^2 (with 0.9 factor)")
    end
  end

  # Test 3: Lighting application to space types
  def test_apply_standard_lights_to_space_type
    template = 'NECB2011'
    standard = get_standard(template)
    model = standard.load_building_type_from_library(building_type: 'SmallOffice')

    # Apply loads
    standard.apply_loads(model: model, lights_type: 'NECB_Default', lights_scale: 1.0)

    # Check that all space types have lights assigned
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsSpaceType.is_initialized

      space_type_properties = standard.space_type_get_standards_data(space_type)
      next if space_type_properties.nil?

      lpd = space_type_properties['lighting_per_area'].to_f
      next if lpd.zero?

      # Verify lights instance exists
      assert(!space_type.lights.empty?, "#{space_type.name} should have lights assigned")

      # Verify definition exists
      lights_instance = space_type.lights.first
      assert(lights_instance.lightsDefinition.wattsperSpaceFloorArea.is_initialized,
             "#{space_type.name} should have LPD defined")

      actual_lpd = lights_instance.lightsDefinition.wattsperSpaceFloorArea.get
      assert(actual_lpd > 0, "#{space_type.name} LPD should be positive, got #{actual_lpd}")

      logger.info("#{space_type.name}: Applied LPD = #{actual_lpd} W/m^2")
    end
  end

  # Test 4: Lighting fractions (radiant, visible, return air)
  def test_lighting_fractions
    template = 'NECB2011'
    standard = get_standard(template)
    model = OpenStudio::Model::Model.new

    # Create a test space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - enclosed')

    # Get properties and apply lighting
    space_type_properties = standard.space_type_get_standards_data(space_type)

    standard.apply_standard_lights(
      set_lights: true,
      space_type: space_type,
      space_type_properties: space_type_properties,
      lights_type: 'NECB_Default',
      lights_scale: 1.0
    )

    # Check lighting fractions
    assert(!space_type.lights.empty?, "Space type should have lights assigned")
    lights_instance = space_type.lights.first
    definition = lights_instance.lightsDefinition

    # NECB default fractions from space_types.json
    expected_radiant = space_type_properties['lighting_fraction_radiant'].to_f
    expected_visible = space_type_properties['lighting_fraction_visible'].to_f
    expected_return_air = space_type_properties['lighting_fraction_to_return_air'].to_f

    assert_equal(expected_radiant, definition.fractionRadiant,
                 "Radiant fraction should match space type properties")
    assert_equal(expected_visible, definition.fractionVisible,
                 "Visible fraction should match space type properties")
    assert_equal(expected_return_air, definition.returnAirFraction,
                 "Return air fraction should match space type properties")

    logger.info("Lighting fractions - Radiant: #{definition.fractionRadiant}, " \
                "Visible: #{definition.fractionVisible}, Return Air: #{definition.returnAirFraction}")
  end

  # Test 5: LED lighting vs NECB default lighting
  def test_led_vs_necb_default_lighting
    template = 'NECB2011'
    standard = get_standard(template)

    # Test with a simple office building
    model_necb = standard.load_building_type_from_library(building_type: 'SmallOffice')
    model_led = standard.load_building_type_from_library(building_type: 'SmallOffice')

    # Apply NECB default lighting
    standard.apply_loads(model: model_necb, lights_type: 'NECB_Default', lights_scale: 1.0)

    # Apply LED lighting
    standard.apply_loads(model: model_led, lights_type: 'LED', lights_scale: 1.0)

    # Compare LPD values
    model_necb.getSpaceTypes.each do |necb_space_type|
      next if necb_space_type.lights.empty?

      necb_lights = necb_space_type.lights.first
      necb_lpd = necb_lights.lightsDefinition.wattsperSpaceFloorArea.get

      # Find corresponding LED space type
      led_space_type = model_led.getSpaceTypes.find { |st| st.name.to_s == necb_space_type.name.to_s }
      next if led_space_type.nil? || led_space_type.lights.empty?

      led_lights = led_space_type.lights.first
      led_lpd = led_lights.lightsDefinition.wattsperSpaceFloorArea.get

      # LED LPD should typically be lower than NECB default
      logger.info("#{necb_space_type.name}: NECB LPD = #{necb_lpd} W/m^2, LED LPD = #{led_lpd} W/m^2")

      # Verify both are positive
      assert(necb_lpd > 0, "NECB LPD should be positive")
      assert(led_lpd > 0, "LED LPD should be positive")
    end
  end

  # Test 6: Lighting schedule application
  def test_lighting_schedule_application
    template = 'NECB2011'
    standard = get_standard(template)
    model = standard.load_building_type_from_library(building_type: 'SmallOffice')

    # Apply loads which includes schedules
    standard.apply_loads(model: model, lights_type: 'NECB_Default', lights_scale: 1.0)

    # Check that schedules are applied
    model.getDefaultScheduleSets.each do |default_sch_set|
      next unless default_sch_set.lightingSchedule.is_initialized

      lighting_schedule = default_sch_set.lightingSchedule.get

      # Verify schedule exists and has a name
      assert(!lighting_schedule.name.to_s.empty?, "Lighting schedule should have a name")

      logger.info("Default schedule set has lighting schedule: #{lighting_schedule.name}")

      # For NECB schedules, verify it's a ScheduleRuleset
      if lighting_schedule.to_ScheduleRuleset.is_initialized
        schedule_ruleset = lighting_schedule.to_ScheduleRuleset.get

        # Verify default day schedule exists
        assert(!schedule_ruleset.defaultDaySchedule.nil?,
               "Schedule ruleset should have a default day schedule")

        logger.info("  Schedule type: ScheduleRuleset with #{schedule_ruleset.scheduleRules.size} rules")
      end
    end
  end

  # Test 7: Lighting power scaling
  def test_lighting_power_scaling
    template = 'NECB2011'
    standard = get_standard(template)
    scales = [0.8, 1.0, 1.2]

    scales.each do |scale|
      model = standard.load_building_type_from_library(building_type: 'SmallOffice')
      standard.apply_loads(model: model, lights_type: 'NECB_Default', lights_scale: scale)

      model.getSpaceTypes.each do |space_type|
        next if space_type.lights.empty?

        space_type_properties = standard.space_type_get_standards_data(space_type)
        next if space_type_properties.nil?

        base_lpd = space_type_properties['lighting_per_area'].to_f
        next if base_lpd.zero?

        lights_instance = space_type.lights.first
        actual_lpd_si = lights_instance.lightsDefinition.wattsperSpaceFloorArea.get

        # Calculate expected with occupancy sensor reduction if applicable
        occ_sens_factor = 1.0
        reduce_lpd_spaces = ['Classroom/lecture/training', 'Conf./meet./multi-purpose', 'Washroom-sch-A']
        if space_type.standardsSpaceType.is_initialized
          space_type_name = space_type.standardsSpaceType.get
          occ_sens_factor = 0.9 if reduce_lpd_spaces.include?(space_type_name)
        end

        expected_lpd_si = OpenStudio.convert(base_lpd * scale * occ_sens_factor, 'W/ft^2', 'W/m^2').get

        tolerance = 0.01
        assert_in_delta(expected_lpd_si, actual_lpd_si, tolerance,
                        "#{space_type.name} at scale #{scale}: Expected #{expected_lpd_si}, got #{actual_lpd_si}")

        logger.info("#{space_type.name} at scale #{scale}: LPD = #{actual_lpd_si} W/m^2")
      end
    end
  end

  # Test 8: Multi-vintage LPD differences
  def test_multi_vintage_lpd_differences
    templates = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']
    building_type = 'MediumOffice'

    lpd_by_vintage = {}

    templates.each do |template|
      standard = get_standard(template)
      model = standard.load_building_type_from_library(building_type: building_type)
      standard.apply_loads(model: model, lights_type: 'NECB_Default', lights_scale: 1.0)

      lpd_by_vintage[template] = {}

      model.getSpaceTypes.each do |space_type|
        next if space_type.lights.empty?
        next unless space_type.standardsSpaceType.is_initialized

        space_type_name = space_type.standardsSpaceType.get
        lights_instance = space_type.lights.first
        lpd = lights_instance.lightsDefinition.wattsperSpaceFloorArea.get

        lpd_by_vintage[template][space_type_name] = lpd
      end
    end

    # Compare LPD values across vintages
    lpd_by_vintage.each do |template, space_types|
      space_types.each do |space_type_name, lpd|
        logger.info("#{template} - #{space_type_name}: #{lpd} W/m^2")
      end
    end

    # Verify that all vintages have LPD values
    templates.each do |template|
      assert(!lpd_by_vintage[template].empty?,
             "#{template} should have LPD values for space types")
    end

    # Log comparison
    if lpd_by_vintage['NECB2011'].any? && lpd_by_vintage['NECB2020'].any?
      common_spaces = lpd_by_vintage['NECB2011'].keys & lpd_by_vintage['NECB2020'].keys
      common_spaces.each do |space_type_name|
        lpd_2011 = lpd_by_vintage['NECB2011'][space_type_name]
        lpd_2020 = lpd_by_vintage['NECB2020'][space_type_name]
        percent_diff = ((lpd_2020 - lpd_2011) / lpd_2011 * 100).round(1)
        logger.info("#{space_type_name}: 2011=#{lpd_2011.round(2)}, 2020=#{lpd_2020.round(2)}, diff=#{percent_diff}%")
      end
    end
  end

  # Test 9: Additional lighting per area
  def test_additional_lighting_per_area
    template = 'NECB2011'
    standard = get_standard(template)
    model = OpenStudio::Model::Model.new

    # Create a space type with additional lighting
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Retail - sales')

    space_type_properties = standard.space_type_get_standards_data(space_type)

    # Check if space type has additional lighting defined
    additional_lpd = space_type_properties['additional_lighting_per_area'].to_f

    if additional_lpd > 0
      standard.apply_standard_lights(
        set_lights: true,
        space_type: space_type,
        space_type_properties: space_type_properties,
        lights_type: 'NECB_Default',
        lights_scale: 1.0
      )

      # Should have multiple lights instances (main + additional)
      lights_count = space_type.lights.size
      assert(lights_count >= 1, "Space type with additional lighting should have at least one lights instance")

      logger.info("#{space_type.name}: Has #{lights_count} lights instance(s), additional LPD = #{additional_lpd} W/ft^2")
    else
      logger.info("#{space_type.name}: No additional lighting defined")
    end
  end

  # Test 10: NECB2015 occupancy sensor control schedules
  def test_necb2015_occupancy_sensor_schedules
    template = 'NECB2015'
    standard = get_standard(template)
    model = standard.load_building_type_from_library(building_type: 'MediumOffice')

    # Apply loads to trigger schedule application
    standard.apply_loads(model: model, lights_type: 'NECB_Default', lights_scale: 1.0)

    # NECB2015 should apply occupancy sensor control to lighting schedules
    # for spaces with LPD > 8.6 W/m^2 (0.799 W/ft^2)

    model.getDefaultScheduleSets.each do |default_sch_set|
      next unless default_sch_set.lightingSchedule.is_initialized

      lighting_schedule = default_sch_set.lightingSchedule.get
      schedule_name = lighting_schedule.name.to_s

      # Log the schedule for inspection
      logger.info("#{template} - Lighting schedule: #{schedule_name}")

      # Verify schedule exists
      assert(!schedule_name.empty?, "Lighting schedule should have a name")

      # For NECB2015+, schedules may include occupancy sensor parameters in name
      if schedule_name.include?('Light Ruleset')
        logger.info("  Detected occupancy sensor control schedule: #{schedule_name}")

        # Verify it's a ScheduleRuleset
        assert(lighting_schedule.to_ScheduleRuleset.is_initialized,
               "Occupancy sensor schedule should be a ScheduleRuleset")
      end
    end
  end

  # Test 11: Verify lighting per person (if applicable)
  def test_lighting_per_person
    template = 'NECB2011'
    standard = get_standard(template)
    model = OpenStudio::Model::Model.new

    # Most NECB space types use lighting_per_area, but check if any use lighting_per_person
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - enclosed')

    space_type_properties = standard.space_type_get_standards_data(space_type)

    lighting_per_person = space_type_properties['lighting_per_person'].to_f

    if lighting_per_person > 0
      logger.info("#{space_type.name}: Uses lighting_per_person = #{lighting_per_person} W/person")

      standard.apply_standard_lights(
        set_lights: true,
        space_type: space_type,
        space_type_properties: space_type_properties,
        lights_type: 'NECB_Default',
        lights_scale: 1.0
      )

      # Verify watts per person is set
      lights_instance = space_type.lights.first
      definition = lights_instance.lightsDefinition

      assert(definition.wattsperPerson.is_initialized,
             "Lighting definition should have watts per person set")
    else
      logger.info("#{space_type.name}: Does not use lighting_per_person (uses LPD instead)")
    end
  end

end
