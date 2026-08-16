#!/usr/bin/env ruby
# frozen_string_literal: true

# Building-stock adapter: NRCan footprint records in, OpenStudio massing out.
#
#   ruby scripts/building_stock.rb --fsa K1P --limit 10 --out /tmp/massing
#   ruby scripts/building_stock.rb --point 45.4215,-75.6972 --radius 300 --out /tmp/massing
#   ruby scripts/building_stock.rb --bbox -75.70,45.41,-75.69,45.43 --out /tmp/massing
#   ruby scripts/building_stock.rb --from-cache records.json --out /tmp/massing   # offline
#
# WHY THIS IS A SCRIPT AND NOT PART OF THE GEM (D-71): openstudio-geometry is
# SDK-only and offline, and `spec.files` is `lib/**/*`, so nothing here ships in
# the gem. The fetch lives beside its consumer without putting a network
# dependency inside it. `OpenStudioGeometry::Footprint` still never learns where
# a ring came from.
#
# AUTH follows scripts/fetch_necb_8_4_text.rb in openstudio-necb: endpoint and
# X-API-Key come from the environment, else from .mcp.json (gitignored, never
# committed with a live key). Nothing is hardcoded, and the key is never
# printed, never written to the cache, and never stored in a model.
# openstudio-simulation's Remote backend declines to hardcode agent-facing MCP
# endpoints for exactly this reason; reading them at runtime is the same rule
# honoured, not an exception to it.
#
# CACHE: `--cache` writes the raw records, `--from-cache` rebuilds from them
# with no network at all — so a fetch is reproducible and CI never needs the
# MCP, the same split the NECB text fetcher uses.

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'optparse'
require_relative '../lib/openstudio_geometry'

