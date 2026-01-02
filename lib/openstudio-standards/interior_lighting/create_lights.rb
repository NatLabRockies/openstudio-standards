module OpenstudioStandards
  # The InteriorLighting module provides methods to create, modify, and get information about interior lighting
  module InteriorLighting
    # @!group Create Lights
    # Methods to create lights objects

    # Adds a lights object to a space or space type.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] the name of the lights object
    # @param lighting_power [Double] lighting power in watts per unit area or per person
    # @param lighting_power_type [Double] type of lighting power ('Watts/Area', 'Watts/Person'). 'Watts/Area' is W/m^2.
    # @param return_air_fraction [Double] return air fraction
    # @param radiant_fraction [Double] radiant fraction
    # @param visible_fraction [Double] visible fraction
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio space type object
    # @param space [OpenStudio::Model::Space] OpenStudio space object
    # @return [OpenStudio::Model::Lights] The created lights object
    def self.create_lights(model,
                           name: nil,
                           lighting_power: 5.0,
                           lighting_power_type: 'Watts/Area',
                           return_air_fraction: 0.0,
                           radiant_fraction: 0.365,
                           visible_fraction: 0.2,
                           space_type: nil,
                           space: nil)
      # create lights definition object
      lights_def = OpenStudio::Model::LightsDefinition.new(model)
      lights_def.setName("#{name} Definition") unless name.nil?
      lights_def.setWattsperSpaceFloorArea(lighting_power) if lighting_power_type == 'Watts/Area'
      lights_def.setWattsperPerson(lighting_power) if lighting_power_type == 'Watts/Person'
      lights_def.setReturnAirFraction(return_air_fraction)
      lights_def.setFractionRadiant(radiant_fraction)
      lights_def.setFractionVisible(visible_fraction)

      # create lights object
      lights = OpenStudio::Model::Lights.new(lights_def)
      lights.setName(name) unless name.nil?
      if !space_type.nil? && space.nil?
        lights.setSpaceType(space_type)
      elsif !space.nil? && space_type.nil?
        lights.setSpace(space)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.InteriorLighting.create_lights', 'Must pass in either space_type or space.')
        return nil
      end

      return lights
    end
  end
end
