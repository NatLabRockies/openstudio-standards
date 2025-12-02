# *********************************************************************
# *  Copyright (c) 2008-2025, Natural Resources Canada
# *  All rights reserved.
# *
# *  This library is free software; you can redistribute it and/or
# *  modify it under the terms of the GNU Lesser General Public
# *  License as published by the Free Software Foundation; either
# *  version 2.1 of the License, or (at your option) any later version.
# *
# *  This library is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *  Lesser General Public License for more details.
# *
# *  You should have received a copy of the GNU Lesser General Public
# *  License along with this library; if not, write to the Free Software
# *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# **********************************************************************/

require 'tbd'

module BTAP
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

    #this was a copy of the sketchup plugin method.
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
      #puts "Done zone renaming equipment"
    end

    def self.match_surfaces(model)
      model.getSpaces.sort.each do |space1|
        model.getSpaces.sort.each do |space2|
          space1.matchSurfaces(space2)
        end
      end
      return model
    end

    def self.intersect_surfaces(model)
      model.getSpaces.sort.each do |space1|
        model.getSpaces.sort.each do |space2|
          space1.intersectSurfaces(space2)
        end
      end
      return model
    end

    # This method will scale the model
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param x [Float] x scalar multiplier.
    # @param y [Float] y scalar multiplier.
    # @param z [Float] z scalar multiplier.
    # @return [OpenStudio::Model::Model] the model object.
    def self.scale_model(model, x, y, z)
      # Identity matrix for setting space origins
      m = OpenStudio::Matrix.new(4, 4, 0)

      m[0, 0] = 1.0 / x
      m[1, 1] = 1.0 / y
      m[2, 2] = 1.0 / z
      m[3, 3] = 1.0
      t = OpenStudio::Transformation.new(m)
      model.getPlanarSurfaceGroups().each do |planar_surface|
        planar_surface.changeTransformation(t)
      end
      return model
    end

    def self.get_fwdr(model)
      outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
      outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
      self.get_surface_to_subsurface_ratio(outdoor_walls)
    end

    def self.get_srr(model)
      outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
      outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")
      self.get_surface_to_subsurface_ratio(outdoor_roofs)
    end

    def self.get_surface_to_subsurface_ratio(surfaces)
      total_gross_surface_area = 0.0
      total_net_surface_area = 0.0
      surfaces.each do |surface|
        total_gross_surface_area = total_gross_surface_area + surface.grossArea
        total_net_surface_area = total_net_surface_area + surface.netArea
      end
      return 1.0 - (total_net_surface_area / total_gross_surface_area)
    end

    # This method will rotate the model
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param degrees [Float] rotation value
    # @return [OpenStudio::Model::Model] the model object.
    def self.rotate_model(model, degrees)
      # Identity matrix for setting space origins
      t = OpenStudio::Transformation::rotation(OpenStudio::Vector3d.new(0, 0, 1), degrees * Math::PI / 180)
      model.getPlanarSurfaceGroups().each {|planar_surface| planar_surface.changeTransformation(t)}
      return model
    end

    def self.rotate_building(model:, degrees: nil)
      # report as not applicable if effective relative rotation is 0
      if degrees == 0 || degrees.nil?
        puts ('The requested rotation was 0 or nil degrees. The model was not rotated.')
        return
      end

      # check the relative_building_rotation for reasonableness
      degrees -= 360.0 * (degrees / 360.0).truncate if (degrees > 360) || (degrees < -360)

      # reporting initial condition of model
      building = model.getBuilding
      # rotate the building
      final_building_angle = building.setNorthAxis(building.northAxis + degrees)
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
    end

    #This module contains helper functions that deal with Space objects.
    module Spaces
      #This method will return the horizontal placement type. (N,S,W,E,C) In the
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
        exterior_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces,
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

      ##
      # Fetch a space's full height.
      #
      # @param space [OpenStudio::Model::Space] a space
      #
      # @return [Float] full height of space (0 if invalid input)
      def self.space_height(space = nil)
        TBD.spaceHeight(space)
      end

      ##
      # Fetch a space's width.
      #
      # @param space [OpenStudio::Model::Space] a space
      #
      # @return [Float] width of a space (0 if invalid input)
      def self.space_width(space = nil)
        TBD.spaceWidth(space)
      end
    end

    #This Module contains methods that create, modify and query Thermal zone objects.
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
    end

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

      #["FixedWindow" , "OperableWindow" , "Door" , "GlassDoor", "OverheadDoor" , "Skylight", "TubularDaylightDiffuser","TubularDaylightDome"]
      def self.filter_subsurfaces_by_types(subsurfaces, subSurfaceTypes)

        #check to see if a string or an array was passed.
        if subSurfaceTypes.kind_of?(String)
          temp = subSurfaceTypes
          subSurfaceTypes = Array.new()
          subSurfaceTypes.push(temp)
        end
        subSurfaceTypes.each do |subSurfaceType|
          unless OpenStudio::Model::SubSurface::validSubSurfaceTypeValues.include?(subSurfaceType)
            raise("ERROR: Invalid surface type = #{subSurfaceType} Correct Values are: #{OpenStudio::Model::SubSurface::validSubSurfaceTypeValues}")
          end
        end
        return_array = Array.new()
        if subSurfaceTypes.size == 0 or subSurfaceTypes[0].upcase == "All".upcase
          return_array = self
        else
          subsurfaces.each do |subsurface|
            subSurfaceTypes.each do |subSurfaceType|
              if subsurface.subSurfaceType == subSurfaceType
                return_array.push(subsurface)
              end
            end
          end
        end
        return return_array

      end

      #This method creates a new construction based on the current, changes the rsi and assign the construction to the current surface.
      #Most of the meat of this method is in the construction class. Testing is done there.
      def self.set_surfaces_construction_conductance(surfaces, conductance)
        surfaces.each do |surface|
          #a bit of acrobatics to get the construction object from the ConstrustionBase object's name.
          construction = OpenStudio::Model::getConstructionByName(surface.model, surface.construction.get.name.to_s).get
          #create a new construction with the requested conductance value based on the current construction.

          new_construction = BTAP::Resources::Envelope::Constructions::customize_opaque_construction(surface.model, construction, conductance)
          surface.setConstruction(new_construction)
        end
        return surfaces
      end

      #  This method sets the boundary condition for a surface and it's matching surface.
      #  If set to adiabatic, it will remove all subsurfaces since E+ cannot have adiabatic sub surfaces.
      def self.set_surfaces_boundary_condition(model, surfaces, boundaryCondition)
        surfaces = BTAP::Common::validate_array(model, surfaces, "Surface")
        if OpenStudio::Model::Surface::validOutsideBoundaryConditionValues.include?(boundaryCondition)
          surfaces.each do |surface|
            if boundaryCondition == "Adiabatic"
              #need to remove subsurface as you cannot have a adiabatic surface with a
              #subsurface.
              surface.subSurfaces.each do |subsurface|
                subsurface.remove
              end

              #A bug with adiabatic surfaces. They do not hold the default contruction.
              surface.setConstruction(surface.construction.get()) if surface.isConstructionDefaulted
            end

            surface.setOutsideBoundaryCondition(boundaryCondition)
            adj_surface = surface.adjacentSurface
            unless adj_surface.empty?
              adj_surface.get.setOutsideBoundaryCondition(boundaryCondition)
            end
          end
        else
          puts "ERROR: Invalid Boundary Condition = " + boundary_condition
          puts "Correct Values are:"
          puts OpenStudio::Model::Surface::validOutsideBoundaryConditionValues
        end
      end

      def self.filter_by_non_defaulted_surfaces(surfaces)
        non_defaulted_surfaces = Array.new()
        surfaces.each {|surface| non_defaulted_surfaces << surface unless surface.isConstructionDefaulted}
        return non_defaulted_surfaces
      end

      def self.filter_by_boundary_condition(surfaces, boundary_conditions)
        #check to see if a string or an array was passed.
        if boundary_conditions.kind_of?(String)
          temp = boundary_conditions
          boundary_conditions = Array.new()
          boundary_conditions.push(temp)
        end
        #ensure boundary conditions are valid
        boundary_conditions.each do |boundary_condition|
          unless OpenStudio::Model::Surface::validOutsideBoundaryConditionValues.include?(boundary_condition)
            raise "ERROR: Invalid Boundary Condition = " + boundary_condition + "Correct Values are:" + OpenStudio::Model::Surface::validOutsideBoundaryConditionValues.to_s
          end
        end
        #create return array.
        return_array = Array.new()

        if boundary_conditions.size == 0 or boundary_conditions[0].upcase == "All".upcase
          return_array = surfaces
        else
          surfaces.each do |surface|
            boundary_conditions.each do |condition|
              if surface.outsideBoundaryCondition == condition
                return_array.push(surface)
              end
            end
          end
        end
        return return_array
      end

      def self.filter_by_surface_types(surfaces, surfaceTypes)

        #check to see if a string or an array was passed.
        if surfaceTypes.kind_of?(String)
          temp = surfaceTypes
          surfaceTypes = Array.new()
          surfaceTypes.push(temp)
        end
        surfaceTypes.each do |surfaceType|
          unless OpenStudio::Model::Surface::validSurfaceTypeValues.include?(surfaceType)
            raise("ERROR: Invalid surface type = #{surfaceType} Correct Values are: #{OpenStudio::Model::Surface::validSurfaceTypeValues}")
          end
        end
        return_array = Array.new()
        if surfaceTypes.size == 0 or surfaceTypes[0].upcase == "All".upcase
          return_array = self
        else
          surfaces.each do |surface|
            surfaceTypes.each do |surfaceType|
              if surface.surfaceType == surfaceType
                return_array.push(surface)
              end
            end
          end
        end
        return return_array
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

      # 2018-09-27 Chris Kirney
      # This method takes a surface in the x-y plane (z coordinates are ignored) with an upwardly pointing normal and
      # turns it into convex quadrialaterals.  If the original surface is already a convex quadrilateral then this method
      # will go to a lot of trouble to return the same thing (only with the coordinates of the points rounded).  If
      # the surface is already a concave surface then this method will return it broken into a bunch of quadrilaters
      # (maybe a triangle here and there). Neither of the above are especially useful.  However, the point of this
      # method is if you pass this a concave surface it will return convex surfaces that you can then use with other
      # methods that only apply to convex surfaces (such as a method which fits skylights into a roof).  Note that
      # surfaces per say are not returned.  Rather, an array containing 4 points arranged in counter clockwise order is
      # returned.  These points are also in the x-y plane with an upwardly pointing normal.  No z coordinate is returned.
      #
      # The method works by first looking for upward pointing lines.  It then looks for cooresponding downward pointing
      # lines.  Since all of the surfaces are closed there should always be enough upward and downward pointing lines.
      # Horizontal lines are ignored.  It then checks to see which y projections of the upward and downward pointing
      # lines overlap.  It then sees which of these overlaping lines overlap.  Ultimately you wind up with a whole bunch
      # of overlapping y projections that coorespond with different upward pointing lines.  These overlapping
      # y projects are either unique, or they precisely match other overlapping y projections.  The point is that, in
      # the case of a convex shape, an upward pointing line may overlap with some lines close, and some far away, with
      # some lines in between.  The method then sorts through the overlapping y projections to see which are closest
      # to a given upward pointing line.  It keeps the unique ones, and the ones that are closest.  The end result
      # should be downward pointing line segments that correspond to an upward pointing line segment with no intervening
      # lines.  The last part of the method assembles the quadrilaterals from the remaining downward pointing line
      # segments which correspond with a given upward pointing line segment.
      def self.make_convex_surfaces(surface:, tol: 12)
        # Note that points on surfaces are given counterclockwise when looking at the surface from the opposite direction as
        # the outward normal (i.e. the outward normal is pointing at you).  I use point_a1, point_a2, point_b1 and point b2
        # lots.  For this, point_a refers to vectors pointing up.  In this case point_a1 is at the top of the vector and
        # point_a2 is at the bottom of the vector.  Contrarily, point_b refers to vectors pointing down.  In this case
        # point_b1 is at the bottom of the vector and point_b2 is at the top.  All of this comes about because I cycle
        # through the points starting at the 2nd point and and going to the last point.  I count vectors as starting from
        # the last point and going toward the current point.
        # See following where P1 through P4 are the points.  When cycling through a is where you start and b is where you
        # end.  the o is the tip of the outward normal pointing at you.
        #    P2b------------aP1
        #     a              b
        #     |              |
        #     |      o       |
        #     |              |
        #     b              a
        #     P3a-----------bP4
        surf_verts = []
        # Get the vertices from the surface, keep the x and y coordinates, and turn the vertices from OpenStudio's
        # data structure to a differet one which is a little easier to deal with.  Also, round them to the given
        # tolerance.  This is done because some numbers that should match don't because of tiny errors.
        surface.vertices.each do |vert|
          surf_vert = {
              x: vert.x.to_f.round(tol),
              y: vert.y.to_f.round(tol),
              z: vert.z.to_f
          }
          surf_verts << surf_vert
        end
        # If the surface is a triangle or less then do nothing and return it.
        return surf_verts if surf_verts.length <= 3
        # Adding the first vertex to the end so that it is accounted for.
        surf_verts << surf_verts[0]
        # Following we go through the points, look for upward pointing lines, then look for downward pointing lines to
        # their left (only to the left because everything goes counter-clockwise).  If there is a line find how much the
        # current upward pointing line overlaps with it in the y direction.
        overlap_segs = []
        new_surfs = []
        for i in 1..(surf_verts.length - 1)
          # Is this line segment pointing up?  If no, then ignore it and go to the next line segment.
          if surf_verts[i][:y] > surf_verts[i - 1][:y]
            # Go through each line segment
            for j in 1..(surf_verts.length - 1)
              # Is the line segment to the left of the current (index i) line segment?  If no, then ignore it and go to the next one.
              # I revised this to check if the start or end of the current (index i) line segment is to the left of the
              # line segment being checked.
              #if surf_verts[j][:x] < surf_verts[i][:x] and surf_verts[j - 1][:x] < surf_verts[i - 1][:x]
              if surf_verts[j][:x] < surf_verts[i][:x] || surf_verts[j - 1][:x] < surf_verts[i - 1][:x]
                # Is the line segment pointing down?  If no, then ignore it and go to the next line segment.
                if surf_verts[j][:y] < surf_verts[j - 1][:y]
                  # Do the y coordinates of the line segment overlap with the current (index i) line segment?  If no
                  # then ignore it and go to the next line segment.
                  overlap_y = line_segment_overlap_y?(point_a1: surf_verts[i][:y], point_a2: surf_verts[i - 1][:y], point_b1: surf_verts[j][:y], point_b2: surf_verts[j - 1][:y])
                  unless overlap_y[:overlap_start].nil? || overlap_y[:overlap_end].nil?
                    unless overlap_y[:overlap_start] == overlap_y[:overlap_end]
                      overlap_seg = {
                          index_a1: i,
                          index_a2: i - 1,
                          index_b1: j,
                          index_b2: j - 1,
                          point_b1: surf_verts[j],
                          point_b2: surf_verts[j - 1],
                          overlap_y: overlap_y
                      }
                      overlap_segs << overlap_seg
                    end
                  end
                end
              end
            end
          end
        end
        # This part:
        # 1. Subdivides the overlapping segments found above into either unique overlaps between the upward and downward
        #    pointing lines or overlapping segments that exactly match one another.
        # 2. Goes through each upward pointing line and finds the closest overlapping downward pointing line segments (if
        #    these downward pointing segments belong together they are re-attached).
        # 3. Makes quadrilaterals (or triangles as the case may be) out of each upward pointing line and the closest
        #    downward pointing line segment.
        if overlap_segs.length > 1
          # Subdivide the overlapping segments found above into either unique overlaps between the upward and downward
          # pointing lines or overlapping segments that exactly match one another.
          overlap_segs = subdivide_overlaps(overlap_segs: overlap_segs)
          # Remove redundant overlapping segments
          recheck = true
          while recheck
            recheck = false
            # Go through each overlapping segment and look for duplicate segments
            overlap_segs.each_with_index do |ind_overlap_seg, seg_index|
              # Find duplicate overlapping segments
              redundant_segs = overlap_segs.select { |check_seg| check_seg == ind_overlap_seg}
              # Remove the first one and then restart the while loop to recompile the seg_index
              if redundant_segs.size > 1
                overlap_segs.delete_at(seg_index)
                recheck = true
              end
            end
          end
          for i in 1..(surf_verts.length - 1)
            # Does the line point up?  No then ignore and go on to the next one.
            if surf_verts[i][:y] > surf_verts[i - 1][:y]
              # Finds the closest overlapping downward pointing line segments that correspond to this upward pointing
              # line (if some of these downward pointing segments belong together then re-attached them).
              closest_overlaps = get_overlapping_segments(overlap_segs: overlap_segs, index: i, point_a1: surf_verts[i], point_a2: surf_verts[i - 1])
              closest_overlaps = closest_overlaps.sort_by {|closest_overlap| closest_overlap[:overlap_y][:overlap_start]}
              # Create the quadrilaterals out of the downward pointing line segments closest to the current upward
              # pointing line.
              for j in 0..(closest_overlaps.length - 1)
                new_surf = []
                z_loc = surf_verts[closest_overlaps[j][:index_a1]][:z]
                y_loc = closest_overlaps[j][:overlap_y][:overlap_start]
                x_loc = line_segment_overlap_x_coord(y_check: y_loc, point_b1: surf_verts[closest_overlaps[j][:index_a1]], point_b2: surf_verts[closest_overlaps[j][:index_a2]])
                new_surf << {x: x_loc.to_f.round(tol), y: y_loc.to_f.round(tol), z: z_loc.to_f.round(tol)}
                x_loc = line_segment_overlap_x_coord(y_check: y_loc, point_b1: closest_overlaps[j][:point_b1], point_b2: closest_overlaps[j][:point_b2])
                z_loc = surf_verts[closest_overlaps[j][:index_b2]][:z]
                new_surf << {x: x_loc.to_f.round(tol), y: y_loc.to_f.round(tol), z: z_loc.to_f.round(tol)}
                y_loc = closest_overlaps[j][:overlap_y][:overlap_end]
                x_loc = line_segment_overlap_x_coord(y_check: y_loc, point_b1: closest_overlaps[j][:point_b1], point_b2: closest_overlaps[j][:point_b2])
                z_loc = surf_verts[closest_overlaps[j][:index_b1]][:z]
                new_surf << {x: x_loc.to_f.round(tol), y: y_loc.to_f.round(tol), z: z_loc.to_f.round(tol)}
                x_loc = line_segment_overlap_x_coord(y_check: y_loc, point_b1: surf_verts[closest_overlaps[j][:index_a1]], point_b2: surf_verts[closest_overlaps[j][:index_a2]])
                z_loc = surf_verts[closest_overlaps[j][:index_a2]][:z]
                new_surf << {x: x_loc.to_f.round(tol), y: y_loc.to_f.round(tol), z: z_loc.to_f.round(tol)}
                # Check if this should be a triangle.
                for k in 0..(new_surf.length - 1)
                  break_now = false
                  for l in 0..(new_surf.length - 1)
                    next if k == l
                    if (new_surf[k][:x] == new_surf[l][:x]) && (new_surf[k][:y] == new_surf[l][:y])
                      new_surf.delete_at(l)
                      break_now = true
                      break
                    end
                  end
                  if break_now == true
                    break
                  end
                end
                new_surfs << new_surf
              end
            end
          end
        elsif overlap_segs.length == 1
          # There is only one overlapping downward line, thus this is a quadrilateral already so just return it.
          # Remove the last vertex as we had artificially added it at the start.
          surf_verts.pop
          new_surfs << surf_verts
        end
        return new_surfs
      end

      # This method takes the y projections of a bunch of overlapping line segments and sorts them to determines which
      # are unique and, if they are not unique, which is closest to the current, upwardly pointing, line.  If several
      # overlapping segments belong to the same line they are put together (after the 'subdivide_overlaps' method broke
      # them apart).  The end result is the method returns the closet point downward pointing line segments closest to
      # the given upward pointing line segment.
      #
      # overlap_segs: This is an array of hashes that looks like:
      #                     overlap_seg = {
      #                         index_a1: i,
      #                         index_a2: i-1,
      #                         index_b1: j,
      #                         index_b2: j-1,
      #                         point_b1: surf_verts[j],
      #                         point_b2: surf_verts[j-1],
      #                         overlap_y: overlap_y
      #                     }
      # index_a1:  The index of the array of points that cooresponds with the top of line a (points up)
      # index_a1:  The index of the array of points that cooresponds with the bottom of line a (points up)
      # index_b1:  The index of the array of points that cooresponds with the bottom of line b (points down)
      # index_b1:  The index of the array of points that cooresponds with the top of line b (points down)
      # point_b1:  The coordinates of the bottom of line b
      # point_b2:  The coordinates of the top of line b
      #
      # overlap_y: A hash that contains the coordinates of the top and bottom of the y projection of the overlapping
      # lines (line a and line b)
      #         overlap_y = {
      #             overlap_start: overlap_start,
      #             overlap_end: overlap_end
      #         }
      # overlap_start:  The y coordinate of the top of the overlap
      # overlap_end:  The y coordinate of the bottom of the overlap
      #
      # index: The index of the array of points that cooresponds with the top of of the current upward pointing line.
      #
      # point_a1:  The coordinates of the top of the first line
      # point_a2:  The coordinates of the  bottom of the first line
      # This naming convention was chosen because this method was originally designed to work with the
      # 'make_concave_surfaces' method (see above).  That method choses lines that point up and then sees where they
      # overlap with lines pointing down.  The point_1 of each line is the end of the line.  In this case a lines point
      # up and b lines point down.
      def self.get_overlapping_segments(overlap_segs:, index:, point_a1:, point_a2:)
        closest_overlaps = []
        linea_overlaps = []
        # This goes through all the line segments and determines which correspond to the current upward pointing line
        # segment(line a).  It also determines the x coordinate distance between the top and bottom of the overlapping
        # portions of the line segments.
        curr_overlap_segs = overlap_segs.select { |seg| (seg[:index_a1] == index) && (seg[:index_a2] == (index - 1)) }
        curr_overlap_segs.each do |overlap_seg|
          line_a_x_top = line_segment_overlap_x_coord(y_check: overlap_seg[:overlap_y][:overlap_start], point_b1: point_a1, point_b2: point_a2)
          line_a_x_bottom = line_segment_overlap_x_coord(y_check: overlap_seg[:overlap_y][:overlap_end], point_b1: point_a1, point_b2: point_a2)
          line_b_x_top = line_segment_overlap_x_coord(y_check: overlap_seg[:overlap_y][:overlap_start], point_b1: overlap_seg[:point_b1], point_b2: overlap_seg[:point_b2])
          line_b_x_bottom = line_segment_overlap_x_coord(y_check: overlap_seg[:overlap_y][:overlap_end], point_b1: overlap_seg[:point_b1], point_b2: overlap_seg[:point_b2])
          x_distance_top = line_a_x_top - line_b_x_top
          x_distance_bottom = line_a_x_bottom - line_b_x_bottom
          linea_overlap = {
            dx_top: x_distance_top,
            dx_bottom: x_distance_bottom,
            overlap: overlap_seg
          }
          linea_overlaps << linea_overlap
        end

        # This sorts through the overlapping downward pointing line segments corresponding to the current upward pointing
        # line a.  The overlapping downward pointing line segments closest to the current upward pointing line segment
        # are kept.  The other are discarded.  Unique overlapping line segments are kept as well.  There should only be
        # unuique overlapping line segments or overlapping line segments that precisely match one another because of
        # the 'subdivide_overlaps' method which this method is supposed to work with.
        linea_overlaps.each do |line_a_overlap|
          overlaps = linea_overlaps.select { |seg| seg[:overlap][:overlap_y] == line_a_overlap[:overlap][:overlap_y]}
          if overlaps.size > 1
            redundant_overlap = closest_overlaps.select { |dup_seg| dup_seg[:overlap_y] == overlaps[0][:overlap][:overlap_y] }
            closest_overlaps << (overlaps.min_by { |dup_seg| dup_seg[:dx_top] })[:overlap] if redundant_overlap.empty?
          elsif overlaps.size == 1
            closest_overlaps << overlaps[0][:overlap]
          end
        end

        # This combines the line segments that belong together.  These were broken apart because of the
        # 'subdivide_overlaps' method.
        overlap_exts = [closest_overlaps[0]]
        for j in 0..(closest_overlaps.length - 1)
          index = 0
          found = false
          for l in 0..(overlap_exts.length - 1)
            if overlap_exts[l][:index_b1] == closest_overlaps[j][:index_b1] && overlap_exts[l][:index_b2] == closest_overlaps[j][:index_b2]
              index = l
              found = true
              break
            end
          end
          if found == false
            overlap_exts << closest_overlaps[j]
            index = overlap_exts.length - 1
          end
          for k in 0..(closest_overlaps.length - 1)
            if (closest_overlaps[j][:index_b1] == closest_overlaps[k][:index_b1]) && (closest_overlaps[j][:index_b2] == closest_overlaps[k][:index_b2])
              if closest_overlaps[k][:overlap_y][:overlap_start] >= overlap_exts[index][:overlap_y][:overlap_start]
                overlap_exts[index][:overlap_y][:overlap_start] = closest_overlaps[k][:overlap_y][:overlap_start]
              end
              if closest_overlaps[k][:overlap_y][:overlap_end] <= overlap_exts[index][:overlap_y][:overlap_end]
                overlap_exts[index][:overlap_y][:overlap_end] = closest_overlaps[k][:overlap_y][:overlap_end]
              end
            end
          end
        end
        return overlap_exts
      end

      # This method was originally written to work with the 'make_concave_surfaces' method above.  It takes the
      # y-components of a bunch of line segemnts and cuts them up until they either are unique (no other overlapping
      # components) or they match the y-components of other line segments.
      # overlap_segs: This is an array of hashes that looks like:
      #                     overlap_seg = {
      #                         index_a1: i,
      #                         index_a2: i-1,
      #                         index_b1: j,
      #                         index_b2: j-1,
      #                         point_b1: surf_verts[j],
      #                         point_b2: surf_verts[j-1],
      #                         overlap_y: overlap_y
      #                     }
      # index_a1:  The index of the array of points that cooresponds with the top of line a (points up)
      # index_a1:  The index of the array of points that cooresponds with the bottom of line a (points up)
      # index_b1:  The index of the array of points that cooresponds with the bottom of line b (points down)
      # index_b1:  The index of the array of points that cooresponds with the top of line b (points down)
      # point_b1:  The coordinates of the bottom of line b
      # point_b2:  The coordinates of the top of line b
      #
      # overlap_y: A hash that contains the coordinates of the top and bottom of the y projection of the overlapping
      # lines (line a and line b)
      #         overlap_y = {
      #             overlap_start: overlap_start,
      #             overlap_end: overlap_end
      #         }
      # overlap_start:  The y coordinate of the top of the overlap
      # overlap_end:  The y coordinate of the bottom of the overlap
      def self.subdivide_overlaps(overlap_segs:)
        restart = true
        # Keep doing this until the y projections of the lines are either unique or the match the y projections of other
        # lines.
        while restart == true
          restart = false
          overlap_segs.each_with_index do |overlap_seg, curr_seg_index|
            for j in 0..(overlap_segs.length - 1)
              # Skip this y projection if it is the same as that in overlap_seg
              if overlap_seg == overlap_segs[j]
                next
              end
              # Check to see if the y projection of line a overlaps with the y projection of line b
              overlap_segs_overlap = line_segment_overlap_y?(point_a1: overlap_seg[:overlap_y][:overlap_start], point_a2: overlap_seg[:overlap_y][:overlap_end], point_b1: overlap_segs[j][:overlap_y][:overlap_end], point_b2: overlap_segs[j][:overlap_y][:overlap_start])
              # If the y projections of the two lines overlap then the components of overlap_segs_overlap should not be
              # nil.
              unless ((overlap_segs_overlap[:overlap_start].nil?) || (overlap_segs_overlap[:overlap_end].nil?))
                # If the two overlaping segments start and end at the same point then do nothing and go to the next segment.
                if (overlap_seg[:overlap_y][:overlap_start] == overlap_segs[j][:overlap_y][:overlap_start]) && (overlap_seg[:overlap_y][:overlap_end] == overlap_segs[j][:overlap_y][:overlap_end])
                  next
                  # If the start point of one overlapping segment shares the end point of the other overlapping segment then
                  # they are not really overlapping.  Ignore and go to the next point.
                elsif overlap_segs_overlap[:overlap_start] == overlap_segs_overlap[:overlap_end]
                  next
                  # If the overlap_seg segment covers beyond the overlap_segs[j] segment then break overlap_seg into three smaller pieces:
                  # -One piece for where overlap_seg starts to where overlap_segs[j] starts;
                  # -One piece to cover overlap_segs[j] (the middle part); and
                  # -One piece for where overlap_segs[j] ends to where overlap_seg ends (the bottom part).
                  # The overlap_segs[j] remains as it is associated with another upward pointing line segment.
                  # If overlap_seg starts at the same point as overlap_segs[j] or ends at the same point as overlap_segs[j]
                  # then overlap_seg is broken into two pieces (no mid piece).
                elsif (overlap_seg[:overlap_y][:overlap_start] >= overlap_segs[j][:overlap_y][:overlap_start]) && (overlap_seg[:overlap_y][:overlap_end] <= overlap_segs[j][:overlap_y][:overlap_end])
                  # If the overlap_seg and overlap_segs[j] start at the same point replace overlap_seg with two segments (
                  # one top and one bottom).
                  if overlap_seg[:overlap_y][:overlap_start] == overlap_segs[j][:overlap_y][:overlap_start]
                    overlap_top = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    overlap_bottom_over = {
                        overlap_start: overlap_segs_overlap[:overlap_end],
                        overlap_end: overlap_seg[:overlap_y][:overlap_end]
                    }
                    overlap_bottom = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_bottom_over
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(curr_seg_index)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_bottom
                  elsif overlap_seg[:overlap_y][:overlap_end] == overlap_segs[j][:overlap_y][:overlap_end]
                    # If the overlap_seg and overlap_segs[j] end at the same point replace overlap_seg with two segments (
                    # one top and one bottom).
                    overlap_top_over = {
                        overlap_start: overlap_seg[:overlap_y][:overlap_start],
                        overlap_end: overlap_segs_overlap[:overlap_start]
                    }
                    overlap_top = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_top_over
                    }
                    overlap_bottom = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(curr_seg_index)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_bottom
                  elsif (overlap_seg[:overlap_y][:overlap_start] > overlap_segs[j][:overlap_y][:overlap_start]) && (overlap_seg[:overlap_y][:overlap_end] < overlap_segs[j][:overlap_y][:overlap_end])
                    # If the overlap_seg stretches above and below overlap_segs[j] then break overlap_seg into three pieces
                    # (one top, one middle, one bottom).
                    overlap_top_over = {
                        overlap_start: overlap_seg[:overlap_y][:overlap_start],
                        overlap_end: overlap_segs_overlap[:overlap_start]
                    }
                    overlap_top = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_top_over
                    }
                    overlap_mid = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    overlap_bottom_over = {
                        overlap_start: overlap_segs_overlap[:overlap_end],
                        overlap_end: overlap_seg[:overlap_y][:overlap_end]
                    }
                    overlap_bottom = {
                        index_a1: overlap_seg[:index_a1],
                        index_a2: overlap_seg[:index_a2],
                        index_b1: overlap_seg[:index_b1],
                        index_b2: overlap_seg[:index_b2],
                        point_b1: overlap_seg[:point_b1],
                        point_b2: overlap_seg[:point_b2],
                        overlap_y: overlap_bottom_over
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(curr_seg_index)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_mid
                    overlap_segs << overlap_bottom
                  end
                  restart = true
                  break
                  # If the overlap_segs[j] segment covers beyond the overlap_seg segment then break overlap_segs[j] into three smaller pieces:
                  # -One piece for where overlap_segs[j] starts to where overlap_seg starts;
                  # -One piece to cover overlap_seg (the middle part); and
                  # -One piece for where overlap_seg ends to where overlap_segs[j] ends (the bottom part).
                  # The overlap_seg remains as it is associated with another upward pointing line segment.
                  # If overlap_segs[j] starts at the same point as overlap_seg or ends at the same point as overlap_seg
                  # then overlap_segs[j] is broken into two pieces (no mid piece).
                elsif overlap_seg[:overlap_y][:overlap_start] <= overlap_segs[j][:overlap_y][:overlap_start] && overlap_seg[:overlap_y][:overlap_end] >= overlap_segs[j][:overlap_y][:overlap_end]
                  # If the overlap_seg and overlap_segs[j] start at the same point replace overlap_segs[j] with two segments (
                  # one top and one bottom).
                  if overlap_seg[:overlap_y][:overlap_start] == overlap_segs[j][:overlap_y][:overlap_start]
                    overlap_top = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    overlap_bottom_over = {
                        overlap_start: overlap_segs_overlap[:overlap_end],
                        overlap_end: overlap_segs[j][:overlap_y][:overlap_end]
                    }
                    overlap_bottom = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_bottom_over
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(j)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_bottom
                  elsif overlap_seg[:overlap_y][:overlap_end] == overlap_segs[j][:overlap_y][:overlap_end]
                    # If the overlap_seg and overlap_segs[j] end at the same point replace overlap_segs[j] with two segments (
                    # one top and one bottom).
                    overlap_top_over = {
                        overlap_start: overlap_segs[j][:overlap_y][:overlap_start],
                        overlap_end: overlap_segs_overlap[:overlap_start]
                    }
                    overlap_top = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_top_over
                    }
                    overlap_bottom = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(j)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_bottom
                  elsif overlap_seg[:overlap_y][:overlap_start] < overlap_segs[j][:overlap_y][:overlap_start] && overlap_seg[:overlap_y][:overlap_end] > overlap_segs[j][:overlap_y][:overlap_end]
                    # If the overlap_segs[j] stretches above and below overlap_seg then break overlap_segs[j] into three pieces
                    # (one top, one middle, one bottom).
                    overlap_top_over = {
                        overlap_start: overlap_segs[j][:overlap_y][:overlap_start],
                        overlap_end: overlap_segs_overlap[:overlap_start]
                    }
                    overlap_top = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_top_over
                    }
                    overlap_mid = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_segs_overlap
                    }
                    overlap_bottom_over = {
                        overlap_start: overlap_segs_overlap[:overlap_end],
                        overlap_end: overlap_segs[j][:overlap_y][:overlap_end]
                    }
                    overlap_bottom = {
                        index_a1: overlap_segs[j][:index_a1],
                        index_a2: overlap_segs[j][:index_a2],
                        index_b1: overlap_segs[j][:index_b1],
                        index_b2: overlap_segs[j][:index_b2],
                        point_b1: overlap_segs[j][:point_b1],
                        point_b2: overlap_segs[j][:point_b2],
                        overlap_y: overlap_bottom_over
                    }
                    # delete the existing y projection overlaps and replace it with the ones we just made.
                    overlap_segs.delete_at(j)
                    overlap_segs << overlap_top
                    overlap_segs << overlap_mid
                    overlap_segs << overlap_bottom
                  end
                  restart = true
                  break
                  # if overlap_seg covers the top of overlap_segs[j] then break overlap_seg into a top and an overlap portion
                  # ond break overlap_segs[j] into an overlap portion and a bottom portion.
                elsif (overlap_seg[:overlap_y][:overlap_start] >= overlap_segs[j][:overlap_y][:overlap_start]) && (overlap_seg[:overlap_y][:overlap_end] <= overlap_segs[j][:overlap_y][:overlap_start]) && (overlap_seg[:overlap_y][:overlap_end] > overlap_segs[j][:overlap_y][:overlap_end])
                  overlap_top_over = {
                      overlap_start: overlap_seg[:overlap_y][:overlap_start],
                      overlap_end: overlap_segs_overlap[:overlap_start]
                  }
                  overlap_top = {
                      index_a1: overlap_seg[:index_a1],
                      index_a2: overlap_seg[:index_a2],
                      index_b1: overlap_seg[:index_b1],
                      index_b2: overlap_seg[:index_b2],
                      point_b1: overlap_seg[:point_b1],
                      point_b2: overlap_seg[:point_b2],
                      overlap_y: overlap_top_over
                  }
                  overlap_mid_seg = {
                      index_a1: overlap_seg[:index_a1],
                      index_a2: overlap_seg[:index_a2],
                      index_b1: overlap_seg[:index_b1],
                      index_b2: overlap_seg[:index_b2],
                      point_b1: overlap_seg[:point_b1],
                      point_b2: overlap_seg[:point_b2],
                      overlap_y: overlap_segs_overlap
                  }
                  overlap_mid_segs = {
                      index_a1: overlap_segs[j][:index_a1],
                      index_a2: overlap_segs[j][:index_a2],
                      index_b1: overlap_segs[j][:index_b1],
                      index_b2: overlap_segs[j][:index_b2],
                      point_b1: overlap_segs[j][:point_b1],
                      point_b2: overlap_segs[j][:point_b2],
                      overlap_y: overlap_segs_overlap
                  }
                  overlap_bottom_over = {
                      overlap_start: overlap_segs_overlap[:overlap_end],
                      overlap_end: overlap_segs[j][:overlap_y][:overlap_end]
                  }
                  overlap_bottom = {
                      index_a1: overlap_segs[j][:index_a1],
                      index_a2: overlap_segs[j][:index_a2],
                      index_b1: overlap_segs[j][:index_b1],
                      index_b2: overlap_segs[j][:index_b2],
                      point_b1: overlap_segs[j][:point_b1],
                      point_b2: overlap_segs[j][:point_b2],
                      overlap_y: overlap_bottom_over
                  }
                  # delete the existing y projection overlaps and replace it with the ones we just made.
                  if curr_seg_index > j
                    overlap_segs.delete_at(curr_seg_index)
                    overlap_segs.delete_at(j)
                  else
                    overlap_segs.delete_at(j)
                    overlap_segs.delete_at(curr_seg_index)
                  end
                  overlap_segs << overlap_top
                  overlap_segs << overlap_mid_seg
                  overlap_segs << overlap_mid_segs
                  overlap_segs << overlap_bottom
                  restart = true
                  break
                elsif (overlap_seg[:overlap_y][:overlap_start] >= overlap_segs[j][:overlap_y][:overlap_end]) && (overlap_seg[:overlap_end] < overlap_segs[j][:overlap_end]) && (overlap_seg[:overlap_y][:overlap_start] <= overlap_segs[j][:overlap_y][:overlap_start])
                  # if overlap_seg covers the bottom of overlap_segs[j] then break overlap_segs[j] into a top and an overlap portion
                  # ond break overlap_seg into an overlap portion and a bottom portion.
                  overlap_top_over = {
                      overlap_start: overlap_segs[j][:overlap_y][:overlap_start],
                      overlap_end: overlap_segs_overlap[:overlap_start]
                  }
                  overlap_top = {
                      index_a1: overlap_segs[j][:index_a1],
                      index_a2: overlap_segs[j][:index_a2],
                      index_b1: overlap_segs[j][:index_b1],
                      index_b2: overlap_segs[j][:index_b2],
                      point_b1: overlap_segs[j][:point_b1],
                      point_b2: overlap_segs[j][:point_b2],
                      overlap_y: overlap_top_over
                  }
                  overlap_mid_seg = {
                      index_a1: overlap_seg[:index_a1],
                      index_a2: overlap_seg[:index_a2],
                      index_b1: overlap_seg[:index_b1],
                      index_b2: overlap_seg[:index_b2],
                      point_b1: overlap_seg[:point_b1],
                      point_b2: overlap_seg[:point_b2],
                      overlap_y: overlap_segs_overlap
                  }
                  overlap_mid_segs = {
                      index_a1: overlap_segs[j][:index_a1],
                      index_a2: overlap_segs[j][:index_a2],
                      index_b1: overlap_segs[j][:index_b1],
                      index_b2: overlap_segs[j][:index_b2],
                      point_b1: overlap_segs[j][:point_b1],
                      point_b2: overlap_segs[j][:point_b2],
                      overlap_y: overlap_segs_overlap
                  }
                  overlap_bottom_over = {
                      overlap_start: overlap_segs_overlap[:overlap_end],
                      overlap_end: overlap_seg[:overlap_y][:overlap_end]
                  }
                  overlap_bottom = {
                      index_a1: overlap_seg[:index_a1],
                      index_a2: overlap_seg[:index_a2],
                      index_b1: overlap_seg[:index_b1],
                      index_b2: overlap_seg[:index_b2],
                      point_b1: overlap_seg[:point_b1],
                      point_b2: overlap_seg[:point_b2],
                      overlap_y: overlap_bottom_over
                  }
                  # delete the existing y projection overlaps and replace it with the ones we just made.
                  if curr_seg_index > j
                    overlap_segs.delete_at(curr_seg_index)
                    overlap_segs.delete_at(j)
                  else
                    overlap_segs.delete_at(j)
                    overlap_segs.delete_at(curr_seg_index)
                  end
                  overlap_segs << overlap_top
                  overlap_segs << overlap_mid_seg
                  overlap_segs << overlap_mid_segs
                  overlap_segs << overlap_bottom
                  restart = true
                  break
                end
              end
            end
            if restart == true
              break
            end
          end
        end
        return overlap_segs
      end

      # This method determines if the y component of 2 lines overlap.
      # point_a1:  The top of the first line
      # point_a2:  The bottom of the first line
      # point_b1:  The bottom of the second line
      # point_b2:  The top of the second line.
      # This naming convention was chosen because this method was originally designed to work with the
      # 'make_concave_surfaces' method (see above).  That method choses lines that point up and then sees where they
      # overlap with lines pointing down.  The point_1 of each line is the end of the line.  In this case a lines point
      # up and b lines point down.
      def self.line_segment_overlap_y?(point_a1:, point_a2:, point_b1:, point_b2:)
        overlap_start = nil
        overlap_end = nil
        # If line a overlaps with the bottom of line b do this:
        if (point_a1 >= point_b1) && (point_a2 <= point_b1)
          overlap_start = point_a1
          overlap_end = point_b1
          # This checks if all of line b is overlapped by line a
          if point_a1 >= point_b2
            overlap_start = point_b2
          end
          # If line a overlaps with the top of line b do this:
        elsif (point_a1 >= point_b2) && (point_a2 <= point_b2)
          overlap_start = point_b2
          overlap_end = point_a2
          # This checks if all of line b is overlapped by line a
          if point_a2 <= point_b1
            overlap_end = point_b1
          end
          # This checks if all of line a fits in line b
        elsif (point_a1 <= point_b2) && (point_a2 >= point_b1)
          overlap_start = point_a1
          overlap_end = point_a2
        end
        # Overlap vectors always point down.  Thus overlap_start is the y location of the top of the overlap vector and
        # overlap_end is the y location of the bottom of the overlap vector.  The overlap vector will later be constructed
        # using point_b1 and point_b2 and checking which overlaps are closest (and not obstructed) by other overlaps.
        overlap_y = {
            overlap_start: overlap_start,
            overlap_end: overlap_end
        }
        return overlap_y
      end

      # This method determines the x coordinate of where a given y coordinate crosses a given line.
      # y_check:  The y coordinate that you want to determine the x coordinate for on a line
      # point_b1: The coordinates of the bottom of the line
      # point_b2: The coordinates of the top of the line
      def self.line_segment_overlap_x_coord(y_check:, point_b1:, point_b2:)
        # If the line is vertical then all x coordinates are the same
        if point_b1[:x] == point_b2[:x]
          xcross = point_b2[:x]
          # If the line is horizontal you cannot find the y intercept
        elsif (point_b1[:y] == point_b2[:y])
          raise("This line is horizontal so no y intercept can be found.")
          # Otherwise determine the line coefficients and get the intercept
        else
          a = (point_b1[:y] - point_b2[:y]) / (point_b1[:x] - point_b2[:x])
          b = point_b1[:y] - a * point_b1[:x]
          xcross = (y_check - b) / a
        end
        return xcross
      end

      # This method finds the centroid of a surface using the point averaging method.  OpenStudio already has something
      # which does this but you have to turn something into a special OpenStudio surface first which you may not want
      # to do.
      def self.surf_centroid(surf:)
        new_surf_cent = {
            x: 0,
            y: 0,
            z: 0
        }
        surf.each do |surf_vert|
          new_surf_cent[:x] += surf_vert[:x]
          new_surf_cent[:y] += surf_vert[:y]
          new_surf_cent[:z] += surf_vert[:z]
        end
        new_surf_cent[:x] /= surf.length
        new_surf_cent[:y] /= surf.length
        new_surf_cent[:z] /= surf.length
        return new_surf_cent
      end

      # This method calculates the surface area of a 2-D polygon from an array of OpenStudio vertices.  It ignores any z
      # vertices.  This method assumes that the polygon is complete, has no holes, does not cross itself, and that the
      # vertices are provided in counter-clockwise order.  This method is used in cases when you want to find the area
      # of something before creating an OpenStudio surface/subsurface.
      #
      # Input arguments:
      # vetices:  Array of openstudio vertices.
      #
      # Output:
      # Area:  Float, area of polygot represented by the vertices.
      def self.getSurfaceAreafromVertices(vertices:)
        area = 0.0
        numberVertices = vertices.size

        # Check that a polygon is actually provided and not just a line or point.  Return 0 if the vertices are a line
        # or point.
        return 0.0 if numberVertices < 3

        # Go through the vertices and get the cross product.  This adopted from:
        # https://web.archive.org/web/20100405070507/http://valis.cs.uiuc.edu/~sariel/research/CG/compgeom/msg00831.html
        vertices.each_with_index do |vertex, i|
          j = (i + 1) % numberVertices
          area += vertex.x.to_f * vertices[j].y.to_f
          area -= vertex.y.to_f * vertices[j].x.to_f
        end
        return area
      end

      # Calculate the perimeter from a set of OpenStudio vertices.
      # Calculated by iterating through vertex pairs, subtracting the difference, and getting the length of the returned
      # Vector3d object.
      def self.getSurfacePerimeterFromVertices(vertices:)
        perimeter = 0.0
        return 0.0 if vertices.size < 2
        (vertices.size - 1).times do |i|
          perimeter += (vertices[i] - vertices[(i + 1) % vertices.size]).length
        end
        return perimeter
      end 
    end #Module Surfaces
  end #module Geometry
end