module BuildingStock
  SERVER = 'building-stock'
  DATASET = 'nrcan-buildings'
  ROOT = File.expand_path('../..', __dir__)

  class Error < StandardError; end

  # Minimal JSON-RPC client for the HTTP MCP server. Stateless: one POST per
  # call, no session, no initialize handshake.
  class Client
    def initialize(endpoint: nil, api_key: nil, timeout: 60)
      config = mcp_config
      @endpoint = URI(endpoint || ENV['BUILDING_STOCK_MCP_URL'] || config['url'] ||
                      raise(Error, "no #{SERVER} url: set BUILDING_STOCK_MCP_URL or configure .mcp.json"))
      @api_key = api_key || ENV['BUILDING_STOCK_API_KEY'] || config.dig('headers', 'X-API-Key') ||
                 raise(Error, "no #{SERVER} API key: set BUILDING_STOCK_API_KEY or configure .mcp.json")
      @timeout = timeout
    end

    def mcp_config
      path = File.join(ROOT, '.mcp.json')
      return {} unless File.exist?(path)

      JSON.parse(File.read(path)).dig('mcpServers', SERVER) || {}
    rescue JSON::ParserError
      {}
    end

    # One tools/call. The server answers as SSE ("data: {...}") whose
    # result.content[0].text is itself a JSON document.
    def call(tool, arguments, attempts: 3)
      request = Net::HTTP::Post.new(@endpoint)
      request['X-API-Key'] = @api_key
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json, text/event-stream'
      request.body = { jsonrpc: '2.0', id: 1, method: 'tools/call',
                       params: { name: tool, arguments: arguments } }.to_json

      response = nil
      attempts.times do |attempt|
        response = Net::HTTP.start(@endpoint.host, @endpoint.port, use_ssl: @endpoint.scheme == 'https',
                                                                   read_timeout: @timeout) do |http|
          http.request(request)
        end
        break if response.code == '200'
        # Back off on throttling and transient server faults; fail fast on 4xx.
        raise(Error, "#{tool}: HTTP #{response.code}") unless %w[429 500 502 503 504].include?(response.code)
        sleep(2**attempt) if attempt < attempts - 1
      end
      raise(Error, "#{tool}: HTTP #{response.code} after #{attempts} attempts") unless response.code == '200'

      unwrap(response.body, tool)
    end

    def unwrap(body, tool)
      payload = body.lines.filter_map do |line|
        next unless line.start_with?('data: ')

        JSON.parse(line.delete_prefix('data: ')) rescue nil
      end.find { |frame| frame.key?('result') || frame.key?('error') }
      payload ||= (JSON.parse(body) rescue nil)
      raise(Error, "#{tool}: no JSON-RPC frame in response") if payload.nil?
      raise(Error, "#{tool}: RPC error #{payload['error']}") if payload['error']

      text = payload.dig('result', 'content', 0, 'text')
      raise(Error, "#{tool}: empty result") if text.nil?

      JSON.parse(text)
    end

    def query(mode, options)
      common = { dataset_id: DATASET, include_geometry: true, limit: options[:limit] }
      result = case mode
               when :fsa    then call('query_buildings_fsa', common.merge(fsa: options[:fsa]))
               when :point  then call('query_buildings_point',
                                      common.merge(lat: options[:lat], lon: options[:lon],
                                                   radius_m: options[:radius]))
               when :bbox   then call('query_buildings_bbox',
                                      common.merge(west: options[:west], south: options[:south],
                                                   east: options[:east], north: options[:north]))
               else raise(Error, "unknown query mode #{mode}")
               end
      result['buildings'] || []
    end
  end

  # What the adapter needs from a record, and why a record is unusable.
  module Records
    HEIGHT_FIELDS = %w[height_max_m].freeze

    module_function

    # height_min_m is the lowest ROOF point (a podium), not ground level —
    # subtracting it understates the building. Only height_max_m is the height.
    def height_of(record)
      HEIGHT_FIELDS.each do |field|
        value = record[field]
        return [value.to_f, field] if value && value.to_f.positive?
      end
      [nil, nil]
    end

    def rejection(record)
      return 'no geometry (query with include_geometry: true)' if record['geometry_geojson'].nil?
      return 'no usable height' if height_of(record).first.nil?
      return 'no footprint area' unless record['building_area_m2'].to_f.positive?

      nil
    end

    # Everything worth carrying into the audit so a massing is reproducible
    # from its source record. The API key is deliberately NOT part of this.
    def provenance(record, height_field)
      { feature_id: record['feature_id'], dataset: DATASET, height_field: height_field,
        building_class: record['building_class'], vintage_year: record['vintage_year'],
        fsa: record['fsa'], climate_zone: record['climate_zone'],
        province_code: record['province_code'], csd_name: record['csd_name'] }.compact
    end
  end

  module Adapter
    module_function

    # One record -> one model. Storey height is the caller's call, never
    # inferred here: the publisher's own estimated_floors implies 3.5 m, the
    # openstudio-standards default is 10 ft, and the gem default is 3.8 m.
    #
    # `multiplier:` defaults to :mid, unlike the gem facade. Stock work builds
    # towers in bulk: a 28-storey record with per-edge perimeter zoning is 336
    # real spaces at :none and 36 at :mid, for the same loads and the same
    # envelope. Pass multiplier: :none when you need every storey addressable.
    #
    # Perimeter SPACES are one per outline edge; the thermal ZONES they join are
    # N/E/S/W + Core, so a many-edged outline still presents the 5 zones per
    # storey a modeller expects (gem-side, see Footprint.edge_orientation).
    #
    # @return [Hash] { model:, record:, audit:, skipped: <reason> }
    def to_model(record, floor_to_floor_height: OpenStudioGeometry::Footprint::NRCAN_IMPLIED,
                 zoning: :core_perimeter, multiplier: :mid, audit: nil)
      audit ||= OpenStudioGeometry::AuditLog.new
      reason = Records.rejection(record)
      if reason
        audit.warn(:geometry, 'building-stock record skipped',
                   inputs: { feature_id: record['feature_id'], reason: reason })
        return { model: nil, record: record, audit: audit, skipped: reason }
      end

      height, field = Records.height_of(record)
      model = OpenStudioGeometry.create_from_footprint(
        geojson: record['geometry_geojson'], height_m: height,
        floor_to_floor_height: floor_to_floor_height, zoning: zoning, multiplier: multiplier,
        source: Records.provenance(record, field), audit: audit
      )
      stamp(model, record)
      { model: model, record: record, audit: audit }
    end

    # Carry the record's own attributes on the model so the NEXT stage (WWR by
    # class and vintage, weather by FSA/climate zone, space types) can read them
    # without re-querying. Deliberately NOT setStandardsBuildingType:
    # building_class is NRCan's heuristic, not a standards building type, and
    # conflating them would silently mis-tag every model.
    def stamp(model, record)
      properties = model.getBuilding.additionalProperties
      %w[feature_id building_class vintage_year fsa climate_zone province_code csd_uid
         building_area_m2 height_max_m estimated_floors estimated_gfa_m2].each do |key|
        value = record[key]
        next if value.nil?

        properties.setFeature("nrcan_#{key}", value.is_a?(Numeric) ? value.to_f : value.to_s)
      end
      model.getBuilding.setName("NRCan #{record['feature_id']}") if record['feature_id']
    end
  end
end

# ------------------------------------------------------------------ CLI

