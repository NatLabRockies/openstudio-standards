require_relative 'report/html'
require_relative 'report/svg'
require_relative 'report/charts'
require_relative 'report/checklist'
require_relative 'report/model_query'
require_relative 'report/diagrams'
require_relative 'report/sections'

module OpenStudioNECB
  # Renders a ComplianceResult into ONE self-contained HTML file suitable for
  # submission to an authority having jurisdiction: verdict-first summary, both
  # compliance paths, an AHJ-style checklist derived from the audit log, and
  # per-domain proposed-vs-reference sections with inline-SVG charts and system
  # schematics. No external resources, no scripts (native <details> only).
  module Report
    module_function

    # @param result [ComplianceResult, #report] anything exposing #report and
    #   #audit (and optionally #proposed_model / #reference_model)
    # @param path [String] output .html path
    # @param options [Hash] project metadata: :project_name, :address,
    #   :permit_number, :prepared_by, :professional_of_record, :date
    # @return [String] the path written
    def write_html(result, path, options = {})
      File.write(path, render(result, options))
      path
    end

    # @return [String] the full HTML document
    def render(result, options = {})
      report = result.report
      audit_entries = result.audit ? result.audit.entries : []
      proposed_data = result.respond_to?(:proposed_model) ? ModelQuery.extract(result.proposed_model) : nil
      reference_data = result.respond_to?(:reference_model) ? ModelQuery.extract(result.reference_model) : nil

      ctx = {
        report: report,
        audit_entries: audit_entries,
        checklist_rows: Checklist.rows(audit_entries),
        proposed: proposed_data,
        reference: reference_data,
        options: options
      }
      body = Sections.render_all(ctx)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>NECB #{H.esc(report['vintage'])} Compliance Report#{options[:project_name] ? " — #{H.esc(options[:project_name])}" : ''}</title>
        <style>#{H::CSS}</style>
        </head>
        <body>
        #{body}
        </body>
        </html>
      HTML
    end
  end
end
