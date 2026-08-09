# Regenerate the committed catalog artifacts at the gem root:
#
#   SYSTEM_CATALOG.html  build-verified visual catalog (OpenStudioHVAC.catalog_html —
#                        every row is really BUILT on the bundled fixture, so this
#                        needs the OpenStudio SDK bindings on the load path)
#   SYSTEM_CATALOG.csv   flat one-row-per-system table (name, canonical_name, family,
#                        sys_abbr, heating_coil_type, heat_source, baseboard_type,
#                        needs_boiler)
#   SYSTEM_CATALOG.txt   plain-text listing grouped by family: legacy name -> canonical name
#
# Run after ANY edit to lib/openstudio_hvac/data/systems.json (or to canonical.rb,
# which generates the canonical names) so the committed artifacts cannot drift:
#
#   cd openstudio-hvac && ruby scripts/regenerate_catalog.rb
#
# The CSV/TXT writers live here rather than in catalog_report.rb because they are
# release artifacts, not a library feature; the HTML is the library's own
# CatalogReport.to_html.
require 'csv'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
require 'openstudio_hvac'

rows = OpenStudioHVAC.systems.sort_by { |r| [r['family'], r['name']] }
families = rows.group_by { |r| r['family'] }

# ---- CSV ----
csv_path = File.join(ROOT, 'SYSTEM_CATALOG.csv')
CSV_COLUMNS = %w[name canonical_name family sys_abbr heating_coil_type heat_source baseboard_type
                 needs_boiler].freeze
CSV.open(csv_path, 'w') do |csv|
  csv << CSV_COLUMNS
  # Pass values through as-is: a missing key must stay an UNQUOTED empty field
  # (Ruby's CSV writes an explicit "" for an empty String, but nothing for nil).
  rows.each { |r| csv << CSV_COLUMNS.map { |k| r[k] } }
end
puts "wrote #{csv_path} (#{rows.size} systems)"

# ---- TXT ----
txt_path = File.join(ROOT, 'SYSTEM_CATALOG.txt')
File.open(txt_path, 'w') do |io|
  io.puts "openstudio-hvac system catalog — #{rows.size} systems, #{families.size} families"
  io.puts 'Each entry:  <argument name  (the exact build_system string)>'
  io.puts '             -> <canonical name  (human-readable, Canonical.name; also a valid resolver key)>'
  io.puts
  families.keys.sort.each do |family|
    members = families[family]
    abbrs = members.map { |r| r['sys_abbr'] }.compact.uniq.sort
    header = "== #{family} (#{members.size})"
    header += "  [#{abbrs.join(', ')}]" unless abbrs.empty?
    io.puts header
    members.each do |r|
      io.puts "   #{r['name']}"
      io.puts "      -> #{r['canonical_name']}"
    end
    io.puts
  end
end
puts "wrote #{txt_path}"

# ---- HTML ----
html_path = File.join(ROOT, 'SYSTEM_CATALOG.html')
OpenStudioHVAC.catalog_html(html_path)
puts "wrote #{html_path}"