if __FILE__ == $PROGRAM_NAME
  options = { limit: 25, radius: 500, storey_height: OpenStudioGeometry::Footprint::NRCAN_IMPLIED,
              zoning: :core_perimeter, multiplier: :mid, out: nil, cache: nil,
              from_cache: nil, klass: nil }
  parser = OptionParser.new do |o|
    o.banner = 'Usage: ruby scripts/building_stock.rb [query] --out DIR'
    o.on('--fsa CODE', 'query by forward sortation area (e.g. K1P)') { |v| options[:fsa] = v }
    o.on('--point LAT,LON', 'query around a point') { |v| options[:lat], options[:lon] = v.split(',').map(&:to_f) }
    o.on('--radius M', Float, 'point search radius, metres (500)') { |v| options[:radius] = v }
    o.on('--bbox W,S,E,N', 'query a bounding box') do |v|
      options[:west], options[:south], options[:east], options[:north] = v.split(',').map(&:to_f)
    end
    o.on('--limit N', Integer, 'max records (25)') { |v| options[:limit] = v }
    o.on('--class NAME', 'keep only this building_class') { |v| options[:klass] = v }
    o.on('--storey-height M', Float, "metres (#{OpenStudioGeometry::Footprint::NRCAN_IMPLIED})") do |v|
      options[:storey_height] = v
    end
    o.on('--zoning MODE', %w[core_perimeter single], 'core_perimeter | single') { |v| options[:zoning] = v.to_sym }
    o.on('--multiplier MODE', %w[mid none], 'mid (ground/mid/top, default) | none (every storey)') do |v|
      options[:multiplier] = v.to_sym
    end
    o.on('--out DIR', 'write .osm files and manifest.json here') { |v| options[:out] = v }
    o.on('--cache FILE', 'save fetched records here') { |v| options[:cache] = v }
    o.on('--from-cache FILE', 'rebuild from saved records, no network') { |v| options[:from_cache] = v }
    o.on('--dry-run', 'fetch and report, build nothing') { options[:dry_run] = true }
    o.on('-h', '--help') { puts o; exit }
  end
  parser.parse!

  records =
    if options[:from_cache]
      JSON.parse(File.read(options[:from_cache]))
    else
      client = BuildingStock::Client.new
      mode = if options[:fsa] then :fsa
             elsif options[:lat] then :point
             elsif options[:west] then :bbox
             else abort(parser.to_s)
             end
      client.query(mode, options)
    end
  records = records.select { |r| r['building_class'] == options[:klass] } if options[:klass]
  warn "fetched #{records.size} record(s)"

  if options[:cache]
    FileUtils.mkdir_p(File.dirname(options[:cache]))
    File.write(options[:cache], JSON.pretty_generate(records))
    warn "cached -> #{options[:cache]}"
  end
  exit if options[:dry_run]
  abort('--out is required to build') unless options[:out]

  FileUtils.mkdir_p(options[:out])
  audit = OpenStudioGeometry::AuditLog.new
  manifest = []
  records.each do |record|
    result = BuildingStock::Adapter.to_model(
      record, floor_to_floor_height: options[:storey_height], zoning: options[:zoning],
      multiplier: options[:multiplier], audit: audit
    )
    if result[:skipped]
      manifest << { feature_id: record['feature_id'], skipped: result[:skipped] }
      next
    end

    name = "#{record['feature_id'][0, 8]}.osm"
    result[:model].save(File.join(options[:out], name), true)
    entry = audit.entries.reverse.find { |e| e[:action].to_s.include?('measured-footprint') }
    manifest << { feature_id: record['feature_id'], osm: name, building_class: record['building_class'],
                  storeys: entry[:inputs][:storeys_above], zoning: entry[:inputs][:zoning],
                  perimeter_zone_depth: entry[:inputs][:perimeter_zone_depth],
                  footprint_area_m2: entry[:inputs][:footprint_area_m2],
                  spaces: result[:model].getSpaces.size,
                  thermal_zones: result[:model].getThermalZones.size,
                  zones_per_storey: result[:model].getThermalZones
                                          .count { |z| z.nameString.start_with?('Story 0 ') } }
  end

  File.write(File.join(options[:out], 'manifest.json'), JSON.pretty_generate(manifest))
  built = manifest.count { |m| m[:osm] }
  zoned = manifest.count { |m| m[:zoning] == :core_perimeter }
  warn "built #{built}/#{records.size} (#{zoned} core/perimeter, #{manifest.size - built} skipped)"
  warn "manifest -> #{File.join(options[:out], 'manifest.json')}"
  warn "warnings: #{audit.warnings.size}"
end
