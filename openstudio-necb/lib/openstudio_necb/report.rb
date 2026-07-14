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
      proposed_model = result.respond_to?(:proposed_model) ? result.proposed_model : nil
      reference_model = result.respond_to?(:reference_model) ? result.reference_model : nil
      proposed_data = proposed_model ? ModelQuery.extract(proposed_model) : nil
      reference_data = reference_model ? ModelQuery.extract(reference_model) : nil

      # HVAC diagrams are drawn by openstudio-hvac's loop-diagram engine, driven
      # DIRECTLY off the SDK models here (report.rb is the only SDK-touching
      # place — the section modules stay SDK-free). Each is a plain hash of
      # inline-SVG strings; the engine never raises. The icon <defs> they
      # reference are embedded ONCE below.
      proposed_hvac = proposed_model ? OpenStudioHVAC.model_hvac_diagrams(proposed_model) : nil
      reference_hvac = reference_model ? OpenStudioHVAC.model_hvac_diagrams(reference_model) : nil

      ctx = {
        report: report,
        audit_entries: audit_entries,
        checklist_rows: Checklist.rows(audit_entries),
        proposed: proposed_data,
        reference: reference_data,
        proposed_hvac: proposed_hvac,
        reference_hvac: reference_hvac,
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
        <style>#{H::CSS}#{OpenStudioHVAC::CatalogReport::DIAGRAM_CSS}</style>
        </head>
        <body>
        #{OpenStudioHVAC.hvac_icon_defs}
        #{body}
        #{loop_select_script}
        </body>
        </html>
      HTML
    end

    # ONE inline, self-contained (no external refs) script that wires every
    # per-building HVAC loop dropdown: on change it shows the chosen loop's panel
    # and hides the rest within the same chooser. Native <select> + a few lines
    # of vanilla JS — no libraries, no network requests.
    def loop_select_script
      <<~SCRIPT
        <script>
        document.querySelectorAll('.loop-select').forEach(function(sel){
          function show(){ var v=sel.value, view=sel.closest('.hvac-select').querySelector('.loop-view');
            view.querySelectorAll('.loop-panel').forEach(function(p){ p.hidden = (p.id !== v); }); }
          sel.addEventListener('change', show); show();
        });
        </script>
      SCRIPT
    end
  end
end
