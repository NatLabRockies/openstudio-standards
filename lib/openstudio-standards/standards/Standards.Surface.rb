class Standard
  # @!group Surface

  # This method searches through a model a returns vertical exterior surfaces which help
  # enclose a conditioned space.  It distinguishes between walls adjacent to plenums and wall adjacent to other
  # conditioned spaces (as attics in OpenStudio are considered plenums and conditioned spaces though many would
  # not agree).  It returns a hash of the total exposed wall area adjacent to conditioned spaces (including plenums), the
  # total exposed plenum wall area, the total exposed non-plenum area (adjacent to conditioned spaces), the exposed
  # plenum walls and the exposed non-plenum walls (adjacent to conditioned spaces).
  # @author Chris Kirney
  # @note 2018-09-12
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param max_angle [Double] maximum angle to consider surface
  # @param min_angle [Double] minimum angle to consider surface
  # @return [Hash] hash of exposed surface information
  def find_exposed_conditioned_vertical_surfaces(model, max_angle: 91, min_angle: 89)
    exposed_surfaces = []
    plenum_surfaces = []
    exp_plenum_area = 0
    total_exp_area = 0
    exp_nonplenum_area = 0
    sub_surfaces_info = []
    sub_surface_area = 0
    # Sort through each space
    model.getSpaces.sort.each do |space|
      # Is the space heated or cooled?
      cooled = OpenstudioStandards::Space.space_cooled?(space)
      heated = OpenstudioStandards::Space.space_heated?(space)
      # Assume conditioned means the space is heated, cooled, or both.
      if heated || cooled
        # If the space is conditioned then go through each surface and determine if it a vertial exterior wall.
        space.surfaces.sort.each do |surface|
          # I define an exterior wall as one that is called a wall and that has a boundary contion of Outdoors.
          # Note that this will not include foundation walls.
          next unless surface.surfaceType == 'Wall'
          next unless surface.outsideBoundaryCondition == 'Outdoors'

          # Determine if the wall is vertical which I define as being between 89 and 91 degrees from horizontal.
          tilt_radian = surface.tilt
          tilt_degrees = OpenStudio.convert(tilt_radian, 'rad', 'deg').get
          sub_surface_info = []
          if tilt_degrees <= max_angle && tilt_degrees >= min_angle
            # If the wall is vertical determine if it is adjacent to a plenum.  If yes include it in the array of
            # plenum walls and add it to the plenum wall area counter (accounting for space multipliers).
            if OpenstudioStandards::Space.space_plenum?(space)
              plenum_surfaces << surface
              exp_plenum_area += surface.grossArea * space.multiplier
            else
              # If not a plenum then include it in the array of non-plenum walls and add it to the non-plenum area
              # counter (accounting for space multipliers).
              exposed_surfaces << surface
              exp_nonplenum_area += surface.grossArea * space.multiplier
              surface.subSurfaces.sort.each do |sub_surface|
                sub_surface_area += sub_surface.grossArea.to_f * space.multiplier
                sub_surface_info << {
                  'subsurface_name' => sub_surface.nameString,
                  'subsurface_type' => sub_surface.subSurfaceType,
                  'gross_area_m2' => sub_surface.grossArea.to_f,
                  'construction_name' => sub_surface.construction.get.nameString
                }
              end
              unless sub_surface_info.empty?
                sub_surfaces_info << {
                  'surface_name' => surface.nameString,
                  'subsurfaces' => sub_surface_info
                }
              end
            end
            # Regardless of if the wall is adjacent to a plenum or not add it to the exposed wall area adjacent to
            # conditioned spaces (accounting for space multipliers).
            total_exp_area += surface.grossArea * space.multiplier
          end
        end
      end
    end
    fdwr = 999
    unless exp_nonplenum_area < 0.1
      fdwr = sub_surface_area / exp_nonplenum_area
    end
    # Add everything into a hash and return that hash to whomever called the method.
    exp_surf_info = {
      'total_exp_wall_area_m2' => total_exp_area,
      'exp_plenum_wall_area_m2' => exp_plenum_area,
      'exp_nonplenum_wall_area_m2' => exp_nonplenum_area,
      'exp_plenum_walls' => plenum_surfaces,
      'exp_nonplenum_walls' => exposed_surfaces,
      'fdwr' => fdwr,
      'sub_surfaces' => sub_surfaces_info
    }
    return exp_surf_info
  end

  # This method is similar to the 'find_exposed_conditioned_vertical_surfaces' above only it is for roofs.  Again, it
  # distinguishes between plenum and non plenum roof area but collects and returns both.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] hash of exposed roof information
  def find_exposed_conditioned_roof_surfaces(model)
    exposed_surfaces = []
    plenum_surfaces = []
    exp_plenum_area = 0
    total_exp_area = 0
    exp_nonplenum_area = 0
    sub_surfaces_info = []
    sub_surface_area = 0
    # Sort through each space and determine if it conditioned.  Conditioned meaning it is either heated, cooled, or both.
    model.getSpaces.sort.each do |space|
      cooled = OpenstudioStandards::Space.space_cooled?(space)
      heated = OpenstudioStandards::Space.space_heated?(space)
      # If the space is conditioned sort through the surfaces looking for outdoor roofs.
      if heated || cooled
        space.surfaces.sort.each do |surface|
          # Assume a roof is of type 'RoofCeiling' and has an 'Outdoors' boundary condition.
          next unless surface.surfaceType == 'RoofCeiling'
          next unless surface.outsideBoundaryCondition == 'Outdoors'

          # Determine if the roof is adjacent to a plenum.
          sub_surface_info = []
          if OpenstudioStandards::Space.space_plenum?(space)
            # If the roof is adjacent to a plenum add it to the plenum roof array and the plenum roof area counter
            # (accounting for space multipliers).
            plenum_surfaces << surface
            exp_plenum_area += surface.grossArea * space.multiplier
          else
            # If the roof is not adjacent to a plenum add it to the non-plenum roof array and the non-plenum roof area
            # counter (accounting for space multipliers).
            exposed_surfaces << surface
            exp_nonplenum_area += surface.grossArea * space.multiplier
            surface.subSurfaces.sort.each do |sub_surface|
              sub_surface_area += sub_surface.grossArea.to_f * space.multiplier
              sub_surface_info << {
                'subsurface_name' => sub_surface.nameString,
                'subsurface_type' => sub_surface.subSurfaceType,
                'gross_area_m2' => sub_surface.grossArea.to_f,
                'construction_name' => sub_surface.construction.get.nameString
              }
            end
            unless sub_surface_info.empty?
              sub_surfaces_info << {
                'surface_name' => surface.nameString,
                'subsurfaces' => sub_surface_info
              }
            end
          end
          # Regardless of if the roof is adjacent to a plenum or not add it to the total roof area counter (accounting
          # for space multipliers).
          total_exp_area += surface.grossArea * space.multiplier
        end
      end
    end
    srr = 999
    unless exp_nonplenum_area < 0.1
      srr = sub_surface_area / exp_nonplenum_area
    end
    # Put the information into a hash and return it to whomever called this method.
    exp_surf_info = {
      'total_exp_roof_area_m2' => total_exp_area,
      'exp_plenum_roof_area_m2' => exp_plenum_area,
      'exp_nonplenum_roof_area_m2' => exp_nonplenum_area,
      'exp_plenum_roofs' => plenum_surfaces,
      'exp_nonplenum_roofs' => exposed_surfaces,
      'srr' => srr,
      'sub_surfaces' => sub_surfaces_info
    }
    return exp_surf_info
  end

  # This method finds the centroid of the highest roof(s).  It cycles through each space and finds which surfaces are
  # described as roofceiling whose outside boundary condition is outdoors.  Of those surfaces that do it looks for the
  # highest one(s) and finds the centroid of those.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] It returns the following hash:
  #   roof_cent = {
  #     top_spaces:  array of spaces which contain the highest roofs,
  #     roof_centroid:  global x, y, and z coords of the centroid of the highest roof surfaces,
  #     roof_area:  area of the highst roof surfaces}
  #   Each element of the top_spaces is a hash containing the following:
  #     top_space = {
  #       space:  OpenStudio space containing the surface,
  #       x:  global x coord of the centroid of roof surface(s),
  #       y:  global y coord of the centroid of roof surface(s),
  #       z:  global z coord of the centroid of roof surface(s),
  #       area_m2:  area of the roof surface(s)}
  def find_highest_roof_centre(model)
    # Initialize some variables
    tol = 6
    max_height = -1000000000000000
    top_spaces = []
    spaces_info = []
    roof_centroid = [0, 0, 0]
    # Go through each space looking for outdoor roofs
    model.getSpaces.sort.each do |space|
      outdoor_roof = false
      space_max = -1000000000000000
      max_surf = nil
      space_surfaces = space.surfaces
      # Go through each surface in the space.  If it is an outdoor roofceiling then continue.  Otherwise go to the next
      # space.
      space_surfaces.each do |surface|
        outdoor_roof = true if surface.surfaceType.to_s.upcase == 'ROOFCEILING' && surface.outsideBoundaryCondition.to_s.upcase == 'OUTDOORS'
        # Is this surface the highest roof on this space?
        if surface.centroid.z.to_f.round(tol) > space_max
          space_max = surface.centroid.z.to_f.round(tol)
          max_surf = surface
        end
      end
      # If no outdoor roofceiling go to the next space.
      next if outdoor_roof == false

      z_origin = space.zOrigin.to_f
      ceiling_centroid = [0, 0, 0]

      # Go through the surfaces and look for ones that are the highest.  Any that are the highest get added to the
      # centroid calculation.
      space_surfaces.each do |sp_surface|
        if max_surf.centroid.z.to_f.round(tol) == sp_surface.centroid.z.to_f.round(tol)
          ceiling_centroid[0] += sp_surface.centroid.x.to_f * sp_surface.grossArea.to_f
          ceiling_centroid[1] += sp_surface.centroid.y.to_f * sp_surface.grossArea.to_f
          ceiling_centroid[2] += sp_surface.grossArea.to_f
        end
      end

      # Calculate the centroid of the highest surface/surfaces for this space.
      ceiling_centroid[0] /= ceiling_centroid[2]
      ceiling_centroid[1] /= ceiling_centroid[2]

      # Put the info into an array containing hashes of spaces with outdoor roofceilings
      spaces_info << {
        space: space,
        x: ceiling_centroid[0] + space.xOrigin.to_f,
        y: ceiling_centroid[1] + space.yOrigin.to_f,
        z: max_surf.centroid.z.to_f + z_origin,
        area_m2: ceiling_centroid[2]
      }
      # This is to determine which are the global highest outdoor roofceilings
      if max_height.round(tol) < (max_surf.centroid.z.to_f + z_origin).round(tol)
        max_height = (max_surf.centroid.z.to_f + z_origin).round(tol)
      end
    end
    # Go through the roofceilings and find the highest one(s) and calculate the centroid.
    spaces_info.each do |space_info|
      # If the outdoor roofceiling is one of the highest ones add it to an array of hashes and get the info needed to
      # calculate the centroid
      if space_info[:z].to_f.round(tol) == max_height.round(tol)
        top_spaces << space_info
        roof_centroid[0] += space_info[:x] * space_info[:area_m2]
        roof_centroid[1] += space_info[:y] * space_info[:area_m2]
        roof_centroid[2] += space_info[:area_m2]
      end
    end
    # calculate the centroid of the highest outdoor roofceiling(s) and add the info to a hash to return to whomever
    # called this method.
    roof_centroid[0] /= roof_centroid[2]
    roof_centroid[1] /= roof_centroid[2]
    roof_cent = {
      top_spaces: top_spaces,
      roof_centroid: [roof_centroid[0], roof_centroid[1], max_height],
      roof_area: roof_centroid[2]
    }
    return roof_cent
  end

  # Returns the surface and subsurface UA product
  #
  # @param surface [OpenStudio::Model::Surface] OpenStudio model surface object
  # @return [Double] UA product in W/K
  def surface_subsurface_ua(surface)
    # Compute the surface UA product
    cons = surface.construction.get
    fc_obj_type = cons.iddObjectType.valueName.to_s
    if surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod' && surface.construction.is_initialized
      case fc_obj_type
        when 'OS_Construction_FfactorGroundFloor'
          cons = surface.construction.get.to_FFactorGroundFloorConstruction.get
          ffac = cons.fFactor
          area = cons.area
          peri = cons.perimeterExposed
          ua = ffac * peri * surface.netArea / area
        when 'OS_Construction_CfactorUndergroundWall'
          cons = surface.construction.get.to_CFactorUndergroundWallConstruction.get
          cfac = cons.cFactor
          heig = cons.height

          # From 90.1-2019 Section A.9.4.1: Interior vertical surfaces (SI units)
          r_inside_film = 0.1197548
          r_outside_film = 0.0

          # EnergyPlus Engineering Manual equation 3.195
          r_soil = 0.0607 + (0.3479 * heig)

          r_eff = (1 / cfac) + r_soil
          u_eff = 1 / (r_eff + r_inside_film + r_outside_film)

          ua = u_eff * surface.netArea
      end
    elsif fc_obj_type == 'OS_Construction_AirBoundary'
      # Air boundary meant for lighting and air exchanges, no heat transfer happen in this surface.
      ua = 0.0
    else
      ua = surface.uFactor.get * surface.netArea if surface.uFactor.is_initialized
    end

    surface.subSurfaces.sort.each do |subsurface|
      subsurface_construction = subsurface.construction.get
      u_factor = OpenstudioStandards::SqlFile.construction_calculated_fenestration_u_factor(subsurface_construction)
      if !u_factor && subsurface.uFactor.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.surface', "Failed to search subsurface construction: #{subsurface_construction.name.get} u factor from simulation output file (SQL). It is likely due to the model is not simulated.")
        u_factor = subsurface.uFactor.get
      end
      prm_raise(u_factor, @sizing_run_dir, "Failed to calculate subsurface #{subsurface_construction.name.get} u-factor. It is likely the subsurface construction is not defined or the model is not simulated")
      ua += u_factor * subsurface.netArea
    end

    ua
  end

  # Adjust the fenestration area to the values specified by the reduction value in a surface
  #
  # @param surface [OpenStudio::Model:Surface] openstudio surface object
  # @param reduction [Double] ratio of adjustments
  # @param model [OpenStudio::Model::Model] openstudio model
  # @return [Boolean] returns true if successful, false if not
  def surface_adjust_fenestration_in_a_surface(surface, reduction, model)
    # Subsurfaces in this surface
    # Default case only handles reduction
    if reduction < 1.0
      surface.subSurfaces.sort.each do |ss|
        next unless ss.subSurfaceType == 'FixedWindow' || ss.subSurfaceType == 'OperableWindow' || ss.subSurfaceType == 'GlassDoor'

        if OpenstudioStandards::Geometry.sub_surface_vertical_rectangle?(ss)
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_raising_sill(ss, reduction)
        else
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(ss, reduction)
        end
      end
    end
    return true
  end
end
