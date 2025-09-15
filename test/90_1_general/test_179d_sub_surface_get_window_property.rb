require_relative '../helpers/minitest_helper'

class ACM179dASHRAE9012007WindowPropsTest < Minitest::Test

  def rough_opening_area_with_multiplier(sub_surface)
    window_area = sub_surface.roughOpeningArea
    window_area *= sub_surface.multiplier
    space_ = sub_surface.space
    if space_.is_initialized
      window_area *= space_.get.multiplier # This picks the ThermalZone multiplier
    end
  end

  def test_sub_surface_get_window_property

    model = OpenStudio::Model::exampleModel
    # Can't set a multiplier on a SubSurface in E+ if part of a daylighting
    # enclosure
    model.getDaylightingControls.each(&:remove)
    model.getIlluminanceMaps.each(&:remove)

    model.getSubSurfaces.select{|s| s.subSurfaceType == 'FixedWindow'}.each(&:remove)
    assert_equal(1, model.getSubSurfaces.size)
    assert_equal(1, model.getSubSurfaces.select{|s| s.subSurfaceType == 'Door'}.size)
    door = model.getSubSurfaces.select{|s| s.subSurfaceType == 'Door'}.first
    door.setName("Door")

    # Grab a space without the door
    # We sort_by to ensure consistency
    space = model.getSpaces.select{|space| space.surfaces.all? {|s| s.subSurfaces.empty? }}.sort_by(&:nameString).last
    walls = space.surfaces.select{|s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors'}.sort_by(&:azimuth)
    assert_equal(2, walls.size)

    window_no_frame = walls[0].setWindowToWallRatio(0.4).get
    window_no_frame.setName("Window Without Frame")
    window_w_frame = walls[1].setWindowToWallRatio(0.4).get
    window_w_frame.setName("Window With Frame")

    assert_equal(3, model.getSubSurfaces.size)
    assert_equal(1, model.getSubSurfaces.select{|s| s.subSurfaceType == 'Door'}.size)
    assert_equal(2, model.getSubSurfaces.select{|s| s.subSurfaceType == 'FixedWindow'}.size)

    frame = OpenStudio::Model::WindowPropertyFrameAndDivider.new(model)
    frame.setFrameWidth(0.02)
    frame.setFrameConductance(283.91)

    assert window_w_frame.setWindowPropertyFrameAndDivider(frame)

    template = '179D 90.1-2007'
    standard = Standard.build(template)

    standard.model_add_design_days_and_weather_file(model, 'ASHRAE 169-2013-3A')

    output_folder = "#{__dir__}/output/sub_surface_get_window_property"
    FileUtils.rm_rf(output_folder)
    FileUtils.mkdir_p(output_folder)

    assert standard.model_run_sizing_run(model, output_folder)
    refute_empty(model.sqlFile)

    # Not a window or skylight
    h = standard.sub_surface_get_window_property(door)
    assert_nil(h)

    h = standard.sub_surface_get_window_property(window_w_frame)
    refute_nil(h)
    assert_in_delta(12.45, window_w_frame.roughOpeningArea, 0.01)
    expected = {"name"=> window_w_frame.nameString, "window_type"=>"FixedWindow", "surface_type"=>"Wall", "area_m2"=>12.45, "shgc"=>0.39, "u_value"=>3.270}
    assert_equal(expected.keys, h.keys)
    expected.keys.each do |k|
      if expected[k].is_a?(Float)
        assert_in_delta(expected[k].round(2), h[k].round(2), 0.015, "'#{k}' does not match for #{expected['name']}")
      else
        assert_equal(expected[k], h[k], "'#{k}' does not match for #{expected['name']}")
      end
    end

    h = standard.sub_surface_get_window_property(window_no_frame)
    refute_nil(h)
    assert_in_delta(12.0, window_no_frame.roughOpeningArea, 0.01)
    expected = {"name"=>"Window Without Frame", "window_type"=>"FixedWindow", "surface_type"=>"Wall", "area_m2"=>12.0, "shgc"=>0.391, "u_value"=>3.241}
    assert_equal(expected.keys, h.keys)
    expected.keys.each do |k|
      if expected[k].is_a?(Float)
        assert_in_delta(expected[k].round(2), h[k].round(2), 0.015, "'#{k}' does not match for #{expected['name']}")
      else
        assert_equal(expected[k], h[k], "'#{k}' does not match for #{expected['name']}")
      end
    end

    ### Test with multipliers
    window_w_frame.setMultiplier(2)
    window_no_frame.setMultiplier(2)
    space.thermalZone.get.setMultiplier(3)
    FileUtils.rm_rf(output_folder)
    FileUtils.mkdir_p(output_folder)

    assert standard.model_run_sizing_run(model, output_folder)
    refute_empty(model.sqlFile)

    h = standard.sub_surface_get_window_property(window_w_frame)
    refute_nil(h)
    assert_in_delta(12.45, window_w_frame.roughOpeningArea, 0.01)
    area_with_mult = rough_opening_area_with_multiplier(window_w_frame)
    assert_in_delta(12.45 * 3 * 2, area_with_mult, 0.015)
    expected = {"name"=> window_w_frame.nameString, "window_type"=>"FixedWindow", "surface_type"=>"Wall", "area_m2"=>74.7, "shgc"=>0.39, "u_value"=>3.270}
    assert_equal(expected.keys, h.keys)
    expected.keys.each do |k|
      if expected[k].is_a?(Float)
        assert_in_delta(expected[k].round(2), h[k].round(2), 0.015, "'#{k}' does not match for #{expected['name']}")
      else
        assert_equal(expected[k], h[k], "'#{k}' does not match for #{expected['name']}")
      end
    end

    h = standard.sub_surface_get_window_property(window_no_frame)
    refute_nil(h)
    assert_in_delta(12.0, window_no_frame.roughOpeningArea, 0.01)
    area_with_mult = rough_opening_area_with_multiplier(window_no_frame)
    assert_in_delta(12.0 * 3 * 2, area_with_mult)
    expected = {"name"=>"Window Without Frame", "window_type"=>"FixedWindow", "surface_type"=>"Wall", "area_m2"=>72.0, "shgc"=>0.391, "u_value"=>3.241}
    assert_equal(expected.keys, h.keys)
    expected.keys.each do |k|
      if expected[k].is_a?(Float)
        assert_in_delta(expected[k].round(2), h[k].round(2), 0.015, "'#{k}' does not match for #{expected['name']}")
      else
        assert_equal(expected[k], h[k], "'#{k}' does not match for #{expected['name']}")
      end
    end
  end

end
