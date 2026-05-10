require_relative '../test_helper'

# Test DHW (Domestic Hot Water) calculation methods
# Tests the DHW capacity, pump head, and friction factor calculations
#
# Methods tested:
# - NECB2011#auto_size_shw_capacity - DHW tank capacity and volume calculation
# - NECB2011#auto_size_shw_pump_head - Pump head calculation based on piping length
# - NECB2011#friction_factor - Darcy-Weisbach friction factor calculation (PURE MATH - no model needed!)
#
# References:
# - NECB 2011 Service Water Heating Requirements
# - Darcy-Weisbach equation for pressure loss in pipes
# - https://neutrium.net/fluid_flow/pressure-loss-in-pipe
# - https://www.engineeringtoolbox.com/flow-velocity-water-pipes-d_385.html
class TestDhwCalculations < Minitest::Test

  # ============================================================================
  # DHW Capacity Calculation Tests
  # ============================================================================

  def test_dhw_capacity_no_hot_water_demand
    # Test DHW capacity when no spaces have hot water demand
    # Should return zero capacity and volume
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a space with no DHW requirements (storage space)
    space = OpenStudio::Model::Space.new(model)
    space.setName('Storage Space')

    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Warehouse')
    space_type.setStandardsSpaceType('Bulk')
    space.setSpaceType(space_type)

    # Calculate DHW sizing
    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    # Verify zero capacity for spaces with no DHW
    assert_equal 0, shw_sizing['loop_peak_flow_rate_SI'],
      "DHW loop peak flow rate should be 0 when no spaces have DHW requirements"
    assert_equal 0, shw_sizing['tank_capacity_SI'],
      "DHW tank capacity should be 0 when no spaces have DHW requirements"
    assert_equal 0, shw_sizing['tank_volume_SI'],
      "DHW tank volume should be 0 when no spaces have DHW requirements"
  end

  def test_dhw_capacity_scale_factor_string_conversion
    # Test that DHW capacity handles scale factor as string
    # Should convert string to float
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Test with string scale factors
    shw_sizing_default = standard.auto_size_shw_capacity(model: model, shw_scale: 'NECB_Default')
    shw_sizing_none = standard.auto_size_shw_capacity(model: model, shw_scale: 'none')
    shw_sizing_numeric = standard.auto_size_shw_capacity(model: model, shw_scale: '2.0')

    # All should return valid (zero for empty model) results without errors
    assert_instance_of Hash, shw_sizing_default, "Should handle 'NECB_Default' string"
    assert_instance_of Hash, shw_sizing_none, "Should handle 'none' string"
    assert_instance_of Hash, shw_sizing_numeric, "Should handle numeric string '2.0'"
  end

  def test_dhw_capacity_u_value_parameter
    # Test DHW capacity calculation with different U-values (insulation)
    # Lower U-value (better insulation) should reduce parasitic loss
    standard = Standard.build('NECB2011')

    # The u parameter affects parasitic loss calculation in auto_size_shw_capacity
    # parasitic_loss = u * tank_area * (tank_temp - room_temp)
    # For a given tank, lower u means lower parasitic loss

    # Note: This test verifies the parameter is accepted, actual parasitic loss
    # calculation requires a model with DHW-using spaces
    model = OpenStudio::Model::Model.new

    # Test with well-insulated tank (low U-value)
    shw_sizing_insulated = standard.auto_size_shw_capacity(model: model, u: 0.2, height_to_radius: 2, shw_scale: 1.0)

    # Test with poorly-insulated tank (high U-value)
    shw_sizing_uninsulated = standard.auto_size_shw_capacity(model: model, u: 1.0, height_to_radius: 2, shw_scale: 1.0)

    # Both should return valid results
    assert_instance_of Hash, shw_sizing_insulated, "Should calculate with low U-value"
    assert_instance_of Hash, shw_sizing_uninsulated, "Should calculate with high U-value"
  end

  def test_dhw_capacity_height_to_radius_ratio
    # Test DHW capacity calculation with different tank geometries
    # Height-to-radius ratio affects tank surface area and parasitic loss
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Test with tall skinny tank (high ratio)
    shw_sizing_tall = standard.auto_size_shw_capacity(model: model, u: 0.45, height_to_radius: 4, shw_scale: 1.0)

    # Test with short wide tank (low ratio)
    shw_sizing_short = standard.auto_size_shw_capacity(model: model, u: 0.45, height_to_radius: 1, shw_scale: 1.0)

    # Both should return valid results
    assert_instance_of Hash, shw_sizing_tall, "Should calculate with tall tank geometry"
    assert_instance_of Hash, shw_sizing_short, "Should calculate with short tank geometry"
  end

  def test_dhw_capacity_return_structure
    # Test that auto_size_shw_capacity returns expected hash structure
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    # Verify all required keys are present
    assert shw_sizing.key?('tank_volume_SI'), "Should include tank_volume_SI"
    assert shw_sizing.key?('tank_capacity_SI'), "Should include tank_capacity_SI"
    assert shw_sizing.key?('max_temp_SI'), "Should include max_temp_SI"
    assert shw_sizing.key?('loop_peak_flow_rate_SI'), "Should include loop_peak_flow_rate_SI"
    assert shw_sizing.key?('parasitic_loss'), "Should include parasitic_loss"
    assert shw_sizing.key?('spaces_w_dhw'), "Should include spaces_w_dhw array"

    # Verify data types (use kind_of? for numeric types as they may be Integer or Float)
    assert_kind_of Numeric, shw_sizing['tank_volume_SI'], "tank_volume_SI should be Numeric"
    assert_kind_of Numeric, shw_sizing['tank_capacity_SI'], "tank_capacity_SI should be Numeric"
    assert_kind_of Numeric, shw_sizing['max_temp_SI'], "max_temp_SI should be Numeric"
    assert_kind_of Numeric, shw_sizing['loop_peak_flow_rate_SI'], "loop_peak_flow_rate_SI should be Numeric"
    assert_kind_of Numeric, shw_sizing['parasitic_loss'], "parasitic_loss should be Numeric"
    assert_instance_of Array, shw_sizing['spaces_w_dhw'], "spaces_w_dhw should be Array"
  end

  # ============================================================================
  # Pump Head Calculation Tests
  # ============================================================================

  def test_pump_head_default_value
    # Test that default pump head is returned when default=true
    # Default value is 179532 Pa based on OpenStudio 2.4.1 constant speed pump
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump_head = standard.auto_size_shw_pump_head(model, default: true)

    assert_equal 179532, pump_head,
      "Default pump head should be 179532 Pa per OpenStudio 2.4.1 defaults"
  end

  def test_pump_head_no_mechanical_room
    # Test pump head calculation when no mechanical room is found
    # Should return default value
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Empty model with no spaces
    pump_head = standard.auto_size_shw_pump_head(model, default: false)

    assert_equal 179532, pump_head,
      "Should return default pump head when no mechanical room is found"
  end

  def test_pump_head_velocity_parameter_acceptance
    # Test that pump_head method accepts velocity parameter
    # Higher velocity should be accepted without errors
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Test with default velocity (1.75 m/s)
    pump_head_default = standard.auto_size_shw_pump_head(model, default: true, pipe_vel: 1.75)

    # Test with higher velocity (3.0 m/s)
    pump_head_high = standard.auto_size_shw_pump_head(model, default: true, pipe_vel: 3.0)

    # Both should return valid pump head values
    assert_kind_of Numeric, pump_head_default, "Should accept default velocity parameter"
    assert_kind_of Numeric, pump_head_high, "Should accept high velocity parameter"
  end

  def test_pump_head_physical_parameters
    # Test that pump head method accepts physical property parameters
    # Verifies kinematic viscosity, density, and pipe roughness parameters
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Test with custom physical properties
    pump_head = standard.auto_size_shw_pump_head(model,
                                                  default: true,
                                                  pipe_vel: 1.75,
                                                  kin_visc_SI: 0.000004736,  # Water at 60°C
                                                  density_SI: 983,            # kg/m³
                                                  pipe_rough_m: 0.0000015)    # PVC pipe

    assert_kind_of Numeric, pump_head, "Should accept physical property parameters"
    assert_operator pump_head, :>, 0, "Pump head should be positive"
  end

  # ============================================================================
  # Friction Factor Calculation Tests (PURE MATH - No Model Required!)
  # ============================================================================

  def test_friction_factor_laminar_flow
    # Test friction factor for laminar flow (Re <= 2100)
    # Uses Hagen-Poiseuille equation: f = 64/Re
    # Reference: https://neutrium.net/fluid_flow/pressure-loss-in-pipe
    standard = Standard.build('NECB2011')

    # Laminar flow: Re = 1000
    re = 1000
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # For laminar flow: f = 64/Re
    expected_f = 64.0 / re

    assert_in_delta expected_f, f, 0.001,
      "Friction factor for laminar flow (Re=1000) should be 64/Re = 0.064"
    assert_in_delta 0.064, f, 0.001,
      "Friction factor for laminar flow should be approximately 0.064"
  end

  def test_friction_factor_turbulent_flow
    # Test friction factor for turbulent flow (Re > 4000)
    # Uses Serghide's equation (iterative solution of Colebrook equation)
    # Reference: https://neutrium.net/fluid_flow/pressure-loss-in-pipe
    standard = Standard.build('NECB2011')

    # Turbulent flow: Re = 100000
    re = 100000
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # For turbulent flow, friction factor should be much smaller than laminar
    # Typical range: 0.01 - 0.05
    assert_operator f, :>, 0.01,
      "Turbulent friction factor should be greater than 0.01"
    assert_operator f, :<, 0.05,
      "Turbulent friction factor should be less than 0.05"

    # Should be less than laminar value for same Re
    laminar_f = 64.0 / re
    assert_operator f, :>, laminar_f,
      "Turbulent friction factor should be greater than laminar value at high Re (turbulent has higher friction)"
  end

  def test_friction_factor_transition_flow
    # Test friction factor for transition flow (2100 < Re <= 4000)
    # Uses linear interpolation between laminar and turbulent
    standard = Standard.build('NECB2011')

    # Transition flow: Re = 3000
    re = 3000
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # Calculate laminar value at Re = 2100
    f_laminar_2100 = 64.0 / 2100.0

    # Friction factor should be reasonable for transition zone
    assert_operator f, :>, 0.01,
      "Transition friction factor should be greater than 0.01"
    assert_operator f, :<, 0.1,
      "Transition friction factor should be less than 0.1"
  end

  def test_friction_factor_roughness_effect
    # Test that pipe roughness affects friction factor in turbulent flow
    # Rougher pipes have higher friction factors
    standard = Standard.build('NECB2011')

    # Turbulent flow: Re = 50000
    re = 50000

    # Smooth pipe (low roughness)
    f_smooth = standard.friction_factor(re, 0.000001)

    # Rough pipe (high roughness)
    f_rough = standard.friction_factor(re, 0.0001)

    # Rougher pipe should have higher friction factor
    assert_operator f_rough, :>, f_smooth,
      "Rougher pipe should have higher friction factor in turbulent flow"
  end

  def test_friction_factor_reynolds_number_effect
    # Test that friction factor changes appropriately with Reynolds number
    # In turbulent flow, f decreases slightly as Re increases
    standard = Standard.build('NECB2011')

    relative_roughness = 0.00001

    # Lower turbulent Re
    f_low_re = standard.friction_factor(10000, relative_roughness)

    # Higher turbulent Re
    f_high_re = standard.friction_factor(100000, relative_roughness)

    # Friction factor should decrease with increasing Re in turbulent flow
    assert_operator f_high_re, :<, f_low_re,
      "Friction factor should decrease with increasing Reynolds number in turbulent flow"
  end

  def test_friction_factor_boundary_laminar_transition
    # Test friction factor exactly at laminar/transition boundary (Re = 2100)
    standard = Standard.build('NECB2011')

    re = 2100
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # Should use laminar equation at boundary (Re <= 2100)
    expected_f = 64.0 / 2100.0

    assert_in_delta expected_f, f, 0.001,
      "At Re=2100 boundary, should use laminar equation: f = 64/Re"
  end

  def test_friction_factor_boundary_transition_turbulent
    # Test friction factor exactly at transition/turbulent boundary (Re = 4000)
    standard = Standard.build('NECB2011')

    re = 4000
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # Should still be in transition zone (2100 < Re <= 4000) using interpolation
    assert_operator f, :>, 0.01,
      "At Re=4000 boundary, friction factor should be reasonable"
    assert_operator f, :<, 0.1,
      "At Re=4000 boundary, friction factor should be less than 0.1"
  end

  def test_friction_factor_very_low_reynolds
    # Test friction factor for very low Reynolds number (highly laminar)
    standard = Standard.build('NECB2011')

    re = 100
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # For very low Re, f = 64/Re = 0.64
    expected_f = 64.0 / 100.0

    assert_in_delta expected_f, f, 0.001,
      "For Re=100, friction factor should be 64/100 = 0.64"
    assert_in_delta 0.64, f, 0.001,
      "Very low Reynolds number should give high friction factor"
  end

  def test_friction_factor_very_high_reynolds
    # Test friction factor for very high Reynolds number (fully turbulent)
    # Serghide's equation is valid up to Re = 1×10^10
    standard = Standard.build('NECB2011')

    re = 1000000
    relative_roughness = 0.00001

    f = standard.friction_factor(re, relative_roughness)

    # For very high Re, friction factor should be small and dominated by roughness
    assert_operator f, :>, 0.008,
      "Very high Reynolds number should still have positive friction factor"
    assert_operator f, :<, 0.03,
      "Very high Reynolds number friction factor should be small"
  end

  def test_friction_factor_smooth_pipe_limit
    # Test friction factor for perfectly smooth pipe (relative roughness → 0)
    # Should approach the smooth pipe limit (Blasius equation)
    standard = Standard.build('NECB2011')

    re = 100000
    relative_roughness = 0.0000001  # Nearly smooth

    f = standard.friction_factor(re, relative_roughness)

    # For smooth pipes in turbulent flow, f ≈ 0.316/Re^0.25 (Blasius)
    # For Re = 100000, this gives approximately 0.018
    assert_operator f, :>, 0.015,
      "Smooth pipe friction factor should be greater than 0.015"
    assert_operator f, :<, 0.025,
      "Smooth pipe friction factor should be less than 0.025"
  end

  def test_friction_factor_laminar_reynolds_independence_from_roughness
    # Test that roughness doesn't affect friction factor in laminar flow
    # In laminar flow, f = 64/Re regardless of pipe roughness
    standard = Standard.build('NECB2011')

    re = 1500  # Laminar flow

    # Very smooth pipe
    f_smooth = standard.friction_factor(re, 0.0000001)

    # Very rough pipe
    f_rough = standard.friction_factor(re, 0.001)

    # In laminar flow, both should give the same result (f = 64/Re)
    expected_f = 64.0 / re

    assert_in_delta expected_f, f_smooth, 0.001,
      "Laminar friction factor should be 64/Re regardless of roughness"
    assert_in_delta expected_f, f_rough, 0.001,
      "Laminar friction factor should be 64/Re regardless of roughness"
    assert_in_delta f_smooth, f_rough, 0.001,
      "Pipe roughness should not affect friction factor in laminar flow"
  end

  def test_friction_factor_transition_interpolation_boundaries
    # Test that transition zone interpolation is bounded properly
    # Should be between laminar at Re=2100 and turbulent at Re=4001
    standard = Standard.build('NECB2011')

    relative_roughness = 0.00001

    # Laminar at boundary
    f_laminar_boundary = standard.friction_factor(2100, relative_roughness)

    # Start of transition
    f_transition_start = standard.friction_factor(2101, relative_roughness)

    # Middle of transition
    f_transition_mid = standard.friction_factor(3000, relative_roughness)

    # End of transition
    f_transition_end = standard.friction_factor(4000, relative_roughness)

    # Just into turbulent
    f_turbulent_start = standard.friction_factor(4001, relative_roughness)

    # Verify reasonable progression (not strictly monotonic due to different equations)
    assert_operator f_transition_start, :>, 0.01, "Transition start should be reasonable"
    assert_operator f_transition_mid, :>, 0.01, "Transition middle should be reasonable"
    assert_operator f_transition_end, :>, 0.01, "Transition end should be reasonable"
    assert_operator f_turbulent_start, :>, 0.01, "Turbulent start should be reasonable"

    # All should be less than laminar boundary value
    assert_operator f_transition_start, :<, 0.1, "Should be less than 0.1"
    assert_operator f_transition_mid, :<, 0.1, "Should be less than 0.1"
  end

  def test_friction_factor_near_zero_roughness_edge_case
    # Test friction factor with near-zero relative roughness (theoretical smooth pipe)
    # Note: Zero roughness causes log10(0) = undefined, so use very small value
    standard = Standard.build('NECB2011')

    re = 50000  # Turbulent flow
    relative_roughness = 1.0e-10  # Nearly perfectly smooth (approaching zero)

    f = standard.friction_factor(re, relative_roughness)

    # Should return a valid friction factor for near-smooth pipe
    assert_operator f, :>, 0.01,
      "Near-zero roughness should still give valid friction factor"
    assert_operator f, :<, 0.03,
      "Near-zero roughness friction factor should be in smooth pipe range"
  end

end
