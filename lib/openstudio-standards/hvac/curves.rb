module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Curves
    # Methods to create and modify curves for HVAC systems

    # Convert biquadratic curves that are a function of temperature
    # from IP (F) to SI (C) or vice-versa.  The curve is of the form
    # z = C1 + C2*x + C3*x^2 + C4*y + C5*y^2 + C6*x*y
    # where C1, C2, ... are the coefficients,
    # x is the first independent variable (in F or C)
    # y is the second independent variable (in F or C)
    # and z is the resulting value
    #
    # @author Scott Horowitz, NREL
    # @param coeffs [Array<Double>] an array of 6 coefficients, in order
    # @return [Array<Double>] the revised coefficients in the new unit system
    def self.convert_curve_biquadratic(coeffs, ip_to_si: true)
      if ip_to_si
        # Convert IP curves to SI curves
        si_coeffs = []
        si_coeffs << (coeffs[0] + (32.0 * (coeffs[1] + coeffs[3])) + (1024.0 * (coeffs[2] + coeffs[4] + coeffs[5])))
        si_coeffs << ((9.0 / 5.0 * coeffs[1]) + (576.0 / 5.0 * coeffs[2]) + (288.0 / 5.0 * coeffs[5]))
        si_coeffs << (81.0 / 25.0 * coeffs[2])
        si_coeffs << ((9.0 / 5.0 * coeffs[3]) + (576.0 / 5.0 * coeffs[4]) + (288.0 / 5.0 * coeffs[5]))
        si_coeffs << (81.0 / 25.0 * coeffs[4])
        si_coeffs << (81.0 / 25.0 * coeffs[5])
        return si_coeffs
      else
        # Convert SI curves to IP curves
        ip_coeffs = []
        ip_coeffs << (coeffs[0] - (160.0 / 9.0 * (coeffs[1] + coeffs[3])) + (25_600.0 / 81.0 * (coeffs[2] + coeffs[4] + coeffs[5])))
        ip_coeffs << (5.0 / 9.0 * (coeffs[1] - (320.0 / 9.0 * coeffs[2]) - (160.0 / 9.0 * coeffs[5])))
        ip_coeffs << (25.0 / 81.0 * coeffs[2])
        ip_coeffs << (5.0 / 9.0 * (coeffs[3] - (320.0 / 9.0 * coeffs[4]) - (160.0 / 9.0 * coeffs[5])))
        ip_coeffs << (25.0 / 81.0 * coeffs[4])
        ip_coeffs << (25.0 / 81.0 * coeffs[5])
        return ip_coeffs
      end
    end

    # Create a biquadratic curve of the form
    # z = C1 + C2*x + C3*x^2 + C4*y + C5*y^2 + C6*x*y
    #
    # @author Scott Horowitz, NREL
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param coeffs [Array<Double>] an array of 6 coefficients, in order
    # @param name [String] the name of the curve
    # @param min_x [Double] the minimum value of independent variable X that will be used
    # @param max_x [Double] the maximum value of independent variable X that will be used
    # @param min_y [Double] the minimum value of independent variable Y that will be used
    # @param max_y [Double] the maximum value of independent variable Y that will be used
    # @param min_out [Double] the minimum value of dependent variable Z
    # @param max_out [Double] the maximum value of dependent variable Z
    # @return [OpenStudio::Model::CurveBiquadratic] a biquadratic curve
    def self.create_curve_biquadratic(model, coeffs, name: 'CurveBiquadratic', min_x: nil, max_x: nil, min_y: nil, max_y: nil, min_out: nil, max_out: nil)
      curve = OpenStudio::Model::CurveBiquadratic.new(model)
      curve.setName(name)
      curve.setCoefficient1Constant(coeffs[0])
      curve.setCoefficient2x(coeffs[1])
      curve.setCoefficient3xPOW2(coeffs[2])
      curve.setCoefficient4y(coeffs[3])
      curve.setCoefficient5yPOW2(coeffs[4])
      curve.setCoefficient6xTIMESY(coeffs[5])
      curve.setMinimumValueofx(min_x) unless min_x.nil?
      curve.setMaximumValueofx(max_x) unless max_x.nil?
      curve.setMinimumValueofy(min_y) unless min_y.nil?
      curve.setMaximumValueofy(max_y) unless max_y.nil?
      curve.setMinimumCurveOutput(min_out) unless min_out.nil?
      curve.setMaximumCurveOutput(max_out) unless max_out.nil?
      return curve
    end

    # Create a bicubic curve of the form
    # z = C1 + C2*x + C3*x^2 + C4*y + C5*y^2 + C6*x*y + C7*x^3 + C8*y^3 + C9*x^2*y + C10*x*y^2
    #
    # @author Scott Horowitz, NREL
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param coeffs [Array<Double>] an array of 10 coefficients, in order
    # @param name [String] the name of the curve
    # @param min_x [Double] the minimum value of independent variable X that will be used
    # @param max_x [Double] the maximum value of independent variable X that will be used
    # @param min_y [Double] the minimum value of independent variable Y that will be used
    # @param max_y [Double] the maximum value of independent variable Y that will be used
    # @param min_out [Double] the minimum value of dependent variable Z
    # @param max_out [Double] the maximum value of dependent variable Z
    # @return [OpenStudio::Model::CurveBicubic] a bicubic curve
    def self.create_curve_bicubic(model, coeffs, name: 'CurveBicubic', min_x: nil, max_x: nil, min_y: nil, max_y: nil, min_out: nil, max_out: nil)
      curve = OpenStudio::Model::CurveBicubic.new(model)
      curve.setName(name)
      curve.setCoefficient1Constant(coeffs[0])
      curve.setCoefficient2x(coeffs[1])
      curve.setCoefficient3xPOW2(coeffs[2])
      curve.setCoefficient4y(coeffs[3])
      curve.setCoefficient5yPOW2(coeffs[4])
      curve.setCoefficient6xTIMESY(coeffs[5])
      curve.setCoefficient7xPOW3(coeffs[6])
      curve.setCoefficient8yPOW3(coeffs[7])
      curve.setCoefficient9xPOW2TIMESY(coeffs[8])
      curve.setCoefficient10xTIMESYPOW2(coeffs[9])
      curve.setMinimumValueofx(min_x) unless min_x.nil?
      curve.setMaximumValueofx(max_x) unless max_x.nil?
      curve.setMinimumValueofy(min_y) unless min_y.nil?
      curve.setMaximumValueofy(max_y) unless max_y.nil?
      curve.setMinimumCurveOutput(min_out) unless min_out.nil?
      curve.setMaximumCurveOutput(max_out) unless max_out.nil?
      return curve
    end

    # Create a quadratic curve of the form
    # z = C1 + C2*x + C3*x^2
    #
    # @author Scott Horowitz, NREL
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param coeffs [Array<Double>] an array of 3 coefficients, in order
    # @param name [String] the name of the curve
    # @param min_x [Double] the minimum value of independent variable X that will be used
    # @param max_x [Double] the maximum value of independent variable X that will be used
    # @param min_out [Double] the minimum value of dependent variable Z
    # @param max_out [Double] the maximum value of dependent variable Z
    # @param is_dimensionless [Boolean] if true, the X independent variable is considered unitless
    #   and the resulting output dependent variable is considered unitless
    # @return [OpenStudio::Model::CurveQuadratic] a quadratic curve
    def self.create_curve_quadratic(model, coeffs, name: 'CurveQuadratic', min_x: nil, max_x: nil, min_out: nil, max_out: nil, is_dimensionless: false)
      curve = OpenStudio::Model::CurveQuadratic.new(model)
      curve.setName(name)
      curve.setCoefficient1Constant(coeffs[0])
      curve.setCoefficient2x(coeffs[1])
      curve.setCoefficient3xPOW2(coeffs[2])
      curve.setMinimumValueofx(min_x) unless min_x.nil?
      curve.setMaximumValueofx(max_x) unless max_x.nil?
      curve.setMinimumCurveOutput(min_out) unless min_out.nil?
      curve.setMaximumCurveOutput(max_out) unless max_out.nil?
      if is_dimensionless
        curve.setInputUnitTypeforX('Dimensionless')
        curve.setOutputUnitType('Dimensionless')
      end
      return curve
    end

    # Create a cubic curve of the form
    # z = C1 + C2*x + C3*x^2 + C4*x^3
    #
    # @author Scott Horowitz, NREL
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param coeffs [Array<Double>] an array of 4 coefficients, in order
    # @param name [String] the name of the curve
    # @param min_x [Double] the minimum value of independent variable X that will be used
    # @param max_x [Double] the maximum value of independent variable X that will be used
    # @param min_out [Double] the minimum value of dependent variable Z
    # @param max_out [Double] the maximum value of dependent variable Z
    # @return [OpenStudio::Model::CurveCubic] a cubic curve
    def self.create_curve_cubic(model, coeffs, name: 'CurveCubic', min_x: nil, max_x: nil, min_out: nil, max_out: nil)
      curve = OpenStudio::Model::CurveCubic.new(model)
      curve.setName(name)
      curve.setCoefficient1Constant(coeffs[0])
      curve.setCoefficient2x(coeffs[1])
      curve.setCoefficient3xPOW2(coeffs[2])
      curve.setCoefficient4xPOW3(coeffs[3])
      curve.setMinimumValueofx(min_x) unless min_x.nil?
      curve.setMaximumValueofx(max_x) unless max_x.nil?
      curve.setMinimumCurveOutput(min_out) unless min_out.nil?
      curve.setMaximumCurveOutput(max_out) unless max_out.nil?
      return curve
    end

    # Create an exponential curve of the form
    # z = C1 + C2*x^C3
    #
    # @author Scott Horowitz, NREL
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param coeffs [Array<Double>] an array of 3 coefficients, in order
    # @param name [String] the name of the curve
    # @param min_x [Double] the minimum value of independent variable X that will be used
    # @param max_x [Double] the maximum value of independent variable X that will be used
    # @param min_out [Double] the minimum value of dependent variable Z
    # @param max_out [Double] the maximum value of dependent variable Z
    # @return [OpenStudio::Model::CurveExponent] an exponent curve
    def self.create_curve_exponent(model, coeffs, name: 'CurveExponent', min_x: nil, max_x: nil, min_out: nil, max_out: nil)
      curve = OpenStudio::Model::CurveExponent.new(model)
      curve.setName(name)
      curve.setCoefficient1Constant(coeffs[0])
      curve.setCoefficient2Constant(coeffs[1])
      curve.setCoefficient3Constant(coeffs[2])
      curve.setMinimumValueofx(min_x) unless min_x.nil?
      curve.setMaximumValueofx(max_x) unless max_x.nil?
      curve.setMinimumCurveOutput(min_out) unless min_out.nil?
      curve.setMaximumCurveOutput(max_out) unless max_out.nil?
      return curve
    end
  end
end
