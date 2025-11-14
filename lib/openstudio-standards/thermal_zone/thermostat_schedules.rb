module OpenstudioStandards
  # The ThermalZone module provides methods to set thermostats and get information about model thermal zones
  module ThermalZone
    # Adds thermostat schedules to thermal zones based on the standards space type
    # Chooses the thermostat schedule with the most restrictive setpoints (maximum heating, lowest cooling) in the schedule if multiple space types are present
    #
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] OpenStudio ThermalZone objects
    # @return [Boolean] returns true if successful, false if not
    def self.thermal_zones_set_thermostat_schedules(thermal_zones)
      # load and return thermostat mapping data
      thermostat_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/../prototypes/common/data/thermostat_schedule_lookup.json"), symbolize_names: true)

      # std call to access model_add_schedule
      # @todo refactor once schedule data is separate
      std = Standard.build('90.1-2013')

      thermal_zones.each do |thermal_zone|
        # skip plenums
        if OpenstudioStandards::ThermalZone.thermal_zone_plenum?(thermal_zone)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "Thermal Zone '#{thermal_zone.name}' is a plenum. Not adding thermostat schedules.")
          next
        end

        # get space types
        thermal_zone_space_types = []
        thermal_zone.spaces.each do |space|
          if space.spaceType.is_initialized
            thermal_zone_space_types << space.spaceType.get
          end
        end

        # check if additional properties set, and if not add it
        has_space_type = thermal_zone_space_types[0].additionalProperties.hasFeature('standards_space_type')
        unless has_space_type
          OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(thermal_zone.model)
        end

        # add thermostat schedules for space type
        zone_thermostats_options = []
        thermal_zone_space_types.each do |space_type|
          heating_thermostat_sch_name = nil
          cooling_thermostat_sch_name = nil

          # get the standards space type
          space_type_name = space_type.additionalProperties.getFeatureAsString('standards_space_type').get

          # get the thermostat data associated with this space type
          space_type_data = thermostat_data.select { |h| h[:space_type] == space_type_name }

          # get unique possible heating and cooling setpoint schedules
          heating_thermostat_schs = space_type_data.map { |h| h[:heating_setpoint_schedule] }.compact.uniq
          cooling_thermostat_schs = space_type_data.map { |h| h[:cooling_setpoint_schedule] }.compact.uniq

          # check if there is a unique heating and cooling thermostat schedule for this space type
          if (heating_thermostat_schs.size < 2) && (cooling_thermostat_schs.size < 2)
            # if so, use it
            heating_thermostat_sch_name = heating_thermostat_schs[0]
            cooling_thermostat_sch_name = cooling_thermostat_schs[0]
          else
            # if not, get the heating and cooling thermostat schedule by standards building type
            if space_type.standardsBuildingType.is_initialized
              # select down to building type
              space_type_data = space_type_data.select { |h| h[:standards_building_type] == space_type.standardsBuildingType.get }
              if space_type_data.empty?
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "No thermostat schedule data is available for space type '#{space_type.name} with standards space type #{space_type_name} and standards building type #{space_type.standardsBuildingType.get}. Unable to create thermostat schedules.")
                next
              else
                heating_thermostat_sch_name = space_type_data[0][:heating_setpoint_schedule]
                cooling_thermostat_sch_name = space_type_data[0][:cooling_setpoint_schedule]
              end
            else
              # unable to find standards building type
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "Multiple thermostat schedules are available for space type '#{space_type.name} with standards space type #{space_type_name} depending on building type, but building type is not specified. Using a default schedule for this space type.")
              space_type_data = thermostat_data.find { |h| h[:space_type] == space_type_name }
              heating_thermostat_sch_name = space_type_data[:heating_setpoint_schedule]
              cooling_thermostat_sch_name = space_type_data[:cooling_setpoint_schedule]
            end
          end

          # make thermostat
          thermostat = space_type.model.getThermostatSetpointDualSetpointByName("#{space_type.name} Thermostat")
          if thermostat.is_initialized
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "#{space_type.name} thermostat already in model.")
            thermostat = thermostat.get
          else
            thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(space_type.model)
            thermostat.setName("#{space_type.name} Thermostat")

            unless heating_thermostat_sch_name.nil?
              thermostat.setHeatingSetpointTemperatureSchedule(std.model_add_schedule(space_type.model, heating_thermostat_sch_name))
              OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "#{space_type.name} set heating setpoint schedule to #{heating_thermostat_sch_name}.")
            end

            unless cooling_thermostat_sch_name.nil?
              thermostat.setCoolingSetpointTemperatureSchedule(std.model_add_schedule(space_type.model, cooling_thermostat_sch_name))
              OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "#{space_type.name} set cooling setpoint schedule to #{cooling_thermostat_sch_name}.")
            end
          end

          # log the schedules
          zone_thermostats_options << thermostat
        end

        # If only one thermostat, use it
        if zone_thermostats_options.size == 1
          thermal_zone.setThermostatSetpointDualSetpoint(zone_thermostats_options[0])
        elsif zone_thermostats_options.size > 1
          # otherwise find the zone thermostat with the most restrictive setpoints
          # @todo logic here to pick between options
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "Multiple thermostat options for thermal zone #{zone.name} depending on space types.")
          thermal_zone.setThermostatSetpointDualSetpoint(zone_thermostats_options[0])
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "Unable to find valid thermostat options for thermal zone #{zone.name} depending on space types.")
        end
      end

      return true
    end

    # Adds thermostat schedules with a 0F heating setpoint and 120F cooling setpoint.
    # These numbers are outside of the threshold that is considered heated or cooled by thermal_zone_heated? and thermal_zone_cooled?
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if successful, false if not
    def self.thermal_zone_set_unconditioned_thermostat(thermal_zone)
      # Heated to 0F (below thermal_zone_heated?(thermal_zone)  threshold)
      htg_t_f = 0.0
      htg_t_c = OpenStudio.convert(htg_t_f, 'F', 'C').get
      htg_stpt_sch = OpenStudio::Model::ScheduleRuleset.new(thermal_zone.model)
      htg_stpt_sch.setName('Unconditioned Minimal Heating')
      htg_stpt_sch.defaultDaySchedule.setName('Unconditioned Minimal Heating Default')
      htg_stpt_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), htg_t_c)

      # Cooled to 120F (above thermal_zone_cooled?(thermal_zone)  threshold)
      clg_t_f = 120.0
      clg_t_c = OpenStudio.convert(clg_t_f, 'F', 'C').get
      clg_stpt_sch = OpenStudio::Model::ScheduleRuleset.new(thermal_zone.model)
      clg_stpt_sch.setName('Unconditioned Minimal Cooling')
      clg_stpt_sch.defaultDaySchedule.setName('Unconditioned Minimal Cooling Default')
      clg_stpt_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_t_c)

      # Thermostat
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(thermal_zone.model)
      thermostat.setName("#{thermal_zone.name} Unconditioned Thermostat")
      thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
      thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
      thermal_zone.setThermostatSetpointDualSetpoint(thermostat)

      return true
    end
  end
end
