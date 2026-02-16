module OpenstudioStandards
  # The Equipment module provides methods to create, modify, and get information about equipment
  module Equipment
    # @!group Create Typical Equipment
    # Methods to create typical equipment

    # Create typical equipment in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Boolean] returns true if successful, false if not
    def self.create_typical_equipment(model)
      # load equipment data
      electric_equipment_space_type_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/electric_equipment_space_types.json"), symbolize_names: true)
      gas_equipment_space_type_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/gas_equipment_space_types.json"), symbolize_names: true)

      if electric_equipment_space_type_data.nil? || gas_equipment_space_type_data.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', 'Unable to load equipment space types data. No equipment will be added to model.')
        return false
      end

      # loop over space types and apply equipment
      model.getSpaceTypes.each do |space_type|
        # remove existing equipment objects
        space_type.electricEquipment.sort.each(&:remove)
        space_type.gasEquipment.sort.each(&:remove)

        # remove existing equipment objects from spaces
        space_type.spaces.each do |space|
          space.electricEquipment.sort.each(&:remove)
          space.gasEquipment.sort.each(&:remove)
        end

        # get building type
        standards_building_type = nil
        if space_type.standardsBuildingType.is_initialized
          standards_building_type = space_type.standardsBuildingType.get
        end

        # get equipment space type from the object
        has_electric_equipment_space_type = space_type.additionalProperties.hasFeature('electric_equipment_space_type')
        has_gas_equipment_space_type = space_type.additionalProperties.hasFeature('natural_gas_equipment_space_type')
        unless has_electric_equipment_space_type || has_gas_equipment_space_type
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Space type '#{space_type.name}' does not have a electric_equipment_space_type or natural_gas_equipment_space_type property assigned. Ignoring space type.")
          next
        end
        if has_electric_equipment_space_type
          electric_equipment_space_type = space_type.additionalProperties.getFeatureAsString('electric_equipment_space_type').to_s
        else
          electric_equipment_space_type = nil
        end
        if has_gas_equipment_space_type
          gas_equipment_space_type = space_type.additionalProperties.getFeatureAsString('natural_gas_equipment_space_type').to_s
        else
          gas_equipment_space_type = nil
        end

        if has_electric_equipment_space_type && !electric_equipment_space_type.nil? && (electric_equipment_space_type != 'na')
          # get equipment properties for the electric equipment space type
          electric_equipment_space_type_properties = electric_equipment_space_type_data.select { |r| (r[:electric_equipment_space_type_name] == electric_equipment_space_type) && (r[:standards_building_type] == standards_building_type) }
          if electric_equipment_space_type_properties.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Unable to find electric equipment space type data for '#{electric_equipment_space_type}' with standards_building_type #{standards_building_type}.")
          else
            electric_equipment_space_type_properties = electric_equipment_space_type_properties[0]
            elec_equip_per_area = electric_equipment_space_type_properties[:electric_equipment_per_area].to_f
            elec_equip_frac_latent = electric_equipment_space_type_properties[:electric_equipment_fraction_latent]
            elec_equip_frac_radiant = electric_equipment_space_type_properties[:electric_equipment_fraction_radiant]
            elec_equip_frac_lost = electric_equipment_space_type_properties[:electric_equipment_fraction_lost]
            if elec_equip_per_area > 0
              definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
              definition.setName("#{space_type.name} Elec Equip Definition")
              definition.setWattsperSpaceFloorArea(OpenStudio.convert(elec_equip_per_area.to_f, 'W/ft^2', 'W/m^2').get)
              definition.resetFractionLatent unless definition.isFractionLatentDefaulted
              definition.resetFractionRadiant unless definition.isFractionRadiantDefaulted
              definition.resetFractionLost unless definition.isFractionLostDefaulted
              definition.setFractionLatent(elec_equip_frac_latent.to_f) if elec_equip_frac_latent
              definition.setFractionRadiant(elec_equip_frac_radiant.to_f) if elec_equip_frac_radiant
              definition.setFractionLost(elec_equip_frac_lost.to_f) if elec_equip_frac_lost
              instance = OpenStudio::Model::ElectricEquipment.new(definition)
              instance.setName("#{space_type.name} Elec Equip")
              instance.setSpaceType(space_type)
            end
          end
        end

        if has_gas_equipment_space_type && !gas_equipment_space_type.nil? && (gas_equipment_space_type != 'na')
          # get equipment properties for the gas equipment space type
          gas_equipment_space_type_properties = gas_equipment_space_type_data.select { |r| (r[:natural_gas_equipment_space_type_name] == gas_equipment_space_type) && (r[:standards_building_type] == standards_building_type) }
          if gas_equipment_space_type_properties.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Unable to find gas equipment space type data for '#{gas_equipment_space_type}' with standards_building_type #{standards_building_type}.")
          else
            gas_equipment_space_type_properties = gas_equipment_space_type_properties[0]
            gas_equip_per_area = gas_equipment_space_type_properties[:gas_equipment_per_area].to_f
            gas_equip_frac_latent = gas_equipment_space_type_properties[:gas_equipment_fraction_latent]
            gas_equip_frac_radiant = gas_equipment_space_type_properties[:gas_equipment_fraction_radiant]
            gas_equip_frac_lost = gas_equipment_space_type_properties[:gas_equipment_fraction_lost]
            if gas_equip_per_area > 0
              definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
              definition.setName("#{space_type.name} Gas Equip Definition")
              definition.setWattsperSpaceFloorArea(OpenStudio.convert(gas_equip_per_area.to_f, 'Btu/hr*ft^2', 'W/m^2').get)
              definition.resetFractionLatent unless definition.isFractionLatentDefaulted
              definition.resetFractionRadiant unless definition.isFractionRadiantDefaulted
              definition.resetFractionLost unless definition.isFractionLostDefaulted
              definition.setFractionLatent(gas_equip_frac_latent.to_f) if gas_equip_frac_latent
              definition.setFractionRadiant(gas_equip_frac_radiant.to_f) if gas_equip_frac_radiant
              definition.setFractionLost(gas_equip_frac_lost.to_f) if gas_equip_frac_lost
              instance = OpenStudio::Model::GasEquipment.new(definition)
              instance.setName("#{space_type.name} Gas Equip")
              instance.setSpaceType(space_type)
            end
          end
        end
      end

      return true
    end
  end
end
