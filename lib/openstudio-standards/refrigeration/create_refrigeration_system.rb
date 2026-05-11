module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Create Refrigeration System
    # Methods to add a refrigeration system

    # Adds a refrigerated system to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param refrigeration_equipment [Array<OpenStudio::Model::ModelObject>] Array of RefrigerationCase and/or RefrigerationWalkIn objects
    # @param template [String] Technology or standards level, either 'old', 'new', or 'advanced'
    # @param operation_type [String] Temperature regime, either 'MT' Medium Temperature, or 'LT' Low Temperature
    # @param refrigerant [String] Refrigerant type.
    # @return [OpenStudio::Model::RefrigerationCase] the refrigeration case
    def self.create_refrigeration_system(model, refrigeration_equipment,
                                         template: 'new',
                                         operation_type: 'MT',
                                         refrigerant: 'R404a')
      # Add refrigeration system
      ref_system = OpenStudio::Model::RefrigerationSystem.new(model)
      ref_system.setName("#{operation_type} Refrigeration System")
      ref_system.setRefrigerationSystemWorkingFluidType(refrigerant)
      ref_system.setSuctionTemperatureControlType('ConstantSuctionTemperature')

      # Add equipment to the system and sum capacity.
      # Allowable equipment are refrigeration cases and walkins.
      rated_capacity_w = 0
      refrigeration_equipment.each do |ref_equip|
        if ref_equip.to_RefrigerationCase.is_initialized
          ref_case = ref_equip.to_RefrigerationCase.get
          rated_capacity_w += ref_case.ratedTotalCoolingCapacityperUnitLength * ref_case.caseLength
          ref_system.addCase(ref_case)
        elsif ref_equip.to_RefrigerationWalkIn.is_initialized
          ref_walkin = ref_equip.to_RefrigerationWalkIn.get
          rated_capacity_w += ref_walkin.ratedCoilCoolingCapacity
          ref_system.addWalkin(ref_walkin)
        end
      end

      # Calculate number of compressors
      rated_compressor_capacity_btu_per_hr = 60_000.0
      number_of_compressors = (rated_capacity_w / OpenStudio.convert(rated_compressor_capacity_btu_per_hr, 'Btu/h', 'W').get).ceil

      # add compressors
      (1..number_of_compressors).each do |compressor_number|
        compressor = OpenstudioStandards::Refrigeration.create_compressor(model,
                                                                          template: template,
                                                                          operation_type: operation_type)
        compressor.setName("#{ref_system.name} Compressor #{compressor_number}")
        ref_system.addCompressor(compressor)
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Added #{number_of_compressors} compressors, each with a capacity of #{rated_compressor_capacity_btu_per_hr.round} Btu/hr to serve #{OpenStudio.convert(rated_capacity_w, 'W', 'Btu/hr').get.round} Btu/hr of case and walkin load.")

      # Heat rejection as a function of temperature
      heat_rejection_curve = OpenStudio::Model::CurveLinear.new(model)
      heat_rejection_curve.setName('Condenser Heat Rejection Function of Temperature')
      heat_rejection_curve.setCoefficient1Constant(0.0)
      heat_rejection_curve.setCoefficient2x(22000.0)
      heat_rejection_curve.setMinimumValueofx(-50.0)
      heat_rejection_curve.setMaximumValueofx(50.0)

      # Add condenser
      condenser = OpenStudio::Model::RefrigerationCondenserAirCooled.new(model)
      condenser.setRatedEffectiveTotalHeatRejectionRateCurve(heat_rejection_curve)
      condenser.setRatedSubcoolingTemperatureDifference(OpenStudio.convert(2.0, 'F', 'C').get)
      condenser.setMinimumFanAirFlowRatio(0.0)
      condenser.setRatedFanPower(0.04 * rated_capacity_w)
      condenser.setCondenserFanSpeedControlType('VariableSpeed')
      ref_system.setRefrigerationCondenser(condenser)

      return ref_system
    end
  end
end
