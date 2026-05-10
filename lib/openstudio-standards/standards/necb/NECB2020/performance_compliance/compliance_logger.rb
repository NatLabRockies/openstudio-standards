# frozen_string_literal: true

module OpenstudioStandards
  module NECB2020
    # Compliance logger for NECB 2020 Section 8.4 Performance Path
    #
    # Tracks all changes made during reference building generation and proposed building
    # documentation with before/after values, code article references, and validation status.
    # Provides structured logging for debugging and compliance reporting.
    #
    # @example Basic usage
    #   logger = ComplianceLogger.new
    #   logger.log_envelope_change(
    #     article: '8.4.4.3.(1)',
    #     component_name: 'South Wall',
    #     component_type: 'ExteriorWall',
    #     proposed_value: 0.5,
    #     reference_value: 0.315,
    #     code_reference: 'NECB 2020 Table 3.2.1.3',
    #     units: 'W/(m²·K)'
    #   )
    #   logs = logger.get_logs_by_section('8.4.4')
    #
    class ComplianceLogger
      attr_reader :logs

      # Initialize a new compliance logger
      def initialize
        @logs = {
          section_8_4_1: [], # Compliance methodology
          section_8_4_2: [], # Calculation methods
          section_8_4_3: [], # Proposed building
          section_8_4_4: []  # Reference building
        }
        @start_time = Time.now
      end

      # Log an envelope component change (walls, roofs, windows, etc.)
      #
      # @param article [String] NECB article number (e.g., '8.4.4.3.(1)')
      # @param component_name [String] Name of component (e.g., 'South Wall')
      # @param component_type [String] Type of component (e.g., 'ExteriorWall', 'Window', 'Roof')
      # @param proposed_value [Numeric] Original value from proposed building
      # @param reference_value [Numeric] New value applied to reference building
      # @param code_reference [String] Code table/article source (e.g., 'NECB 2020 Table 3.2.1.3')
      # @param units [String] Units of measurement (e.g., 'W/(m²·K)', 'L/(s·m²)')
      # @param passed [Boolean] Whether validation passed (default: true)
      # @return [Hash] The logged entry
      def log_envelope_change(article:, component_name:, component_type:,
                               proposed_value:, reference_value:,
                               code_reference:, units:, passed: true)
        entry = create_log_entry(
          article: article,
          action: 'Applied prescriptive requirement',
          component_name: component_name,
          component_type: component_type,
          proposed_value: proposed_value,
          reference_value: reference_value,
          code_reference: code_reference,
          units: units,
          passed: passed
        )

        add_to_section(article, entry)
        entry
      end

      # Log HVAC system selection for a thermal block
      #
      # @param article [String] NECB article number (e.g., '8.4.4.7.(1)')
      # @param thermal_block [String] Name of thermal block/zone
      # @param system_type [Integer] NECB system type (1-7)
      # @param system_name [String] Descriptive system name
      # @param building_type [String] Building/space type classification
      # @param num_stories [Integer] Number of stories
      # @param rationale [String] Why this system was selected
      # @param code_reference [String] Code table reference
      # @param passed [Boolean] Whether validation passed
      # @return [Hash] The logged entry
      def log_hvac_system_selection(article:, thermal_block:, system_type:,
                                     system_name:, building_type:, num_stories:,
                                     rationale:, code_reference:, passed: true)
        entry = {
          section: extract_section(article),
          article: article,
          action: 'Selected HVAC system',
          thermal_block: thermal_block,
          system_type: system_type,
          system_name: system_name,
          building_type: building_type,
          num_stories: num_stories,
          rationale: rationale,
          code_reference: code_reference,
          timestamp: Time.now,
          passed: passed
        }

        add_to_section(article, entry)
        entry
      end

      # Log equipment efficiency change
      #
      # @param article [String] NECB article number
      # @param equipment_name [String] Name of equipment
      # @param equipment_type [String] Type (e.g., 'Boiler', 'Chiller', 'Fan')
      # @param proposed_efficiency [Numeric] Proposed efficiency value
      # @param reference_efficiency [Numeric] Reference (prescriptive) efficiency
      # @param efficiency_metric [String] Metric name (e.g., 'COP', 'Thermal Efficiency', 'kW/ton')
      # @param code_reference [String] Code table reference
      # @param passed [Boolean] Whether validation passed
      # @return [Hash] The logged entry
      def log_equipment_efficiency(article:, equipment_name:, equipment_type:,
                                   proposed_efficiency:, reference_efficiency:,
                                   efficiency_metric:, code_reference:, passed: true)
        entry = create_log_entry(
          article: article,
          action: 'Applied prescriptive efficiency',
          component_name: equipment_name,
          component_type: equipment_type,
          proposed_value: proposed_efficiency,
          reference_value: reference_efficiency,
          code_reference: code_reference,
          units: efficiency_metric,
          passed: passed
        )

        add_to_section(article, entry)
        entry
      end

      # Log when no change is required (proposed already meets prescriptive)
      #
      # @param article [String] NECB article number
      # @param component_name [String] Name of component
      # @param component_type [String] Type of component
      # @param reason [String] Why no change was needed
      # @param value [Numeric] The value (same for proposed and reference)
      # @param units [String] Units of measurement
      # @return [Hash] The logged entry
      def log_no_change_required(article:, component_name:, component_type: nil,
                                  reason:, value: nil, units: nil)
        entry = {
          section: extract_section(article),
          article: article,
          action: 'No change required',
          component_name: component_name,
          component_type: component_type,
          reason: reason,
          value: value,
          units: units,
          timestamp: Time.now,
          passed: true
        }

        add_to_section(article, entry)
        entry
      end

      # Log general article application (for characteristics that don't change values)
      #
      # @param article [String] NECB article number
      # @param action [String] Description of action taken
      # @param details [Hash] Additional details
      # @param passed [Boolean] Whether validation passed
      # @return [Hash] The logged entry
      def log_article(article:, action:, details: {}, passed: true)
        entry = {
          section: extract_section(article),
          article: article,
          action: action,
          details: details,
          timestamp: Time.now,
          passed: passed
        }

        add_to_section(article, entry)
        entry
      end

      # Log compliance validation result
      #
      # @param article [String] NECB article number
      # @param test_name [String] Name of compliance test
      # @param proposed_value [Numeric] Value from proposed building
      # @param reference_value [Numeric] Value from reference building (or limit)
      # @param passed [Boolean] Whether test passed
      # @param message [String] Detailed message
      # @return [Hash] The logged entry
      def log_compliance_test(article:, test_name:, proposed_value:,
                              reference_value:, passed:, message:)
        entry = {
          section: extract_section(article),
          article: article,
          action: 'Compliance validation',
          test_name: test_name,
          proposed_value: proposed_value,
          reference_value: reference_value,
          passed: passed,
          message: message,
          timestamp: Time.now
        }

        add_to_section(article, entry)
        entry
      end

      # Get all logs for a specific section
      #
      # @param section_number [String] Section number (e.g., '8.4.3', '8.4.4')
      # @return [Array<Hash>] Array of log entries
      def get_logs_by_section(section_number)
        section_key = "section_#{section_number.gsub('.', '_')}".to_sym
        @logs[section_key] || []
      end

      # Get all logs for a specific article
      #
      # @param article_number [String] Article number (e.g., '8.4.4.3.(1)')
      # @return [Array<Hash>] Array of log entries
      def get_logs_by_article(article_number)
        section = extract_section(article_number)
        get_logs_by_section(section).select { |entry| entry[:article] == article_number }
      end

      # Get summary statistics
      #
      # @return [Hash] Summary with counts by section, pass/fail status
      def get_summary
        {
          total_entries: total_entries,
          by_section: {
            '8.4.1': @logs[:section_8_4_1].length,
            '8.4.2': @logs[:section_8_4_2].length,
            '8.4.3': @logs[:section_8_4_3].length,
            '8.4.4': @logs[:section_8_4_4].length
          },
          passed: total_passed,
          failed: total_failed,
          elapsed_time: Time.now - @start_time
        }
      end

      # Check if all logged items passed validation
      #
      # @return [Boolean] true if all passed
      def all_passed?
        total_failed == 0
      end

      private

      # Create a standard log entry with value change tracking
      def create_log_entry(article:, action:, component_name:, component_type:,
                           proposed_value:, reference_value:, code_reference:,
                           units:, passed:)
        change_magnitude = calculate_change(proposed_value, reference_value)
        change_percent = calculate_percent_change(proposed_value, reference_value)

        {
          section: extract_section(article),
          article: article,
          action: action,
          component_name: component_name,
          component_type: component_type,
          proposed_value: proposed_value,
          reference_value: reference_value,
          change_magnitude: change_magnitude,
          change_percent: change_percent,
          code_reference: code_reference,
          units: units,
          timestamp: Time.now,
          passed: passed
        }
      end

      # Extract section number from article (e.g., '8.4.4.3.(1)' -> '8.4.4')
      def extract_section(article)
        parts = article.split('.')
        parts[0..2].join('.')
      end

      # Add entry to appropriate section
      def add_to_section(article, entry)
        section = extract_section(article)
        section_key = "section_#{section.gsub('.', '_')}".to_sym
        @logs[section_key] ||= []
        @logs[section_key] << entry
      end

      # Calculate absolute change
      def calculate_change(before, after)
        return nil if before.nil? || after.nil?
        after - before
      end

      # Calculate percent change
      def calculate_percent_change(before, after)
        return nil if before.nil? || after.nil? || before == 0
        ((after - before) / before.to_f * 100).round(1)
      end

      # Count total entries
      def total_entries
        @logs.values.map(&:length).sum
      end

      # Count passed entries
      def total_passed
        @logs.values.flatten.count { |entry| entry[:passed] == true }
      end

      # Count failed entries
      def total_failed
        @logs.values.flatten.count { |entry| entry[:passed] == false }
      end
    end
  end
end
