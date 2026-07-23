#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixed-point comparison (phylroy's design): a legacy NECB2020 archetype is
# itself a building built to NECB 2020 rules, so running it through the new
# reference pipeline should approximately reproduce it. Every difference is
# one of: (a) a logged interpretation divergence (D-XX), (b) a reference-only
# rule the archetype doesn't carry, or (c) a genuine defect in one lineage.
# Compares the legacy input OSM vs the pipeline's reference model
# (sweep_run_<type>/reference_sizing/in.osm from necb_archetype_sweep.rb).
# Usage: ruby scripts/necb_fixed_point_diff.rb [types...]

require 'openstudio'

CACHE = '/tmp/openstudio_necb_legacy_archetype_e2e'
TYPES = ARGV.empty? ? %w[Warehouse FullServiceRestaurant HighriseApartment PrimarySchool RetailStandalone] : ARGV

def load_osm(path)
  m = OpenStudio::Model::Model.load(OpenStudio::Path.new(path))
  m.empty? ? nil : m.get
end

def opt(v) = v.respond_to?(:is_initialized) ? (v.is_initialized ? v.get : nil) : v

def surface_u(model)
  us = Hash.new { |h, k| h[k] = [] }
  model.getSurfaces.each do |s|
    next unless s.outsideBoundaryCondition == 'Outdoors'

    c = opt(s.construction) or next
    u = c.thermalConductance
    us["#{s.surfaceType.downcase} U"] << u.get.round(3) if u.is_initialized
  end
  us.transform_values { |v| v.tally.max_by { |_, n| n }[0] } # dominant value
end

def lpd_by_space_type(model)
  model.getSpaceTypes.filter_map do |st|
    lpd = st.lightingPowerPerFloorArea
    [st.nameString[0, 40], lpd.is_initialized ? lpd.get.round(2) : nil] if st.spaces.any?
  end.to_h
end

def hvac_signature(model)
  {
    'air loops' => model.getAirLoopHVACs.size,
    'coil types' => (model.getAirLoopHVACs.flat_map do |l|
      l.supplyComponents.map { |c| c.iddObjectType.valueName.sub('OS_', '') }
                        .grep(/Coil|Fan|HeatExchanger/)
    end).tally.sort.to_h,
    'plant loops' => model.getPlantLoops.size,
    'boiler eff' => model.getBoilerHotWaters.map { |b| b.nominalThermalEfficiency.round(3) }.uniq,
    'chiller COP' => model.getChillerElectricEIRs.map { |c| c.referenceCOP.round(2) }.uniq,
    'DX cool COP' => model.getCoilCoolingDXSingleSpeeds.map { |c| opt(c.ratedCOP)&.round(2) }.uniq,
    'ERVs' => model.getHeatExchangerAirToAirSensibleAndLatents.size,
    'zone equipment' => model.getThermalZones.flat_map { |z| z.equipment.map { |e| e.iddObjectType.valueName.sub('OS_', '').sub('ZoneHVAC_', '') } }.tally.sort.to_h,
    'baseboards' => model.getZoneHVACBaseboardConvectiveWaters.size + model.getZoneHVACBaseboardConvectiveElectrics.size,
    'infiltration flow/ext area' => model.getSpaceInfiltrationDesignFlowRates.filter_map { |i| opt(i.flowperExteriorSurfaceArea)&.round(5) }.uniq,
    'SWH heater eff' => model.getWaterHeaterMixeds.map { |w| opt(w.heaterThermalEfficiency)&.round(3) }.uniq
  }
end

TYPES.each do |type|
  legacy_path = File.join(CACHE, "sweep_necb2020_#{type.downcase}.osm")
  ref_path = File.join(CACHE, "sweep_run_#{type.downcase}", 'reference_sizing', 'in.osm')
  unless File.exist?(legacy_path) && File.exist?(ref_path)
    puts "#{type}: MISSING (#{legacy_path} / #{ref_path})"
    next
  end
  legacy = load_osm(legacy_path)
  ref = load_osm(ref_path)
  puts "\n=== #{type} — legacy archetype vs new-pipeline reference ==="
  { 'envelope U (dominant)' => [surface_u(legacy), surface_u(ref)],
    'LPD W/m2' => [lpd_by_space_type(legacy), lpd_by_space_type(ref)],
    'hvac' => [hvac_signature(legacy), hvac_signature(ref)] }.each do |section, (a, b)|
    keys = (a.keys | b.keys)
    keys.each do |k|
      same = a[k] == b[k]
      next if same && section != 'hvac' # print all hvac rows; only diffs elsewhere

      puts format('  %-24s %-38s legacy=%-28s ref=%s', section, k.to_s[0, 38],
                  a[k].inspect[0, 28], same ? '(same)' : b[k].inspect[0, 60])
    end
  end
end
