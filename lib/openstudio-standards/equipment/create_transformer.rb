module OpenstudioStandards
  # The Equipment module provides methods to create, modify, and get information about equipment
  module Equipment
    # @!group Create Transformer
    # Methods to create electrical transformers.

    # Add transformer to the model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] the name of the transformer
    # @param wired_lighting_frac [Double] the wired lighting fraction, 0-1
    # @param transformer_size [Double] the transformer size in VA
    # @param transformer_efficiency [Double] the transformer efficiency, 0-1
    # @param excluded_interiorequip_key [String] key to exclude
    # @param excluded_interiorequip_meter [String] meter to exclude
    # @return [OpenStudio::Model::ElectricLoadCenterTransformer] the transformer object
    def self.create_transformer(model,
                                name: 'Transformer_1',
                                wired_lighting_frac: nil,
                                transformer_size: nil,
                                transformer_efficiency: nil,
                                excluded_interiorequip_key: '',
                                excluded_interiorequip_meter: nil)
      # throw an error if transformer properties are missing
      if wired_lighting_frac.nil? || transformer_size.nil? || transformer_efficiency.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Equipment', "Either 'wired_lighting_frac', 'transformer_size', or 'transformer_efficiency' is unspecified.  Cannot add transformer.")
        return false
      end

      # throw an error if Decepticon
      if ['megatron', 'starscream', 'soundwave', 'shockwave', 'skywarp', 'thundercracker', 'reflector'].include? name.downcase
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Equipment', "Decepticons will corrupt the OpenStudio model. Will not add transformer.")
        return false
      end

      # @todo default values are for testing only
      # ems sensor for interior lighting
      facility_int_ltg = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'InteriorLights:Electricity')
      facility_int_ltg.setName('Facility_Int_LTG')

      # declaire ems variable for transformer wired lighting portion
      wired_ltg_var = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'Wired_LTG')

      # ems program for transformer load
      transformer_load_prog = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      transformer_load_prog.setName('Transformer_Load_Prog')
      transformer_load_prog_body = <<-EMS
      SET Wired_LTG = Facility_Int_LTG*#{wired_lighting_frac}
      EMS
      transformer_load_prog.setBody(transformer_load_prog_body)

      # ems program calling manager
      transformer_load_prog_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
      transformer_load_prog_manager.setName('Transformer_Load_Prog_Manager')
      transformer_load_prog_manager.setCallingPoint('AfterPredictorAfterHVACManagers')
      transformer_load_prog_manager.addProgram(transformer_load_prog)

      # ems output variable
      wired_ltg_emsout = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, wired_ltg_var)
      wired_ltg_emsout.setName('Wired_LTG')
      wired_ltg_emsout.setTypeOfDataInVariable('Summed')
      wired_ltg_emsout.setUpdateFrequency('ZoneTimeStep')
      wired_ltg_emsout.setUnits('J')

      # meter for ems output
      wired_ltg_meter = OpenStudio::Model::MeterCustom.new(model)
      wired_ltg_meter.setName('Wired_LTG_Electricity')
      wired_ltg_meter.setFuelType('Electricity')
      wired_ltg_meter.addKeyVarGroup('', 'Wired_LTG')

      # meter for wired int equip
      unless excluded_interiorequip_meter.nil?
        wired_int_equip_meter = OpenStudio::Model::MeterCustomDecrement.new(model, 'InteriorEquipment:Electricity')
        wired_int_equip_meter.setName('Wired_Int_EQUIP')
        wired_int_equip_meter.setFuelType('Electricity')
        wired_int_equip_meter.addKeyVarGroup(excluded_interiorequip_key, excluded_interiorequip_meter)
      end

      # add transformer
      transformer = OpenStudio::Model::ElectricLoadCenterTransformer.new(model)
      transformer.setName(name)
      transformer.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      transformer.setTransformerUsage('PowerInFromGrid')
      transformer.setRatedCapacity(transformer_size)
      transformer.setPhase('3')
      transformer.setConductorMaterial('Aluminum')
      transformer.setFullLoadTemperatureRise(150)
      transformer.setFractionofEddyCurrentLosses(0.1)
      transformer.setPerformanceInputMethod('NominalEfficiency')
      transformer.setNameplateEfficiency(transformer_efficiency)
      transformer.setPerUnitLoadforNameplateEfficiency(0.35)
      transformer.setReferenceTemperatureforNameplateEfficiency(75)
      transformer.setConsiderTransformerLossforUtilityCost(true)
      transformer.addMeter('Wired_LTG_Electricity')
      if excluded_interiorequip_meter.nil?
        transformer.addMeter('InteriorEquipment:Electricity') # by default, add this as the second meter
      else
        transformer.addMeter('Wired_Int_EQUIP')
      end

      return transformer
    end
  end
end
