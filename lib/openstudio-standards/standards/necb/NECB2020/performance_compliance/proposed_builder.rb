# frozen_string_literal: true

module OpenstudioStandards
  module NECB2020
    # Proposed building processor for NECB 2020 Section 8.4.3
    #
    # Extracts and documents characteristics of the proposed building per Section 8.4.3.
    # The proposed building is NOT modified - this class only reads and logs its properties
    # for comparison with the reference building.
    #
    # @example Basic usage
    #   logger = ComplianceLogger.new
    #   builder = ProposedBuilder.new(proposed_model, logger)
    #   builder.document_all_characteristics
    #
    class ProposedBuilder
      attr_reader :model, :logger

      # Initialize proposed building processor
      #
      # @param model [OpenStudio::Model::Model] The proposed building model
      # @param logger [ComplianceLogger] Logger for tracking documentation
      def initialize(model, logger)
        @model = model
        @logger = logger
      end

      # Document all proposed building characteristics per Section 8.4.3
      #
      # @return [Hash] Summary of documented characteristics
      def document_all_characteristics
        results = {}

        results[:envelope] = document_envelope_properties
        results[:lighting] = document_lighting_properties
        results[:schedules] = document_operating_schedules
        results[:internal_loads] = document_internal_loads
        results[:hvac] = document_hvac_configuration
        results[:service_water_heating] = document_swh_properties

        results
      end

      # Document building envelope properties per Article 8.4.3.3
      #
      # @return [Hash] Envelope characteristics
      def document_envelope_properties
        envelope_data = {
          walls: [],
          roofs: [],
          windows: [],
          doors: [],
          air_leakage: nil
        }

        # Article 8.4.3.3.(1) - Solar absorptance
        model.getSurfaces.each do |surface|
          next unless surface.outsideBoundaryCondition == 'Outdoors'

          construction = surface.construction
          if construction.is_initialized
            const = construction.get
            absorptance = get_solar_absorptance(const)

            surface_data = {
              name: surface.nameString,
              type: surface.surfaceType,
              area_m2: surface.grossArea,
              construction: const.nameString,
              solar_absorptance: absorptance || 0.7, # Default per 8.4.3.3.(1)
              azimuth_deg: surface.azimuth * 180 / Math::PI
            }

            case surface.surfaceType
            when 'Wall'
              surface_data[:u_factor] = get_u_factor(const)
              envelope_data[:walls] << surface_data
            when 'RoofCeiling'
              surface_data[:u_factor] = get_u_factor(const)
              envelope_data[:roofs] << surface_data
            end
          end
        end

        # Windows - Article 8.4.3.3.(2) - SHGC
        model.getSubSurfaces.each do |subsurface|
          next unless subsurface.outsideBoundaryCondition == 'Outdoors'
          next unless subsurface.subSurfaceType.include?('Window')

          construction = subsurface.construction
          if construction.is_initialized
            const = construction.get
            shgc = get_shgc(const)

            window_data = {
              name: subsurface.nameString,
              area_m2: subsurface.grossArea,
              construction: const.nameString,
              u_factor: get_u_factor(const),
              shgc: shgc,
              shgc_adjusted: shgc.nil? ? nil : (shgc * 0.8).round(3) # Per 8.4.3.3.(2)
            }

            envelope_data[:windows] << window_data
          end
        end

        # Article 8.4.3.3.(3) - Air leakage
        envelope_data[:air_leakage] = document_air_leakage

        # Log envelope documentation
        logger.log_article(
          article: '8.4.3.3',
          action: 'Documented proposed building envelope',
          details: {
            num_walls: envelope_data[:walls].length,
            num_roofs: envelope_data[:roofs].length,
            num_windows: envelope_data[:windows].length,
            total_wall_area: envelope_data[:walls].sum { |w| w[:area_m2] }.round(1),
            total_window_area: envelope_data[:windows].sum { |w| w[:area_m2] }.round(1)
          }
        )

        envelope_data
      end

      # Document air leakage per Article 8.4.3.3.(3)
      #
      # @return [Hash] Air leakage characteristics
      def document_air_leakage
        # Get infiltration from spaces
        total_infiltration_m3_per_s = 0.0
        above_ground_wall_area = 0.0

        model.getSpaces.each do |space|
          space.spaceInfiltrationDesignFlowRates.each do |infiltration|
            flow_rate = infiltration.designFlowRate
            total_infiltration_m3_per_s += flow_rate.get if flow_rate.is_initialized
          end

          # Calculate above-ground wall area
          space.surfaces.each do |surface|
            if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
              above_ground_wall_area += surface.grossArea
            end
          end
        end

        # Calculate I75Pa (normalized by above-ground wall area)
        i_75pa = above_ground_wall_area > 0 ? (total_infiltration_m3_per_s / above_ground_wall_area) : 0.0

        # Calculate adjusted I_AGW per Article 8.4.2.9
        c_factor = (5.0 / 75.0)**0.65
        total_surface_area = calculate_total_surface_area
        i_agw = c_factor * i_75pa * above_ground_wall_area / total_surface_area

        {
          i_75pa: i_75pa.round(6),
          above_ground_wall_area_m2: above_ground_wall_area.round(1),
          total_surface_area_m2: total_surface_area.round(1),
          i_agw: i_agw.round(6),
          units: 'L/(s·m²)'
        }
      end

      # Document interior lighting per Article 8.4.3.4
      #
      # @return [Hash] Lighting characteristics
      def document_lighting_properties
        lighting_data = {
          by_space_type: [],
          total_power_w: 0.0,
          total_floor_area_m2: 0.0
        }

        model.getSpaceTypes.each do |space_type|
          next if space_type.spaces.empty?

          total_lighting_power = 0.0
          total_area = 0.0
          has_occupancy_controls = false
          has_daylight_controls = false

          space_type.spaces.each do |space|
            total_area += space.floorArea

            space.lights.each do |light|
              power = light.getLightingPower(space.floorArea, space.numberOfPeople)
              total_lighting_power += power
            end

            # Check for controls
            has_occupancy_controls ||= space.spaceType.is_initialized &&
                                        check_occupancy_controls(space)
            has_daylight_controls ||= !space.daylightingControls.empty?
          end

          lpd = total_area > 0 ? (total_lighting_power / total_area) : 0.0

          space_type_data = {
            name: space_type.nameString,
            floor_area_m2: total_area.round(1),
            lighting_power_w: total_lighting_power.round(1),
            lpd_w_per_m2: lpd.round(2),
            occupancy_controls: has_occupancy_controls,
            daylight_controls: has_daylight_controls
          }

          lighting_data[:by_space_type] << space_type_data
          lighting_data[:total_power_w] += total_lighting_power
          lighting_data[:total_floor_area_m2] += total_area
        end

        lighting_data[:overall_lpd] = lighting_data[:total_floor_area_m2] > 0 ?
                                        (lighting_data[:total_power_w] / lighting_data[:total_floor_area_m2]).round(2) : 0.0

        # Log lighting documentation
        logger.log_article(
          article: '8.4.3.4',
          action: 'Documented proposed building lighting',
          details: {
            overall_lpd: lighting_data[:overall_lpd],
            total_power_w: lighting_data[:total_power_w].round(1),
            num_space_types: lighting_data[:by_space_type].length
          }
        )

        lighting_data
      end

      # Document operating schedules per Article 8.4.3.2.(1)
      #
      # @return [Hash] Schedule information
      def document_operating_schedules
        schedules = {
          thermostats: [],
          occupancy: [],
          lighting: [],
          equipment: []
        }

        model.getThermalZones.each do |zone|
          if zone.thermostatSetpointDualSetpoint.is_initialized
            thermostat = zone.thermostatSetpointDualSetpoint.get

            schedules[:thermostats] << {
              zone: zone.nameString,
              heating_schedule: thermostat.heatingSetpointTemperatureSchedule.is_initialized ?
                                thermostat.heatingSetpointTemperatureSchedule.get.nameString : nil,
              cooling_schedule: thermostat.coolingSetpointTemperatureSchedule.is_initialized ?
                                thermostat.coolingSetpointTemperatureSchedule.get.nameString : nil
            }
          end
        end

        # Log schedules
        logger.log_article(
          article: '8.4.3.2.(1)',
          action: 'Documented proposed building schedules',
          details: {
            num_thermostat_schedules: schedules[:thermostats].length
          }
        )

        schedules
      end

      # Document internal loads per Article 8.4.3.2.(2)
      #
      # @return [Hash] Internal load information
      def document_internal_loads
        loads = {
          people: [],
          equipment: [],
          total_people: 0,
          total_equipment_w: 0.0
        }

        model.getSpaces.each do |space|
          space.people.each do |people|
            num_people = people.getNumberOfPeople(space.floorArea)
            loads[:people] << {
              space: space.nameString,
              number_of_people: num_people.round(1)
            }
            loads[:total_people] += num_people
          end

          space.electricEquipment.each do |equipment|
            power = equipment.getDesignLevel(space.floorArea, space.numberOfPeople)
            loads[:equipment] << {
              space: space.nameString,
              power_w: power.round(1)
            }
            loads[:total_equipment_w] += power
          end
        end

        # Log internal loads
        logger.log_article(
          article: '8.4.3.2.(2)',
          action: 'Documented proposed building internal loads',
          details: {
            total_people: loads[:total_people].round(0),
            total_equipment_w: loads[:total_equipment_w].round(1)
          }
        )

        loads
      end

      # Document HVAC system configuration
      #
      # @return [Hash] HVAC system information
      def document_hvac_configuration
        hvac_data = {
          air_loops: [],
          plant_loops: [],
          zone_equipment: []
        }

        model.getAirLoopHVACs.each do |air_loop|
          hvac_data[:air_loops] << {
            name: air_loop.nameString,
            design_supply_air_flow_rate_m3_per_s: air_loop.designSupplyAirFlowRate.is_initialized ?
                                                   air_loop.designSupplyAirFlowRate.get : nil
          }
        end

        model.getPlantLoops.each do |plant_loop|
          hvac_data[:plant_loops] << {
            name: plant_loop.nameString,
            fluid_type: plant_loop.fluidType
          }
        end

        # Log HVAC configuration
        logger.log_article(
          article: '8.4.3.1',
          action: 'Documented proposed building HVAC',
          details: {
            num_air_loops: hvac_data[:air_loops].length,
            num_plant_loops: hvac_data[:plant_loops].length
          }
        )

        hvac_data
      end

      # Document service water heating properties
      #
      # @return [Hash] SWH information
      def document_swh_properties
        swh_data = {
          water_heaters: []
        }

        model.getWaterHeaterMixeds.each do |wh|
          swh_data[:water_heaters] << {
            name: wh.nameString,
            capacity_w: wh.heaterMaximumCapacity.is_initialized ? wh.heaterMaximumCapacity.get : nil,
            volume_m3: wh.tankVolume.is_initialized ? wh.tankVolume.get : nil
          }
        end

        # Log SWH
        logger.log_article(
          article: '8.4.3.6',
          action: 'Documented proposed building service water heating',
          details: {
            num_water_heaters: swh_data[:water_heaters].length
          }
        )

        swh_data
      end

      private

      # Get solar absorptance from construction
      def get_solar_absorptance(construction)
        # Try to get from exterior layer
        if construction.respond_to?(:layers) && !construction.layers.empty?
          exterior_layer = construction.layers.first
          if exterior_layer.respond_to?(:solarAbsorptance)
            return exterior_layer.solarAbsorptance
          end
        end
        nil
      end

      # Get U-factor from construction
      def get_u_factor(construction)
        if construction.respond_to?(:uFactor)
          u_factor_optional = construction.uFactor
          return u_factor_optional.get if u_factor_optional.is_initialized
        end
        nil
      end

      # Get SHGC from window construction
      def get_shgc(construction)
        if construction.respond_to?(:to_FenestrationMaterial_Glazing)
          glazing = construction.to_FenestrationMaterial_Glazing
          if glazing.is_initialized
            return glazing.get.solarTransmittance if glazing.get.respond_to?(:solarTransmittance)
          end
        end
        nil
      end

      # Calculate total building surface area (for air leakage calculation)
      def calculate_total_surface_area
        total_area = 0.0

        model.getSurfaces.each do |surface|
          if surface.outsideBoundaryCondition == 'Outdoors' || surface.outsideBoundaryCondition == 'Ground'
            total_area += surface.grossArea
          end
        end

        total_area
      end

      # Check if space has occupancy controls
      def check_occupancy_controls(space)
        # Simplified check - look for "Occ" in schedule names
        space.lights.each do |light|
          if light.schedule.is_initialized
            schedule = light.schedule.get
            return true if schedule.nameString.downcase.include?('occ')
          end
        end
        false
      end
    end
  end
end
