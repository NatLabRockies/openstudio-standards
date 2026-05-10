# frozen_string_literal: true

require 'erb'

module OpenstudioStandards
  module NECB2020
    # HTML compliance report generator for NECB 2020 Section 8.4
    #
    # Generates detailed HTML reports showing:
    # - Compliance summary with pass/fail indicators
    # - Section 8.4.3 proposed building characteristics
    # - Section 8.4.4 reference building changes (before/after tables)
    # - Section 8.4.1/8.4.2 compliance validation results
    #
    # @example Basic usage
    #   generator = ComplianceReportGenerator.new(logger, compliance_data)
    #   html = generator.generate_html
    #   generator.save_report('path/to/report.html')
    #
    class ComplianceReportGenerator
      attr_reader :logger, :compliance_data

      # Initialize report generator
      #
      # @param logger [ComplianceLogger] Logger with all logged data
      # @param compliance_data [Hash] Additional compliance data (models, results, etc.)
      def initialize(logger, compliance_data = {})
        @logger = logger
        @compliance_data = compliance_data
      end

      # Generate HTML report
      #
      # @return [String] HTML content
      def generate_html
        template = ERB.new(html_template, trim_mode: '-')
        template.result(binding)
      end

      # Save report to file
      #
      # @param file_path [String] Path to save HTML file
      # @return [String] Path to saved file
      def save_report(file_path)
        html = generate_html
        File.write(file_path, html)
        file_path
      end

      private

      # HTML template
      def html_template
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>NECB 2020 Performance Compliance Report</title>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                max-width: 1200px;
                margin: 0 auto;
                padding: 20px;
                background: #f5f5f5;
              }
              .container {
                background: white;
                padding: 30px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              }
              h1 {
                color: #2c3e50;
                border-bottom: 3px solid #3498db;
                padding-bottom: 10px;
              }
              h2 {
                color: #34495e;
                margin-top: 30px;
                border-bottom: 2px solid #ecf0f1;
                padding-bottom: 5px;
              }
              h3 {
                color: #7f8c8d;
                margin-top: 20px;
              }
              .summary {
                background: #ecf0f1;
                padding: 20px;
                border-radius: 5px;
                margin: 20px 0;
              }
              .pass {
                color: #27ae60;
                font-weight: bold;
              }
              .fail {
                color: #e74c3c;
                font-weight: bold;
              }
              table {
                width: 100%;
                border-collapse: collapse;
                margin: 15px 0;
              }
              th, td {
                padding: 12px;
                text-align: left;
                border-bottom: 1px solid #ddd;
              }
              th {
                background-color: #3498db;
                color: white;
                font-weight: 600;
              }
              tr:hover {
                background-color: #f5f5f5;
              }
              .section {
                margin: 30px 0;
                padding: 20px;
                border-left: 4px solid #3498db;
                background: #f8f9fa;
              }
              .article {
                margin: 15px 0;
                padding: 15px;
                background: white;
                border-radius: 4px;
              }
              .code-ref {
                font-size: 0.9em;
                color: #7f8c8d;
                font-style: italic;
              }
              .metric {
                display: inline-block;
                margin: 10px 20px 10px 0;
              }
              .metric-label {
                font-weight: 600;
                color: #34495e;
              }
              .metric-value {
                font-size: 1.2em;
                color: #2c3e50;
              }
            </style>
          </head>
          <body>
            <div class="container">
              <h1>NECB 2020 Performance Path Compliance Report</h1>

              <%= generate_building_info %>
              <%= generate_compliance_summary %>
              <%= generate_section_8_4_3 %>
              <%= generate_section_8_4_4 %>
              <%= generate_section_8_4_1 %>

              <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #7f8c8d;">
                <p>Generated by openstudio-standards NECB 2020 Performance Compliance Module</p>
                <p>Report Date: <%= Time.now.strftime('%Y-%m-%d %H:%M:%S') %></p>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      # Generate building information section
      def generate_building_info
        <<~HTML
          <div class="summary">
            <h2>Building Information</h2>
            <div class="metric">
              <span class="metric-label">Climate Zone:</span>
              <span class="metric-value">#{compliance_data[:climate_zone] || 'N/A'}</span>
            </div>
            <div class="metric">
              <span class="metric-label">HDD18:</span>
              <span class="metric-value">#{compliance_data[:hdd18]&.round(0) || 'N/A'}</span>
            </div>
            <div class="metric">
              <span class="metric-label">Weather File:</span>
              <span class="metric-value">#{File.basename(compliance_data[:epw_file] || 'N/A')}</span>
            </div>
          </div>
        HTML
      end

      # Generate compliance summary
      def generate_compliance_summary
        summary = logger.get_summary
        compliant = compliance_data[:compliance_result]&.[](:compliant)

        status_class = compliant ? 'pass' : 'fail'
        status_text = compliant ? '✓ COMPLIANT' : '✗ NOT COMPLIANT'

        <<~HTML
          <div class="summary">
            <h2>Compliance Summary</h2>
            <div class="metric">
              <span class="metric-label">Overall Status:</span>
              <span class="metric-value #{status_class}">#{status_text}</span>
            </div>
            <div class="metric">
              <span class="metric-label">Total Log Entries:</span>
              <span class="metric-value">#{summary[:total_entries]}</span>
            </div>
            <div class="metric">
              <span class="metric-label">Validation Results:</span>
              <span class="metric-value">#{summary[:passed]} passed, #{summary[:failed]} failed</span>
            </div>
          </div>
        HTML
      end

      # Generate Section 8.4.3 (Proposed Building)
      def generate_section_8_4_3
        logs = logger.get_logs_by_section('8.4.3')

        html = <<~HTML
          <div class="section">
            <h2>Section 8.4.3: Proposed Building Characteristics</h2>
            <p>The following characteristics were documented from the proposed building:</p>
        HTML

        logs.group_by { |log| log[:article] }.each do |article, article_logs|
          html += <<~HTML
            <div class="article">
              <h3>Article #{article}</h3>
          HTML

          article_logs.each do |log|
            html += "<p><strong>#{log[:action]}</strong></p>"
            if log[:details]
              html += "<ul>"
              log[:details].each do |key, value|
                html += "<li>#{key}: #{value}</li>"
              end
              html += "</ul>"
            end
          end

          html += "</div>"
        end

        html += "</div>"
        html
      end

      # Generate Section 8.4.4 (Reference Building)
      def generate_section_8_4_4
        logs = logger.get_logs_by_section('8.4.4')

        html = <<~HTML
          <div class="section">
            <h2>Section 8.4.4: Reference Building Requirements</h2>
            <p>The following prescriptive requirements were applied to the reference building:</p>
        HTML

        # Group by subsection (8.4.4.3, 8.4.4.5, etc.)
        logs.group_by { |log| log[:article].split('.')[0..3].join('.') }.each do |subsection, subsection_logs|
          html += <<~HTML
            <div class="article">
              <h3>Articles #{subsection}</h3>
          HTML

          # Create table if we have value changes
          value_change_logs = subsection_logs.select { |log| log[:proposed_value] && log[:reference_value] }

          if !value_change_logs.empty?
            html += <<~HTML
              <table>
                <thead>
                  <tr>
                    <th>Component</th>
                    <th>Proposed</th>
                    <th>Reference</th>
                    <th>Change</th>
                    <th>Code Reference</th>
                  </tr>
                </thead>
                <tbody>
            HTML

            value_change_logs.each do |log|
              change_display = if log[:change_percent]
                                 "#{log[:change_percent]}%"
                               elsif log[:change_magnitude]
                                 log[:change_magnitude].round(3).to_s
                               else
                                 'N/A'
                               end

              html += <<~HTML
                <tr>
                  <td>#{log[:component_name]}</td>
                  <td>#{log[:proposed_value]&.round(3)} #{log[:units]}</td>
                  <td>#{log[:reference_value]&.round(3)} #{log[:units]}</td>
                  <td>#{change_display}</td>
                  <td class="code-ref">#{log[:code_reference]}</td>
                </tr>
              HTML
            end

            html += "</tbody></table>"
          end

          # Show other logs
          other_logs = subsection_logs - value_change_logs
          other_logs.each do |log|
            html += "<p><strong>#{log[:action]}</strong>"
            html += " - #{log[:details]}" if log[:details]
            html += "</p>"
          end

          html += "</div>"
        end

        html += "</div>"
        html
      end

      # Generate Section 8.4.1 (Compliance Validation)
      def generate_section_8_4_1
        logs = logger.get_logs_by_section('8.4.1')
        compliance_result = compliance_data[:compliance_result]

        html = <<~HTML
          <div class="section">
            <h2>Section 8.4.1: Compliance Validation</h2>
        HTML

        if compliance_result
          # Annual energy
          if compliance_result[:annual_energy]
            ae = compliance_result[:annual_energy]
            status_class = ae[:passed] ? 'pass' : 'fail'
            html += <<~HTML
              <div class="article">
                <h3>Article 8.4.1.2.(2) - Annual Energy Consumption</h3>
                <p class="#{status_class}">#{ae[:message]}</p>
                <table>
                  <tr>
                    <th>Metric</th>
                    <th>Value</th>
                  </tr>
                  <tr>
                    <td>Proposed Building Annual Energy</td>
                    <td>#{ae[:proposed_energy_gj]} GJ</td>
                  </tr>
                  <tr>
                    <td>Building Energy Target (Reference)</td>
                    <td>#{ae[:building_energy_target_gj]} GJ</td>
                  </tr>
                  <tr>
                    <td>Margin</td>
                    <td>#{ae[:margin_gj]} GJ (#{ae[:margin_percent]}%)</td>
                  </tr>
                </table>
              </div>
            HTML
          end

          # Unmet hours
          if compliance_result[:unmet_heating_hours]
            uh = compliance_result[:unmet_heating_hours]
            status_class = uh[:passed] ? 'pass' : 'fail'
            html += <<~HTML
              <div class="article">
                <h3>Article 8.4.1.2.(3) - Heating Unmet Hours</h3>
                <p class="#{status_class}">#{uh[:message]}</p>
              </div>
            HTML
          end

          if compliance_result[:unmet_cooling_hours]
            uc = compliance_result[:unmet_cooling_hours]
            status_class = uc[:passed] ? 'pass' : 'fail'
            html += <<~HTML
              <div class="article">
                <h3>Article 8.4.1.2.(4) - Cooling Unmet Hours</h3>
                <p class="#{status_class}">#{uc[:message]}</p>
              </div>
            HTML
          end
        else
          html += "<p><em>Simulations not run - compliance validation not performed</em></p>"
        end

        html += "</div>"
        html
      end
    end
  end
end
