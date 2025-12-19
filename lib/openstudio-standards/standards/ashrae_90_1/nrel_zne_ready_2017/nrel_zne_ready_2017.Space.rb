class NRELZNEReady2017 < ASHRAE901
  # @!group Space

  # Determines the method used to extend the daylighted area horizontally
  # next to a window.  If the method is 'fixed', 2 ft is added to the
  # width of each window.  If the method is 'proportional', a distance
  # equal to half of the head height of the window is added.  If the method is 'none',
  # no additional width is added.
  #
  # @return [String] returns 'fixed' or 'proportional'
  def space_daylighted_area_window_width(space)
    method = 'proportional'
    return method
  end

  # Determine if the space requires daylighting controls for
  # toplighting, primary sidelighting, and secondary sidelighting.
  # Defaults to false for all types.
  #
  # @param space [OpenStudio::Model::Space] the space in question
  # @param areas [Hash] a hash of daylighted areas
  # @return [Array<Bool>] req_top_ctrl, req_pri_ctrl, req_sec_ctrl
  def space_daylighting_control_required?(space, areas)
    req_top_ctrl = true
    req_pri_ctrl = true
    req_sec_ctrl = true

    # Get the LPD of the space
    space_lpd_w_per_m2 = space.lightingPowerPerFloorArea

    # Primary Sidelighting
    # Check if the primary sidelit area contains less than 150W of lighting
    if areas['primary_sidelighted_area'] < 0.01
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Space', "For #{space.name}, primary sidelighting control not required because primary sidelighted area = 0ft2 per 9.4.1.1(e).")
      req_pri_ctrl = false
    elsif areas['primary_sidelighted_area'] * space_lpd_w_per_m2 < 150.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Space', "For #{space.name}, primary sidelighting control not required because less than 150W of lighting are present in the primary daylighted area per 9.4.1.1(e).")
      req_pri_ctrl = false
    else
      # Check the size of the windows
      if areas['total_window_area'] < OpenStudio.convert(20.0, 'ft^2', 'm^2').get
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Space', "For #{space.name}, primary sidelighting control not required because there are less than 20ft2 of window per 9.4.1.1(e) Exception 2.")
        req_pri_ctrl = false
      end
    end

    # Secondary Sidelighting
    # Check if the primary and secondary sidelit areas contains less than 300W of lighting
    if areas['secondary_sidelighted_area'] < 0.01
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Space', "For #{space.name}, secondary sidelighting control not required because secondary sidelighted area = 0ft2 per 9.4.1.1(e).")
      req_sec_ctrl = false
    elsif (areas['primary_sidelighted_area'] + areas['secondary_sidelighted_area']) * space_lpd_w_per_m2 < 300
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Space', "For #{space.name}, secondary sidelighting control not required because less than 300W of lighting are present in the combined primary and secondary daylighted areas per 9.4.1.1(e).")
      req_sec_ctrl = false
    else
      # Check the size of the windows
      if areas['total_window_area'] < OpenStudio.convert(20.0, 'ft^2', 'm^2').get
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Space', "For #{space.name}, secondary sidelighting control not required because there are less than 20ft2 of window per 9.4.1.1(e) Exception 2.")
        req_sec_ctrl = false
      end
    end

    # Toplighting
    # Check if the toplit area contains less than 150W of lighting
    if areas['toplighted_area'] < 0.01
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Space', "For #{space.name}, toplighting control not required because toplighted area = 0ft2 per 9.4.1.1(f).")
      req_top_ctrl = false
    elsif areas['toplighted_area'] * space_lpd_w_per_m2 < 150
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Space', "For #{space.name}, toplighting control not required because less than 150W of lighting are present in the toplighted area per 9.4.1.1(f).")
      req_top_ctrl = false
    end

    return [req_top_ctrl, req_pri_ctrl, req_sec_ctrl]
  end

  # Determine the fraction controlled by each sensor and which window each sensor should go near.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param areas [Hash] a hash of daylighted areas
  # @param sorted_windows [Hash] a hash of windows, sorted by priority
  # @param sorted_skylights [Hash] a hash of skylights, sorted by priority
  # @param req_top_ctrl [Boolean] if toplighting controls are required
  # @param req_pri_ctrl [Boolean] if primary sidelighting controls are required
  # @param req_sec_ctrl [Boolean] if secondary sidelighting controls are required
  # @return [Array] array of 4 items
  #   [sensor 1 fraction, sensor 2 fraction, sensor 1 window, sensor 2 window]
  def space_daylighting_fractions_and_windows(space,
                                              areas,
                                              sorted_windows,
                                              sorted_skylights,
                                              req_top_ctrl,
                                              req_pri_ctrl,
                                              req_sec_ctrl)
    sensor_1_frac = 0.0
    sensor_2_frac = 0.0
    sensor_1_window = nil
    sensor_2_window = nil

    # Get the area of the space
    space_area_m2 = space.floorArea

    if req_top_ctrl && req_pri_ctrl && req_sec_ctrl
      # Sensor 1 controls toplighted area
      sensor_1_frac = areas['toplighted_area'] / space_area_m2
      sensor_1_window = sorted_skylights[0]
      # Sensor 2 controls primary + secondary area
      sensor_2_frac = (areas['primary_sidelighted_area'] + areas['secondary_sidelighted_area']) / space_area_m2
      sensor_2_window = sorted_windows[0]
    elsif !req_top_ctrl && req_pri_ctrl && req_sec_ctrl
      # Sensor 1 controls primary area
      sensor_1_frac = areas['primary_sidelighted_area'] / space_area_m2
      sensor_1_window = sorted_windows[0]
      # Sensor 2 controls secondary area
      sensor_2_frac = (areas['secondary_sidelighted_area'] / space_area_m2)
      sensor_2_window = sorted_windows[0]
    elsif req_top_ctrl && !req_pri_ctrl && req_sec_ctrl
      # Sensor 1 controls toplighted area
      sensor_1_frac = areas['toplighted_area'] / space_area_m2
      sensor_1_window = sorted_skylights[0]
      # Sensor 2 controls secondary area
      sensor_2_frac = (areas['secondary_sidelighted_area'] / space_area_m2)
      sensor_2_window = sorted_windows[0]
    elsif req_top_ctrl && !req_pri_ctrl && !req_sec_ctrl
      # Sensor 1 controls toplighted area
      sensor_1_frac = areas['toplighted_area'] / space_area_m2
      sensor_1_window = sorted_skylights[0]
    elsif !req_top_ctrl && req_pri_ctrl && !req_sec_ctrl
      # Sensor 1 controls primary area
      sensor_1_frac = areas['primary_sidelighted_area'] / space_area_m2
      sensor_1_window = sorted_windows[0]
    elsif !req_top_ctrl && !req_pri_ctrl && req_sec_ctrl
      # Sensor 1 controls secondary area
      sensor_1_frac = areas['secondary_sidelighted_area'] / space_area_m2
      sensor_1_window = sorted_windows[0]
    end

    return [sensor_1_frac, sensor_2_frac, sensor_1_window, sensor_2_window]
  end
end
