#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixed-point comparison (phylroy's design): a legacy NECB2020 archetype is
# itself a building built to NECB 2020 rules, so running it through the new
# reference pipeline should approximately reproduce it. Every difference is
# one of: (a) a logged interpretation divergence (D-XX), (b) a reference-only
# rule the archetype doesn't carry, or (c) a genuine defect in one lineage.
# Compares the legacy input OSM vs the pipeline's FINAL reference model
# (sweep_run_<type>/reference_annual/in.osm — post-sizing efficiencies, ERV
# determination and pump transfer applied; falls back to reference_sizing
# when the sweep ran in sizing-only mode). Object-level and fast: no
# simulation, just model loads.
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
  # Ground/Foundation surfaces INCLUDED — the Outdoors-only version had a
  # blind spot that hid the Warehouse slab divergence for three diff passes
  # (D-32: 4,598 m2 of it).
  us = Hash.new { |h, k| h[k] = [] }
  model.getSurfaces.each do |s|
    prefix = case s.outsideBoundaryCondition
             when 'Outdoors' then ''
             when 'Ground', 'Foundation', 'GroundFCfactorMethod', 'GroundSlabPreprocessorAverage' then 'ground '
             else next
             end
    c = opt(s.construction) or next
    u = c.thermalConductance
    us["#{prefix}#{s.surfaceType.downcase} U"] << u.get.round(3) if u.is_initialized
  end
  us.transform_values { |v| v.tally.max_by { |_, n| n }[0] } # dominant value
end

def lpd_by_space_type(model)
  model.getSpaceTypes.filter_map do |st|
    lpd = st.lightingPowerPerFloorArea
    [st.nameString[0, 40], lpd.is_initialized ? lpd.get.round(2) : nil] if st.spaces.any?
  end.to_h
end

# Staged reference systems (8.4.4.9.(7)/8.4.4.10.(8)) hold their fan and coils
# inside an AirLoopHVACUnitarySystem — expand it so the fingerprint keeps seeing
# them. Inlined rather than calling the hvac gem: this script loads only the SDK.
def supply_components_deep(air_loop)
  air_loop.supplyComponents.flat_map do |comp|
    unitary = comp.to_AirLoopHVACUnitarySystem
    next [comp] unless unitary.is_initialized

    unitary = unitary.get
    [unitary.supplyFan, unitary.coolingCoil, unitary.heatingCoil, unitary.supplementalHeatingCoil]
      .filter_map { |o| o.is_initialized ? o.get : nil }
  end
end

def hvac_signature(model)
  fans = (model.getFanConstantVolumes + model.getFanVariableVolumes + model.getFanOnOffs)
  pumps = model.getPumpConstantSpeeds + model.getPumpVariableSpeeds
  spms = model.getSetpointManagers
  {
    'air loops' => model.getAirLoopHVACs.size,
    'coil types' => (model.getAirLoopHVACs.flat_map do |l|
      supply_components_deep(l).map { |c| c.iddObjectType.valueName.sub('OS_', '') }
                               .grep(/Coil|Fan|HeatExchanger/)
    end).tally.sort.to_h,
    'staged coil stages' => (model.getCoilCoolingDXMultiSpeeds + model.getCoilHeatingDXMultiSpeeds +
                             model.getCoilHeatingGasMultiStages).map { |c| c.stages.size }.tally.sort.to_h,
    'staged DX cool COP' => model.getCoilCoolingDXMultiSpeeds.map { |c| c.stages.last&.grossRatedCoolingCOP&.round(2) }.uniq.sort,
    'staged gas burner eff' => model.getCoilHeatingGasMultiStages.map { |c| c.stages.last&.gasBurnerEfficiency&.round(3) }.uniq.sort,
    'plant loops' => model.getPlantLoops.size,
    'boiler eff' => model.getBoilerHotWaters.map { |b| b.nominalThermalEfficiency.round(3) }.uniq.sort,
    'chiller COP' => model.getChillerElectricEIRs.map { |c| c.referenceCOP.round(2) }.uniq.sort,
    'DX cool COP' => model.getCoilCoolingDXSingleSpeeds.map { |c| opt(c.ratedCOP)&.round(2) }.uniq.sort,
    'DX heat COP' => model.getCoilHeatingDXSingleSpeeds.map { |c| c.ratedCOP.round(2) }.uniq.sort,
    'fan Pa (rise)' => fans.map { |f| f.pressureRise.round(0) }.tally.sort.to_h,
    'fan total eff' => fans.map { |f| f.fanTotalEfficiency.round(3) }.uniq.sort,
    'pump W (hard)' => pumps.filter_map { |p| opt(p.ratedPowerConsumption)&.round(0) }.uniq.sort,
    'pump head Pa' => pumps.filter_map { |p| opt(p.ratedPumpHead)&.round(0) }.uniq.sort,
    'tower fan W' => model.getCoolingTowerSingleSpeeds.filter_map { |t| opt(t.fanPoweratDesignAirFlowRate)&.round(0) },
    'tower count' => model.getCoolingTowerSingleSpeeds.size,
    'SPM types' => spms.map { |s| s.iddObjectType.valueName.sub('OS_SetpointManager_', '') }.tally.sort.to_h,
    'economizer' => model.getControllerOutdoorAirs.map(&:getEconomizerControlType).tally.sort.to_h,
    'ERVs' => model.getHeatExchangerAirToAirSensibleAndLatents.size,
    'ERV sens eff @100% heat' => model.getHeatExchangerAirToAirSensibleAndLatents.map { |e| opt(e.sensibleEffectivenessat100HeatingAirFlow)&.round(2) }.uniq.sort,
    'terminal min flow m3/s' => model.getAirTerminalSingleDuctVAVReheats.filter_map { |t| opt(t.fixedMinimumAirFlowRate)&.round(3) }.uniq.sort.first(6),
    'terminal reheat frac' => model.getAirTerminalSingleDuctVAVReheats.map { |t| opt(t.maximumFlowFractionDuringReheat)&.round(2) }.uniq.sort_by(&:to_f),
    'zone equipment' => model.getThermalZones.flat_map { |z| z.equipment.map { |e| e.iddObjectType.valueName.sub('OS_', '').sub('ZoneHVAC_', '') } }.tally.sort.to_h,
    'baseboards' => model.getZoneHVACBaseboardConvectiveWaters.size + model.getZoneHVACBaseboardConvectiveElectrics.size,
    'infiltration flow/ext area' => model.getSpaceInfiltrationDesignFlowRates.filter_map { |i| opt(i.flowperExteriorSurfaceArea)&.round(5) }.uniq.sort,
    'infiltration objects' => model.getSpaceInfiltrationDesignFlowRates.size,
    'SWH heater eff' => model.getWaterHeaterMixeds.map { |w| opt(w.heaterThermalEfficiency)&.round(3) }.uniq.sort,
    'SWH tank m3' => model.getWaterHeaterMixeds.map { |w| opt(w.tankVolume)&.round(3) }.uniq.sort_by(&:to_f)
  }
end

TYPES.each do |type|
  legacy_path = File.join(CACHE, "sweep_necb2020_#{type.downcase}.osm")
  ref_path = %w[reference_annual reference_sizing]
             .map { |d| File.join(CACHE, "sweep_run_#{type.downcase}", d, 'in.osm') }
             .find { |p| File.exist?(p) }.to_s
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
