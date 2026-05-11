module OpenstudioStandards
  # The ServiceWaterHeating module provides methods to create, modify, and get information about service water heating
  module ServiceWaterHeating
    # @!group Create Piping Losses
    # Methods to add service water heating piping losses

    # Adds piping losses to a service water heating Loop.
    # Assumes the piping system use insulated 0.75 inch copper piping.
    # For circulating systems, assume length of piping is proportional to the building floor area and number of stories.
    # For non-circulating systems, assume that the water heaters are close to the point of use.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param service_water_loop [OpenStudio::Model::PlantLoop] the service water heating loop
    # @param circulating [Boolean] use true for circulating systems, false for non-circulating systems
    # @param pipe_insulation_thickness [Double] the thickness of the pipe insulation, in m. Use 0 for no insulation
    # @param floor_area [Double] the area of building served by the service water heating loop, in m^2
    #   If nil, will use the total building floor area. Only used if circulating is true.
    # @param number_of_stories [Integer] the number of stories served by the service water heating loop
    #   If nil, will use the total building number of stories. Only used if circulating is true.
    # @param pipe_length [Double] the length of the pipe in meters. Default is 6.1 m / 20 ft.
    #   Only used if circulating is false.
    # @param air_temperature [Double] the temperature of the air surrounding the piping, in C. Default is 21.1 C / 70 F.
    # @return [Boolean] returns true if successful, false if not
    def self.create_service_water_heating_piping_losses(model,
                                                        service_water_loop,
                                                        circulating: true,
                                                        pipe_insulation_thickness: 0.0,
                                                        floor_area: nil,
                                                        number_of_stories: nil,
                                                        pipe_length: 6.1,
                                                        air_temperature: 21.1)

      # Estimate pipe length
      if circulating
        # For circulating systems, get pipe length based on the size of the building.
        # Formula from A.3.1 PrototypeModelEnhancements_2014_0.pdf

        # get the floor area
        floor_area = model.getBuilding.floorArea if floor_area.nil?
        floor_area_ft2 = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get

        # get the number of stories
        number_of_stories = model.getBuilding.buildingStories.size if number_of_stories.nil?

        # calculate the piping length
        pipe_length_ft = 2.0 * (Math.sqrt(floor_area_ft2 / number_of_stories) + (10.0 * (number_of_stories - 1.0)))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Pipe length #{pipe_length_ft.round}ft = 2.0 * ( (#{floor_area_ft2.round}ft2 / #{number_of_stories} stories)^0.5 + (10.0ft * (#{number_of_stories} stories - 1.0) ) )")
      else
        # For non-circulating systems, assume water heater is close to point of use

        # get pipe length
        pipe_length_m = pipe_length.nil? ? 6.1 : pipe_length

        pipe_length_ft = OpenStudio.convert(pipe_length_m, 'm', 'ft').get
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Pipe length #{pipe_length_ft.round}ft. For non-circulating systems, assume water heater is close to point of use.")
      end

      # For systems whose water heater object represents multiple pieces
      # of equipment, multiply the piping length by the number of pieces of equipment.
      service_water_loop.supplyComponents('OS_WaterHeater_Mixed'.to_IddObjectType).each do |sc|
        next unless sc.to_WaterHeaterMixed.is_initialized

        water_heater = sc.to_WaterHeaterMixed.get

        # get number of water heaters
        if water_heater.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
          comp_qty = water_heater.additionalProperties.getFeatureAsInteger('component_quantity').get
        else
          comp_qty = 1
        end

        # if more than 1 water heater, multiply the pipe length by the number of water heaters,
        # unless the user has specified a pipe length
        if comp_qty > 1 && pipe_length.nil?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Piping length has been multiplied by #{comp_qty}X because #{water_heater.name} represents #{comp_qty} pieces of equipment.")
          pipe_length_ft *= comp_qty
          break
        end
      end

      # Service water heating piping heat loss scheduled air temperature
      air_temperature_f = OpenStudio.convert(air_temperature, 'C', 'F').get
      swh_piping_air_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                air_temperature,
                                                                                                name: "#{service_water_loop.name} Piping Air Temp - #{air_temperature_f.round}F",
                                                                                                schedule_type_limit: 'Temperature')

      # Service water heating piping heat loss scheduled air velocity
      swh_piping_air_velocity_m_per_s = 0.3
      swh_piping_air_velocity_mph = OpenStudio.convert(swh_piping_air_velocity_m_per_s, 'm/s', 'mile/hr').get
      swh_piping_air_velocity_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                    swh_piping_air_velocity_m_per_s,
                                                                                                    name: "#{service_water_loop.name} Piping Air Velocity - #{swh_piping_air_velocity_mph.round(2)}mph")

      # Material for 3/4in type L (heavy duty) copper pipe
      copper_pipe = OpenStudio::Model::StandardOpaqueMaterial.new(model)
      copper_pipe.setName('Copper pipe 0.75in type L')
      copper_pipe.setRoughness('Smooth')
      copper_pipe.setThickness(OpenStudio.convert(0.045, 'in', 'm').get)
      copper_pipe.setThermalConductivity(386.0)
      copper_pipe.setDensity(OpenStudio.convert(556, 'lb/ft^3', 'kg/m^3').get)
      copper_pipe.setSpecificHeat(OpenStudio.convert(0.092, 'Btu/lb*R', 'J/kg*K').get)
      copper_pipe.setThermalAbsorptance(0.9) # @todo find reference for property
      copper_pipe.setSolarAbsorptance(0.7) # @todo find reference for property
      copper_pipe.setVisibleAbsorptance(0.7) # @todo find reference for property

      # Construction for pipe
      pipe_construction = OpenStudio::Model::Construction.new(model)

      # Add insulation material to insulated pipe
      if pipe_insulation_thickness > 0
        # Material for fiberglass insulation
        # R-value from Owens-Corning 1/2in fiberglass pipe insulation
        # https://www.grainger.com/product/OWENS-CORNING-1-2-Thick-40PP22
        # but modified until simulated heat loss = 17.7 Btu/hr/ft of pipe with 140F water and 70F air
        pipe_insulation_thickness_in = OpenStudio.convert(pipe_insulation_thickness, 'm', 'in').get
        insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model)
        insulation.setName("Fiberglass batt #{pipe_insulation_thickness_in.round(2)}in")
        insulation.setRoughness('Smooth')
        insulation.setThickness(OpenStudio.convert(pipe_insulation_thickness_in, 'in', 'm').get)
        insulation.setThermalConductivity(OpenStudio.convert(0.46, 'Btu*in/hr*ft^2*R', 'W/m*K').get)
        insulation.setDensity(OpenStudio.convert(0.7, 'lb/ft^3', 'kg/m^3').get)
        insulation.setSpecificHeat(OpenStudio.convert(0.2, 'Btu/lb*R', 'J/kg*K').get)
        insulation.setThermalAbsorptance(0.9) # Irrelevant for Pipe:Indoor; no radiation model is used
        insulation.setSolarAbsorptance(0.7) # Irrelevant for Pipe:Indoor; no radiation model is used
        insulation.setVisibleAbsorptance(0.7) # Irrelevant for Pipe:Indoor; no radiation model is used

        pipe_construction.setName("Copper pipe 0.75in type L with #{pipe_insulation_thickness_in.round(2)}in fiberglass batt")
        pipe_construction.setLayers([insulation, copper_pipe])
      else
        pipe_construction.setName('Uninsulated copper pipe 0.75in type L')
        pipe_construction.setLayers([copper_pipe])
      end

      heat_loss_pipe = OpenStudio::Model::PipeIndoor.new(model)
      heat_loss_pipe.setName("#{service_water_loop.name} Pipe #{pipe_length_ft.round}ft")
      heat_loss_pipe.setEnvironmentType('Schedule')
      heat_loss_pipe.setAmbientTemperatureSchedule(swh_piping_air_temp_sch)
      heat_loss_pipe.setAmbientAirVelocitySchedule(swh_piping_air_velocity_sch)
      heat_loss_pipe.setConstruction(pipe_construction)
      heat_loss_pipe.setPipeInsideDiameter(OpenStudio.convert(0.785, 'in', 'm').get)
      heat_loss_pipe.setPipeLength(OpenStudio.convert(pipe_length_ft, 'ft', 'm').get)

      heat_loss_pipe.addToNode(service_water_loop.demandInletNode)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added #{pipe_length_ft.round}ft of #{pipe_construction.name} losing heat to #{air_temperature_f.round}F air to #{service_water_loop.name}.")
      return true
    end

    # @!endgroup Create Piping Losses
  end
end
