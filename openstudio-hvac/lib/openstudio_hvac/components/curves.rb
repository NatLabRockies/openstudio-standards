require 'json'

module OpenStudioHVAC
  # Builds OpenStudio performance-curve objects from the gem's data/curves.json.
  module Curves
    DATA_PATH = File.expand_path('../data/curves.json', __dir__)

    def self.data
      @data ||= JSON.parse(File.read(DATA_PATH))['curves']
    end

    # Build (or fetch, if already present in the model) a named curve.
    #
    # @param model [OpenStudio::Model::Model]
    # @param name [String] a curve name from data/curves.json
    # @return [OpenStudio::Model::Curve]
    def self.build(model, name)
      existing = model.getCurves.find { |c| c.nameString == name }
      return existing unless existing.nil?

      spec = data[name]
      raise(ArgumentError, "unknown curve '#{name}'") if spec.nil?

      curve = case spec['type']
              when 'biquadratic' then build_biquadratic(model, spec)
              when 'quadratic'   then build_quadratic(model, spec)
              when 'cubic'       then build_cubic(model, spec)
              else raise(ArgumentError, "unknown curve type '#{spec['type']}' for '#{name}'")
              end
      curve.setName(name)
      curve
    end

    def self.build_biquadratic(model, spec)
      curve = OpenStudio::Model::CurveBiquadratic.new(model)
      curve.setCoefficient1Constant(spec['coeff_1_constant'])
      curve.setCoefficient2x(spec['coeff_2_x'])
      curve.setCoefficient3xPOW2(spec['coeff_3_x2'])
      curve.setCoefficient4y(spec['coeff_4_y'])
      curve.setCoefficient5yPOW2(spec['coeff_5_y2'])
      curve.setCoefficient6xTIMESY(spec['coeff_6_xy'])
      curve.setMinimumValueofx(spec['min_x'])
      curve.setMaximumValueofx(spec['max_x'])
      curve.setMinimumValueofy(spec['min_y'])
      curve.setMaximumValueofy(spec['max_y'])
      curve
    end

    def self.build_quadratic(model, spec)
      curve = OpenStudio::Model::CurveQuadratic.new(model)
      curve.setCoefficient1Constant(spec['coeff_1_constant'])
      curve.setCoefficient2x(spec['coeff_2_x'])
      curve.setCoefficient3xPOW2(spec['coeff_3_x2'])
      curve.setMinimumValueofx(spec['min_x'])
      curve.setMaximumValueofx(spec['max_x'])
      curve
    end

    def self.build_cubic(model, spec)
      curve = OpenStudio::Model::CurveCubic.new(model)
      curve.setCoefficient1Constant(spec['coeff_1_constant'])
      curve.setCoefficient2x(spec['coeff_2_x'])
      curve.setCoefficient3xPOW2(spec['coeff_3_x2'])
      curve.setCoefficient4xPOW3(spec['coeff_4_x3'])
      curve.setMinimumValueofx(spec['min_x'])
      curve.setMaximumValueofx(spec['max_x'])
      curve
    end
  end
end
