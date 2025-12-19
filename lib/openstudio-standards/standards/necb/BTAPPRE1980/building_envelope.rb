class BTAPPRE1980
  # Reduces the WWR to the values specified by the NECB
  # NECB 3.2.1.4
  def apply_standard_window_to_wall_ratio(model:, fdwr_set: -1.0, necb_hdd: true)
    # NECB FDWR limit
    hdd = get_necb_hdd18(model: model, necb_hdd: necb_hdd)

    # Get the maximum NECB fdwr
    # fdwr_set settings:
    # 0-1:  Remove all windows and add windows to match this fdwr
    # -1:  Remove all windows and add windows to match max fdwr from NECB
    # -2:  Do not apply any fdwr changes, leave windows alone (also works for fdwr > 1)
    # -3:  Use old method which reduces existing window size (if necessary) to meet maximum NECB fdwr limit
    # <-3.1:  Remove all the windows
    # > 1:  Do nothing

    return if fdwr_set.to_f > 1.0
    return apply_max_fdwr_nrcan(model: model, fdwr_lim: fdwr_set.to_f) if fdwr_set.to_f >= 0.0 && fdwr_set <= 1.0
    return if fdwr_set.to_f >= -1.1 && fdwr_set <= -0.9
    return if fdwr_set.to_f >= -2.1 && fdwr_set <= -1.9
    return apply_limit_fdwr(model: model, fdwr_lim: (max_fwdr(hdd) * 100.0).to_f.round(1)) if fdwr_set.to_f >= -3.1 && fdwr_set <= -2.9
    return apply_max_fdwr_nrcan(model: model, fdwr_lim: fdwr_set.to_f) if fdwr_set < -3.1
  end

  # Reduces the SRR to the values specified by the PRM. SRR reduction
  # will be done by shrinking vertices toward the centroid.
  def apply_standard_skylight_to_roof_ratio(model:, srr_set: -1.0, srr_opt: '')
    # If srr_set is between 1.0 and 1.2 set it to the maximum allowed by the NECB.  If srr_set is between 0.0 and 1.0
    # apply whatever was passed.  If srr_set >= 1.2 then set the existing srr of the building to be the necb maximum
    # only if the the srr exceeds this maximum (otherwise leave it to be whatever was modeled).

    # srr_set settings:
    #   0-1:  Remove all skylights and add skylights to match this srr
    #    -1:  Remove all skylights and add skylights to match max srr from NECB
    #    -2:  Do not apply any srr changes, leave skylights alone (also works for srr > 1)
    #    -3:  Use old method which reduces existing skylight size (if necessary) to meet maximum NECB skylight limit
    # <-3.1:  Remove all skylights
    #   > 1:  Do nothing
    #
    # By default, :srr_opt is an empty string (" "). If set to "osut", SRR is
    # instead met using OSut's addSkylights (:srr_set numeric values may apply).
    return if srr_set.to_f > 1.0
    return apply_max_srr_nrcan(model: model, srr_lim: srr_set.to_f, srr_opt: srr_opt) if srr_set.to_f >= 0.0 && srr_set.to_f <= 1.0

    # No skylights set for BTAPPRE1980 buildings.
    return if srr_set.to_f >= -1.1 && srr_set <= -0.9
    return if srr_set.to_f >= -2.1 && srr_set <= -1.9
    return apply_max_srr_nrcan(model: model, srr_lim: srr_set.to_f, srr_opt: srr_opt) if srr_set.to_f < -3.1

    # Continue with the rest of this method, use old method which reduces existing skylight size (if necessary) to
    # meet maximum srr limit
    return unless srr_set.to_f >= -3.1 && srr_set <= -2.9

    # SRR limit
    srr_lim = get_standards_constant('skylight_to_roof_ratio_max_value') * 100.0

    # Loop through all spaces in the model, and
    # per the PNNL PRM Reference Manual, find the areas
    # of each space conditioning category (res, nonres, semi-heated)
    # separately.  Include space multipliers.
    nr_wall_m2 = 0.001 # Avoids divide by zero errors later
    nr_sky_m2 = 0
    res_wall_m2 = 0.001
    res_sky_m2 = 0
    sh_wall_m2 = 0.001
    sh_sky_m2 = 0
    total_roof_m2 = 0.001
    total_subsurface_m2 = 0
    model.getSpaces.sort.each do |space|
      # Loop through all surfaces in this space
      wall_area_m2 = 0
      sky_area_m2 = 0
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'

        # Skip non-walls
        next unless surface.surfaceType == 'RoofCeiling'

        # This wall's gross area (including skylight area)
        wall_area_m2 += surface.grossArea * space.multiplier
        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          sky_area_m2 += ss.netArea * space.multiplier
        end
      end

      # Determine the space category
      cat = 'NonRes'
      if OpenstudioStandards::Space.space_residential?(space)
        cat = 'Res'
      end
      # if space.is_semiheated
      # cat = 'Semiheated'
      # end

      # Add to the correct category
      case cat
      when 'NonRes'
        nr_wall_m2 += wall_area_m2
        nr_sky_m2 += sky_area_m2
      when 'Res'
        res_wall_m2 += wall_area_m2
        res_sky_m2 += sky_area_m2
      when 'Semiheated'
        sh_wall_m2 += wall_area_m2
        sh_sky_m2 += sky_area_m2
      end
      total_roof_m2 += wall_area_m2
      total_subsurface_m2 += sky_area_m2
    end

    # Calculate the SRR of each category
    srr_nr = ((nr_sky_m2 / nr_wall_m2) * 100).round(1)
    srr_res = ((res_sky_m2 / res_wall_m2) * 100).round(1)
    srr_sh = ((sh_sky_m2 / sh_wall_m2) * 100).round(1)
    srr = ((total_subsurface_m2 / total_roof_m2) * 100.0).round(1)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The skylight to roof ratios (SRRs) are: NonRes: #{srr_nr.round}%, Res: #{srr_res.round}%.")

    # Check against SRR limit
    red_nr = srr_nr > srr_lim
    red_res = srr_res > srr_lim
    red_sh = srr_sh > srr_lim

    # Stop here unless windows need reducing
    return true unless srr > srr_lim

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Reducing the size of all windows (by raising sill height) to reduce window area down to the limit of #{srr_lim.round}%.")
    # Determine the factors by which to reduce the window / door area
    mult = srr_lim / srr

    # Reduce the subsurface areas
    model.getSpaces.sort.each do |space|
      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'RoofCeiling'

        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          # Reduce the size of the subsurface
          red = 1.0 - mult
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(ss, red)
        end
      end
    end

    return true
  end

  # Go through the default construction sets and hard-assigned
  # constructions. Clone the existing constructions and set their
  # intended surface type and standards construction type per
  # the PRM.  For some standards, this will involve making
  # modifications.  For others, it will not.
  #
  # 90.1-2007, 90.1-2010, 90.1-2013
  # @return [Boolean] returns true if successful, false if not

  def apply_standard_construction_properties(
    model:,
    runner: nil,
    ext_wall_cond: nil,
    ext_floor_cond: nil,
    ext_roof_cond: nil,
    ground_wall_cond: nil,
    ground_floor_cond: nil,
    ground_roof_cond: nil,
    door_construction_cond: nil,
    fixed_window_cond: nil,
    glass_door_cond: nil,
    overhead_door_cond: nil,
    skylight_cond: nil,
    glass_door_solar_trans: nil,
    fixed_wind_solar_trans: nil,
    skylight_solar_trans: nil,
    necb_hdd: true
  )
    # this call should be removed for a more general application.
    model.getDefaultConstructionSets.sort.each do |set|
      # Set the SHGC of the default glazing material before making new constructions based on it and changing U-values.
      assign_SHGC_to_windows(model: model, default_construction_set: set, necb_hdd: necb_hdd)
    end
    super(model: model,
          runner: runner,
          ext_wall_cond: ext_wall_cond,
          ext_floor_cond: ext_floor_cond,
          ext_roof_cond: ext_roof_cond,
          ground_wall_cond: ground_wall_cond,
          ground_floor_cond: ground_floor_cond,
          ground_roof_cond: ground_roof_cond,
          door_construction_cond: door_construction_cond,
          fixed_window_cond: fixed_window_cond,
          glass_door_cond: glass_door_cond,
          overhead_door_cond: overhead_door_cond,
          skylight_cond: skylight_cond,
          glass_door_solar_trans: glass_door_solar_trans,
          fixed_wind_solar_trans: fixed_wind_solar_trans,
          skylight_solar_trans: skylight_solar_trans,
          necb_hdd: necb_hdd)
  end

  def assign_SHGC_to_windows(model:, default_construction_set:, necb_hdd: true)
    # Get HDD to determine which SHGC to use
    hdd = get_necb_hdd18(model: model, necb_hdd: necb_hdd)
    # Determine the solar heat gain coefficient from the standards data
    shgc_table = @standards_data['SHGC']
    shgc = eval(shgc_table[0]['formula'])
    # Find the default window construction material
    sub_surf_consts = default_construction_set.defaultExteriorSubSurfaceConstructions.get
    fixed_window_material = OpenStudio::Model.getConstructionByName(model, sub_surf_consts.fixedWindowConstruction.get.name.to_s).get.getLayer(0).to_SimpleGlazing.get
    # Reset the SHGC for the window material.  When I wrote this all of the windows, doors etc. used the same window
    # material.  So I set the SHGC for that material expecting it will be modified for all of the other constructions
    # too.
    fixed_window_material.setSolarHeatGainCoefficient(shgc.to_f)
  end
end
