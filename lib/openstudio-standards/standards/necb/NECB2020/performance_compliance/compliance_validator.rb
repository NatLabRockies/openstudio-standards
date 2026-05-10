# frozen_string_literal: true

module OpenstudioStandards
  module NECB2020
    # Compliance validator for NECB 2020 Section 8.4.1 and 8.4.2
    #
    # Validates compliance by comparing proposed and reference building simulation results
    # per Articles 8.4.1.2 (compliance criteria) and 8.4.2 (calculation methods).
    #
    # @example Basic usage
    #   validator = ComplianceValidator.new(logger)
    #   result = validator.validate_compliance(proposed_sql, reference_sql)
    #
    class ComplianceValidator
      attr_reader :logger

      # Initialize compliance validator
      #
      # @param logger [ComplianceLogger] Logger for tracking validation results
      def initialize(logger)
        @logger = logger
      end

      # Validate compliance between proposed and reference buildings
      #
      # @param proposed_sql [OpenStudio::SqlFile] Proposed building simulation results
      # @param reference_sql [OpenStudio::SqlFile] Reference building simulation results
      # @return [Hash] Compliance validation results
      def validate_compliance(proposed_sql, reference_sql)
        results = {
          compliant: false,
          annual_energy: nil,
          unmet_heating_hours: nil,
          unmet_cooling_hours: nil
        }

        # Article 8.4.1.2.(2) - Annual energy consumption
        results[:annual_energy] = validate_annual_energy(proposed_sql, reference_sql)

        # Article 8.4.1.2.(3) - Heating unmet hours
        results[:unmet_heating_hours] = validate_heating_unmet_hours(proposed_sql, reference_sql)

        # Article 8.4.1.2.(4) - Cooling unmet hours
        results[:unmet_cooling_hours] = validate_cooling_unmet_hours(proposed_sql, reference_sql)

        # Overall compliance
        results[:compliant] = results[:annual_energy][:passed] &&
                             results[:unmet_heating_hours][:passed] &&
                             results[:unmet_cooling_hours][:passed]

        results
      end

      # Validate annual energy consumption per Article 8.4.1.2.(2)
      #
      # @param proposed_sql [OpenStudio::SqlFile] Proposed building SQL
      # @param reference_sql [OpenStudio::SqlFile] Reference building SQL
      # @return [Hash] Validation result
      def validate_annual_energy(proposed_sql, reference_sql)
        proposed_energy_gj = get_total_site_energy_gj(proposed_sql)
        reference_energy_gj = get_total_site_energy_gj(reference_sql)

        passed = proposed_energy_gj <= reference_energy_gj
        margin_gj = reference_energy_gj - proposed_energy_gj
        margin_percent = ((margin_gj / reference_energy_gj) * 100).round(1)

        message = if passed
                    "PASS: Proposed energy (#{proposed_energy_gj.round(1)} GJ) ≤ Building energy target (#{reference_energy_gj.round(1)} GJ). Margin: #{margin_gj.round(1)} GJ (#{margin_percent}%)"
                  else
                    "FAIL: Proposed energy (#{proposed_energy_gj.round(1)} GJ) > Building energy target (#{reference_energy_gj.round(1)} GJ). Exceeds by: #{(-margin_gj).round(1)} GJ"
                  end

        logger.log_compliance_test(
          article: '8.4.1.2.(2)',
          test_name: 'Annual Energy Consumption',
          proposed_value: proposed_energy_gj.round(1),
          reference_value: reference_energy_gj.round(1),
          passed: passed,
          message: message
        )

        {
          passed: passed,
          proposed_energy_gj: proposed_energy_gj.round(1),
          reference_energy_gj: reference_energy_gj.round(1),
          building_energy_target_gj: reference_energy_gj.round(1),
          margin_gj: margin_gj.round(1),
          margin_percent: margin_percent,
          message: message
        }
      end

      # Validate heating unmet hours per Article 8.4.1.2.(3)
      #
      # @param proposed_sql [OpenStudio::SqlFile] Proposed building SQL
      # @param reference_sql [OpenStudio::SqlFile] Reference building SQL
      # @return [Hash] Validation result
      def validate_heating_unmet_hours(proposed_sql, reference_sql)
        proposed_hours = get_heating_unmet_hours(proposed_sql)
        reference_hours = get_heating_unmet_hours(reference_sql)

        proposed_passed = proposed_hours <= 100
        reference_passed = reference_hours <= 100
        passed = proposed_passed && reference_passed

        message = if passed
                    "PASS: Proposed (#{proposed_hours.round(0)} hrs) and Reference (#{reference_hours.round(0)} hrs) both ≤ 100 hours"
                  else
                    failures = []
                    failures << "Proposed: #{proposed_hours.round(0)} hrs" unless proposed_passed
                    failures << "Reference: #{reference_hours.round(0)} hrs" unless reference_passed
                    "FAIL: Heating unmet hours exceed 100 for #{failures.join(', ')}"
                  end

        logger.log_compliance_test(
          article: '8.4.1.2.(3)',
          test_name: 'Heating Unmet Hours',
          proposed_value: proposed_hours.round(0),
          reference_value: reference_hours.round(0),
          passed: passed,
          message: message
        )

        {
          passed: passed,
          proposed_hours: proposed_hours.round(0),
          reference_hours: reference_hours.round(0),
          limit_hours: 100,
          message: message
        }
      end

      # Validate cooling unmet hours per Article 8.4.1.2.(4)
      #
      # @param proposed_sql [OpenStudio::SqlFile] Proposed building SQL
      # @param reference_sql [OpenStudio::SqlFile] Reference building SQL
      # @return [Hash] Validation result
      def validate_cooling_unmet_hours(proposed_sql, reference_sql)
        proposed_hours = get_cooling_unmet_hours(proposed_sql)
        reference_hours = get_cooling_unmet_hours(reference_sql)

        difference_percent = reference_hours > 0 ? (((proposed_hours - reference_hours) / reference_hours) * 100).round(1) : 0.0
        passed = difference_percent <= 10.0

        message = if passed
                    "PASS: Proposed unmet hours difference (#{difference_percent}%) ≤ +10%"
                  else
                    "FAIL: Proposed unmet hours difference (#{difference_percent}%) > +10%"
                  end

        logger.log_compliance_test(
          article: '8.4.1.2.(4)',
          test_name: 'Cooling Unmet Hours Difference',
          proposed_value: proposed_hours.round(0),
          reference_value: reference_hours.round(0),
          passed: passed,
          message: message
        )

        {
          passed: passed,
          proposed_hours: proposed_hours.round(0),
          reference_hours: reference_hours.round(0),
          difference_percent: difference_percent,
          limit_percent: 10.0,
          message: message
        }
      end

      private

      # Get total site energy from SQL file (GJ)
      def get_total_site_energy_gj(sql_file)
        return 0.0 unless sql_file

        # Query for total site energy
        query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='Site and Source Energy' AND RowName='Total Site Energy' AND ColumnName='Total Energy' AND Units='GJ'"

        value = sql_file.execAndReturnFirstDouble(query)
        return value.get if value.is_initialized

        0.0
      end

      # Get heating unmet hours from SQL file
      def get_heating_unmet_hours(sql_file)
        return 0.0 unless sql_file

        # Query for time setpoint not met during occupied heating
        query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='SystemSummary' AND ReportForString='Entire Facility' AND TableName='Time Setpoint Not Met' AND RowName='Facility' AND ColumnName='During Heating'"

        value = sql_file.execAndReturnFirstDouble(query)
        return value.get if value.is_initialized

        0.0
      end

      # Get cooling unmet hours from SQL file
      def get_cooling_unmet_hours(sql_file)
        return 0.0 unless sql_file

        # Query for time setpoint not met during occupied cooling
        query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='SystemSummary' AND ReportForString='Entire Facility' AND TableName='Time Setpoint Not Met' AND RowName='Facility' AND ColumnName='During Cooling'"

        value = sql_file.execAndReturnFirstDouble(query)
        return value.get if value.is_initialized

        0.0
      end
    end
  end
end
