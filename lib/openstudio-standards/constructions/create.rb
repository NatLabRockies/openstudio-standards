module OpenstudioStandards
  # The Constructions module provides methods create, modify, and get information about model Constructions
  module Constructions
    # @!group Create
    # Methods to create Constructions

    # This will create a deep copy of the construction, meaning it will clone and create new material objects as well
    # This function will clone
    #
    # @param construction [OpenStudio::Model::Construction] OpenStudio Construction object object
    # @return [OpenStudio::Model::Construction] New OpenStudio Construction object
    def self.construction_deep_copy(construction)
      cons_obj_type = construction.iddObjectType.valueName.to_s
      case cons_obj_type
      when 'OS_Construction_FfactorGroundFloor'
        new_construction = construction.clone.to_FFactorGroundFloorConstruction.get
        f_const = construction.to_FFactorGroundFloorConstruction.get
        new_construction.setFFactor(f_const.fFactor)
        new_construction.setArea(f_const.area)
        new_construction.setPerimeterExposed(f_const.perimeterExposed)
      when 'OS_Construction_CfactorUndergroundWall'
        c_const = construction.to_CFactorUndergroundWallConstruction.get
        new_construction = c_const.clone.to_CFactorUndergroundWallConstruction.get
        new_construction.setCFactor(c_const.cFactor)
        new_construction.setHeight(c_const.height)
      when 'OS_Construction_AirBoundary'
        a_const = construction.to_ConstructionAirBoundary.get
        new_construction = a_const.clone.to_ConstructionAirBoundary.get
        new_construction.setAirExchangeMethod(a_const.airExchangeMethod)
        new_construction.setSimpleMixingAirChangesPerHour(a_const.simpleMixingAirChangesPerHour)
        new_construction.setSimpleMixingSchedule(a_const.simpleMixingSchedule)
      else
        # Layer by layer construction
        if cons_obj_type == 'OS_Construction_InternalSource'
          new_construction = construction.clone.to_ConstructionWithInternalSource.get
          i_const = construction.to_ConstructionWithInternalSource.get
          new_construction.setSourcePresentAfterLayerNumber(i_const.sourcePresentAfterLayerNumber)
          new_construction.setTemperatureCalculationRequestedAfterLayerNumber(i_const.temperatureCalculationRequestedAfterLayerNumber)
          new_construction.setDimensionsForTheCTFCalculation(i_const.dimensionsForTheCTFCalculation)
          new_construction.setTubeSpacing(i_const.tubeSpacing)
          new_construction.setTwoDimensionalTemperatureCalculationPosition(i_const.twoDimensionalTemperatureCalculationPosition)
        else
          new_construction = construction.clone.to_Construction.get
        end
        (0..new_construction.layers.length - 1).each do |layer_number|
          cloned_layer = new_construction.getLayer(layer_number).clone.to_Material.get
          new_construction.setLayer(layer_number, cloned_layer)
        end
      end

      return new_construction
    end

    # Return the existing adiabatic floor construction, or create one if absent.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Construction] OpenStudio Construction object
    def self.model_get_adiabatic_floor_construction(model)
      adiabatic_construction_name = 'Adiabatic floor construction'

      # Check if adiabatic floor construction already exists in the model
      adiabatic_construct_exists = model.getConstructionByName(adiabatic_construction_name).is_initialized

      # Check to see if adiabatic construction has been constructed. If so, return it. Else, construct it.
      return model.getConstructionByName(adiabatic_construction_name).get if adiabatic_construct_exists

      # Assign construction to adiabatic construction
      cp02_carpet_pad = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
      cp02_carpet_pad.setName('CP02 CARPET PAD')
      cp02_carpet_pad.setRoughness('VeryRough')
      cp02_carpet_pad.setThermalResistance(0.21648)
      cp02_carpet_pad.setThermalAbsorptance(0.9)
      cp02_carpet_pad.setSolarAbsorptance(0.7)
      cp02_carpet_pad.setVisibleAbsorptance(0.8)

      normalweight_concrete_floor = OpenStudio::Model::StandardOpaqueMaterial.new(model)
      normalweight_concrete_floor.setName('100mm Normalweight concrete floor')
      normalweight_concrete_floor.setRoughness('MediumSmooth')
      normalweight_concrete_floor.setThickness(0.1016)
      normalweight_concrete_floor.setThermalConductivity(2.31)
      normalweight_concrete_floor.setDensity(2322)
      normalweight_concrete_floor.setSpecificHeat(832)

      nonres_floor_insulation = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
      nonres_floor_insulation.setName('Nonres_Floor_Insulation')
      nonres_floor_insulation.setRoughness('MediumSmooth')
      nonres_floor_insulation.setThermalResistance(2.88291975297193)
      nonres_floor_insulation.setThermalAbsorptance(0.9)
      nonres_floor_insulation.setSolarAbsorptance(0.7)
      nonres_floor_insulation.setVisibleAbsorptance(0.7)

      floor_adiabatic_construction = OpenStudio::Model::Construction.new(model)
      floor_adiabatic_construction.setName(adiabatic_construction_name)
      floor_layers = OpenStudio::Model::MaterialVector.new
      floor_layers << cp02_carpet_pad
      floor_layers << normalweight_concrete_floor
      floor_layers << nonres_floor_insulation
      floor_adiabatic_construction.setLayers(floor_layers)

      return floor_adiabatic_construction
    end

    # Return the existing adiabatic wall construction, or create one if absent.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Construction] OpenStudio Construction object
    def self.model_get_adiabatic_wall_construction(model)
      adiabatic_construction_name = 'Adiabatic wall construction'

      # Check if adiabatic wall construction already exists in the model
      adiabatic_construct_exists = model.getConstructionByName(adiabatic_construction_name).is_initialized

      # Check to see if adiabatic construction has been constructed. If so, return it. Else, construct it.
      return model.getConstructionByName(adiabatic_construction_name).get if adiabatic_construct_exists

      g01_13mm_gypsum_board = OpenStudio::Model::StandardOpaqueMaterial.new(model)
      g01_13mm_gypsum_board.setName('G01 13mm gypsum board')
      g01_13mm_gypsum_board.setRoughness('Smooth')
      g01_13mm_gypsum_board.setThickness(0.0127)
      g01_13mm_gypsum_board.setThermalConductivity(0.1600)
      g01_13mm_gypsum_board.setDensity(800)
      g01_13mm_gypsum_board.setSpecificHeat(1090)
      g01_13mm_gypsum_board.setThermalAbsorptance(0.9)
      g01_13mm_gypsum_board.setSolarAbsorptance(0.7)
      g01_13mm_gypsum_board.setVisibleAbsorptance(0.5)

      wall_adiabatic_construction = OpenStudio::Model::Construction.new(model)
      wall_adiabatic_construction.setName(adiabatic_construction_name)
      wall_layers = OpenStudio::Model::MaterialVector.new
      wall_layers << g01_13mm_gypsum_board
      wall_layers << g01_13mm_gypsum_board
      wall_adiabatic_construction.setLayers(wall_layers)

      return wall_adiabatic_construction
    end

    # @!endgroup Create
  end
end
