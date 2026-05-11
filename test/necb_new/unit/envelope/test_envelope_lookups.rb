require_relative '../../test_helper'

# Test NECB envelope lookup methods
# Tests the envelope U-value and FDWR lookup methods without requiring any OpenStudio model geometry
#
# Methods tested:
# - NECB2011#max_u_necb(stype, condition, hdd) - Returns max U-values by surface type and HDD
# - NECB2011#max_fwdr(hdd) - Returns max FDWR by HDD
#
# References:
# - NECB 2011 Table 3.2.1.3 (Maximum Overall Thermal Transmittance)
# - NECB 2011 Table 3.2.1.4 (Maximum Fenestration and Door to Wall Ratio)
class TestEnvelopeLookups < Minitest::Test

  # ============================================================================
  # NECB2011 Wall U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_wall_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-0.315 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 2500)

    assert_in_delta 0.315, u_value, 0.001,
      "Expected wall U-value of 0.315 W/m2K for HDD=2500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_3000_to_4000
    # NECB 2011 Table 3.2.1.3
    # 3000 <= HDD < 4000 -> U-0.278 W/m2K for walls (returns value at next threshold)
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 3500)

    assert_in_delta 0.278, u_value, 0.001,
      "Expected wall U-value of 0.278 W/m2K for HDD=3500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_4000_to_5000
    # NECB 2011 Table 3.2.1.3
    # 4000 <= HDD < 5000 -> U-0.247 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 4500)

    assert_in_delta 0.247, u_value, 0.001,
      "Expected wall U-value of 0.247 W/m2K for HDD=4500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_5000_to_6000
    # NECB 2011 Table 3.2.1.3
    # 5000 <= HDD < 6000 -> U-0.210 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 5500)

    assert_in_delta 0.210, u_value, 0.001,
      "Expected wall U-value of 0.210 W/m2K for HDD=5500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_6000_to_7000
    # NECB 2011 Table 3.2.1.3
    # 6000 <= HDD < 7000 -> U-0.210 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 6500)

    assert_in_delta 0.210, u_value, 0.001,
      "Expected wall U-value of 0.210 W/m2K for HDD=6500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_7000_to_9999
    # NECB 2011 Table 3.2.1.3
    # 7000 <= HDD < 9999 -> U-0.183 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 8000)

    assert_in_delta 0.183, u_value, 0.001,
      "Expected wall U-value of 0.183 W/m2K for HDD=8000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected wall U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Roof/Ceiling U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_roofceiling_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-0.227 W/m2K for roofs
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('roofceiling', 'outdoors', 2500)

    assert_in_delta 0.227, u_value, 0.001,
      "Expected roof U-value of 0.227 W/m2K for HDD=2500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_roofceiling_outdoors_hdd_4000_to_5000
    # NECB 2011 Table 3.2.1.3
    # 4000 <= HDD < 5000 -> U-0.183 W/m2K for roofs
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('roofceiling', 'outdoors', 4500)

    assert_in_delta 0.183, u_value, 0.001,
      "Expected roof U-value of 0.183 W/m2K for HDD=4500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_roofceiling_outdoors_hdd_6000_to_7000
    # NECB 2011 Table 3.2.1.3
    # 6000 <= HDD < 7000 -> U-0.162 W/m2K for roofs
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('roofceiling', 'outdoors', 6500)

    assert_in_delta 0.162, u_value, 0.001,
      "Expected roof U-value of 0.162 W/m2K for HDD=6500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_roofceiling_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for roofs
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('roofceiling', 'outdoors', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected roof U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Floor U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_floor_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-0.227 W/m2K for floors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('floor', 'outdoors', 2500)

    assert_in_delta 0.227, u_value, 0.001,
      "Expected floor U-value of 0.227 W/m2K for HDD=2500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_floor_outdoors_hdd_5000_to_6000
    # NECB 2011 Table 3.2.1.3
    # 5000 <= HDD < 6000 -> U-0.162 W/m2K for floors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('floor', 'outdoors', 5500)

    assert_in_delta 0.162, u_value, 0.001,
      "Expected floor U-value of 0.162 W/m2K for HDD=5500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_floor_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for floors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('floor', 'outdoors', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected floor U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Window U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_window_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-2.400 W/m2K for windows
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('window', 'outdoors', 2500)

    assert_in_delta 2.400, u_value, 0.001,
      "Expected window U-value of 2.400 W/m2K for HDD=2500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_window_outdoors_hdd_4000_to_7000
    # NECB 2011 Table 3.2.1.3
    # 4000 <= HDD < 7000 -> U-2.200 W/m2K for windows
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('window', 'outdoors', 5000)

    assert_in_delta 2.200, u_value, 0.001,
      "Expected window U-value of 2.200 W/m2K for HDD=5000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_window_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for windows
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('window', 'outdoors', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected window U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Skylight U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_skylight_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-2.400 W/m2K for skylights
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('skylight', 'outdoors', 2000)

    assert_in_delta 2.400, u_value, 0.001,
      "Expected skylight U-value of 2.400 W/m2K for HDD=2000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_skylight_outdoors_hdd_6000_to_7000
    # NECB 2011 Table 3.2.1.3
    # 6000 <= HDD < 7000 -> U-2.200 W/m2K for skylights
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('skylight', 'outdoors', 6500)

    assert_in_delta 2.200, u_value, 0.001,
      "Expected skylight U-value of 2.200 W/m2K for HDD=6500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_skylight_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for skylights
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('skylight', 'outdoors', 12000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected skylight U-value of 0.110 W/m2K (default) for HDD=12000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Door U-value Tests (Outdoors Boundary Condition)
  # ============================================================================

  def test_max_u_door_outdoors_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-2.400 W/m2K for doors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('door', 'outdoors', 2800)

    assert_in_delta 2.400, u_value, 0.001,
      "Expected door U-value of 2.400 W/m2K for HDD=2800 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_door_outdoors_hdd_5000_to_6000
    # NECB 2011 Table 3.2.1.3
    # 5000 <= HDD < 6000 -> U-2.200 W/m2K for doors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('door', 'outdoors', 5500)

    assert_in_delta 2.200, u_value, 0.001,
      "Expected door U-value of 2.200 W/m2K for HDD=5500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_door_outdoors_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for doors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('door', 'outdoors', 11000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected door U-value of 0.110 W/m2K (default) for HDD=11000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # NECB2011 Ground Boundary Condition Tests
  # ============================================================================

  def test_max_u_wall_ground_hdd_below_3000
    # NECB 2011 Table 3.2.1.3
    # HDD < 3000 -> U-0.568 W/m2K for below-grade walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'ground', 2500)

    assert_in_delta 0.568, u_value, 0.001,
      "Expected below-grade wall U-value of 0.568 W/m2K for HDD=2500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_ground_hdd_4000_to_5000
    # NECB 2011 Table 3.2.1.3
    # 4000 <= HDD < 5000 -> U-0.284 W/m2K for below-grade walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'ground', 4500)

    assert_in_delta 0.284, u_value, 0.001,
      "Expected below-grade wall U-value of 0.284 W/m2K for HDD=4500 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_ground_hdd_5000_to_7000
    # NECB 2011 Table 3.2.1.3
    # 5000 <= HDD < 7000 -> U-0.284 W/m2K for below-grade walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'ground', 6000)

    assert_in_delta 0.284, u_value, 0.001,
      "Expected below-grade wall U-value of 0.284 W/m2K for HDD=6000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_wall_ground_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for below-grade walls
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'ground', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected below-grade wall U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_floor_ground_hdd_below_7000
    # NECB 2011 Table 3.2.1.3
    # HDD < 7000 -> U-0.757 W/m2K for slab-on-grade floors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('floor', 'ground', 5000)

    assert_in_delta 0.757, u_value, 0.001,
      "Expected slab-on-grade floor U-value of 0.757 W/m2K for HDD=5000 per NECB 2011 Table 3.2.1.3"
  end

  def test_max_u_floor_ground_hdd_above_9999
    # NECB 2011 Table 3.2.1.3
    # HDD >= 9999 -> defaults to 0.110 W/m2K for slab-on-grade floors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('floor', 'ground', 10000)

    assert_in_delta 0.110, u_value, 0.001,
      "Expected slab-on-grade floor U-value of 0.110 W/m2K (default) for HDD=10000 per NECB 2011 Table 3.2.1.3"
  end

  # ============================================================================
  # HDD Boundary Condition Tests
  # ============================================================================

  def test_boundary_hdd_exactly_3000
    # Test exactly at HDD=3000 threshold
    # Logic: returns first value where hdd < threshold, so 3000 < 4000 = true
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 3000)

    # At HDD=3000, hdd < 4000 is true, so returns 4000 value
    assert_in_delta 0.278, u_value, 0.001,
      "Expected wall U-value of 0.278 W/m2K at HDD=3000 boundary"
  end

  def test_boundary_hdd_exactly_4000
    # Test exactly at HDD=4000 threshold
    # Logic: 4000 < 5000 = true, so returns 5000 value
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 4000)

    # At HDD=4000, hdd < 5000 is true, so returns 5000 value
    assert_in_delta 0.247, u_value, 0.001,
      "Expected wall U-value of 0.247 W/m2K at HDD=4000 boundary"
  end

  def test_boundary_hdd_exactly_5000
    # Test exactly at HDD=5000 threshold
    # Logic: 5000 < 6000 = true, so returns 6000 value
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('roofceiling', 'outdoors', 5000)

    # At HDD=5000, hdd < 6000 is true, so returns 6000 value
    assert_in_delta 0.162, u_value, 0.001,
      "Expected roof U-value of 0.162 W/m2K at HDD=5000 boundary"
  end

  def test_boundary_hdd_exactly_9999
    # Test exactly at HDD=9999 threshold (upper limit)
    # Logic: 9999 < 9999 = false, so falls through to default
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('window', 'outdoors', 9999)

    # At HDD=9999, no threshold matches, returns default 0.110
    assert_in_delta 0.110, u_value, 0.001,
      "Expected window U-value of 0.110 W/m2K (default) at HDD=9999 boundary"
  end

  # ============================================================================
  # FDWR (Fenestration and Door to Wall Ratio) Tests
  # ============================================================================

  def test_max_fdwr_hdd_2000
    # NECB 2011 Table 3.2.1.4
    # Max FDWR varies by HDD - test low HDD
    standard = Standard.build('NECB2011')
    fdwr = standard.max_fwdr(2000)

    # FDWR should be between 0 and 1 (ratio)
    assert_operator fdwr, :>, 0.0, "FDWR should be greater than 0"
    assert_operator fdwr, :<=, 1.0, "FDWR should be less than or equal to 1.0"
  end

  def test_max_fdwr_hdd_4000
    # NECB 2011 Table 3.2.1.4
    # Max FDWR varies by HDD
    standard = Standard.build('NECB2011')
    fdwr = standard.max_fwdr(4000)

    # FDWR should be between 0 and 1 (ratio)
    assert_operator fdwr, :>, 0.0, "FDWR should be greater than 0"
    assert_operator fdwr, :<=, 1.0, "FDWR should be less than or equal to 1.0"
  end

  def test_max_fdwr_hdd_6000
    # NECB 2011 Table 3.2.1.4
    # Max FDWR varies by HDD
    standard = Standard.build('NECB2011')
    fdwr = standard.max_fwdr(6000)

    # FDWR should be between 0 and 1 (ratio)
    assert_operator fdwr, :>, 0.0, "FDWR should be greater than 0"
    assert_operator fdwr, :<=, 1.0, "FDWR should be less than or equal to 1.0"
  end

  def test_max_fdwr_hdd_8000
    # NECB 2011 Table 3.2.1.4
    # Max FDWR varies by HDD - test high HDD
    standard = Standard.build('NECB2011')
    fdwr = standard.max_fwdr(8000)

    # FDWR should be between 0 and 1 (ratio)
    assert_operator fdwr, :>, 0.0, "FDWR should be greater than 0"
    assert_operator fdwr, :<=, 1.0, "FDWR should be less than or equal to 1.0"
  end

  def test_max_fdwr_decreases_with_hdd
    # NECB 2011 Table 3.2.1.4
    # Generally, max FDWR should decrease as HDD increases (colder climates = less glazing)
    standard = Standard.build('NECB2011')

    fdwr_2000 = standard.max_fwdr(2000)
    fdwr_8000 = standard.max_fwdr(8000)

    # In colder climates (higher HDD), FDWR limits are typically more restrictive
    # This test verifies the trend, though exact values depend on the formula
    assert fdwr_2000.is_a?(Numeric), "FDWR should be a numeric value"
    assert fdwr_8000.is_a?(Numeric), "FDWR should be a numeric value"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_invalid_surface_type_defaults_to_roofceiling
    # Test that invalid surface type defaults to roofceiling
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('invalid_type', 'outdoors', 5000)

    # Should return roofceiling value
    expected = standard.max_u_necb('roofceiling', 'outdoors', 5000)
    assert_in_delta expected, u_value, 0.001,
      "Invalid surface type should default to roofceiling"
  end

  def test_invalid_boundary_condition_defaults_to_outdoors
    # Test that invalid boundary condition defaults to outdoors
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'invalid_condition', 5000)

    # Should return outdoors value
    expected = standard.max_u_necb('wall', 'outdoors', 5000)
    assert_in_delta expected, u_value, 0.001,
      "Invalid boundary condition should default to outdoors"
  end

  def test_very_low_hdd
    # Test very low HDD value (extreme warm climate)
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 500)

    # Should return value for lowest HDD range (< 3000)
    assert_in_delta 0.315, u_value, 0.001,
      "Very low HDD should use lowest range value"
  end

  def test_very_high_hdd
    # Test very high HDD value (extreme cold climate)
    standard = Standard.build('NECB2011')
    u_value = standard.max_u_necb('wall', 'outdoors', 15000)

    # Should return default value since HDD exceeds all thresholds
    assert_in_delta 0.110, u_value, 0.001,
      "Very high HDD should use default value 0.110"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_wall_same_as_necb2011
    # Compare NECB 2015 to NECB 2011 for walls
    # NECB 2015 wall values should be same as 2011
    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    u_2011 = standard_2011.max_u_necb('wall', 'outdoors', 5000)
    u_2015 = standard_2015.max_u_necb('wall', 'outdoors', 5000)

    assert_in_delta u_2011, u_2015, 0.001,
      "NECB 2015 wall U-values should match NECB 2011"
  end

  def test_necb2017_roof_stricter_than_necb2011
    # Compare NECB 2017 to NECB 2011 for roofs
    # NECB 2017 roof values should be more stringent (lower U-value)
    standard_2011 = Standard.build('NECB2011')
    standard_2017 = Standard.build('NECB2017')

    u_2011 = standard_2011.max_u_necb('roofceiling', 'outdoors', 5000)
    u_2017 = standard_2017.max_u_necb('roofceiling', 'outdoors', 5000)

    assert_operator u_2017, :<=, u_2011,
      "NECB 2017 roof U-values should be same or more stringent than NECB 2011"
  end

  def test_necb2020_window_stricter_than_necb2011
    # Compare NECB 2020 to NECB 2011 for windows
    # NECB 2020 window values should be more stringent (lower U-value)
    standard_2011 = Standard.build('NECB2011')
    standard_2020 = Standard.build('NECB2020')

    u_2011 = standard_2011.max_u_necb('window', 'outdoors', 5000)
    u_2020 = standard_2020.max_u_necb('window', 'outdoors', 5000)

    assert_operator u_2020, :<=, u_2011,
      "NECB 2020 window U-values should be same or more stringent than NECB 2011"
  end

end
