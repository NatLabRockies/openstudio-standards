module OpenstudioStandards
  # The ServiceWaterHeating module provides methods to create, modify, and get information about service water heating
  module ServiceWaterHeating
    # @!group Create Water Use
    # Methods to add service water uses

    # Creates a water use and attaches it to a service water loop and a space, if provided
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] Use name of the water use object, e.g. main or laundry
    # @param flow_rate [Double] the peak flow rate of the water use in m^3/s
    # @param flow_rate_fraction_schedule [OpenStudio::Model::Schedule] the flow rate fraction schedule
    # @param water_use_temperature [Double] mixed water use temperature at the fixture, in degrees C. Default is 43.3 C / 110 F.
    # @param water_use_temperature_schedule [OpenStudio::Model::Schedule] water use temperature schedule.
    #   If nil, will be defaulted to a constant temperature schedule based on the water_use_temperature
    # @param sensible_fraction [Double] the water use equipment sensible fraction to the space
    # @param latent_fraction [Double] the water use equipment latent fraction to the space
    # @param service_water_loop [OpenStudio::Model::PlantLoop] if provided, add the water use fixture to this loop
    # @param hot_water_supply_temperature_schedule [OpenStudio::Model::Schedule] hot water supply
    #   temperature schedule for the water use connections. When nil and a service_water_loop is
    #   given, the loop's own setpoint schedule is used. When nil and there is no loop, the field
    #   is left blank and EnergyPlus takes the supply temperature from the water inlet node.
    # @param cold_water_supply_temperature_schedule [OpenStudio::Model::Schedule] cold water supply
    #   temperature schedule. Left blank by default, so EnergyPlus uses the site water mains
    #   temperature, which varies seasonally.
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [OpenStudio::Model::WaterUseEquipment] OpenStudio WaterUseEquipment object
    def self.create_water_use(model,
                              name: 'Main Water Use',
                              flow_rate: 0.0,
                              flow_rate_fraction_schedule: nil,
                              water_use_temperature: 43.3,
                              water_use_temperature_schedule: nil,
                              sensible_fraction: 0.2,
                              latent_fraction: 0.05,
                              service_water_loop: nil,
                              hot_water_supply_temperature_schedule: nil,
                              cold_water_supply_temperature_schedule: nil,
                              space: nil)
      # IP conversions for naming
      flow_rate_gpm = OpenStudio.convert(flow_rate, 'm^3/s', 'gal/min').get
      water_use_temperature_f = OpenStudio.convert(water_use_temperature, 'C', 'F').get

      # default name
      name = 'Main Water Use' if name.nil?

      # water use definition
      water_use_def = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)

      # set sensible and latent fractions
      water_use_sensible_frac_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                    sensible_fraction,
                                                                                                    name: "Fraction Sensible - #{sensible_fraction}",
                                                                                                    schedule_type_limit: 'Fractional')
      water_use_latent_frac_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                  latent_fraction,
                                                                                                  name: "Fraction Latent - #{latent_fraction}",
                                                                                                  schedule_type_limit: 'Fractional')
      water_use_def.setSensibleFractionSchedule(water_use_sensible_frac_sch)
      water_use_def.setLatentFractionSchedule(water_use_latent_frac_sch)
      water_use_def.setPeakFlowRate(flow_rate)
      water_use_def.setName("#{name} #{flow_rate_gpm.round(4)}gpm #{water_use_temperature_f.round}F")

      # target mixed water temperature
      if water_use_temperature_schedule.nil?
        water_use_temperature_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                         water_use_temperature,
                                                                                                         name: "Mixed Water At Faucet Temp - #{water_use_temperature_f.round}F",
                                                                                                         schedule_type_limit: 'Temperature')
      end
      water_use_def.setTargetTemperatureSchedule(water_use_temperature_schedule)

      # create water use equipment
      water_fixture = OpenStudio::Model::WaterUseEquipment.new(water_use_def)
      water_fixture.setFlowRateFractionSchedule(flow_rate_fraction_schedule)

      # create water use connection
      swh_connection = OpenStudio::Model::WaterUseConnections.new(model)
      swh_connection.addWaterUseEquipment(water_fixture)

      # add to the space if provided
      if space.nil?
        water_fixture.setName("#{name} Service Water Use #{flow_rate_gpm.round(4)}gpm #{water_use_temperature_f.round}F")
        swh_connection.setName("#{name} WUC #{flow_rate_gpm.round(4)}gpm #{water_use_temperature_f.round}F")
      else
        water_fixture.setName("#{space.name} Service Water Use #{flow_rate_gpm.round(4)}gpm #{water_use_temperature_f.round}F")
        swh_connection.setName("#{space.name} WUC #{flow_rate_gpm.round(4)}gpm #{water_use_temperature_f.round}F")
        water_fixture.setSpace(space)
      end

      # add to the service water loop if provided
      unless service_water_loop.nil?
        service_water_loop.addDemandBranchForComponent(swh_connection)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Adding water fixture to #{service_water_loop.name}.")
      end

      # State the supply temperature the connection draws at.
      #
      # Left blank, EnergyPlus reads it from the water inlet node instead, and compares it with
      # the target temperature every iteration. During warmup the loop has not been heated yet --
      # 31 C against a 82 C target on a hospital booster -- so every draw warns on every
      # iteration. On one hospital that is 64.6 million warnings and roughly 45 of the 89 minutes
      # the model takes to run. Naming the temperature the loop actually holds stops the
      # comparison depending on the instantaneous loop state.
      #
      # The loop's own setpoint schedule is reused rather than a new one built to match it, so
      # this adds no objects to the model.
      hot_water_supply_temperature_schedule ||= OpenstudioStandards::ServiceWaterHeating.service_water_loop_temperature_schedule(service_water_loop)
      swh_connection.setHotWaterSupplyTemperatureSchedule(hot_water_supply_temperature_schedule) unless hot_water_supply_temperature_schedule.nil?
      swh_connection.setColdWaterSupplyTemperatureSchedule(cold_water_supply_temperature_schedule) unless cold_water_supply_temperature_schedule.nil?

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added #{water_fixture.name}.")

      return water_fixture
    end

    # @!endgroup Create Water Use
  end
end
