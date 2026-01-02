require_relative '../../helpers/minitest_helper'

class TestHVACCurves < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_convert_curve_biquadratic
    coeffs_ip = [3.670270705, -0.098652414, 0.000955906, 0.006552414, -0.0000156, -0.000131877]
    coeffs_si = @hvac.convert_curve_biquadratic(coeffs_ip)
    assert_in_delta(1.5509, coeffs_si[0], 0.0001, 'Coefficient 1 is not correct')
    assert_in_delta(-0.07505, coeffs_si[1], 0.0001, 'Coefficient 2 is not correct')
    assert_in_delta(0.003097, coeffs_si[2], 0.0001, 'Coefficient 3 is not correct')
    assert_in_delta(0.0024, coeffs_si[3], 0.0001, 'Coefficient 4 is not correct')
    assert_in_delta(-5.0544e-05, coeffs_si[4], 0.0001, 'Coefficient 5 is not correct')
    assert_in_delta(-0.000427, coeffs_si[5], 0.0001, 'Coefficient 6 is not correct')
  end

  def test_create_curve_biquadratic
    model = OpenStudio::Model::Model.new
    coeffs_ip = [3.670270705, -0.098652414, 0.000955906, 0.006552414, -0.0000156, -0.000131877]
    coeffs_si = @hvac.convert_curve_biquadratic(coeffs_ip)
    curve = @hvac.create_curve_biquadratic(model, coeffs_si)
    assert(curve.is_a?(OpenStudio::Model::CurveBiquadratic), 'Curve is not a CurveBicubic')
  end

  def test_create_curve_bicubic
    model = OpenStudio::Model::Model.new
    coeffs = [60000.0, 1600.0, 13.5, -500.0, 8.2, -3.75, 0.055, -0.09, 0.006, -0.0375]
    curve = @hvac.create_curve_bicubic(model, coeffs)
    assert(curve.is_a?(OpenStudio::Model::CurveBicubic), 'Curve is not a CurveBicubic')
  end

  def test_create_curve_quadratic
    model = OpenStudio::Model::Model.new
    coeffs = [0.75, 0.4, -0.15]
    curve = @hvac.create_curve_quadratic(model, coeffs)
    assert(curve.is_a?(OpenStudio::Model::CurveQuadratic), 'Curve is not a CurveQuadratic')
  end

  def test_create_curve_cubic
    model = OpenStudio::Model::Model.new
    coeffs = [1.0, 0.5, -0.2, 0.05]
    curve = @hvac.create_curve_cubic(model, coeffs)
    assert(curve.is_a?(OpenStudio::Model::CurveCubic), 'Curve is not a CurveCubic')
  end

  def test_create_curve_exponent
    model = OpenStudio::Model::Model.new
    coeffs = coeffs = [0.75, 0.4, -0.15]
    curve = @hvac.create_curve_exponent(model, coeffs)
    assert(curve.is_a?(OpenStudio::Model::CurveExponent), 'Curve is not a CurveExponent')
  end
end
