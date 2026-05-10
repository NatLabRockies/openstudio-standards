# frozen_string_literal: true

module OpenstudioStandards
  module NECB2020
    # HVAC system selector for NECB 2020 Table 8.4.4.7-A
    #
    # Implements the system selection logic from Table 8.4.4.7-A to determine
    # which NECB system type (1-7) should be used for each thermal block/space
    # in the reference building.
    #
    # @example Basic usage
    #   selector = ReferenceHVACSelector.new(standard, model, logger)
    #   system_type = selector.select_system_for_space(space)
    #
    class ReferenceHVACSelector
      attr_reader :standard, :model, :logger

      # Initialize HVAC system selector
      #
      # @param standard [Standard] NECB2020 standard instance
      # @param model [OpenStudio::Model::Model] The reference building model
      # @param logger [ComplianceLogger] Logger for tracking system selections
      def initialize(standard, model, logger)
        @standard = standard
        @model = model
        @logger = logger
      end

      # Select HVAC system for a space based on Table 8.4.4.7-A
      #
      # @param space [OpenStudio::Model::Space] The space to evaluate
      # @return [Integer] NECB system type (1-7)
      def select_system_for_space(space)
        # Use existing NECB system selection logic
        system_type = standard.get_necb_spacetype_system_selection(space)

        # Get building characteristics for logging
        building = model.getBuilding
        num_stories = standard.model_get_building_properties(model)['number_of_above_ground_stories']

        # Get space type classification
        space_type_name = space.spaceType.is_initialized ? space.spaceType.get.nameString : 'Unknown'

        # Log the system selection
        logger.log_hvac_system_selection(
          article: '8.4.4.7.(1)',
          thermal_block: space.nameString,
          system_type: system_type,
          system_name: get_system_name(system_type),
          building_type: space_type_name,
          num_stories: num_stories || 1,
          rationale: get_selection_rationale(space_type_name, num_stories, system_type),
          code_reference: 'NECB 2020 Table 8.4.4.7-A'
        )

        system_type
      end

      # Select HVAC system for a thermal zone
      #
      # @param thermal_zone [OpenStudio::Model::ThermalZone] The zone to evaluate
      # @return [Integer] NECB system type (1-7)
      def select_system_for_zone(thermal_zone)
        # Use existing NECB system selection logic
        system_type = standard.get_necb_thermal_zone_system_selection(thermal_zone)

        # Log the system selection
        logger.log_hvac_system_selection(
          article: '8.4.4.7.(1)',
          thermal_block: thermal_zone.nameString,
          system_type: system_type,
          system_name: get_system_name(system_type),
          building_type: 'Mixed' ,
          num_stories: standard.model_get_building_properties(model)['number_of_above_ground_stories'] || 1,
          rationale: "Zone-level system selection",
          code_reference: 'NECB 2020 Table 8.4.4.7-A'
        )

        system_type
      end

      private

      # Get descriptive system name for system type
      def get_system_name(system_type)
        case system_type
        when 1
          'System 1 - PTAC/Room AC'
        when 2
          'System 2 - Split AC/Heat Pump'
        when 3
          'System 3 - Single-Zone Rooftop Unit'
        when 4
          'System 4 - MAU + Local Units'
        when 5
          'System 5 - Refrigeration + MAU'
        when 6
          'System 6 - VAV with Reheat'
        when 7
          'System 7 - VAV with PFP Boxes'
        else
          "System #{system_type}"
        end
      end

      # Get rationale for system selection
      def get_selection_rationale(space_type, num_stories, system_type)
        "#{space_type}, #{num_stories} stories → System #{system_type} per Table 8.4.4.7-A"
      end
    end
  end
end
