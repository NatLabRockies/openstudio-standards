class NECB2011
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
    # <-3.1:  Remove all windows and doors
    # > 1:  Do nothing

    return if fdwr_set.to_f > 1.0
    return apply_max_fdwr_nrcan(model: model, fdwr_lim: fdwr_set.to_f) if fdwr_set.to_f >= 0.0 && fdwr_set.to_f <= 1.0
    return apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fwdr(hdd).round(3)) if fdwr_set.to_f >= -1.1 && fdwr_set.to_f <= -0.9
    return if fdwr_set.to_f >= -2.1 && fdwr_set.to_f <= -1.9
    return apply_limit_fdwr(model: model, fdwr_lim: (max_fwdr(hdd) * 100.0).round(1)) if fdwr_set.to_f >= -3.1 && fdwr_set.to_f <= -2.9
    return apply_max_fdwr_nrcan(model: model, fdwr_lim: fdwr_set.to_f) if fdwr_set.to_f < -3.1
  end

  def apply_limit_fdwr(model:, fdwr_lim:)
    # Loop through all spaces in the model, and
    # per the PNNL PRM Reference Manual, find the areas
    # of each space conditioning category (res, nonres, semi-heated)
    # separately.  Include space multipliers.
    nr_wall_m2 = 0.001 # Avoids divide by zero errors later
    nr_wind_m2 = 0
    res_wall_m2 = 0.001
    res_wind_m2 = 0
    sh_wall_m2 = 0.001
    sh_wind_m2 = 0
    total_wall_m2 = 0.001
    total_subsurface_m2 = 0.0
    # Store the space conditioning category for later use
    space_cats = {}
    model.getSpaces.sort.each do |space|
      # Loop through all surfaces in this space
      wall_area_m2 = 0
      wind_area_m2 = 0
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType.casecmp('wall').zero?

        # This wall's gross area (including window area)
        wall_area_m2 += surface.grossArea * space.multiplier
        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          wind_area_m2 += ss.netArea * space.multiplier
        end
      end

      # Determine the space category
      # @todo This should really use the heating/cooling loads
      # from the proposed building.  However, in an attempt
      # to avoid another sizing run just for this purpose,
      # conditioned status is based on heating/cooling
      # setpoints.  If heated-only, will be assumed Semiheated.
      # The full-bore method is on the next line in case needed.
      # cat = thermal_zone_conditioning_category(space, template, climate_zone)
      cooled = OpenstudioStandards::Space.space_cooled?(space)
      heated = OpenstudioStandards::Space.space_heated?(space)
      cat = 'Unconditioned'
      # Unconditioned
      if !heated && !cooled
        cat = 'Unconditioned'
        # Heated-Only
      elsif heated && !cooled
        cat = 'Semiheated'
        # Heated and Cooled
      else
        res = OpenstudioStandards::ThermalZone.thermal_zone_residential?(space.thermalZone.get)
        cat = if res
                'ResConditioned'
              else
                'NonResConditioned'
              end
      end
      space_cats[space] = cat
      # NECB2011 keep track of totals for NECB regardless of conditioned or not.
      total_wall_m2 += wall_area_m2
      total_subsurface_m2 += wind_area_m2 # this contains doors as well.

      # Add to the correct category
      case cat
      when 'Unconditioned'
        next # Skip unconditioned spaces
      when 'NonResConditioned'
        nr_wall_m2 += wall_area_m2
        nr_wind_m2 += wind_area_m2
      when 'ResConditioned'
        res_wall_m2 += wall_area_m2
        res_wind_m2 += wind_area_m2
      when 'Semiheated'
        sh_wall_m2 += wall_area_m2
        sh_wind_m2 += wind_area_m2
      end
    end

    # Calculate the WWR of each category
    wwr_nr = ((nr_wind_m2 / nr_wall_m2) * 100.0).round(1)
    wwr_res = ((res_wind_m2 / res_wall_m2) * 100).round(1)
    wwr_sh = ((sh_wind_m2 / sh_wall_m2) * 100).round(1)
    fdwr = ((total_subsurface_m2 / total_wall_m2) * 100).round(1) # used by NECB2011

    # Convert to IP and report
    nr_wind_ft2 = OpenStudio.convert(nr_wind_m2, 'm^2', 'ft^2').get
    nr_wall_ft2 = OpenStudio.convert(nr_wall_m2, 'm^2', 'ft^2').get

    res_wind_ft2 = OpenStudio.convert(res_wind_m2, 'm^2', 'ft^2').get
    res_wall_ft2 = OpenStudio.convert(res_wall_m2, 'm^2', 'ft^2').get

    sh_wind_ft2 = OpenStudio.convert(sh_wind_m2, 'm^2', 'ft^2').get
    sh_wall_ft2 = OpenStudio.convert(sh_wall_m2, 'm^2', 'ft^2').get

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "WWR NonRes = #{wwr_nr.round}%; window = #{nr_wind_ft2.round} ft2, wall = #{nr_wall_ft2.round} ft2.")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "WWR Res = #{wwr_res.round}%; window = #{res_wind_ft2.round} ft2, wall = #{res_wall_ft2.round} ft2.")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "WWR Semiheated = #{wwr_sh.round}%; window = #{sh_wind_ft2.round} ft2, wall = #{sh_wall_ft2.round} ft2.")

    # WWR limit
    wwr_lim = 40.0

    # Check against WWR limit
    red_nr = wwr_nr > wwr_lim
    red_res = wwr_res > wwr_lim
    red_sh = wwr_sh > wwr_lim

    # puts "Current FDWR is #{fdwr}, must be less than #{fdwr_lim}."
    # puts "Current subsurf area is #{total_subsurface_m2} and gross surface area is #{total_wall_m2}"
    # Stop here unless windows / doors need reducing
    return true unless fdwr > fdwr_lim

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Reducing the size of all windows (by raising sill height) to reduce window area down to the limit of #{wwr_lim.round}%.")
    # Determine the factors by which to reduce the window / door area
    mult = fdwr_lim / fdwr
    # Reduce the window area if any of the categories necessary
    model.getSpaces.sort.each do |space|
      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'Wall'

        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          # Reduce the size of the window
          red = 1.0 - mult
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_raising_sill(ss, red)
        end
      end
    end
    return true
  end

  # Reduces the SRR to the values specified by the PRM. SRR reduction
  # will be done by shrinking vertices toward the centroid.
  def apply_standard_skylight_to_roof_ratio(model:, srr_set: -1.0, srr_opt: '')
    # If srr_set is between 1.0 and 1.2 set it to the maximum allowed by the NECB.  If srr_set is between 0.0 and 1.0
    # apply whatever was passed.  If srr_set >= 1.2 then set the existing srr of the building to be the necb maximum
    # only if the the srr exceeds this maximum (otherwise leave it to be whatever was modeled).
    #
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

    # Get the maximum NECB srr
    return apply_max_srr_nrcan(model: model, srr_lim: get_standards_constant('skylight_to_roof_ratio_max_value').to_f, srr_opt: srr_opt) if srr_set.to_f >= -1.1 && srr_set.to_f <= -0.9

    return if srr_set.to_f >= -2.1 && srr_set.to_f <= -1.9
    return apply_max_srr_nrcan(model: model, srr_lim: srr_set.to_f, srr_opt: srr_opt) if srr_set.to_f < -3.1
    return unless srr_set.to_f >= -3.1 && srr_set.to_f <= -2.9

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

  # @author phylroy.lopez@nrcan.gc.ca
  # @param hdd [Float]
  # @return [Double] a constant float
  def max_fwdr(hdd)
    #  get formula from json database.
    return eval(get_standards_formula('fdwr_formula'))
  end

  ##
  # Returns NECB-required U-factor, based on surface type, outside boundary
  # condition, heating-degree-days (18C) and NECB edition (template). The bulk
  # of this should be a CSV file.
  #
  # @author denis@rd2.ca
  #
  # @param stype [#to_s] surface type, e.g. "roofceiling"
  # @param condition [#to_s] outside boundary condition, e.g. "outdoors"
  # @param hdd [#to_f] heating-degree-days 18C
  #
  # @return [Float] required U-factor, defaults to 0.110 W/m2.K.
  def max_u_necb(stype = "roofceiling", condition = "outdoors", hdd = 8000)
    hdd = hdd.respond_to?(:to_f) ? hdd.to_f : 8000

    # Admissible surface types.
    stypes = ["wall", "roofceiling", "floor", "window", "skylight", "door"]
    stype  = stype.respond_to?(:to_s) ? stype.to_s.downcase : "roofceiling"
    stype  = stypes.include?(stype) ? stype : "roofceiling"

    # Admissible outside boundary conditions.
    conditions = ["outdoors", "ground"]
    condition  = condition.respond_to?(:to_s) ? condition.to_s.downcase : "outdoors"
    condition  = conditions.include?(condition) ? condition : "outdoors"

    templates = ["NECB2011", "NECB2015", "NECB2017", "NECB2020"]

    data = {}

    # Initialize data.
    templates.each do |tp|
      data[tp] = {}

      conditions.each do |cd|
        data[tp][cd] = {}

        stypes.each { |st| data[tp][cd][st] = {} }
      end
    end

    # From NECB Part 3 tables. Moving away from BTAP formulas. Should be CSV.
    data["NECB2011"]["outdoors"]["wall"       ][3000] = 0.315
    data["NECB2011"]["outdoors"]["wall"       ][4000] = 0.278
    data["NECB2011"]["outdoors"]["wall"       ][5000] = 0.247
    data["NECB2011"]["outdoors"]["wall"       ][6000] = 0.210
    data["NECB2011"]["outdoors"]["wall"       ][7000] = 0.210
    data["NECB2011"]["outdoors"]["wall"       ][9999] = 0.183
    data["NECB2011"]["outdoors"]["roofceiling"][3000] = 0.227
    data["NECB2011"]["outdoors"]["roofceiling"][4000] = 0.183
    data["NECB2011"]["outdoors"]["roofceiling"][5000] = 0.183
    data["NECB2011"]["outdoors"]["roofceiling"][6000] = 0.162
    data["NECB2011"]["outdoors"]["roofceiling"][7000] = 0.162
    data["NECB2011"]["outdoors"]["roofceiling"][9999] = 0.142
    data["NECB2011"]["outdoors"]["floor"      ][3000] = 0.227
    data["NECB2011"]["outdoors"]["floor"      ][4000] = 0.183
    data["NECB2011"]["outdoors"]["floor"      ][5000] = 0.183
    data["NECB2011"]["outdoors"]["floor"      ][6000] = 0.162
    data["NECB2011"]["outdoors"]["floor"      ][7000] = 0.162
    data["NECB2011"]["outdoors"]["floor"      ][9999] = 0.142
    data["NECB2011"]["outdoors"]["window"     ][3000] = 2.400
    data["NECB2011"]["outdoors"]["window"     ][4000] = 2.200
    data["NECB2011"]["outdoors"]["window"     ][5000] = 2.200
    data["NECB2011"]["outdoors"]["window"     ][6000] = 2.200
    data["NECB2011"]["outdoors"]["window"     ][7000] = 2.200
    data["NECB2011"]["outdoors"]["window"     ][9999] = 1.600
    data["NECB2011"]["outdoors"]["skylight"   ][3000] = 2.400
    data["NECB2011"]["outdoors"]["skylight"   ][4000] = 2.200
    data["NECB2011"]["outdoors"]["skylight"   ][5000] = 2.200
    data["NECB2011"]["outdoors"]["skylight"   ][6000] = 2.200
    data["NECB2011"]["outdoors"]["skylight"   ][7000] = 2.200
    data["NECB2011"]["outdoors"]["skylight"   ][9999] = 1.600
    data["NECB2011"]["outdoors"]["door"       ][3000] = 2.400
    data["NECB2011"]["outdoors"]["door"       ][4000] = 2.200
    data["NECB2011"]["outdoors"]["door"       ][5000] = 2.200
    data["NECB2011"]["outdoors"]["door"       ][6000] = 2.200
    data["NECB2011"]["outdoors"]["door"       ][7000] = 2.200
    data["NECB2011"]["outdoors"]["door"       ][9999] = 1.600
    data["NECB2011"]["ground"  ]["wall"       ][3000] = 0.568
    data["NECB2011"]["ground"  ]["wall"       ][4000] = 0.379
    data["NECB2011"]["ground"  ]["wall"       ][5000] = 0.284
    data["NECB2011"]["ground"  ]["wall"       ][6000] = 0.284
    data["NECB2011"]["ground"  ]["wall"       ][7000] = 0.284
    data["NECB2011"]["ground"  ]["wall"       ][9999] = 0.210
    data["NECB2011"]["ground"  ]["roofceiling"][3000] = 0.568
    data["NECB2011"]["ground"  ]["roofceiling"][4000] = 0.379
    data["NECB2011"]["ground"  ]["roofceiling"][5000] = 0.284
    data["NECB2011"]["ground"  ]["roofceiling"][6000] = 0.284
    data["NECB2011"]["ground"  ]["roofceiling"][7000] = 0.284
    data["NECB2011"]["ground"  ]["roofceiling"][9999] = 0.210
    data["NECB2011"]["ground"  ]["floor"      ][3000] = 0.757
    data["NECB2011"]["ground"  ]["floor"      ][4000] = 0.757
    data["NECB2011"]["ground"  ]["floor"      ][5000] = 0.757
    data["NECB2011"]["ground"  ]["floor"      ][6000] = 0.757
    data["NECB2011"]["ground"  ]["floor"      ][7000] = 0.757
    data["NECB2011"]["ground"  ]["floor"      ][9999] = 0.379

    data["NECB2015"]["outdoors"]["wall"       ][3000] = 0.315
    data["NECB2015"]["outdoors"]["wall"       ][4000] = 0.278
    data["NECB2015"]["outdoors"]["wall"       ][5000] = 0.247
    data["NECB2015"]["outdoors"]["wall"       ][6000] = 0.210
    data["NECB2015"]["outdoors"]["wall"       ][7000] = 0.210
    data["NECB2015"]["outdoors"]["wall"       ][9999] = 0.183
    data["NECB2015"]["outdoors"]["roofceiling"][3000] = 0.227
    data["NECB2015"]["outdoors"]["roofceiling"][4000] = 0.183
    data["NECB2015"]["outdoors"]["roofceiling"][5000] = 0.183
    data["NECB2015"]["outdoors"]["roofceiling"][6000] = 0.162
    data["NECB2015"]["outdoors"]["roofceiling"][7000] = 0.162
    data["NECB2015"]["outdoors"]["roofceiling"][9999] = 0.142
    data["NECB2015"]["outdoors"]["floor"      ][3000] = 0.227
    data["NECB2015"]["outdoors"]["floor"      ][4000] = 0.183
    data["NECB2015"]["outdoors"]["floor"      ][5000] = 0.183
    data["NECB2015"]["outdoors"]["floor"      ][6000] = 0.162
    data["NECB2015"]["outdoors"]["floor"      ][7000] = 0.162
    data["NECB2015"]["outdoors"]["floor"      ][9999] = 0.142
    data["NECB2015"]["outdoors"]["window"     ][3000] = 2.400
    data["NECB2015"]["outdoors"]["window"     ][4000] = 2.200
    data["NECB2015"]["outdoors"]["window"     ][5000] = 2.200
    data["NECB2015"]["outdoors"]["window"     ][6000] = 2.200
    data["NECB2015"]["outdoors"]["window"     ][7000] = 2.200
    data["NECB2015"]["outdoors"]["window"     ][9999] = 1.600
    data["NECB2015"]["outdoors"]["skylight"   ][3000] = 2.400
    data["NECB2015"]["outdoors"]["skylight"   ][4000] = 2.200
    data["NECB2015"]["outdoors"]["skylight"   ][5000] = 2.200
    data["NECB2015"]["outdoors"]["skylight"   ][6000] = 2.200
    data["NECB2015"]["outdoors"]["skylight"   ][7000] = 2.200
    data["NECB2015"]["outdoors"]["skylight"   ][9999] = 1.600
    data["NECB2015"]["outdoors"]["door"       ][3000] = 2.400
    data["NECB2015"]["outdoors"]["door"       ][4000] = 2.200
    data["NECB2015"]["outdoors"]["door"       ][5000] = 2.200
    data["NECB2015"]["outdoors"]["door"       ][6000] = 2.200
    data["NECB2015"]["outdoors"]["door"       ][7000] = 2.200
    data["NECB2015"]["outdoors"]["door"       ][9999] = 1.600
    data["NECB2015"]["ground"  ]["wall"       ][3000] = 0.568
    data["NECB2015"]["ground"  ]["wall"       ][4000] = 0.379
    data["NECB2015"]["ground"  ]["wall"       ][5000] = 0.284
    data["NECB2015"]["ground"  ]["wall"       ][6000] = 0.284
    data["NECB2015"]["ground"  ]["wall"       ][7000] = 0.284
    data["NECB2015"]["ground"  ]["wall"       ][9999] = 0.210
    data["NECB2015"]["ground"  ]["roofceiling"][3000] = 0.568
    data["NECB2015"]["ground"  ]["roofceiling"][4000] = 0.379
    data["NECB2015"]["ground"  ]["roofceiling"][5000] = 0.284
    data["NECB2015"]["ground"  ]["roofceiling"][6000] = 0.284
    data["NECB2015"]["ground"  ]["roofceiling"][7000] = 0.284
    data["NECB2015"]["ground"  ]["roofceiling"][9999] = 0.210
    data["NECB2015"]["ground"  ]["floor"      ][3000] = 0.757
    data["NECB2015"]["ground"  ]["floor"      ][4000] = 0.757
    data["NECB2015"]["ground"  ]["floor"      ][5000] = 0.757
    data["NECB2015"]["ground"  ]["floor"      ][6000] = 0.757
    data["NECB2015"]["ground"  ]["floor"      ][7000] = 0.757
    data["NECB2015"]["ground"  ]["floor"      ][9999] = 0.379

    data["NECB2017"]["outdoors"]["wall"       ][3000] = 0.315
    data["NECB2017"]["outdoors"]["wall"       ][4000] = 0.278
    data["NECB2017"]["outdoors"]["wall"       ][5000] = 0.247
    data["NECB2017"]["outdoors"]["wall"       ][6000] = 0.210
    data["NECB2017"]["outdoors"]["wall"       ][7000] = 0.210
    data["NECB2017"]["outdoors"]["wall"       ][9999] = 0.183
    data["NECB2017"]["outdoors"]["roofceiling"][3000] = 0.193
    data["NECB2017"]["outdoors"]["roofceiling"][4000] = 0.156
    data["NECB2017"]["outdoors"]["roofceiling"][5000] = 0.156
    data["NECB2017"]["outdoors"]["roofceiling"][6000] = 0.138
    data["NECB2017"]["outdoors"]["roofceiling"][7000] = 0.138
    data["NECB2017"]["outdoors"]["roofceiling"][9999] = 0.121
    data["NECB2017"]["outdoors"]["floor"      ][3000] = 0.227
    data["NECB2017"]["outdoors"]["floor"      ][4000] = 0.183
    data["NECB2017"]["outdoors"]["floor"      ][5000] = 0.183
    data["NECB2017"]["outdoors"]["floor"      ][6000] = 0.162
    data["NECB2017"]["outdoors"]["floor"      ][7000] = 0.162
    data["NECB2017"]["outdoors"]["floor"      ][9999] = 0.142
    data["NECB2017"]["outdoors"]["window"     ][3000] = 2.100
    data["NECB2017"]["outdoors"]["window"     ][4000] = 1.900
    data["NECB2017"]["outdoors"]["window"     ][5000] = 1.900
    data["NECB2017"]["outdoors"]["window"     ][6000] = 1.900
    data["NECB2017"]["outdoors"]["window"     ][7000] = 1.900
    data["NECB2017"]["outdoors"]["window"     ][9999] = 1.400
    data["NECB2017"]["outdoors"]["skylight"   ][3000] = 2.100
    data["NECB2017"]["outdoors"]["skylight"   ][4000] = 1.900
    data["NECB2017"]["outdoors"]["skylight"   ][5000] = 1.900
    data["NECB2017"]["outdoors"]["skylight"   ][6000] = 1.900
    data["NECB2017"]["outdoors"]["skylight"   ][7000] = 1.900
    data["NECB2017"]["outdoors"]["skylight"   ][9999] = 1.400
    data["NECB2017"]["outdoors"]["door"       ][3000] = 2.100
    data["NECB2017"]["outdoors"]["door"       ][4000] = 1.900
    data["NECB2017"]["outdoors"]["door"       ][5000] = 1.900
    data["NECB2017"]["outdoors"]["door"       ][6000] = 1.900
    data["NECB2017"]["outdoors"]["door"       ][7000] = 1.900
    data["NECB2017"]["outdoors"]["door"       ][9999] = 1.400
    data["NECB2017"]["ground"  ]["wall"       ][3000] = 0.568
    data["NECB2017"]["ground"  ]["wall"       ][4000] = 0.379
    data["NECB2017"]["ground"  ]["wall"       ][5000] = 0.284
    data["NECB2017"]["ground"  ]["wall"       ][6000] = 0.284
    data["NECB2017"]["ground"  ]["wall"       ][7000] = 0.284
    data["NECB2017"]["ground"  ]["wall"       ][9999] = 0.210
    data["NECB2017"]["ground"  ]["roofceiling"][3000] = 0.568
    data["NECB2017"]["ground"  ]["roofceiling"][4000] = 0.379
    data["NECB2017"]["ground"  ]["roofceiling"][5000] = 0.284
    data["NECB2017"]["ground"  ]["roofceiling"][6000] = 0.284
    data["NECB2017"]["ground"  ]["roofceiling"][7000] = 0.284
    data["NECB2017"]["ground"  ]["roofceiling"][9999] = 0.210
    data["NECB2017"]["ground"  ]["floor"      ][3000] = 0.757
    data["NECB2017"]["ground"  ]["floor"      ][4000] = 0.757
    data["NECB2017"]["ground"  ]["floor"      ][5000] = 0.757
    data["NECB2017"]["ground"  ]["floor"      ][6000] = 0.757
    data["NECB2017"]["ground"  ]["floor"      ][7000] = 0.757
    data["NECB2017"]["ground"  ]["floor"      ][9999] = 0.379

    data["NECB2020"]["outdoors"]["wall"       ][3000] = 0.290
    data["NECB2020"]["outdoors"]["wall"       ][4000] = 0.265
    data["NECB2020"]["outdoors"]["wall"       ][5000] = 0.240
    data["NECB2020"]["outdoors"]["wall"       ][6000] = 0.215
    data["NECB2020"]["outdoors"]["wall"       ][7000] = 0.190
    data["NECB2020"]["outdoors"]["wall"       ][9999] = 0.165
    data["NECB2020"]["outdoors"]["roofceiling"][3000] = 0.164
    data["NECB2020"]["outdoors"]["roofceiling"][4000] = 0.156
    data["NECB2020"]["outdoors"]["roofceiling"][5000] = 0.138
    data["NECB2020"]["outdoors"]["roofceiling"][6000] = 0.121
    data["NECB2020"]["outdoors"]["roofceiling"][7000] = 0.117
    data["NECB2020"]["outdoors"]["roofceiling"][9999] = 0.110
    data["NECB2020"]["outdoors"]["floor"      ][3000] = 0.193
    data["NECB2020"]["outdoors"]["floor"      ][4000] = 0.175
    data["NECB2020"]["outdoors"]["floor"      ][5000] = 0.156
    data["NECB2020"]["outdoors"]["floor"      ][6000] = 0.138
    data["NECB2020"]["outdoors"]["floor"      ][7000] = 0.121
    data["NECB2020"]["outdoors"]["floor"      ][9999] = 0.117
    data["NECB2020"]["outdoors"]["window"     ][3000] = 1.900
    data["NECB2020"]["outdoors"]["window"     ][4000] = 1.900
    data["NECB2020"]["outdoors"]["window"     ][5000] = 1.730
    data["NECB2020"]["outdoors"]["window"     ][6000] = 1.730
    data["NECB2020"]["outdoors"]["window"     ][7000] = 1.440
    data["NECB2020"]["outdoors"]["window"     ][9999] = 1.440
    data["NECB2020"]["outdoors"]["skylight"   ][3000] = 2.690
    data["NECB2020"]["outdoors"]["skylight"   ][4000] = 2.690
    data["NECB2020"]["outdoors"]["skylight"   ][5000] = 2.410
    data["NECB2020"]["outdoors"]["skylight"   ][6000] = 2.410
    data["NECB2020"]["outdoors"]["skylight"   ][7000] = 2.010
    data["NECB2020"]["outdoors"]["skylight"   ][9999] = 2.010
    data["NECB2020"]["outdoors"]["door"       ][3000] = 2.120
    data["NECB2020"]["outdoors"]["door"       ][4000] = 1.900
    data["NECB2020"]["outdoors"]["door"       ][5000] = 1.900
    data["NECB2020"]["outdoors"]["door"       ][6000] = 1.900
    data["NECB2020"]["outdoors"]["door"       ][7000] = 1.900
    data["NECB2020"]["outdoors"]["door"       ][9999] = 1.440
    data["NECB2020"]["ground"  ]["wall"       ][3000] = 0.568
    data["NECB2020"]["ground"  ]["wall"       ][4000] = 0.379
    data["NECB2020"]["ground"  ]["wall"       ][5000] = 0.284
    data["NECB2020"]["ground"  ]["wall"       ][6000] = 0.284
    data["NECB2020"]["ground"  ]["wall"       ][7000] = 0.284
    data["NECB2020"]["ground"  ]["wall"       ][9999] = 0.210
    data["NECB2020"]["ground"  ]["roofceiling"][3000] = 0.568
    data["NECB2020"]["ground"  ]["roofceiling"][4000] = 0.379
    data["NECB2020"]["ground"  ]["roofceiling"][5000] = 0.284
    data["NECB2020"]["ground"  ]["roofceiling"][6000] = 0.284
    data["NECB2020"]["ground"  ]["roofceiling"][7000] = 0.284
    data["NECB2020"]["ground"  ]["roofceiling"][9999] = 0.210
    data["NECB2020"]["ground"  ]["floor"      ][3000] = 0.757
    data["NECB2020"]["ground"  ]["floor"      ][4000] = 0.757
    data["NECB2020"]["ground"  ]["floor"      ][5000] = 0.757
    data["NECB2020"]["ground"  ]["floor"      ][6000] = 0.757
    data["NECB2020"]["ground"  ]["floor"      ][7000] = 0.757
    data["NECB2020"]["ground"  ]["floor"      ][9999] = 0.379

    # Return required U-factor if provided HDD < stored HDD.
    data[@template][condition][stype].each { |hdd18, u| return u if hdd < hdd18 }

    0.110
  end

  ##
  # Adds default construction sets, based on building 'category' & 'structure'
  # selections. This is an alternative method to 'model_apply_construction'
  # & 'apply_standard_construction_properties' methods.
  #
  # @author denis@rd2.ca
  #
  # @param model [OpenStudio::Model::Model] a model
  # @param necb_hdd [Boolean] whether to rely on BTAP to set HDD (vs stat file)
  # @param a [Hash] optional U & SHGC overrides
  # @option a [Hash] eWallU exposed wall Uo (or Ut)
  # @option a [Hash] eFloorU exposed floor Uo (or Ut)
  # @option a [Hash] eRoofU exposed roof Uo (or Ut)
  # @option a [Hash] gWallU ground wall Uo (or Ut)
  # @option a [Hash] gFloorU ground floor Uo (or Ut)
  # @option a [Hash] gRoofU ground roof Uo (or Ut)
  # @option a [Hash] doorU opaque door U
  # @option a [Hash] fenU fenestration U (e.g. fixe, operable, glass door)
  # @option a [Hash] skyU skylight U
  # @option a [Hash] doorSHGC opaque door SHGC
  # @option a [Hash] fenSHGC fenestration SHGC
  # @option a [Hash] skySHGC skylight SHGC
  #
  # @return [Boolean] whether default constructions were successfully added.
  def add_construction_sets(model, necb_hdd, a)
    return false unless model.is_a?(OpenStudio::Model::Model)
    return false unless a.is_a?(Hash)

    btp = BTAP::Resources::Envelope::Constructions # alias
    necb_hdd = true unless [true, false].include?(necb_hdd)

    # Validate argh options (limited to either U or SHGC)
    a.each do |k, v|
      return false unless v.is_a?(Numeric)
      return false unless v.round(3) > 0

      if k.to_s[-1].downcase == "u"
        return false unless v.between?(btp::uMIN, btp::uMAX)
      else
        return false unless v.between?(0.05, 0.95)
      end
    end

    tag  = "space_conditioning_category"
    bldg = model.getBuilding
    hdd  = get_necb_hdd18(model: model, necb_hdd: necb_hdd)

    # Reset constructions.
    model.getPlanarSurfaces.sort.each(&:resetConstruction)

    # Fetch NECB-required U-factors (or provided as arguments).
    eWallU  = a[:eWallU ] ? a[:eWallU ] : max_u_necb("wall", "outdoors", hdd)
    eRoofU  = a[:eRoofU ] ? a[:eRoofU ] : max_u_necb("roofceiling", "outdoors", hdd)
    eFloorU = a[:eFloorU] ? a[:eFloorU] : max_u_necb("floor", "outdoors", hdd)
    gWallU  = a[:gWallU ] ? a[:gWallU ] : max_u_necb("wall", "ground", hdd)
    gFloorU = a[:gFloorU] ? a[:gFloorU] : max_u_necb("floor", "ground", hdd)
    gRoofU  = a[:gRoofU ] ? a[:gRoofU ] : max_u_necb("roofceiling", "ground", hdd)
    doorU   = a[:doorU  ] ? a[:doorU  ] : max_u_necb("door", "outdoors", hdd)
    fenU    = a[:fenU   ] ? a[:fenU   ] : max_u_necb("window", "outdoors", hdd)
    skyU    = a[:skyU   ] ? a[:skyU   ] : max_u_necb("skylight", "outdoors", hdd)

    # FYI: Excerpt of the 'SimpleGlazing' material generated using BTAP:
    #
    #   SimpleGlazing:U=0.220 SHGC=0.600, !- Name
    #     2.2,                            !- U-Factor {W/m2-K}
    #     0.6,                            !- Solar Heat Gain Coefficient
    #     0.21;                           !- Visible Transmittance
    #
    # 1. Identifier 'U=0.220' for an NFRC-rated U-factor of 2.2 W/m2.K ?
    # 2. VT is almost always higher than SHGC - not the other way around. VT
    #    should be set here based on a reasonable LSG ratio:
    #    - eta-publications.lbl.gov/sites/default/files/femp-spec-sel-low-e.pdf
    #    - www.wbdg.org/resources/windows-and-glazing
    #
    # ... for the moment, sticking to SHGC 60%, yet keeping default VT.
    doorSHGC = a[:doorSHGC] ? a[:doorSHGC] : 0.60
    fenSHGC  = a[:fenSHGC ] ? a[:fenSHGC ] : 0.60
    skySHGC  = a[:skySHGC ] ? a[:skySHGC ] : 0.60

    # Fetch corresponding BTAP structure parameters.
    category  = @structure.category
    structure = @structure.structure
    framing   = @structure.framing
    cladding  = @structure.cladding
    finish    = @structure.finish

    # Uninsulated slab-on-grade, except if HDD > 6999 (Uo = 0.379 W/m2.K).
    # If HDD < 7000, slab-on-grade insulation is instead only required along
    # perimeter. Perimeter insulation requires special treatment, à la KIVA. The
    # vast majority of models do not have full-height basements. Exceptions:
    #   - LargeOffice
    #   - LargeHotel
    #   - Hospital
    #
    # The solution is temporarily OK, yet a more nuanced treatment is required
    # for full-height basement cases. This would likely require a space-by-space
    # treatment, based on Z-axis grade-vs-floor height difference - @todo.
    specs          = {}
    specs[:type  ] = :slab
    specs[:uo    ] = nil
    specs[:uo    ] = gFloorU   if hdd > 6999
    specs[:frame ] = :none unless hdd > 6999
    specs[:finish] = :none     if category == "robust"
    specs[:finish] = :none     if category == "industry"
    gFloor         = TBD.genConstruction(model, specs)
    insulation     = TBD.insulatingLayer(gFloor)

    # Ensure insulating layer uniqueness for each insulated construction.
    lyr = TBD.insulatingLayer(gFloor)
    TBD.assignUniqueMaterial(gFloor, lyr[:index]) if lyr[:index]

    # Insulated basement wall. A more nuanced treatment is necessary for
    # multiple basement stories - no insulation required below 2.4m from grade.
    specs          = {}
    specs[:type  ] = :basement
    specs[:uo    ] = gWallU
    gWall          = TBD.genConstruction(model, specs)

    lyr = TBD.insulatingLayer(gWall)
    TBD.assignUniqueMaterial(gWall, lyr[:index]) if lyr[:index]

    # Insulated basement roof. Again, a more nuanced approach is necessary if
    # the basement roof is below 1.2m from grade (e.g. a tunnel).
    specs          = {}
    specs[:type  ] = :roof
    specs[:uo    ] = gRoofU
    specs[:frame ] = :medium
    specs[:finish] = :heavy
    gRoof          = TBD.genConstruction(model, specs)

    lyr = TBD.insulatingLayer(gRoof)
    TBD.assignUniqueMaterial(gRoof, lyr[:index]) if lyr[:index]

    # Outdoor-facing wall.
    specs          = {}
    specs[:type  ] = :wall
    specs[:uo    ] = eWallU
    specs[:frame ] = :medium
    specs[:clad  ] = :heavy  if category == "robust"
    specs[:finish] = :medium if category == "robust"
    specs[:finish] = :medium if framing  == :cmu
    eWall          = TBD.genConstruction(model, specs)

    lyr = TBD.insulatingLayer(eWall)
    TBD.assignUniqueMaterial(eWall, lyr[:index]) if lyr[:index]

    # Outdoor-facing roof.
    specs          = {}
    specs[:type  ] = :roof
    specs[:uo    ] = eRoofU
    specs[:clad  ] = :medium if category == "housing" && structure == :concrete
    specs[:clad  ] = :medium if category == "lodging" && structure == :concrete
    specs[:frame ] = :medium
    specs[:frame ] = :heavy  if framing  == :wood
    specs[:finish] = :medium if category == "robust"
    specs[:finish] = :heavy  if category == "housing" && structure == :concrete
    specs[:finish] = :heavy  if category == "lodging" && structure == :concrete
    eRoof          = TBD.genConstruction(model, specs)

    lyr = TBD.insulatingLayer(eRoof)
    TBD.assignUniqueMaterial(eRoof, lyr[:index]) if lyr[:index]

    # Outdoor-facing floor.
    specs          = {}
    specs[:type  ] = :floor
    specs[:uo    ] = eFloorU
    specs[:finish] = :medium unless framing == :wood
    specs[:finish] = :heavy  if category == "housing" && structure == :concrete
    specs[:finish] = :heavy  if category == "lodging" && structure == :concrete
    eFloor         = TBD.genConstruction(model, specs)

    lyr = TBD.insulatingLayer(eFloor)
    TBD.assignUniqueMaterial(eFloor, lyr[:index]) if lyr[:index]

    # Outdoor-facing, opaque door.
    specs          = {}
    specs[:type  ] = :door
    specs[:uo    ] = doorU
    door           = TBD.genConstruction(model, specs)

    # Outdoor-facing, vertical fenestration.
    specs          = {}
    specs[:type  ] = :window
    specs[:uo    ] = fenU
    specs[:shgc  ] = fenSHGC
    fen            = TBD.genConstruction(model, specs)

    # Outdoor-facing, horizontal skylight.
    specs          = {}
    specs[:type  ] = :skylight
    specs[:uo    ] = skyU
    specs[:shgc  ] = skySHGC
    sky            = TBD.genConstruction(model, specs)

    # Interzone/partition wall.
    specs          = {}
    specs[:type  ] = :partition
    iWall          = TBD.genConstruction(model, specs)

    # Interzone roof/ceiling & floor.
    specs          = {}
    specs[:type  ] = :partition
    specs[:frame ] = :medium unless framing == :wood
    specs[:frame ] = :heavy  if category == "housing" && structure == :concrete
    specs[:frame ] = :heavy  if category == "lodging" && structure == :concrete
    specs[:frame ] = :heavy  if category == "robust"
    specs[:clad  ] = :none   if category == "robust"
    specs[:finish] = :none   if category == "robust"
    iRoof          = TBD.genConstruction(model, specs)
    iFloor         = TBD.genConstruction(model, specs)

    # Shading material.
    specs          = {type: :shading}
    shading        = TBD.genConstruction(model, specs)

    # Building-wide, default constructions.
    intBLDG = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    solBLDG = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    extBLDG = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    subBLDG = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
    intBLDG.setName("BTAP interior constructions BLDG")
    solBLDG.setName("BTAP ground constructions BLDG")
    extBLDG.setName("BTAP exterior constructions BLDG")
    subBLDG.setName("BTAP subsurface constructions BLDG")
    intBLDG.setWallConstruction(iWall)
    intBLDG.setFloorConstruction(iFloor)
    intBLDG.setRoofCeilingConstruction(iRoof)
    solBLDG.setWallConstruction(gWall)
    solBLDG.setFloorConstruction(gFloor)
    solBLDG.setRoofCeilingConstruction(gRoof)
    extBLDG.setWallConstruction(eWall)
    extBLDG.setFloorConstruction(eFloor)
    extBLDG.setRoofCeilingConstruction(eRoof)
    subBLDG.setFixedWindowConstruction(fen)
    subBLDG.setOperableWindowConstruction(fen)
    subBLDG.setGlassDoorConstruction(fen)
    subBLDG.setSkylightConstruction(sky)
    subBLDG.setTubularDaylightDomeConstruction(sky)
    subBLDG.setTubularDaylightDiffuserConstruction(sky)
    subBLDG.setDoorConstruction(door)
    subBLDG.setOverheadDoorConstruction(door)

    setBLDG = OpenStudio::Model::DefaultConstructionSet.new(model)
    setBLDG.setName("BTAP construction set BLDG")
    setBLDG.setDefaultInteriorSurfaceConstructions(intBLDG)
    setBLDG.setDefaultGroundContactSurfaceConstructions(solBLDG)
    setBLDG.setDefaultExteriorSurfaceConstructions(extBLDG)
    setBLDG.setDefaultExteriorSubSurfaceConstructions(subBLDG)
    setBLDG.setInteriorPartitionConstruction(iWall)
    setBLDG.setSpaceShadingConstruction(shading)
    setBLDG.setBuildingShadingConstruction(shading)
    setBLDG.setSiteShadingConstruction(shading)
    setBLDG.setAdiabaticSurfaceConstruction(iWall)

    bldg.setDefaultConstructionSet(setBLDG)

    # Unconditioned, unoccupied spaces (e.g. attics) inherit their own
    # default construction set. Indirectly-conditioned, unoccupied spaces
    # (e.g. plenums) also inherit their own construction set.
    attics  = []
    plenums = []

    model.getSpaces.each do |space|
      prop = space.additionalProperties.getFeatureAsString(tag)
      next if prop.empty?
      next if space.partofTotalFloorArea

      prop = prop.get.downcase
      attics  << space if prop == "unconditioned"
      plenums << space if prop == "nonresconditioned"
    end

    # None of the outdoor-facing surfaces of attics are required to be
    # insulated. All attic interzone surfaces are required to be insulated.
    unless attics.empty?
      specs          = {}
      specs[:type  ] = :slab
      specs[:uo    ] = nil
      specs[:frame ] = :none
      specs[:finish] = :none
      gAtticFloor    = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :basement
      specs[:clad  ] = :none
      specs[:finish] = :none
      gAtticWall     = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :roof
      specs[:uo    ] = nil
      specs[:clad  ] = :none
      specs[:finish] = :heavy
      gAtticRoof     = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :wall
      specs[:uo    ] = nil
      specs[:clad  ] = :none
      specs[:finish] = :none
      eAtticWall     = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :roof
      specs[:uo    ] = nil
      specs[:clad  ] = :none
      eAtticRoof     = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :floor
      specs[:uo    ] = nil
      specs[:finish] = :none
      eAtticFloor    = TBD.genConstruction(model, specs)

      specs          = {}
      specs[:type  ] = :partition
      specs[:uo    ] = eWallU
      iAtticWall     = TBD.genConstruction(model, specs)

      lyr = TBD.insulatingLayer(iAtticWall)
      TBD.assignUniqueMaterial(iAtticWall, lyr[:index]) if lyr[:index]

      specs          = {}
      specs[:type  ] = :floor
      specs[:uo    ] = eFloorU
      specs[:frame ] = :heavy
      specs[:finish] = :none
      specs[:finish] = :heavy if structure == :concrete
      iAtticFloor    = TBD.genConstruction(model, specs)

      lyr = TBD.insulatingLayer(iAtticFloor)
      TBD.assignUniqueMaterial(iAtticFloor, lyr[:index]) if lyr[:index]

      specs          = {}
      specs[:type  ] = :floor
      specs[:uo    ] = eRoofU
      specs[:frame ] = :light
      specs[:frame ] = :heavy if framing == :wood
      specs[:clad  ] = :none
      specs[:clad  ] = :heavy if category == "robust"
      iAtticRoof     = TBD.genConstruction(model, specs)

      lyr = TBD.insulatingLayer(iAtticRoof)
      TBD.assignUniqueMaterial(iAtticRoof, lyr[:index]) if lyr[:index]

      intATTIC = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
      solATTIC = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
      extATTIC = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
      intATTIC.setName("BTAP interior constructions ATTIC")
      solATTIC.setName("BTAP ground constructions ATTIC")
      extATTIC.setName("BTAP exterior constructions ATTIC")
      intATTIC.setWallConstruction(iAtticWall)
      intATTIC.setFloorConstruction(iAtticFloor)
      intATTIC.setRoofCeilingConstruction(iAtticRoof)
      solATTIC.setWallConstruction(gAtticWall)
      solATTIC.setFloorConstruction(gAtticFloor)
      solATTIC.setRoofCeilingConstruction(gAtticRoof)
      extATTIC.setWallConstruction(eAtticWall)
      extATTIC.setFloorConstruction(eAtticFloor)
      extATTIC.setRoofCeilingConstruction(eAtticRoof)

      setATTIC = OpenStudio::Model::DefaultConstructionSet.new(model)
      setATTIC.setName("BTAP construction set ATTIC")
      setATTIC.setDefaultInteriorSurfaceConstructions(intATTIC)
      setATTIC.setDefaultGroundContactSurfaceConstructions(solATTIC)
      setATTIC.setDefaultExteriorSurfaceConstructions(extATTIC)

      attics.each { |attic| attic.setDefaultConstructionSet(setATTIC) }
    end

    # No change for outdoor-facing surfaces (vs BLDG default construction set).
    # Treat interzone 'plenum' floors as uninsulated ceiling tiles.
    unless plenums.empty?
      specs          = {}
      specs[:type  ] = :partition
      specs[:uo    ] = nil
      specs[:clad  ] = :none
      specs[:finish] = :none
      iPlenumFloor   = TBD.genConstruction(model, specs)

      intPLENUM = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
      intPLENUM.setName("BTAP interior constructions PLENUM")
      intPLENUM.setFloorConstruction(iPlenumFloor)

      setPLENUM = OpenStudio::Model::DefaultConstructionSet.new(model)
      setPLENUM.setName("BTAP construction set PLENUM")
      setPLENUM.setDefaultInteriorSurfaceConstructions(intPLENUM)

      plenums.each { |plenum| plenum.setDefaultConstructionSet(setPLENUM) }
    end

    # The above solution should work well for prototype models distributed with
    # OpenStudio-Standards. However, the solution may assign odd construction
    # choices for some 3rd-party models, e.g. underfloor plenums or 'sandwiched'
    # unconditioned spaces. It is quite feasible to introduce a final safeguard
    # check that would loop through all surfaces to:
    #   - check if insulated when required
    #   - ensure uninsulated assemblies unless required
    #   - hard assign constructions if either case
    #
    # Future upgrades could include adding story- or space-specific default
    # construction sets (e.g. CMU walls of a school gym in an otherwise
    # steel-framed school). @todo

    true
  end

  # Go through the default construction sets and hard-assigned
  # constructions. Clone the existing constructions and set their
  # intended surface type and standards construction type per
  # the PRM.  For some standards, this will involve making
  # modifications.  For others, it will not.
  #
  # 90.1-2007, 90.1-2010, 90.1-2013
  # @return [Boolean] returns true if successful, false if not

  def apply_standard_construction_properties(model:,
                                             runner: nil,
                                             # ext surfaces
                                             ext_wall_cond: nil,
                                             ext_floor_cond: nil,
                                             ext_roof_cond: nil,
                                             # ground surfaces
                                             ground_wall_cond: nil,
                                             ground_floor_cond: nil,
                                             ground_roof_cond: nil,
                                             # fixed Windows
                                             fixed_window_cond: nil,
                                             fixed_wind_solar_trans: nil,
                                             fixed_wind_vis_trans: nil,
                                             # operable windows
                                             operable_wind_solar_trans: nil,
                                             operable_window_cond: nil,
                                             operable_wind_vis_trans: nil,
                                             # glass doors
                                             glass_door_cond: nil,
                                             glass_door_solar_trans: nil,
                                             glass_door_vis_trans: nil,
                                             # opaque doors
                                             door_construction_cond: nil,
                                             overhead_door_cond: nil,
                                             # skylights
                                             skylight_cond: nil,
                                             skylight_solar_trans: nil,
                                             skylight_vis_trans: nil,
                                             # tubular daylight dome
                                             tubular_daylight_dome_cond: nil,
                                             tubular_daylight_dome_solar_trans: nil,
                                             tubular_daylight_dome_vis_trans: nil,
                                             # tubular daylight diffuser
                                             tubular_daylight_diffuser_cond: nil,
                                             tubular_daylight_diffuser_solar_trans: nil,
                                             tubular_daylight_diffuser_vis_trans: nil,
                                             necb_hdd: true)

    model.getDefaultConstructionSets.sort.each do |default_surface_construction_set|
      BTAP.runner_register('Info', 'apply_standard_construction_properties', runner)
      if model.weatherFile.empty? || model.weatherFile.get.path.empty? || !File.exist?(model.weatherFile.get.path.get.to_s)

        BTAP.runner_register('Error', 'Weather file is not defined. Please ensure the weather file is defined and exists.', runner)
        return false
      end

      # hdd required in scope for eval function.
      hdd = get_necb_hdd18(model: model, necb_hdd: necb_hdd)
      # Lambdas are preferred over methods in methods for small utility methods.
      correct_cond = lambda do |conductivity, surface_type|
        return conductivity.nil? || conductivity.to_f <= 0.0 || conductivity == 'NECB_Default' ? eval(model_find_objects(@standards_data['surface_thermal_transmittance'], surface_type)[0]['formula']) : conductivity.to_f
      end

      # Converts trans and vis to nil if requesting default.. or casts the string to a float.
      correct_vis_trans = lambda do |value|
        return value.nil? || value.to_f <= 0.0 || value == 'NECB_Default' ? nil : value.to_f
      end

      BTAP::Resources::Envelope::ConstructionSets.customize_default_surface_construction_set!(model: model,
                                                                                              name: "#{default_surface_construction_set.name.get} at hdd = #{get_necb_hdd18(model: model, necb_hdd: necb_hdd)}",
                                                                                              default_surface_construction_set: default_surface_construction_set,
                                                                                              # ext surfaces
                                                                                              ext_wall_cond: correct_cond.call(ext_wall_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Wall'),
                                                                                              ext_floor_cond: correct_cond.call(ext_floor_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Floor'),
                                                                                              ext_roof_cond: correct_cond.call(ext_roof_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'RoofCeiling'),
                                                                                              # ground surfaces
                                                                                              ground_wall_cond: correct_cond.call(ground_wall_cond, 'boundary_condition' => 'Ground', 'surface' => 'Wall'),
                                                                                              ground_floor_cond: correct_cond.call(ground_floor_cond, 'boundary_condition' => 'Ground', 'surface' => 'Floor'),
                                                                                              ground_roof_cond: correct_cond.call(ground_roof_cond, 'boundary_condition' => 'Ground', 'surface' => 'RoofCeiling'),
                                                                                              # fixed Windows
                                                                                              fixed_window_cond: correct_cond.call(fixed_window_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              fixed_wind_solar_trans: correct_vis_trans.call(fixed_wind_solar_trans),
                                                                                              fixed_wind_vis_trans: correct_vis_trans.call(fixed_wind_vis_trans),
                                                                                              # operable windows
                                                                                              operable_wind_solar_trans: correct_vis_trans.call(operable_wind_solar_trans),
                                                                                              operable_window_cond: correct_cond.call(fixed_window_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              operable_wind_vis_trans: correct_vis_trans.call(operable_wind_vis_trans),
                                                                                              # glass doors
                                                                                              glass_door_cond: correct_cond.call(glass_door_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              glass_door_solar_trans: correct_vis_trans.call(glass_door_solar_trans),
                                                                                              glass_door_vis_trans: correct_vis_trans.call(glass_door_vis_trans),
                                                                                              # opaque doors
                                                                                              door_construction_cond: correct_cond.call(door_construction_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Door'),
                                                                                              overhead_door_cond: correct_cond.call(overhead_door_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Door'),
                                                                                              # skylights
                                                                                              skylight_cond: correct_cond.call(skylight_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              skylight_solar_trans: correct_vis_trans.call(skylight_solar_trans),
                                                                                              skylight_vis_trans: correct_vis_trans.call(skylight_vis_trans),
                                                                                              # tubular daylight dome
                                                                                              tubular_daylight_dome_cond: correct_cond.call(skylight_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              tubular_daylight_dome_solar_trans: correct_vis_trans.call(tubular_daylight_dome_solar_trans),
                                                                                              tubular_daylight_dome_vis_trans: correct_vis_trans.call(tubular_daylight_dome_vis_trans),
                                                                                              # tubular daylight diffuser
                                                                                              tubular_daylight_diffuser_cond: correct_cond.call(skylight_cond, 'boundary_condition' => 'Outdoors', 'surface' => 'Window'),
                                                                                              tubular_daylight_diffuser_solar_trans: correct_vis_trans.call(tubular_daylight_diffuser_solar_trans),
                                                                                              tubular_daylight_diffuser_vis_trans: correct_vis_trans.call(tubular_daylight_diffuser_vis_trans))
    end
    # sets all surfaces to use default constructions sets except adiabatic, where it does a hard assignment of the interior wall construction type.
    model.getPlanarSurfaces.sort.each(&:resetConstruction)
    # if the default construction set is defined..try to assign the interior wall to the adiabatic surfaces
    BTAP::Resources::Envelope.assign_interior_surface_construction_to_adiabatic_surfaces(model, nil)
    BTAP.runner_register('Info', ' apply_standard_construction_properties was sucessful.', runner)
  end

  # Set all external surface conductances to NECB values.
  # @author phylroy.lopez@nrcan.gc.ca
  # @param surface [String]
  # @param hdd [Float]
  # @param is_radiant [Boolian]
  # @param scaling_factor [Float]
  # @return [String] surface as RSI
  def set_necb_external_surface_conductance(surface, hdd, is_radiant = false, scaling_factor = 1.0)
    conductance_value = 0
    if surface.outsideBoundaryCondition.casecmp('outdoors').zero?

      case surface.surfaceType.downcase
      when 'wall'
        conductance_value = @standards_data['conductances']['Wall'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      when 'floor'
        conductance_value = @standards_data['conductances']['Floor'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      when 'roofceiling'
        conductance_value = @standards_data['conductances']['Roof'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      end
      if is_radiant
        conductance_value *= 0.80
      end
      return BTAP::Geometry::Surfaces.set_surfaces_construction_conductance([surface], conductance_value)
    end

    return unless surface.outsideBoundaryCondition.downcase =~ /ground/

    case surface.surfaceType.downcase
    when 'wall'
      conductance_value = @standards_data['conductances']['GroundWall'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
    when 'floor'
      conductance_value = @standards_data['conductances']['GroundFloor'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
    when 'roofceiling'
      conductance_value = @standards_data['conductances']['GroundRoof'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
    end
    if is_radiant
      conductance_value *= 0.80
    end
    return BTAP::Geometry::Surfaces.set_surfaces_construction_conductance([surface], conductance_value)
  end

  # Set all external subsurfaces (doors, windows, skylights) to NECB values.
  # @author phylroy.lopez@nrcan.gc.ca
  # @param subsurface [String]
  # @param hdd [Float]
  def set_necb_external_subsurface_conductance(subsurface, hdd)
    conductance_value = 0
    return unless subsurface.outsideBoundaryCondition.downcase.match('outdoors')

    case subsurface.subSurfaceType.downcase
    when /window/
      conductance_value = @standards_data['conductances']['Window'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
    when /door/
      conductance_value = @standards_data['conductances']['Door'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
    end
    subsurface.setRSI(1 / conductance_value)
  end

  # Adds code-minimum constructions based on the building type
  # as defined in the OpenStudio_Standards_construction_sets.json file.
  # Where there is a separate construction set specified for the
  # individual space type, this construction set will be created and applied
  # to this space type, overriding the whole-building construction set.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_add_constructions(model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying constructions')

    # Assign construction to adiabatic construction
    # Assign a material to all internal mass objects
    assign_contruction_to_adiabatic_surfaces(model)
    # The constructions lookup table uses a slightly different list of
    # building types.
    apply_building_default_constructionset(model)
    # Make a construction set for each space type, if one is specified
    # apply_default_constructionsets_to_spacetypes(climate_zone, model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying constructions')

    true
  end

  def apply_building_default_constructionset(model)
    bldg_def_const_set = model_add_construction_set_from_osm(model: model)
    model.getBuilding.setDefaultConstructionSet(bldg_def_const_set)
  end

  def apply_default_constructionsets_to_spacetypes(climate_zone, model)
    model.getSpaceTypes.sort.each do |space_type|
      # Get the standards building type
      stds_building_type = nil
      if space_type.standardsBuildingType.is_initialized
        stds_building_type = space_type.standardsBuildingType.get
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Space type called '#{space_type.name}' has no standards building type.")
      end

      # Get the standards space type
      stds_spc_type = nil
      if space_type.standardsSpaceType.is_initialized
        stds_spc_type = space_type.standardsSpaceType.get
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Space type called '#{space_type.name}' has no standards space type.")
      end

      # If the standards space type is Attic,
      # the building type should be blank.
      if stds_spc_type == 'Attic'
        stds_building_type = ''
      end

      # Attempt to make a construction set for this space type
      # and assign it if it can be created.
      spc_type_const_set = model_add_construction_set_from_osm(model: model)
      if spc_type_const_set.is_initialized
        space_type.setDefaultConstructionSet(spc_type_const_set.get)
      end
    end
  end

  def model_add_construction_set_from_osm(model:,
                                          construction_set_name: 'BTAP-Mass',
                                          osm_path: File.absolute_path(File.join(__FILE__, '..', '..', 'common/construction_defaults.osm')))
    # load resources model
    construction_library = BTAP::FileIO.load_osm(osm_path)

    if !construction_library.getDefaultConstructionSetByName(construction_set_name.to_s).is_initialized
      runner.registerError('Did not find the expected construction in library.')
      return false
    end
    selected_construction_set = construction_library.getDefaultConstructionSetByName(construction_set_name.to_s).get
    new_construction_set = selected_construction_set.clone(model).to_DefaultConstructionSet.get
    return new_construction_set
  end

  def assign_contruction_to_adiabatic_surfaces(model)
    cp02_carpet_pad = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
    cp02_carpet_pad.setName('CP02 CARPET PAD')
    cp02_carpet_pad.setRoughness('VeryRough')
    cp02_carpet_pad.setThermalResistance(0.21648)
    cp02_carpet_pad.setThermalAbsorptance(0.9)
    cp02_carpet_pad.setSolarAbsorptance(0.7)
    cp02_carpet_pad.setVisibleAbsorptance(0.8)

    normalweight_concrete_floor = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    normalweight_concrete_floor.setName('100mm Normalweight concrete floor')
    normalweight_concrete_floor.setRoughness('MediumSmooth')
    normalweight_concrete_floor.setThickness(0.1016)
    normalweight_concrete_floor.setConductivity(2.31)
    normalweight_concrete_floor.setDensity(2322)
    normalweight_concrete_floor.setSpecificHeat(832)

    nonres_floor_insulation = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
    nonres_floor_insulation.setName('Nonres_Floor_Insulation')
    nonres_floor_insulation.setRoughness('MediumSmooth')
    nonres_floor_insulation.setThermalResistance(2.88291975297193)
    nonres_floor_insulation.setThermalAbsorptance(0.9)
    nonres_floor_insulation.setSolarAbsorptance(0.7)
    nonres_floor_insulation.setVisibleAbsorptance(0.7)

    floor_adiabatic_construction = OpenStudio::Model::Construction.new(model)
    floor_adiabatic_construction.setName('Floor Adiabatic construction')
    floor_layers = OpenStudio::Model::MaterialVector.new
    floor_layers << cp02_carpet_pad
    floor_layers << normalweight_concrete_floor
    floor_layers << nonres_floor_insulation
    floor_adiabatic_construction.setLayers(floor_layers)

    g01_13mm_gypsum_board = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    g01_13mm_gypsum_board.setName('G01 13mm gypsum board')
    g01_13mm_gypsum_board.setRoughness('Smooth')
    g01_13mm_gypsum_board.setThickness(0.0127)
    g01_13mm_gypsum_board.setConductivity(0.1600)
    g01_13mm_gypsum_board.setDensity(800)
    g01_13mm_gypsum_board.setSpecificHeat(1090)
    g01_13mm_gypsum_board.setThermalAbsorptance(0.9)
    g01_13mm_gypsum_board.setSolarAbsorptance(0.7)
    g01_13mm_gypsum_board.setVisibleAbsorptance(0.5)

    wall_adiabatic_construction = OpenStudio::Model::Construction.new(model)
    wall_adiabatic_construction.setName('Wall Adiabatic construction')
    wall_layers = OpenStudio::Model::MaterialVector.new
    wall_layers << g01_13mm_gypsum_board
    wall_layers << g01_13mm_gypsum_board
    wall_adiabatic_construction.setLayers(wall_layers)

    m10_200mm_concrete_block_basement_wall = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    m10_200mm_concrete_block_basement_wall.setName('M10 200mm concrete block basement wall')
    m10_200mm_concrete_block_basement_wall.setRoughness('MediumRough')
    m10_200mm_concrete_block_basement_wall.setThickness(0.2032)
    m10_200mm_concrete_block_basement_wall.setConductivity(1.326)
    m10_200mm_concrete_block_basement_wall.setDensity(1842)
    m10_200mm_concrete_block_basement_wall.setSpecificHeat(912)

    basement_wall_construction = OpenStudio::Model::Construction.new(model)
    basement_wall_construction.setName('Basement Wall construction')
    basement_wall_layers = OpenStudio::Model::MaterialVector.new
    basement_wall_layers << m10_200mm_concrete_block_basement_wall
    basement_wall_construction.setLayers(basement_wall_layers)

    basement_floor_construction = OpenStudio::Model::Construction.new(model)
    basement_floor_construction.setName('Basement Floor construction')
    basement_floor_layers = OpenStudio::Model::MaterialVector.new
    basement_floor_layers << m10_200mm_concrete_block_basement_wall
    basement_floor_layers << cp02_carpet_pad
    basement_floor_construction.setLayers(basement_floor_layers)

    model.getSurfaces.sort.each do |surface|
      if surface.outsideBoundaryCondition.to_s == 'Adiabatic'
        if surface.surfaceType.to_s == 'Wall'
          surface.setConstruction(wall_adiabatic_construction)
        else
          surface.setConstruction(floor_adiabatic_construction)
        end
      elsif surface.outsideBoundaryCondition.to_s == 'OtherSideCoefficients'
        # Ground
        if surface.surfaceType.to_s == 'Wall'
          surface.setOutsideBoundaryCondition('Ground')
          surface.setConstruction(basement_wall_construction)
        else
          surface.setOutsideBoundaryCondition('Ground')
          surface.setConstruction(basement_floor_construction)
        end
      end
    end
  end

  def scale_model_geometry(model, x_scale, y_scale, z_scale)
    # Identity matrix for setting space origins
    m = OpenStudio::Matrix.new(4, 4, 0)

    m[0, 0] = 1.0 / x_scale
    m[1, 1] = 1.0 / y_scale
    m[2, 2] = 1.0 / z_scale
    m[3, 3] = 1.0
    t = OpenStudio::Transformation.new(m)
    model.getPlanarSurfaceGroups.each do |planar_surface|
      planar_surface.changeTransformation(t)
    end
    return model
  end

  # This method applies the maximum fenestration and door to wall ratio to a building as per NECB 2011 8.4.4.3 and
  # 3.2.1.4 (or equivalent in other versions of the NECB).  It first checks for al exterior walls adjacent to conditioned
  # spaces.  It distinguishes between plenums and other conditioned spaces.  It uses both to calculate the maximum window
  # area to be applied to the building but attempts to put these windows only on non-plenum conditioned spaces (if
  # possible).
  def apply_max_fdwr_nrcan(model:, fdwr_lim:)
    # First determine which vertical (between 89 and 91 degrees from horizontal) walls are adjacent to conditioned
    # spaces.
    exp_surf_info = find_exposed_conditioned_vertical_surfaces(model)
    # If there are none (or very few) then throw a warning.
    if exp_surf_info['total_exp_wall_area_m2'] < 0.1
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', 'This building has no exposed walls adjacent to heated spaces.')
      return false
    end

    construct_set = model.getBuilding.defaultConstructionSet.get
    fixed_window_construct_set = construct_set.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get

    # IF FDWR is greater than 1 then something is wrong raise an error.  If it is less than 0.001 assume all the windows
    # should go.
    if fdwr_lim > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'This building requires a larger window area than there is wall area.')
      return false
    elsif fdwr_lim < 0.001
      exp_surf_info['exp_nonplenum_walls'].sort.each do |exp_surf|
        exp_surf.subSurfaces.sort.each(&:remove)
      end
      return true
    end
    # Get the required window area.
    win_area = fdwr_lim * exp_surf_info['total_exp_wall_area_m2']
    # Try to put the windows on non-plenum walls if possible.  So determine if you can fit the required window area
    # on the non-plenum wall area.
    if win_area <= exp_surf_info['exp_nonplenum_wall_area_m2']
      # If you can fit the windows on the non-plenum wall area then recalculate the window ratio so that is is only for
      # the non-plenum walls.
      nonplenum_fdwr = win_area / exp_surf_info['exp_nonplenum_wall_area_m2']
      exp_surf_info['exp_nonplenum_walls'].sort.each do |exp_surf|
        # Remove any subsurfaces, add the window, set the name to be whatever the surface name is plus the subsurface
        # type (which will be 'fixedwindow')
        exp_surf.subSurfaces.sort.each(&:remove)
        exp_surf.setWindowToWallRatio(nonplenum_fdwr)
        exp_surf.subSurfaces.sort.each do |sub_surf|
          sub_surf.setSubSurfaceType('FixedWindow')
          sub_surf.setConstruction(fixed_window_construct_set)
          new_name = exp_surf.name.to_s + '_' + sub_surf.subSurfaceType.to_s
          sub_surf.setName(new_name)
        end
      end
    else
      # There was not enough non-plenum wall area so add the windows to both the plenum and non-plenum walls.  This is
      # done separately because the 'find_exposed_conditioned_vertical_surfaces' method returns the plenum and
      # non-plenum walls separately.
      exp_surf_info['exp_nonplenum_walls'].sort.each do |exp_surf|
        # Remove any subsurfaces, add the window, set the name to be whatever the surface name is plus the subsurface
        # type (which will be 'fixedwindow')
        exp_surf.subSurfaces.sort.each(&:remove)
        exp_surf.setWindowToWallRatio(fdwr_lim)
        exp_surf.subSurfaces.sort.each do |sub_surf|
          sub_surf.setSubSurfaceType('FixedWindow')
          sub_surf.setConstruction(fixed_window_construct_set)
          new_name = exp_surf.name.to_s + '_' + sub_surf.subSurfaceType.to_s
          sub_surf.setName(new_name)
        end
      end
      exp_surf_info['exp_plenum_walls'].sort.each do |exp_surf|
        # Remove any subsurfaces, add the window, set the name to be whatever the surface name is plus the subsurface
        # type (which will be 'fixedwindow')
        exp_surf.subSurfaces.sort.each(&:remove)
        exp_surf.setWindowToWallRatio(fdwr_lim)
        exp_surf.subSurfaces.sort.each do |sub_surf|
          sub_surf.setSubSurfaceType('FixedWindow')
          sub_surf.setConstruction(fixed_window_construct_set)
          new_name = exp_surf.name.to_s + '_' + sub_surf.subSurfaceType.to_s
          sub_surf.setName(new_name)
        end
      end
    end
    return true
  end

  # This method is similar to the 'apply_max_fdwr' method above, but applies a maximum skylight-to-roof-area-ratio (SRR)
  # to a building model, as per NECB 2011 8.4.4.3 and 3.2.1.4 (or equivalent in other NECB vintages). There are 2 options:
  #
  # OPTION A: Default, initial BTAP solution. It first checks for all exterior roofs adjacent to conditioned spaces.
  #           It distinguishes between plenums and other conditioned spaces. It uses only the non-plenum roof area to
  #           calculate the maximum skylight area to be applied to the building.
  #
  # OPTION B: Selected if srr_opt == 'osut'. OSut's 'addSkylights' attempts to meet the requested SRR% target, even if
  #           occupied spaces to toplight are under unoccupied plenums or attics - skylight wells are added if needed.
  #           With attics, skylight well walls are considered part of the 'building envelope' (and therefore insulated
  #           like exterior walls). The method returns a building 'gross roof area' (see attr_reader :osut), which
  #           excludes the area of attic roof overhangs.
  def apply_max_srr_nrcan(model:, srr_lim:, srr_opt: '')
    construct_set = model.getBuilding.defaultConstructionSet.get
    skylight_construct_set = construct_set.defaultExteriorSubSurfaceConstructions.get.skylightConstruction.get

    unless srr_opt.to_s.downcase == 'osut' # OPTION A
      # First determine which roof surfaces are adjacent to heated spaces (both plenum and non-plenum).
      exp_surf_info = find_exposed_conditioned_roof_surfaces(model)
      # If the non-plenum roof area is very small raise a warning.  It may be perfectly fine but it is probably a good
      # idea to warn the user.
      if exp_surf_info['exp_nonplenum_roof_area_m2'] < 0.1
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'This building has no exposed ceilings adjacent to spaces that are not attics or plenums.  No skylights will be added.')
        return false
      end

      # If the SRR is greater than one something is seriously wrong so raise an error.  If it is less than 0.001 assume
      # all the skylights should go.
      if srr_lim > 1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'This building requires a larger skylight area than there is roof area.')
        return false
      elsif srr_lim < 0.001
        exp_surf_info['exp_nonplenum_roofs'].sort.each do |exp_surf|
          exp_surf.subSurfaces.sort.each(&:remove)
        end
        return true
      end

      # Go through all of exposed roofs adjacent to heated, non-plenum spaces, remove any existing subsurfaces, and add
      # a skylight in the centroid of the surface, with the same shape of the surface, only scaled to be the area
      # determined by the SRR.  The name of the skylight will be the surface name with the subsurface type attached
      # ('skylight' in this case).  Note that this method will only work if the surface does not fold into itself (like an
      # L or a V).
      exp_surf_info['exp_nonplenum_roofs'].sort.each do |roof|
        # sub_surface_create_centered_subsurface_from_scaled_surface(roof, srr_lim, model)
        sub_surface_create_scaled_subsurfaces_from_surface(surface: roof, area_fraction: srr_lim, construction: skylight_construct_set)
      end
    else # OPTION B
      TBD.clean!
      spaces = model.getSpaces
      types  = model.getSpaceTypes
      roofs  = TBD.facets(spaces, "Outdoors", "RoofCeiling")

      # A model's 'nominal' gross roof area (gra0) may be greater than its
      # 'effective' gross roof area (graX). For instance, the "SmallOffice"
      # prototype model has (unconditioned) attic roof overhangs that end up
      # tallied as a gross roof area in OpenStudio and EnergyPlus. See:
      #
      #   github.com/rd2/osut/blob/117c7dceb59fd8aab771da8ba672c14c97d23bd0
      #   /lib/osut/utils.rb#L6268
      #
      gra0 = roofs.sum(&:grossArea)    # nominal gross roof area
      graX = TBD.grossRoofArea(spaces) # effective gross roof area

      unless gra0.round > 0
        msg = 'Invalid nominal gross roof area. No skylights will be added.'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', msg)
        return false
      end

      unless graX.round > 0
        msg = 'Invalid effective gross roof area. No skylights will be added.'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', msg)
        return false
      end

      self.osut[:gra0] = gra0
      self.osut[:graX] = graX

      # Relying on the total area of attic roof surfaces (for SRR%) exagerrates
      # the requested skylight area, often by 10% to 15%. This makes it unfair
      # for NECBs, and more challenging when dealing with skylight wells. This
      # issue only applies with attics - not plenums. Trim down SRR if required.
      target = srr_lim * graX

      # Filtering out tiny roof surfaces, twisty corridors, etc.
      types = types.reject { |tp| tp.nameString.downcase.include?("undefined") }
      types = types.reject { |tp| tp.nameString.downcase.include?("mech"     ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("elec"     ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("toilet"   ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("locker"   ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("shower"   ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("washroom" ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("corr"     ) }
      types = types.reject { |tp| tp.nameString.downcase.include?("stair"    ) }

      spaces = spaces.reject { |sp| sp.spaceType.empty? }
      spaces = spaces.select { |sp| types.include?(sp.spaceType.get) }

      TBD.addSkyLights(spaces, {area: target})
      self.osut[:logs] = TBD.logs

      skys = TBD.facets(model.getSpaces, "Outdoors", "Skylight")
      skm2 = skys.sum(&:grossArea)

      unless skm2.round == target.round
        msg = "Skylights m2: failed to meet #{target.round} (vs #{skm2.round})"
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', msg)
        return false
      end
    end

    return true
  end
end
