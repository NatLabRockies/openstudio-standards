# BTAP Deprecated
#
# 2026-07-09
# This file will house methods that aren't used inside OpenStudio Standards.
# NRCan task 486 involves cleaning up unused code, however since OpenStudio
# Standards is a library, other people could be using these methods despite them
# not being used inside this repository. For now, they are marked as deprecated
# unless someone expresses otherwise. If there are no concerns these methods
# will soon be removed for the purpose of making developer operations simpler.

module BTAP
  module Deprecated
    def self.msg(klass, method_name)
      warn("[BTAP::Deprecated] #{klass}##{method_name} is considered for " \
           "deletion for the future as of July 2026. If you are still using" \
           "this method, please contact" \
           "nicholas.pneumaticos@nrcan-rncan.gc.ca.")
    end
  end # module Deprecated

  module Geometry
    def self.enumerate_spaces_model(model, prepend_name = false)
      #enumerate stories.
      BTAP::Geometry::BuildingStoreys::auto_assign_spaces_to_stories(model)
      #Enumerate spaces
      model.getBuildingStorys.sort.each do |story|
        spaces = Array.new
        spaces.concat(story.spaces)
        spaces.sort! do |a, b|
          (a.xOrigin <=> b.xOrigin).nonzero? ||
              (a.yOrigin <=> b.yOrigin)
        end
        counter = 1
        spaces.sort.each do |space|
          #puts "old space name : #{space.name}"
          if prepend_name == true
            space.setName("#{story.name}-#{counter.to_s}:#{space.name}")
          else
            space.setName("#{story.name}-#{counter.to_s}")
          end
          counter = counter + 1
          p #uts "new space name : #{space.name}"
        end
      end
    end

    # this was a copy of the sketchup plugin method.
    def self.rename_zones_based_on_spaces(model)

      # loop through thermal zones
      model.getThermalZones.sort.each do |thermal_zone| # this is going through all, not just selection
        #puts "old zone name : #{thermal_zone.name}"
        # reset the array of spaces to be empty
        spaces_in_thermal_zone = []
        # reset length of array of spaces
        number_of_spaces = 0

        # get list of spaces in thermal zone
        spaces = thermal_zone.spaces
        spaces.sort.each do |space|

          # make an array instead of the puts statement
          spaces_in_thermal_zone.push space.name.to_s

        end

        # store length of array
        number_of_spaces = spaces_in_thermal_zone.size

        # sort the array
        spaces_in_thermal_zone = spaces_in_thermal_zone.sort

        # setup a suffix if the thermal zone contains more than one space
        if number_of_spaces > 1
          multi = " - Plus"
        else
          multi = ""
        end

        # rename thermal zone based on first space with prefix added e.g. ThermalZone 203
        if number_of_spaces > 0
          new_name = "ZN:" + spaces_in_thermal_zone[0] + multi
          thermal_zone.setName(new_name)
        else
          puts "#{thermal_zone.name.to_s} did not have any spaces, and will not be renamed."
        end
        #puts "new zone name : #{thermal_zone.name}"
      end
    end

    #This method will rename the zone equipment to have the zone name as a prefix for a model.
    #It will also rename the hot water coils for:
    #    AirTerminalSingleDuctVAVReheat
    #    ZoneHVACBaseboardConvectiveWater
    #    ZoneHVACUnitHeater

    def self.prefix_equipment_with_zone_name(model)
      #puts "Renaming zone equipment."
      # get all thermal zones
      thermal_zones = model.getThermalZones

      # loop through thermal zones
      thermal_zones.each do |thermal_zone| # this is going through all, not just selection

        thermal_zone.equipment.each do |equip|

          #For the hydronic conditions below only, it will rename the zonal coils as well.
          if not equip.to_AirTerminalSingleDuctVAVReheat.empty?

            equip.setName("#{thermal_zone.name}:AirTerminalSingleDuctVAVReheat")
            reheat_coil = equip.to_AirTerminalSingleDuctVAVReheat.get.reheatCoil
            reheat_coil.setName("#{thermal_zone.name}:ReheatCoil")
            #puts reheat_coil.name
          elsif not equip.to_ZoneHVACBaseboardConvectiveWater.empty?
            equip.setName("#{thermal_zone.name}:ZoneHVACBaseboardConvectiveWater")
            heatingCoil = equip.to_ZoneHVACBaseboardConvectiveWater.get.heatingCoil
            heatingCoil.setName("#{thermal_zone.name}:Baseboard HW Htg Coil")
            #puts heatingCoil.name
          elsif not equip.to_ZoneHVACUnitHeater.empty?
            equip.setName("#{thermal_zone.name}:ZoneHVACUnitHeater")
            heatingCoil = equip.to_ZoneHVACUnitHeater.get.heatingCoil
            heatingCoil.setName("#{thermal_zone.name}:Unit Heater Htg Coil")
            #puts heatingCoil.name
            #Add more cases if you wish!!!!!
          else #if the equipment does not follow the above cases, rename
            # it generically and not touch the underlying coils, etc.
            equip.setName("#{thermal_zone.name}:#{equip.name}")
          end

        end
      end
    end

    module BuildingStoreys
      #This method will delete any exisiting stories and then try to assign stories based on
      # the z-axis origin of the space.
      def self.auto_assign_spaces_to_stories(model)
        #delete existing stories.
        model.getBuildingStorys.sort.each {|buildingstory| buildingstory.remove}
        #create hash of building storeys, index is the Z-axis origin of the space.
        building_story_hash = Hash.new()
        model.getSpaces.sort.each do |space|
          if building_story_hash[space.zOrigin].nil?
            building_story_hash[space.zOrigin] = OpenStudio::Model::BuildingStory.new(model)
            building_story_hash[space.zOrigin].setName(building_story_hash.length.to_s)
          end


          space.setBuildingStory(building_story_hash[space.zOrigin])
        end
      end

      # override run to implement the functionality of your script
      # model is an OpenStudio::Model::Model, runner is a OpenStudio::Ruleset::UserScriptRunner
      def self.auto_assign_stories(model)

        # get all spaces
        spaces = model.getSpaces

        #puts("Assigning Stories to Spaces")

        # make has of spaces and minz values
        sorted_spaces = Hash.new
        spaces.sort.each do |space|
          # loop through space surfaces to find min z value
          z_points = []
          space.surfaces.each do |surface|
            surface.vertices.each do |vertex|
              z_points << vertex.z
            end
          end
          minz = z_points.min + space.zOrigin
          sorted_spaces[space] = minz
        end

        # pre-sort spaces
        sorted_spaces = sorted_spaces.sort {|a, b| a[1] <=> b[1]}


        # this should take the sorted list and make and assign stories
        sorted_spaces.sort.each do |space|
          space_obj = space[0]
          space_minz = space[1]
          if space_obj.buildingStory.empty?
            story = OpenstudioStandards::Geometry.model_get_building_story_for_nominal_height(model, space_minz)
            if story.nil?
              story = OpenStudio::Model::BuildingStory.new(model)
              story.setNominalZCoordinate(space_minz)
              story.setName("Building Story #{space_minz.round(1)}m")
            end
            space_obj.setBuildingStory(story)
          end
        end
      end
    end # module BuildingStoreys

    #This module contains helper functions that deal with Space objects.
    module Spaces

      # This method will return the horizontal placement type. (N,S,W,E,C) In the
      # case of a corner, it will take whatever surface area it faces is the
      # largest. It will also return the top, bottom or middle conditions.
      def self.get_space_placement(space)
        horizontal_placement = nil
        vertical_placement = nil
        json_data = nil

        #get all exterior surfaces.
        surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces,
                                                                          ["Outdoors",
                                                                           "Ground",
                                                                           "GroundFCfactorMethod",
                                                                           "GroundSlabPreprocessorAverage",
                                                                           "GroundSlabPreprocessorCore",
                                                                           "GroundSlabPreprocessorPerimeter",
                                                                           "GroundBasementPreprocessorAverageWall",
                                                                           "GroundBasementPreprocessorAverageFloor",
                                                                           "GroundBasementPreprocessorUpperWall",
                                                                           "GroundBasementPreprocessorLowerWall"])

        #exterior Surfaces
        ext_wall_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["Wall"])
        ext_bottom_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["Floor"])
        ext_top_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["RoofCeiling"])

        #Interior Surfaces..if needed....
        internal_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, ["Surface"])
        int_wall_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["Wall"])
        int_bottom_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["Floor"])
        int_top_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["RoofCeiling"])


        vertical_placement = "NA"
        #determine if space is a top or bottom, both or middle space.
        if ext_bottom_surface.size > 0 and ext_top_surface.size > 0 and int_bottom_surface.size == 0 and int_top_surface.size == 0
          vertical_placement = "single_story_space"
        elsif int_bottom_surface.size > 0 and ext_top_surface.size > 0 and int_bottom_surface.size > 0
          vertical_placement = "top"
        elsif ext_bottom_surface.size > 0 and ext_top_surface.size == 0
          vertical_placement = "bottom"
        elsif ext_bottom_surface.size == 0 and ext_top_surface.size == 0
          vertical_placement = "middle"
        end


        #determine if what cardinal direction has the majority of external
        #surface area of the space.
        #set this to 'core' by default and change it if it is found to be a space exposed to a cardinal direction.
        horizontal_placement = nil
        #set up summing hashes for each direction.
        json_data = Hash.new
        walls_area_array = Hash.new
        subsurface_area_array = Hash.new
        boundary_conditions = {}
        boundary_conditions[:outdoors] = ["Outdoors"]
        boundary_conditions[:ground] = [
            "Ground",
            "GroundFCfactorMethod",
            "GroundSlabPreprocessorAverage",
            "GroundSlabPreprocessorCore",
            "GroundSlabPreprocessorPerimeter",
            "GroundBasementPreprocessorAverageWall",
            "GroundBasementPreprocessorAverageFloor",
            "GroundBasementPreprocessorUpperWall",
            "GroundBasementPreprocessorLowerWall"]
        #go through all directions.. need to do north twice since that goes around zero degree mark.
        orientations = [
            {:surface_type => 'Wall', :direction => 'north', :azimuth_from => 0.00, :azimuth_to => 45.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'Wall', :direction => 'north', :azimuth_from => 315.001, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'Wall', :direction => 'east', :azimuth_from => 45.001, :azimuth_to => 135.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'Wall', :direction => 'south', :azimuth_from => 135.001, :azimuth_to => 225.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'Wall', :direction => 'west', :azimuth_from => 225.001, :azimuth_to => 315.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'RoofCeiling', :direction => 'top', :azimuth_from => 0.0, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0},
            {:surface_type => 'Floor', :direction => 'bottom', :azimuth_from => 0.0, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0}
        ]
        [:outdoors, :ground].each do |bc|
          orientations.each do |orientation|
            walls_area_array[orientation[:direction]] = 0.0
            subsurface_area_array[orientation[:direction]] = 0.0
            json_data[orientation[:direction]] = {} if json_data[orientation[:direction]].nil?
            json_data[orientation[:direction]][bc] = {:surface_area => 0.0,
                                                      :glazed_subsurface_area => 0.0,
                                                      :opaque_subsurface_area => 0.0}

          end
        end

        [:outdoors, :ground].each do |bc|
          orientations.each do |orientation|
            # puts "bc= #{bc}"
            # puts boundary_conditions[bc.to_sym]
            # puts boundary_conditions
            surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, boundary_conditions[bc])
            selected_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, [orientation[:surface_type]])
            BTAP::Geometry::Surfaces::filter_by_azimuth_and_tilt(selected_surfaces, orientation[:azimuth_from], orientation[:azimuth_to], orientation[:tilt_from], orientation[:tilt_to]).each do |surface|
              #sum wall area and subsurface area by direction. This is the old way so excluding top and bottom surfaces.
              walls_area_array[orientation[:direction]] += surface.grossArea unless ['RoofCeiling', 'Floor'].include?(orientation[:surface_type])
              subsurface_area_array[orientation[:direction]] += surface.subSurfaces.map {|subsurface| subsurface.grossArea}.inject(0) {|sum, x| sum + x}
              json_data[orientation[:direction]][bc][:surface_area] += surface.grossArea
              glazings = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["FixedWindow", "OperableWindow", "GlassDoor", "Skylight", "TubularDaylightDiffuser", "TubularDaylightDome"])
              doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["Door", "OverheadDoor"])
              json_data[orientation[:direction]][bc][:glazed_subsurface_area] += glazings.map {|subsurface| subsurface.grossArea}.inject(0) {|sum, x| sum + x}
              json_data[orientation[:direction]][bc][:opaque_subsurface_area] += doors.map {|subsurface| subsurface.grossArea}.inject(0) {|sum, x| sum + x}
            end
          end
        end
        puts JSON.pretty_generate(json_data)

        puts walls_area_array
        #find if no direction
        sum= 0.0
        ['north','east','south','west'].each do |direction|
          [:outdoors,:ground].each do |bc|
            sum += json_data[direction][bc][:surface_area]
          end
        end
        if sum == 0.0
          horizontal_placement = "core"
        else
          #find our which cardinal direction has the most exterior surface and declare it that orientation.
          horizontal_placement = walls_area_array.max_by {|k, v| v}[0] #include ext and ground.
        end

        #save JSON data
        json_data = ({:horizontal_placement => horizontal_placement,
                      :vertical_placement => vertical_placement,
        }).merge(json_data)
        puts JSON.pretty_generate(json_data)

        return json_data
      end

      def self.is_perimeter_space?(model, space)
        exterior_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(
          space.surfaces,
          ["Outdoors",
           "Ground",
           "GroundFCfactorMethod",
           "GroundSlabPreprocessorAverage",
           "GroundSlabPreprocessorCore",
           "GroundSlabPreprocessorPerimeter",
           "GroundBasementPreprocessorAverageWall",
           "GroundBasementPreprocessorAverageFloor",
           "GroundBasementPreprocessorUpperWall",
           "GroundBasementPreprocessorLowerWall"])

        return BTAP::Geometry::Surfaces::filter_by_surface_types(exterior_surfaces, ["Wall"]).size > 0
      end

      def self.show(model, space)
        if drawing_interface = BTAP::Common::validate_array(model, space, "Space").first.drawing_interface
          if entity = drawing_interface.entity
            entity.visible = true
          end
        end
      end

      def self.hide(model, space)
        if drawing_interface = BTAP::Common::validate_array(model, space, "Space").first.drawing_interface
          if entity = drawing_interface.entity
            entity.visible = false
          end
        end
      end

      # This method will filter an array of spaces that have an external wall
      # passed floors. Note: if you wish to avoid to create an array of spaces,
      # simply put the space variable in [] brackets
      # Ex: get_all_surfaces_from_spaces( [space1,space2] )
      # @param spaces_array an array of type [OpenStudio::Model::Space]
      # @return an array of spaces.
      def self.filter_perimeter_spaces(model, spaces_array)
        spaces_array = BTAP::Common::validate_array(model, spaces_array, "Space")
        array = Array.new()
        spaces_array.each do |space|
          if space.is_a_perimeter_space?()
            array.push(space)
          end
        end
        return array
      end

      # This method will filter an array of spaces that have no external wall
      # passed floors. Note: if you wish to avoid to create an array of spaces,
      # simply put the space variable in [] brackets
      # Ex: get_all_surfaces_from_spaces( [space1,space2] )
      # @param spaces_array an array of type [OpenStudio::Model::Space]
      # @return an array of spaces.
      def self.filter_core_spaces(model, spaces_array)
        spaces_array = BTAP::Common::validate_array(model, spaces_array, "Space")
        array = Array.new()
        spaces_array.each do |space|
          unless space.is_a_perimeter_space?()
            array.push(space)
          end
        end
        return array
      end

      def self.filter_spaces_by_space_types(model, spaces_array, spacetype_array)
        spaces_array = BTAP::Common::validate_array(model, spaces_array, "Space")
        spacetype_array = BTAP::Common::validate_array(model, spacetype_array, "SpaceType")
        #validate space array
        returnarray = Array.new()
        spaces_array.each do |space|
          returnarray << spacetype_array.include?(space.spaceType())
        end
        return returnarray
      end
    end # module Spaces

    module Zones

      # This method will filter an array of zones that have an external wall
      # passed floors. Note: if you wish to avoid to create an array of spaces,
      # simply put the space variable in [] brackets
      # Ex: get_all_surfaces_from_spaces( [space1,space2] )
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] an array of zones
      # @return [Array<OpenStudio::Model::ThermalZone] an array of thermal zones.
      def self.filter_perimeter_zones(thermal_zones)
        array = Array.new()
        thermal_zones.each do |zone|
          zone.space.each do |space|
            if space.is_a_perimeter_space?()
              array.push(zone)
              next
            end
          end
        end
        return array
      end

      # This method will filter an array of zones that have no external wall
      # passed floors. Note: if you wish to avoid to create an array of spaces,
      # simply put the space variable in [] brackets
      # Ex: ( [space1,space2] )
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone] an array of zones
      # @return [Array<OpenStudio::Model::ThermalZone] an array of zones
      def self.filter_core_zones(thermal_zones)
        array = Array.new()
        thermal_zones.getThermalZones.sort.each do |zone|
          zone.space.each do |space|
            if not space.is_a_perimeter_space?()
              array.push(zone)
              next
            end
          end
        end
        return array
      end
    end # module Zones

    module Surfaces
      def self.create_surface(model, name, os_point3d_array, boundary_condition = "", construction = "")
        os_surface = OpenStudio::Model::Surface.new(os_point3d_array, model)
        os_surface.setName(name)
        if OpenStudio::Model::Surface::validOutsideBoundaryConditionValues.include?(boundary_condition)
          self.set_surfaces_boundary_condition([os_surface], boundary_condition)
        else
          puts "boundary condition not set for #{name}"
        end
        os_surface.setConstruction(construction)
        return os_surface
      end

      # This method will rotate a surface
      # @param planar_surfaces [Array<OpenStudio::Model::Surface>] an array of surfaces
      # @param azimuth_degrees [Float] rotation value
      # @param tilt_degrees [Float] rotation value
      # @param translation_vector [OpenStudio::Vector3d] a vector along which to move all surfaces
      # @return [OpenStudio::Model::Model] the model object.
      def self.rotate_tilt_translate_surfaces(planar_surfaces, azimuth_degrees, tilt_degrees = 0.0, translation_vector = OpenStudio::Vector3d.new(0.0, 0.0, 0.0))
        # Identity matrix for setting space origins
        azimuth_matrix = OpenStudio::Transformation::rotation(OpenStudio::Vector3d.new(0, 0, 1), azimuth_degrees * Math::PI / 180)
        tilt_matrix = OpenStudio::Transformation::rotation(OpenStudio::Vector3d.new(0, 0, 1), tilt_degrees * Math::PI / 180)
        translation_matrix = OpenStudio::createTranslation(translation_vector)
        planar_surfaces.each do |surface|
          surface.changeTransformation(azimuth_matrix)
          surface.changeTransformation(tilt_matrix)
          surface.changeTransformation(translation_matrix)
        end
        return planar_surfaces
      end

      def self.set_fenestration_to_wall_ratio(surfaces, ratio, offset = 0, height_offset_from_floor = true, floor = "all")
        surfaces.each do |surface|
          result = surface.setWindowToWallRatio(ratio, offset, height_offset_from_floor)
          raise("Unable to set FWR for surface " +
                    surface.name.get.to_s +
                    " . Possible reasons are  if the surface is not a wall, if the surface
          is not rectangular in face coordinates, if requested ratio is too large
          (window area ~= surface area) or too small (min dimension of window < 1 foot),
          or if the window clips any remaining sub surfaces. Otherwise, removes all
          existing windows and adds new window to meet requested ratio.") unless result
        end
        return surfaces
      end

      def self.filter_by_non_defaulted_surfaces(surfaces)
        non_defaulted_surfaces = Array.new()
        surfaces.each {|surface| non_defaulted_surfaces << surface unless surface.isConstructionDefaulted}
        return non_defaulted_surfaces
      end

      def self.filter_by_interzonal_surface(surfaces)
        return_array = Array.new()
        surfaces.each do |surface|
          unless surface.adjacentSurface().empty?
            return_array.push(surface)
          end
          return return_array
        end
      end

      # Azimuth start from Y axis, Tilts starts from Z-axis
      def self.filter_by_azimuth_and_tilt(surfaces, azimuth_from, azimuth_to, tilt_from, tilt_to, tolerance = 1.0)
        return_surfaces = []
        surfaces.each do |surface|
          unless OpenStudio::Model::PlanarSurface::findPlanarSurfaces([surface], OpenStudio::OptionalDouble.new(azimuth_from), OpenStudio::OptionalDouble.new(azimuth_to), OpenStudio::OptionalDouble.new(tilt_from), OpenStudio::OptionalDouble.new(tilt_to), tolerance).empty?
            return_surfaces << surface
          end
        end
        return return_surfaces
      end

      def self.show(surfaces)
        surfaces.each do |surface|
          if drawing_interface = surface.drawing_interface
            if entity = drawing_interface.entity
              entity.visible = false
            end
          end
        end
      end

      def self.hide(surfaces)
        surfaces.each do |surface|
          if drawing_interface = surface.drawing_interface
            if entity = drawing_interface.entity
              entity.visible = false
            end
          end
        end
      end
    end # module Surfaces
  end # module Geometry

  module Schedules
    module Fraction
      def self.always_off(model)
        fraction_always_off_name = "FRACTION_ALWAYS_OFF"
        schedule = model.getScheduleRulesetByName(fraction_always_off_name)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
            fraction_always_off_name,
            "FRACTION",
            0.0)
        else
          return schedule.get
        end
      end

      def self.always_on(model)
        fraction_always_on_name  = "FRACTION_ALWAYS_ON"
        schedule = model.getScheduleRulesetByName(fraction_always_on_name)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
            model,
            fraction_always_on_name,
            "FRACTION",
            1.0)
        else
          return schedule.get
        end
      end
    end # module Fraction

    module ON_OFF
      def self.always_on(model)
        on_off_always_on   = "ON_OFF_ALWAYS_ON"
        schedule = model.getScheduleRulesetByName(on_off_always_on)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
            model,
            on_off_always_on,
            "ON_OFF",
            1)
        else
          return schedule.get
        end
      end
    end # module ON_OFF

    module Temperature
      def self.no_heating(model)
        no_heating = "NO_HEATING_SETPOINT"
        schedule = model.getScheduleRulesetByName(no_heating)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
            model,
            no_heating,
            "TEMPERATURE",
            -200.0)
        else
          return schedule.get
        end
      end

      def self.no_cooling(model)
        no_cooling = "NO_COOLING_SETPOINT"
        schedule = model.getScheduleRulesetByName(no_cooling)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
            model,
            no_cooling,
            "TEMPERATURE",
            200.0)
        else
          return schedule.get
        end
      end

      def self.no_heating_cooling_dual_setpoint_schedule(model)
        dual_setpoint_name = "FREE_FLOATING_DUAL_SETPOINT_THERMOSTAT"
        schedule = model.getScheduleRulesetByName(dual_setpoint_name)
        if schedule.empty?
          #create Schedule
          return BTAP::Resources::Schedules::create_annual_thermostat_setpoint_dual_setpoint( model, dual_setpoint_name, self.heating_setpoint_off, self.cooling_setpoint_off)
        else
          return schedule.getThermostatSetpointDualSetpointByName()
        end
      end
    end # module Temperature

    def self.remove_all_schedules(model)
      model.getScheduleBases.sort.each { |item| item.remove }
    end

    def self.create_zonal_occupancy_schedule_on_off(model, thermal_zone)
      model.getFanZoneExhausts.sort.each {|zfe| puts "Fan Ex:#{zfe}"}

      # Create new timeseries object to keep track of on/off states. Default to 30min intervals.
      timeseries  = OpenStudio::TimeSeries.new
      thermal_zone.spaces.sort.each do |space|
        #Iterate through the people object in the space.
        space.spaceType.get.people.each do |people|
          if people.numberofPeopleSchedule.is_initialized() and people.numberofPeopleSchedule.get.to_ScheduleRuleset.is_initialized
            #Get the occupancy schedule.
            occ_schedule = people.numberofPeopleSchedule.get
            #Convert schedule to timeseries and sum up timeseries objects for this space / zone.
            occ_time_series = create_timeseries_from_schedule_ruleset(model,occ_schedule)
            timeseries = timeseries + occ_time_series
          end
        end
      end
      # Return the timeseries converted to
      return create_schedule_variable_interval_from_time_series(model,timeseries)
    end

    # This method will only work with a single occupancy definition.
    def self.set_exhaust_fans_availability_to_building_default_occ_schedule(model)
      # get occupancy schedule if possible.
      if  model.building.get.defaultScheduleSet.is_initialized and
          model.building.get.defaultScheduleSet.get.numberofPeopleSchedule.is_initialized and
          model.building.get.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.is_initialized
        occ_schedule = model.building.get.defaultScheduleSet.get.numberofPeopleSchedule.get
        #get building default occupancy schedule.
        model.getFanZoneExhausts.sort.each do |zfe|
          zfe.setAvailabilitySchedule(occ_schedule)
          zfe.setBalancedExhaustFractionSchedule(occ_schedule)
        end
      else
        raise ("Default occupancy schedule has not been set in model! Unsure what to set exhaust fans to. Exiting.")
      end
      return model.getFanZoneExhausts
    end

    def self.modify_schedule(model, schedule_ruleset, a_coef = 0.0 ,b_coef = 0.0 ,c_coef= 0.0 ,time_shift = nil,time_sign = nil)
      new_schedule = schedule_ruleset.clone( model ).to_ScheduleRuleset.get
      self.modify_schedule!(model, new_schedule, a_coef,b_coef,c_coef ,time_shift,time_sign)
    end

    def self.modify_schedule!(model, schedule_ruleset, a_coef = 0.0 ,b_coef = 0.0 ,c_coef= 0.0 ,time_shift = nil,time_sign = nil)
      schedule_ruleset.scheduleRules.each do |week_rule|
        day_rule = week_rule.daySchedule()
        times = day_rule.times()
        times.each do |time|
          old_value = day_rule.getValue(time)
          day_rule.removeValue(time)
          new_value = "error"
          new_time = "error"
          #set the new value according to Ax2+Bx+C.
          new_value = a_coef * old_value ** 2.0 + b_coef * old_value + c_coef
          unless time_shift.nil? or time_sign.nil?
            command = "new_time = time #{time_sign} #{BTAP::Common::get_time_from_string(time_shift)}"
            eval(command)
            #make sure time is not past 24 hours.
            new_time = new_time - BTAP::Common::get_time_from_string("24:00") if new_time > BTAP::Common::get_time_from_string("24:00")
          end
          day_rule.addValue(time, new_value)
        end
      end
    end

    def self.create_availability_schedule_based_on_another_schedule(model, occupancy_schedule, threshold = 0.05)
      #create new On-Off schedule ruleset.
      availability_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      availability_ruleset.setName("availabilty_based_on_occupancy")
      #iterate though all rules.
      occupancy_schedule.scheduleRules.each do |occ_rule|
        #Create new hourly rule to populate availability schedule hourly data.
        hourly_data = OpenStudio::Model::ScheduleDay.new(model)
        #set schedule type to availabilty.
        hourly_data.setScheduleTypeLimits(BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_on_off(model))
        #iterate though hour / value pairs for 24 hour period.
        occ_rule.daySchedule().times().each do |time|
          #check if time value is greater or equal to the threshold. If true set hour value to 1, else 0.
          occ_rule.daySchedule().getValue(time) >= threshold ? hourly_data.addValue(time, 1.0) : hourly_data.addValue(time, 0.0)
        end
        #create new rule with hourly data and add to availablity ruleset.
        avail_rule = OpenStudio::Model::ScheduleRule.new(availability_ruleset,hourly_data)
        #Set same start and end date.
        avail_rule.setStartDate(occ_rule.getStartDate)
        avail_rule.setEndDate(occ_rule.getEndDate)
      end #loop occ_rule
      #Make sure to set the default schedule to be the same as well.
      avail_default_day = availability_ruleset.defaultDaySchedule()
      avail_default_day.clearValues()
      #iterate though hour / value pairs for 24 hour period.
      occupancy_schedule.defaultDaySchedule().times().each do |time|
        #check if time value is greater or equal to the threshold. If true set hour value to 1, else 0.
        occupancy_schedule.defaultDaySchedule().getValue(time) >= threshold ? avail_default_day.addValue(time, 1.0) : avail_default_day.addValue(time, 0.0)
      end
      return availability_ruleset
    end


    def self.create_setback_schedule_based_on_another_schedule(
        model,
        occupancy_schedule,
        threshold = 0.05,
        heat_setpoint = 22.0,
        heat_setback = 17.0,
        cool_setpoint = 24.0,
        cool_setback =99.0)
      #create new On-Off schedule ruleset.
      heating_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      heating_ruleset.setName("heat_thermostat_based_on_occupancy")
      cooling_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      cooling_ruleset.setName("cool_thermostat_based_on_occupancy")
      #iterate though all rules.
      occupancy_schedule.to_ScheduleRuleset.get.scheduleRules.each do |occ_rule|
        #Create new hourly rule to populate heat/cold schedule hourly data.
        heating_hourly_data = OpenStudio::Model::ScheduleDay.new(model)
        cooling_hourly_data = OpenStudio::Model::ScheduleDay.new(model)
        #set schedule type to availabilty.
        heating_hourly_data.setScheduleTypeLimits(BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_temperature(model))
        cooling_hourly_data.setScheduleTypeLimits(BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_temperature(model))
        #iterate though hour / value pairs for 24 hour period.
        occ_rule.daySchedule().times().each do |time|
          #check if time value is greater or equal to the threshold. If true set hour value to 1, else 0.
          occ_rule.daySchedule().getValue(time) >= threshold ? heating_hourly_data.addValue(time, heat_setpoint) : heating_hourly_data.addValue(time,heat_setback)
          occ_rule.daySchedule().getValue(time) >= threshold ? cooling_hourly_data.addValue(time, cool_setpoint) : cooling_hourly_data.addValue(time,cool_setback)
        end
        #create new rule with hourly data and add to availablity ruleset.
        heating_avail_rule = OpenStudio::Model::ScheduleRule.new(heating_ruleset,heating_hourly_data)
        cooling_avail_rule = OpenStudio::Model::ScheduleRule.new(cooling_ruleset,cooling_hourly_data)
        #Set same start and end date.
        heating_avail_rule.setStartDate(occ_rule.startDate.get)
        heating_avail_rule.setEndDate(occ_rule.endDate.get)
        cooling_avail_rule.setStartDate(occ_rule.startDate.get)
        cooling_avail_rule.setEndDate(occ_rule.endDate.get)
        #set days enforced.
        heating_avail_rule.setApplySunday(occ_rule.applySunday)
        heating_avail_rule.setApplyMonday(occ_rule.applyMonday)
        heating_avail_rule.setApplyTuesday(occ_rule.applyTuesday)
        heating_avail_rule.setApplyWednesday(occ_rule.applyWednesday)
        heating_avail_rule.setApplyThursday(occ_rule.applyThursday)
        heating_avail_rule.setApplyFriday(occ_rule.applyFriday)
        heating_avail_rule.setApplySaturday(occ_rule.applySaturday)

        cooling_avail_rule.setApplySunday(occ_rule.applySunday)
        cooling_avail_rule.setApplyMonday(occ_rule.applyMonday)
        cooling_avail_rule.setApplyTuesday(occ_rule.applyTuesday)
        cooling_avail_rule.setApplyWednesday(occ_rule.applyWednesday)
        cooling_avail_rule.setApplyThursday(occ_rule.applyThursday)
        cooling_avail_rule.setApplyFriday(occ_rule.applyFriday)
        cooling_avail_rule.setApplySaturday(occ_rule.applySaturday)


      end #loop occ_rule
      #Make sure to set the default schedule to be the same as well.
      heating_default_day = heating_ruleset.defaultDaySchedule()
      heating_default_day.clearValues()
      cooling_default_day = cooling_ruleset.defaultDaySchedule()
      cooling_default_day.clearValues()

      #iterate though hour / value pairs for 24 hour period.
      occupancy_schedule.to_ScheduleRuleset.get.defaultDaySchedule().times().each do |time|
        #check if time value is greater or equal to the threshold. If true set hour value to 1, else 0.
        occupancy_schedule.to_ScheduleRuleset.get.defaultDaySchedule().getValue(time) >= threshold ? heating_default_day.addValue(time, heat_setpoint) : heating_default_day.addValue(time, heat_setback)
        occupancy_schedule.to_ScheduleRuleset.get.defaultDaySchedule().getValue(time) >= threshold ? cooling_default_day.addValue(time, cool_setpoint) : cooling_default_day.addValue(time, cool_setback)
      end
      return heating_ruleset,cooling_ruleset
    end

    #Sets all values in a schedule less than min_value to min_value.
    def self.apply_schedule_minimum(min_value,schedule)
      schedule_ruleset = schedule.to_ScheduleRuleset.get unless schedule.to_ScheduleRuleset.empty?
      schedule_ruleset.scheduleRules.each do |week_rule|
        day_rule = week_rule.daySchedule()
        times = day_rule.times()
        times.each do |time|
          old_value = day_rule.getValue(time).to_f
          day_rule.removeValue(time)
          new_value = old_value
          new_value = min_value if old_value < min_value
          day_rule.addValue(time, new_value)
        end
      end
    end

    #Sets all values in a schedule greater than max_value to max_value.
    def self.apply_schedule_maximum(max_value,schedule)
      schedule_ruleset = schedule.to_ScheduleRuleset.get unless schedule.to_ScheduleRuleset.empty?
      schedule_ruleset.scheduleRules.each do |week_rule|
        day_rule = week_rule.daySchedule()
        times = day_rule.times()
        times.each do |time|
          old_value = day_rule.getValue(time).to_f
          day_rule.removeValue(time)
          new_value = old_value
          new_value = max_value if old_value > max_value
          day_rule.addValue(time, new_value)
        end
      end
    end

    def self.create_annual_ruleset_schedule_detailed(model,name,type,schedule_struct  )
      #create new ruleset
      ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      ruleset.setName(name)
      default_day =  ruleset.defaultDaySchedule

      #set types limits
      scheduletype = ""
      case type.downcase
      when "FRACTION".downcase
        scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_fraction(model)
      when "ON_OFF".downcase
        scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_on_off(model)
      when "TEMPERATURE".downcase
        scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_temperature(model)
        # this will set the default day for temperatures to 23.5C
        default_day.clearValues()
        raise "unable to set ScheduleDay type limits" unless default_day.setScheduleTypeLimits(scheduletype)
        default_day.addValue(BTAP::Common::get_time_from_string( "24:00"), 23.5 )
      when "ACTIVITY".downcase
        scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_activity(model)
        # this will set the default day for temperatures to 23.5C
        default_day.clearValues()
        raise "unable to set ScheduleDay type limits" unless default_day.setScheduleTypeLimits(scheduletype)
        default_day.addValue(BTAP::Common::get_time_from_string( "24:00"), 120.0 )
      else
        #if schedule type could not be found raise an exception.
        raise "could  not find schedule limits type :" + type
      end

      #loop through each schedule ruleset.
      schedule_struct.each do |run_period_profile|
        start_end_dates = run_period_profile[0]
        days_of_the_week = run_period_profile[1]
        hourly_schedule =  run_period_profile[2]
        day_rule = OpenStudio::Model::ScheduleDay.new(model)
        day_rule.setName(  name )
        if not day_rule.setScheduleTypeLimits(scheduletype)
          raise "unable to set ScheduleDay type limits"
        end

        hourly_schedule.each do |hour|
          day_rule.addValue(BTAP::Common::get_time_from_string( hour[0]), hour[1] )
        end

        #create weekday rule
        week_rule = OpenStudio::Model::ScheduleRule.new(ruleset,day_rule)
        #Set Default to false
        week_rule.setApplySunday(false)
        week_rule.setApplyMonday(false)
        week_rule.setApplyTuesday(false)
        week_rule.setApplyWednesday(false)
        week_rule.setApplyThursday(false)
        week_rule.setApplyFriday(false)
        week_rule.setApplySaturday(false)
        # Now set actual days it is applied.
        week_rule.setApplySunday(true) if days_of_the_week.include?("Su") or days_of_the_week.include?("Wke") or days_of_the_week.include?("All")
        week_rule.setApplyMonday(true) if days_of_the_week.include?("M") or days_of_the_week.include?("Wkd") or days_of_the_week.include?("All")
        week_rule.setApplyTuesday(true) if days_of_the_week.include?("T") or days_of_the_week.include?("Wkd") or days_of_the_week.include?("All")
        week_rule.setApplyWednesday(true) if days_of_the_week.include?("W") or days_of_the_week.include?("Wkd") or days_of_the_week.include?("All")
        week_rule.setApplyThursday(true) if days_of_the_week.include?("Th") or days_of_the_week.include?("Wkd") or days_of_the_week.include?("All")
        week_rule.setApplyFriday(true) if days_of_the_week.include?("F") or days_of_the_week.include?("Wkd") or days_of_the_week.include?("All")
        week_rule.setApplySaturday(true) if days_of_the_week.include?("S") or days_of_the_week.include?("Wke") or days_of_the_week.include?("All")

        #Set Period Rule
        week_rule.setStartDate( BTAP::Common::get_date_from_string(start_end_dates[0] ) )
        week_rule.setEndDate( BTAP::Common::get_date_from_string(start_end_dates[1] ) )
      end
      return ruleset
    end

    def self.create_annual_fraction_ruleset_schedule(model,name,hourArrayValues)
      self.create_annual_ruleset_schedule(model,name,"FRACTION",hourArrayValues)
    end

    def self.create_annual_on_off_ruleset_schedule(model,name,hourArrayValues)
      self.create_annual_ruleset_schedule(model,name,"ON_OFF",hourArrayValues)
    end

    def self.create_annual_temperature_ruleset_schedule(model,name,hourArrayValues)
      self.create_annual_ruleset_schedule(model,name,"TEMPERATURE",hourArrayValues)
    end
  end # module Schedules

  # Deprecate all the methods in the BTAP module according to the proc below.
  # Note for this to work properly this file should be the first BTAP-related
  # file required by `btap.rb` so that only the methods in this file are
  # deprecated.
  @deprecate_methods = proc do |target_klass, display_klass, methods_list|
    methods_list.each do |method_name|
      old_method = target_klass.instance_method(method_name)
      target_klass.class_eval do
        define_method(method_name) do |*args, &block|
          Deprecated.msg(display_klass, method_name)
          old_method.bind_call(self, *args, &block)
        end
      end
    end
  end

  def self.deprecate_all_nested(namespace)
    namespace.constants(false).select { |c| c != :Deprecated }.each do |name|
      next unless namespace.const_defined?(name, false)
      const = namespace.const_get(name)
      next unless const.is_a?(Module)
      @deprecate_methods.call(const, const, const.instance_methods(false))
      @deprecate_methods.call(const.singleton_class, const, const.methods(false))
      deprecate_all_nested(const)
    end
  end

  deprecate_all_nested(self)
end
