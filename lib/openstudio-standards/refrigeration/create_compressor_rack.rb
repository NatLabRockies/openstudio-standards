module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Create Refrigeration Compressor Rack
    # Methods to add a refrigeration compressor rack

    # Adds a self contained refrigeration compressor rack for a case or walkin to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param refrigeration_equipment [OpenStudio::Model::ModelObject] A RefrigerationCase or RefrigerationWalkIn object
    # @param template [String] Technology or standards level, either 'old', 'new', or 'advanced'
    # @return [OpenStudio::Model::RefrigerationCase] the refrigeration case
    def self.create_compressor_rack(model, refrigeration_equipment,
                                    template: 'new')
      # Add refrigeration system
      ref_rack = OpenStudio::Model::RefrigerationCompressorRack.new(model)
      ref_rack.setName('Self-Contained Refrigeration System')

      # Add refrigeration case or walkin to the rack
      if refrigeration_equipment.to_RefrigerationCase.is_initialized
        ref_case = refrigeration_equipment.to_RefrigerationCase.get
        rated_capacity_w = ref_case.ratedTotalCoolingCapacityperUnitLength * ref_case.caseLength
        ref_rack.addCase(ref_case)
        thermal_zone = ref_case.thermalZone.get
      elsif refrigeration_equipment.to_RefrigerationWalkIn.is_initialized
        ref_walkin = refrigeration_equipment.to_RefrigerationWalkIn.get
        rated_capacity_w = ref_walkin.ratedCoilCoolingCapacity
        ref_rack.addWalkin(ref_walkin)
        thermal_zone = ref_walkin.zoneBoundaryThermalZone.get
      end

      # set zone based on equipment zone
      ref_rack.setHeatRejectionLocation('Zone')
      ref_rack.setHeatRejectionZone(thermal_zone)
      ref_rack.setCondenserType('AirCooled')

      # @todo add cop and curves for compressor racks
      # ref_rack.setDesignCompressorRackCOP(Double)
      # ref_rack.setCompressorRackCOPFunctionofTemperatureCurve(&Curve)
      # ref_rack.setDesignCondenserFanPower(Double)
      # ref_rack.setCondenserFanPowerFunctionofTemperatureCurve(&Curve)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Added compressor rack with capacity #{OpenStudio.convert(rated_capacity_w, 'W', 'Btu/hr').get.round} Btu/hr of load serving #{refrigeration_equipment.name}.")

      return ref_rack
    end
  end
end
