require_relative '../../helpers/minitest_helper'

# Pure-Ruby unit tests for the perimeter/core allocator (no OpenStudio geometry).
class TestGeometryPerimeterCoreAllocation < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    # depth bounds in meters; supply valid_bar_width_min so no unit conversion is needed
    @args = { perimeter_zone_depth: 4.57, perimeter_depth_min: 2.44, perimeter_depth_max: 7.62, valid_bar_width_min: 0.9144 }
  end

  # sum of drawn rectangle area per space type, applying each story's multiplier
  def per_type_totals(result, story_entries)
    totals = Hash.new(0.0)
    result[:rects].each_with_index do |story, i|
      m = story_entries[i][:multiplier]
      story.each { |r| totals[r[:space_type]] += (r[:x1] - r[:x0]) * (r[:y1] - r[:y0]) * m }
    end
    totals
  end

  def assert_in_rel(expected, actual, rel = 1e-4)
    assert_in_delta(expected, actual, rel * [1.0, expected.abs, actual.abs].max)
  end

  def test_allocation_area_conservation
    stories = [
      { length: 60.0, width: 30.0, multiplier: 1 },
      { length: 60.0, width: 30.0, multiplier: 2 },
      { length: 42.0, width: 21.0, multiplier: 1 }
    ]
    cap = stories.sum { |s| s[:multiplier] * s[:length] * s[:width] }
    space_types = {
      'office'   => { floor_area: cap - 3000.0, position: 'perimeter', position_source: 'keyword' },
      'corridor' => { floor_area: 1500.0, position: 'core', position_source: 'circ' },
      'restroom' => { floor_area: 600.0, position: 'core', position_source: 'keyword' },
      'storage'  => { floor_area: 900.0, position: 'core', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    assert_nil(result[:fallback])
    totals = per_type_totals(result, stories)
    space_types.each { |k, v| assert_in_rel(v[:floor_area], totals[k]) }
    assert_in_rel(cap, totals.values.sum)
  end

  def test_allocation_depth_solve
    stories = [{ length: 100.0, width: 50.0, multiplier: 1 }]
    space_types = {
      'core1'  => { floor_area: 1200.0, position: 'core', position_source: 'keyword' },
      'perim1' => { floor_area: (100.0 * 50.0) - 1200.0, position: 'perimeter', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, { perimeter_zone_depth: 4.57, perimeter_depth_min: 0.01, perimeter_depth_max: 40.0, valid_bar_width_min: 0.9144 })
    d = result[:depth]
    geometric_core = (100.0 - (2 * d)) * (50.0 - (2 * d))
    assert_in_delta(1200.0, geometric_core, 1e-6)
  end

  def test_allocation_depth_no_core
    stories = [{ length: 100.0, width: 50.0, multiplier: 1 }]
    space_types = { 'office' => { floor_area: 5000.0, position: 'perimeter', position_source: 'keyword' } }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    # no core assigned: depth defaults to the target, interior filled by perimeter spill
    assert_in_delta(@args[:perimeter_zone_depth], result[:depth], 1e-6)
    assert(result[:moves].any? { |m| m[:to] == :core })
  end

  def test_allocation_spill_ordering
    stories = [{ length: 100.0, width: 100.0, multiplier: 1 }]
    # force overflow by clamping depth to a large minimum
    args = { perimeter_zone_depth: 7.62, perimeter_depth_min: 7.62, perimeter_depth_max: 7.62, valid_bar_width_min: 0.9144 }
    space_types = {
      'sized'   => { floor_area: 3000.0, position: 'core', position_source: 'size' },
      'keyword' => { floor_area: 3000.0, position: 'core', position_source: 'keyword' },
      'circ'    => { floor_area: 3000.0, position: 'core', position_source: 'circ' },
      'office'  => { floor_area: 1000.0, position: 'perimeter', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, args)
    moved = result[:moves].map { |m| m[:space_type] }
    # size-sourced spills before keyword before circ
    assert_equal('sized', moved.first)
    assert(moved.index('keyword').nil? || moved.index('circ').nil? || moved.index('keyword') < moved.index('circ'))
  end

  def test_allocation_explicit_core_not_moved
    stories = [{ length: 100.0, width: 100.0, multiplier: 1 }]
    args = { perimeter_zone_depth: 7.62, perimeter_depth_min: 7.62, perimeter_depth_max: 7.62, valid_bar_width_min: 0.9144 }
    space_types = {
      'wh'  => { floor_area: 9000.0, position: 'core', position_source: 'explicit' },
      'off' => { floor_area: 1000.0, position: 'perimeter', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, args)
    # explicit core is never spilled; instead the depth is reduced below the minimum
    assert(result[:moves].empty?)
    assert(result[:depth] < args[:perimeter_depth_min])
    assert(result[:warnings].any? { |w| w =~ /perimeter depth reduced/i })
    totals = per_type_totals(result, stories)
    assert_in_rel(9000.0, totals['wh'])
  end

  def test_allocation_orientation
    stories = [{ length: 80.0, width: 40.0, multiplier: 1 }]
    cap = 80.0 * 40.0
    space_types = {
      'office' => { floor_area: cap - 700.0, position: 'perimeter', position_source: 'explicit', orientation: ['south'] },
      'core1'  => { floor_area: 700.0, position: 'core', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    south = result[:rects][0].select { |r| r[:facade] == 'S' }.map { |r| r[:space_type] }.uniq
    assert_includes(south, 'office')
  end

  def test_allocation_orientation_overflow
    stories = [{ length: 80.0, width: 40.0, multiplier: 1 }]
    # d solves (80-2d)(40-2d) = 2000 -> d ~= 5.505; south budget d(80-2d) ~= 380 m^2,
    # so the 600 m^2 south-preferring type must overflow onto an adjacent facade
    space_types = {
      'south_office' => { floor_area: 600.0, position: 'perimeter', position_source: 'explicit', orientation: ['south'] },
      'other_office' => { floor_area: 600.0, position: 'perimeter', position_source: 'keyword' },
      'core_support' => { floor_area: 2000.0, position: 'core', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    facades = result[:rects][0].select { |r| r[:space_type] == 'south_office' }.map { |r| r[:facade] }.uniq
    assert_includes(facades, 'S')
    assert(facades.size > 1, "expected overflow onto an adjacent facade, got #{facades.inspect}")
    assert(result[:warnings].any? { |w| w =~ /preferred facades are full/ })
    totals = per_type_totals(result, stories)
    space_types.each { |k, v| assert_in_rel(v[:floor_area], totals[k]) }
  end

  def test_allocation_sliver_consolidation
    stories = Array.new(5) { { length: 100.0, width: 40.0, multiplier: 1 } }
    cap = stories.sum { |s| s[:multiplier] * s[:length] * s[:width] }
    space_types = {
      'office'   => { floor_area: cap * 0.60, position: 'perimeter', position_source: 'keyword' },
      'tiny'     => { floor_area: cap * 0.0005, position: 'perimeter', position_source: 'keyword' },
      'corework' => { floor_area: cap * 0.3995, position: 'core', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    tiny_stories = result[:rects].each_index.select { |i| result[:rects][i].any? { |r| r[:space_type] == 'tiny' } }
    assert(tiny_stories.size < 5, "expected sliver 'tiny' to be consolidated onto fewer stories, got #{tiny_stories.size}")
    totals = per_type_totals(result, stories)
    space_types.each { |k, v| assert_in_rel(v[:floor_area], totals[k]) }
  end

  def test_allocation_degenerate_bar
    stories = [{ length: 100.0, width: 4.0, multiplier: 1 }]
    space_types = {
      'core1'  => { floor_area: 100.0, position: 'core', position_source: 'keyword' },
      'perim1' => { floor_area: 300.0, position: 'perimeter', position_source: 'keyword' }
    }
    result = @geo.perimeter_core_allocation(space_types, stories, @args)
    assert_equal(:sliced, result[:fallback])
  end
end
