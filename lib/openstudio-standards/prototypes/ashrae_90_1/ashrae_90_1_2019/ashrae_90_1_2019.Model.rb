class ASHRAE9012019 < ASHRAE901
  # @!group Model

  # Adjust model to comply with fenestration orientation requirements
  # @note code_sections [90.1-2013_5.5.4.5]
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if successful, false otherwise
  def model_fenestration_orientation(model, climate_zone)
    # Building rotation to meet the same code requirement for
    # 90.1-2010 are kept
    if model.getBuilding.standardsBuildingType.is_initialized
      building_type = model.getBuilding.standardsBuildingType.get

      case building_type
        when 'Hospital'
          # Rotate the building counter-clockwise
          OpenstudioStandards::Geometry.model_set_building_north_axis(model, 270.0)
        when 'SmallHotel'
          # Rotate the building clockwise
          OpenstudioStandards::Geometry.model_set_building_north_axis(model, 180)
      end
    end

    wwr = false
    # Section 6.2.1.2 in the ANSI/ASHRAE/IES Standard 90.1-2013 Determination
    # of Energy Savings: Quantitative Analysis mentions that the SHGC trade-off
    # path is most likely to be used by designers for compliance.
    #
    # The following adjustment are only made for models with simple glazing objects
    non_simple_glazing = false
    shgc_a = 0
    model.getSpaces.each do |space|
      # Get thermal zone multiplier
      multiplier = space.thermalZone.get.multiplier

      space.surfaces.each do |surface|
        surface.subSurfaces.each do |subsurface|
          # Get window subsurface type
          subsurface_type = subsurface.subSurfaceType.to_s.downcase

          # Window, glass doors
          next unless (subsurface_type.include? 'window') || (subsurface_type.include? 'glass')

          # Check if non simple glazing fenestration objects are used
          subsurface_cons = subsurface.construction.get.to_Construction.get
          non_simple_glazing = true unless subsurface_cons.layers[0].to_SimpleGlazing.is_initialized

          if non_simple_glazing
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.ashrae_90_1_2013.model', 'Fenestration objects in the model use non-simple glazing models, fenestration requirements are not applied')
            return false
          end

          # Get subsurface's simple glazing object
          subsurface_shgc = subsurface_cons.layers[0].to_SimpleGlazing.get.solarHeatGainCoefficient

          # Get subsurface area
          subsurface_area = subsurface.grossArea * subsurface.multiplier * multiplier

          # SHGC * Area
          shgc_a += subsurface_shgc * subsurface_area
        end
      end
    end

    # Calculate West, East and total fenestration area
    a_n = OpenstudioStandards::Geometry.model_get_exterior_window_and_wall_area_by_orientation(model)['north_window']
    a_s = OpenstudioStandards::Geometry.model_get_exterior_window_and_wall_area_by_orientation(model)['south_window']
    a_e = OpenstudioStandards::Geometry.model_get_exterior_window_and_wall_area_by_orientation(model)['east_window']
    a_w = OpenstudioStandards::Geometry.model_get_exterior_window_and_wall_area_by_orientation(model)['west_window']
    a_t = a_n + a_s + a_e + a_w

    return true if a_t.abs < 0.01

    # For prototypes SHGC_c assumed to be the building's weighted average SHGC
    shgc_c = shgc_a / a_t
    shgc_c = shgc_c.round(2)

    # West and East facing WWR
    wwr_w = OpenstudioStandards::Geometry.model_get_exterior_window_to_wall_ratio(model, cardinal_direction: 'W')
    wwr_e = OpenstudioStandards::Geometry.model_get_exterior_window_to_wall_ratio(model, cardinal_direction: 'E')

    # Calculate new SHGC for west and east facing fenestration;
    # Create new simple glazing object and assign it to all
    # West and East fenestration
    #
    # Exception 5 is applied when applicable
    shgc_w = 0
    shgc_e = 0

    # Determine requirement criteria
    case climate_zone
      when 'ASHRAE 169-2006-0A',
           'ASHRAE 169-2006-0B',
           'ASHRAE 169-2006-1A',
           'ASHRAE 169-2006-1B',
           'ASHRAE 169-2006-2A',
           'ASHRAE 169-2006-2B',
           'ASHRAE 169-2006-3A',
           'ASHRAE 169-2006-3B',
           'ASHRAE 169-2006-3C',
           'ASHRAE 169-2013-0A',
           'ASHRAE 169-2013-0B',
           'ASHRAE 169-2013-1A',
           'ASHRAE 169-2013-1B',
           'ASHRAE 169-2013-2A',
           'ASHRAE 169-2013-2B',
           'ASHRAE 169-2013-3A',
           'ASHRAE 169-2013-3B',
           'ASHRAE 169-2013-3C'
        criteria = 4
      when 'ASHRAE 169-2006-4A',
           'ASHRAE 169-2006-4B',
           'ASHRAE 169-2006-4C',
           'ASHRAE 169-2006-5A',
           'ASHRAE 169-2006-5B',
           'ASHRAE 169-2006-5C',
           'ASHRAE 169-2006-6A',
           'ASHRAE 169-2006-6B',
           'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B',
           'ASHRAE 169-2013-4A',
           'ASHRAE 169-2013-4B',
           'ASHRAE 169-2013-4C',
           'ASHRAE 169-2013-5A',
           'ASHRAE 169-2013-5B',
           'ASHRAE 169-2013-5C',
           'ASHRAE 169-2013-6A',
           'ASHRAE 169-2013-6B',
           'ASHRAE 169-2013-7A',
           'ASHRAE 169-2013-7B',
           'ASHRAE 169-2013-8A',
           'ASHRAE 169-2013-8B'
        criteria = 5
      else
        return false
    end

    if !((a_w <= a_t / criteria) && (a_e <= a_t / criteria))
      # Calculate new SHGC
      if wwr_w > 0.2
        shgc_w = a_t * shgc_c / (criteria * a_w)
      end
      if wwr_e > 0.2
        shgc_e = a_t * shgc_c / (criteria * a_w)
      end

      # No SHGC adjustment needed
      return true if shgc_w == 0 && shgc_e == 0

      model.getSpaces.each do |space|
        # Get thermal zone multiplier
        multiplier = space.thermalZone.get.multiplier

        space.surfaces.each do |surface|
          # Proceed only for East and West facing surfaces that are required
          # to have their SHGC adjusted
          next unless (OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'W' && shgc_w > 0) ||
                      (OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'E' && shgc_e > 0)

          surface.subSurfaces.each do |subsurface|
            # Get window subsurface type
            subsurface_type = subsurface.subSurfaceType.to_s.downcase

            # Window, glass doors
            next unless (subsurface_type.include? 'window') || (subsurface_type.include? 'glass')

            new_shgc = OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'W' ? shgc_w : shgc_e
            new_shgc = new_shgc.round(2)

            # Get construction/simple glazing associated with the subsurface
            subsurface_org_cons = subsurface.construction.get.to_Construction.get
            subsurface_org_cons_mat = subsurface_org_cons.layers[0].to_SimpleGlazing.get

            # Only proceed if new SHGC is different than orignal one
            next unless (new_shgc - subsurface_org_cons_mat.solarHeatGainCoefficient).abs > 0

            # Clone construction/simple glazing associated with the subsurface
            subsurface_new_cons = subsurface_org_cons.clone(model).to_Construction.get
            subsurface_new_cons.setName("#{subsurface.name} Wind Cons U-#{OpenStudio.convert(subsurface_org_cons_mat.uFactor, 'W/m^2*K', 'Btu/ft^2*h*R').get.round(2)} SHGC #{new_shgc}")
            subsurface_new_cons_mat = subsurface_org_cons_mat.clone(model).to_SimpleGlazing.get
            subsurface_new_cons_mat.setName("#{subsurface.name} Wind SG Mat U-#{OpenStudio.convert(subsurface_org_cons_mat.uFactor, 'W/m^2*K', 'Btu/ft^2*h*R').get.round(2)} SHGC #{new_shgc}")
            subsurface_new_cons_mat.setSolarHeatGainCoefficient(new_shgc)
            new_layers = OpenStudio::Model::MaterialVector.new
            new_layers << subsurface_new_cons_mat
            subsurface_new_cons.setLayers(new_layers)

            # Assign new construction to sub surface
            subsurface.setConstruction(subsurface_new_cons)
          end
        end
      end
    end

    return true
  end

  # Is transfer air required?
  # @note code_sections [90.1-2019_6.5.7.1]
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if transfer air is required, false if not
  def model_transfer_air_required?(model)
    return true
  end

  # Metal coiling door code minimum infiltration rate at 75 Pa
  # @note code_sections [90.1-2019_5.4.3.2]
  #
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Double] Minimum infiltration rate for metal coiling doors
  def model_door_infil_flow_rate_metal_coiling_cfm_ft2(climate_zone)
    case climate_zone
      when 'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B',
           'ASHRAE 169-2013-7A',
           'ASHRAE 169-2013-7B',
           'ASHRAE 169-2013-8A',
           'ASHRAE 169-2013-8B'
        return 0.4
      else
        return 1.0
    end
  end

  # Implement occupancy based lighting level threshold (0.02 W/sqft). This is only for ASHRAE 90.1 2016 onwards.
  # @note code_sections [90.1-2016_9.4.1.1.h/i]
  # @author Xuechen (Jerry) Lei, PNNL
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # @return [Boolean] returns true if successful, false if not
  def model_add_lights_shutoff(model)
    zones = model.getThermalZones
    num_zones = 0
    business_sch_name = prototype_input['business_schedule']
    return if business_sch_name.nil? # This is only for 10 prototypes that do not have continuous operation.

    # Add business schedule
    model_add_schedule(model, business_sch_name)

    # Add EMS object for business schedule variable
    business_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
    business_sensor.setKeyName(business_sch_name)
    business_sensor.setName('Business_Sensor')
    business_sensor_name = business_sensor.name.to_s

    space_types_affected = []
    zones.sort.each do |zone|
      spaces = zone.spaces
      if spaces.length != 1
        puts 'warning, there are more than one spaces in the zone, need to confirm the implementation'
      end
      space = spaces[0]
      space_lights = space.lights
      lights_defined_by_spacetype = false
      if space_lights.empty?
        space_lights = space.spaceType.get.lights
        lights_defined_by_spacetype = true
        space_types_affected << space.spaceType
      end
      space_people = space.people
      if space_people.empty?
        space_people = space.spaceType.get.people
      end

      # guard clause to skip space with no lights
      next if space_lights.empty?

      # if lights are defined at the space type level, clone each lights object and make it individual to the space
      new_space_lights = []
      if lights_defined_by_spacetype
        space_lights.each do |lights|
          new_lights = lights.clone.to_Lights.get
          new_lights.setName("#{space.name}-#{lights.name}")
          new_lights.setSpace(space)
          new_space_lights << new_lights
        end
        space_lights = new_space_lights
      end

      zone_name = zone.name.to_s
      next if zone_name =~ /data\s*center/i # skip data centers

      # EnergyPlus v9.4.0 / OpenStudio v3.1.0 variable name change from 'Zone Lights Electric Power' to 'Zone Lights Electricity Rate'
      # EnergyPlus v9.6.0 / OpenStudio v3.3.0 added Space objects, variable name change from 'Zone Lights Electricity Rate' to 'Space Lights Electricity Rate'
      # https://github.com/NREL/OpenStudio/pull/4104
      if model.version < OpenStudio::VersionString.new('3.1.0')
        light_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Lights Electric Power')
        key_name = zone_name
      elsif model.version < OpenStudio::VersionString.new('3.3.0')
        light_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Lights Electricity Rate')
        key_name = zone_name
      else
        light_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Space Lights Electricity Rate')
        key_name = space.name.to_s
      end
      light_sensor.setKeyName(key_name)
      light_sensor_name_ems = "#{OpenstudioStandards::HVAC.ems_friendly_name(key_name)}_LSr"
      light_sensor.setName(light_sensor_name_ems)

      # get the space floor area for calculations
      space_floor_area = space.floorArea

      # account for multiple lights (also work for single light)
      big_light = space_lights[0] # find the light with highest power (assuming specified by watts/area)
      space_lights.each do |light_x|
        big_light_power = big_light.definition.to_LightsDefinition.get.wattsperSpaceFloorArea.to_f
        light_x_power = light_x.definition.to_LightsDefinition.get.wattsperSpaceFloorArea.to_f
        if light_x_power > big_light_power
          big_light = light_x
        end
      end

      add_lights_prog_0 = ''
      add_lights_prog_null = ''
      light_id = 0
      space_lights.each do |light_x|
        light_id += 1
        # EnergyPlus v9.4 name change for EMS actuators
        # https://github.com/NREL/OpenStudio/pull/4104
        if model.version < OpenStudio::VersionString.new('3.1.0')
          light_x_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(light_x, 'Lights', 'Electric Power Level')
        else
          light_x_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(light_x, 'Lights', 'Electricity Rate')
        end
        light_x_actuator_name_ems = "#{OpenstudioStandards::HVAC.ems_friendly_name(key_name)}_Light#{light_id}_Actuator"
        light_x_actuator.setName(light_x_actuator_name_ems)
        add_lights_prog_null += "\n      SET #{light_x_actuator_name_ems} = NULL,"
        if light_x == big_light
          add_lights_prog_0 += "\n      SET #{light_x_actuator_name_ems} = 0.02*#{space_floor_area}/0.09290304,"
          next
        end
        add_lights_prog_0 += "\n      SET #{light_x_actuator_name_ems} = 0,"
      end

      light_ems_prog = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      light_ems_prog.setName("SET_#{OpenstudioStandards::HVAC.ems_friendly_name(key_name)}_Light_EMS_Program")
      light_ems_prog_body = <<-EMS
      SET #{light_sensor_name_ems}_IP=0.093*#{light_sensor_name_ems}/#{space_floor_area},
      IF (#{business_sensor_name} <= 0) && (#{light_sensor_name_ems}_IP >= 0.02),#{add_lights_prog_0}
      ELSE,#{add_lights_prog_null}
      ENDIF
      EMS
      light_ems_prog.setBody(light_ems_prog_body)

      light_ems_prog_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
      light_ems_prog_manager.setName("SET_#{OpenstudioStandards::HVAC.ems_friendly_name(key_name)}_Light_EMS_Program_Manager")
      light_ems_prog_manager.setCallingPoint('AfterPredictorAfterHVACManagers')
      light_ems_prog_manager.addProgram(light_ems_prog)
    end

    # remove lights at the space type level
    space_types_affected.each do |space_type|
      space_type.get.lights.each(&:remove)
    end

    return true
  end
end
