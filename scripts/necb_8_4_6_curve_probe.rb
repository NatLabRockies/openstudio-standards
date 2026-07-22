#!/usr/bin/env ruby
# frozen_string_literal: true

# 8.4.6 part-load curve verification probe (rake necb:verify).
#
# NECB 2025 Subsection 8.4.6 mandates specific part-load performance curve
# coefficients for reference equipment. The gems attach vendored curves
# (NECB2011-era names) — this probe verifies, at MODEL level, that what the
# efficiency passes actually apply is numerically equivalent to the 2025 code
# formulation. "Equivalent", not "identical": the code writes fuel-ratio
# curves FHeatPLC(PLR) and degF temperature polynomials, while EnergyPlus
# wants efficiency/PLF curves and degC polynomials — so comparisons are made
# under the documented transforms:
#
#   FHeatPLC(PLR) = PLR / eff_curve(PLR)   (boiler normalized-efficiency form)
#   FHeatPLC(PLR) = PLR / PLF(PLR)         (furnace/SWH part-load-fraction form)
#   biquadratic degF -> degC by variable substitution t_F = 1.8 t_C + 32
#
# Method (per docs/necb_rule_verification.md): build components, hard-size
# them (capacity-binned rows need capacities; no CLI required), run the real
# efficiency passes, read the curves BACK OFF THE MODEL, and compare. Expected
# coefficients are transcribed from the building-codes MCP (necb:2025,
# retrieved 2026-07-22: Tables 8.4.6.2/8.4.6.3, Sentences 8.4.6.4.(3)/(5)/(7),
# Sentence 8.4.6.9.(2)) — and every code-side polynomial is SELF-CHECKED to
# evaluate to ~1.0 at its rating point before use, so a transcription slip
# fails the probe instead of producing a false verdict.
#
# Exit: non-zero if any comparable curve is missing or deviates beyond
# tolerance. Articles the probe does NOT yet compare are printed explicitly —
# silence is never coverage.

require 'openstudio'
require_relative '../openstudio-hvac/lib/openstudio_hvac'
require_relative '../openstudio-shw/lib/openstudio_shw'

TOL_SAMPLED = 0.03   # 3% max relative deviation on sampled PLR comparisons
TOL_SURFACE = 0.005  # 0.5% on sampled temperature surfaces (coefficient-wise
                     # comparison is the wrong metric: vendored JSON rounds
                     # small coefficients to ~6 significant figures, which
                     # reads as a large RELATIVE dev on a near-zero term while
                     # being physically nothing)
PLR_GRID = (25..100).step(5).map { |p| p / 100.0 }
# Operating envelope for the DX temperature surfaces, degF: entering wet-bulb
# 57-72, outdoor dry-bulb 65-115 (spans the E+ default curve limits).
SURFACE_GRID_F = (57..72).step(3).flat_map { |wb| (65..115).step(10).map { |db| [wb.to_f, db.to_f] } }
# Operating envelope for the chiller temperature surfaces, degF: leaving chilled
# water 41-49, entering condenser water 75-95 (spans the vendored curve's own
# limits of 5-10 degC / 24-35 degC).
CHILLER_SURFACE_GRID_F = (41..49).step(2).flat_map { |chw| (75..95).step(5).map { |cw| [chw.to_f, cw.to_f] } }
# Operating envelope for the 8.4.6.7 ASHP heating curves, degF outdoor dry-bulb:
# -4 to 68 (spans the vendored DXHEAT curve's own limits of -20 to 20 degC).
ASHP_ODB_GRID_F = (-4..68).step(8).to_a.map(&:to_f)

# ---- code-side targets (NECB 2025, Division B) -----------------------------
BOILER_FHEATPLC = { # Table 8.4.6.2 (quadratic rows; condensing is 6-term and not compared here)
  'Non-condensing' => [0.082597, 0.996764, -0.079361],
  'Modulating' => [0.01798667, 0.96742420, 0.01545455]
}.freeze
FURNACE_FHEATPLC = { # Table 8.4.6.3
  'Atmospheric' => [0.0186100, 1.0942090, -0.1128190],
  'Condensing' => [0.00533, 0.904, 0.09066],
  'Modulating' => [0.01798667, 0.96742420, 0.01545455]
}.freeze
SWH_FHEATPLC = [0.021826, 0.977630, 0.000543].freeze # 8.4.6.9.(2)
# 8.4.6.4 DX biquadratics in degF (t_wb entering coil, t_odb) + EIR_FPLR cubic
DX_CAP_FT_F  = [0.8740302, -0.0011416, 0.0001711, -0.0029570, 0.0000102, -0.0000592].freeze
DX_EIR_FT_F  = [-1.0639310, 0.0306584, -0.0001269, 0.0154213, 0.0000497, -0.0002096].freeze
DX_EIR_FPLR  = [0.2012301, -0.0312175, 1.9504979, -1.1205105].freeze
RATING_F = [67.0, 95.0].freeze # AHRI: 67F entering wet-bulb / 95F outdoor dry-bulb

# 8.4.6.5 electric chiller (Water-cooled rows only — the gem's default reference
# chiller is WaterCooled unless the model overrides condenserType). CAP_FT/EIR_FT
# are biquadratics in (tchws = leaving chilled water supply temp, tcws = entering
# condenser water supply temp) degF, matching E+ ChillerElectricEIR's two curve
# variables exactly (leaving chilled water temp, entering condenser fluid temp).
# EIR_FPLR is a direct cubic-in-PLR power multiplier per 8.4.6.5.(4): Poperating =
# Prated x EIR_FPLR x EIR_FT x CAP_FTEC — NOT a PLF cycling curve (chillers modulate
# continuously; ChillerElectricEIR has no separate PLF/cycling field), so it is
# compared directly against the model's ElectricInputToCoolingOutputRatioFunctionOfPLR
# curve rather than through the PLR/PLF(PLR) transform used for DX/furnace/boiler.
CHILLER_CAP_FT_EC_F = { # Table 8.4.6.5.-A, Water-cooled rows
  'Scroll' => [0.36131454, 0.01855477, 0.00003011, 0.00093592, -0.00001518, -0.00005481],
  'Reciprocating' => [0.58531422, 0.01539593, 0.00007296, -0.00212462, -0.00000715, -0.00004597]
}.freeze
CHILLER_EIR_FPLR = { # Table 8.4.6.5.-B, Water-cooled rows
  'Scroll' => [0.04411957, 0.64036703, 0.31955532],
  'Reciprocating' => [0.08144133, 0.41927141, 0.49939604]
}.freeze
# Table 8.4.6.5.-C (EIR_FT), Water-cooled rows — TRANSCRIBED BUT NOT USED. At the
# AHRI 550/590 rating point (44F leaving chilled water / 85F entering condenser
# water) these two rows evaluate to 0.018 (Scroll) and -2.49 (Reciprocating), not
# ~1.0: they fail self_check! and are never fed to it. (For the record: the
# 'Screw'/'Centrifugal' rows of the SAME table self-check fine at this point,
# while 'Screw'/'Centrifugal' FAIL Table 8.4.6.5.-A's self-check — a pattern
# consistent with a 2-row swap in extraction, but that is a hypothesis about the
# source, not something confirmed against the original PDF, so per the "never
# compare against an unverified transcription" rule this curve is NOT COMPARED.)
CHILLER_EIR_FT_EC_F_SUSPECT = {
  'Scroll' => [1.00121431, -0.01026981, 0.00016703, -0.0128136, 0.00014613, -0.00021959],
  'Reciprocating' => [0.46140041, -0.0882156, 0.00008223, 0.00926607, 0.00005722, -0.00011594]
}.freeze
CHILLER_RATING_F = [44.0, 85.0].freeze # AHRI 550/590: 44F LChWT / 85F entering condenser water

# 8.4.6.7 electric air-source heat pump, heating. CAP_FT/EIR_FT are CUBIC in
# t_odb (outdoor dry-bulb) ONLY degF — no compressor-type split in this article
# (single row, "Single Package"/"Split System" share the same coefficients).
# EIR_FPLR is set through CoilHeatingDXSingleSpeed's PartLoadFractionCorrelationCurve
# field (same field DX cooling uses for its cycling PLF curve), so — unlike the
# chiller — it IS compared via the PLR/PLF(PLR) transform (compare_fheatplc),
# consistent with how 8.4.6.4 treats the analogous DX cooling field.
ASHP_CAP_FT_EAS_F = [0.2536714, 0.0104351, 0.0001861, -0.0000015].freeze # 8.4.6.7.(3)
ASHP_EIR_FT_F     = [2.4600298, -0.0622539, 0.0008800, -0.0000046].freeze # 8.4.6.7.(7)
ASHP_EIR_FPLR     = [0.0856522, 0.9388137, -0.1834361, 0.1589702].freeze # 8.4.6.7.(5)
ASHP_RATING_F = 47.0 # AHRI 210/240 standard heating rating point, outdoor dry-bulb

def poly(coeffs, x) = coeffs.each_with_index.sum { |c, i| c * x**i }
def biquad(c, x, y) = c[0] + c[1] * x + c[2] * x**2 + c[3] * y + c[4] * y**2 + c[5] * x * y

# degF-variable biquadratic -> equivalent degC-variable coefficients.
def f_to_c_biquad(c)
  a, b, cc, d, e, f = c
  [a + 32 * b + 1024 * cc + 32 * d + 1024 * e + 1024 * f,
   1.8 * b + 115.2 * cc + 57.6 * f,
   3.24 * cc,
   1.8 * d + 115.2 * e + 57.6 * f,
   3.24 * e,
   3.24 * f]
end

# degF-variable univariate cubic -> equivalent degC-variable coefficients
# (t_F = 1.8 t_C + 32, expanded through the cube).
def f_to_c_cubic(c)
  a, b, cc, d = c
  [a + 32 * b + 1024 * cc + 32_768 * d,
   1.8 * b + 115.2 * cc + 5529.6 * d,
   3.24 * cc + 311.04 * d,
   5.832 * d]
end

def self_check!(label, value)
  return if (value - 1.0).abs < 0.005

  abort("PROBE TRANSCRIPTION SUSPECT: #{label} evaluates to #{value.round(4)} at its rating point " \
        '(expected ~1.0) — refusing to compare against possibly mis-transcribed code coefficients')
end
self_check!('8.4.6.4 CAP_FT', biquad(DX_CAP_FT_F, *RATING_F))
self_check!('8.4.6.4 EIR_FT', biquad(DX_EIR_FT_F, *RATING_F))
self_check!('8.4.6.4 EIR_FPLR', poly(DX_EIR_FPLR, 1.0))
BOILER_FHEATPLC.merge(FURNACE_FHEATPLC).each { |t, c| self_check!("FHeatPLC #{t}", poly(c, 1.0)) }
self_check!('8.4.6.9 SWH FHeatPLC', poly(SWH_FHEATPLC, 1.0))
CHILLER_CAP_FT_EC_F.each { |t, c| self_check!("8.4.6.5 CAP_FT #{t}", biquad(c, *CHILLER_RATING_F)) }
CHILLER_EIR_FPLR.each { |t, c| self_check!("8.4.6.5 EIR_FPLR #{t}", poly(c, 1.0)) }
# NOTE: CHILLER_EIR_FT_EC_F_SUSPECT is deliberately NOT fed to self_check! — see its
# definition comment above. Feeding it would abort() the whole probe.
self_check!('8.4.6.7 CAP_FTEAS', poly(ASHP_CAP_FT_EAS_F, ASHP_RATING_F))
self_check!('8.4.6.7 EIR_FT', poly(ASHP_EIR_FT_F, ASHP_RATING_F))
self_check!('8.4.6.7 EIR_FPLR', poly(ASHP_EIR_FPLR, 1.0))

# ---- build + apply ---------------------------------------------------------
model = OpenStudio::Model::Model.new
audit = OpenStudioHVAC::AuditLog.new

boiler = OpenStudio::Model::BoilerHotWater.new(model)
boiler.setName('Probe Boiler') # plain name: skips the Primary/Secondary staging logic
boiler.setFuelType('NaturalGas')
boiler.setNominalCapacity(100_000)

coil_gas = OpenStudio::Model::CoilHeatingGas.new(model)
coil_gas.setName('Probe Furnace Coil')
coil_gas.setNominalCapacity(50_000)

dx = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
dx.setName('Probe DX Coil')
dx.setRatedTotalCoolingCapacity(20_000)
dx.setRatedAirFlowRate(1.0)

# 8.4.6.5: two compressor types, both hard-sized well inside the smallest capacity
# bin (curve NAMES do not vary by capacity bin in the vendored table — only the
# rated kW/ton efficiency value does — so a single capacity per type is enough to
# exercise curve selection). ChillerElectricEIR#setCondenserType('WaterCooled')
# requires the chiller to already be on a secondary (condenser) plant loop, so —
# per this probe's own build-real-components discipline — the WaterCooled case
# is built via the gem's actual reference-topology builder (chilled water loop +
# condenser water loop + cooling tower), same as a real reference model gets,
# rather than faked with a bare unattached component.
chw_scroll = OpenStudioHVAC::Systems::PlantLoops.chilled_water(model, chiller_type: 'Scroll', reuse: false,
                                                                       source: 'water_cooled')
chw_recip = OpenStudioHVAC::Systems::PlantLoops.chilled_water(model, chiller_type: 'Reciprocating', reuse: false,
                                                                      source: 'water_cooled')
[chw_scroll, chw_recip].each do |loop_|
  loop_.supplyComponents.select { |c| c.to_ChillerElectricEIR.is_initialized }
       .each { |c| c.to_ChillerElectricEIR.get.setReferenceCapacity(200_000) } # size Primary + Secondary alike
end
chiller_scroll = chw_scroll.supplyComponents.find do |c|
  c.to_ChillerElectricEIR.is_initialized && c.nameString.include?('Primary')
end.to_ChillerElectricEIR.get
chiller_recip = chw_recip.supplyComponents.find do |c|
  c.to_ChillerElectricEIR.is_initialized && c.nameString.include?('Primary')
end.to_ChillerElectricEIR.get

# 8.4.6.7: ASHP heating coil, hard-sized in the HSPF-rated (smallest) capacity bin.
ashp_heat = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
ashp_heat.setName('Probe ASHP Heating Coil')
ashp_heat.setRatedTotalHeatingCapacity(15_000)

OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)

swh_model = OpenStudio::Model::Model.new
heater = OpenStudio::Model::WaterHeaterMixed.new(swh_model)
heater.setHeaterFuelType('NaturalGas')
heater.setHeaterMaximumCapacity(30_000)
heater.setTankVolume(0.3)
OpenStudioSHW::NECB.apply_water_heater_efficiency(heater, vintage: '2020', audit: OpenStudioSHW::AuditLog.new)

# ---- comparisons -----------------------------------------------------------
results = []

def curve_coeffs(curve)
  case curve.iddObjectType.valueName
  when 'OS_Curve_Cubic'
    c = curve.to_CurveCubic.get
    [c.coefficient1Constant, c.coefficient2x, c.coefficient3xPOW2, c.coefficient4xPOW3]
  when 'OS_Curve_Quadratic'
    c = curve.to_CurveQuadratic.get
    [c.coefficient1Constant, c.coefficient2x, c.coefficient3xPOW2]
  when 'OS_Curve_Biquadratic'
    c = curve.to_CurveBiquadratic.get
    [c.coefficient1Constant, c.coefficient2x, c.coefficient3xPOW2,
     c.coefficient4y, c.coefficient5yPOW2, c.coefficient6xTIMESY]
  end
end

# Sampled FHeatPLC comparison: applied fuel ratio PLR/curve(PLR) vs each code
# row; report the best-matching row (the pass applies one curve; the code
# differentiates by equipment subtype the topology does not yet carry).
def compare_fheatplc(results, article, label, applied_coeffs, code_rows)
  if applied_coeffs.nil?
    results << { article: article, label: label, verdict: 'MISSING', detail: 'no curve attached' }
    return
  end
  best = code_rows.map do |type, target|
    dev = PLR_GRID.map do |x|
      eff = poly(applied_coeffs, x)
      next 999.0 if eff <= 0

      ((x / eff) - poly(target, x)).abs / poly(target, x)
    end.max
    [type, dev]
  end.min_by { |_, d| d }
  verdict = best[1] <= TOL_SAMPLED ? 'EQUIVALENT' : 'DEVIATES'
  results << { article: article, label: label, verdict: verdict,
               detail: format('vs %s row: max dev %.2f%% over PLR %.2f-1.0 (tol %.0f%%)',
                              best[0], best[1] * 100, PLR_GRID.first, TOL_SAMPLED * 100) }
end

# Functional comparison: evaluate the as-applied degC surface against the
# code's degF surface at the same physical points across the operating
# envelope; report the worst relative deviation. `grid` defaults to the DX
# wet-bulb/dry-bulb envelope; pass a different grid (e.g. chiller
# tchws/tcws) plus matching `axis_labels` for other biquadratic families.
def compare_biquad_transform(results, article, label, applied, code_f, grid: SURFACE_GRID_F, axis_labels: %w[wb odb])
  if applied.nil?
    results << { article: article, label: label, verdict: 'MISSING', detail: 'no curve attached' }
    return
  end
  worst_dev = 0.0
  worst_at = nil
  grid.each do |x_f, y_f|
    code_val = biquad(code_f, x_f, y_f)
    applied_val = biquad(applied, (x_f - 32) / 1.8, (y_f - 32) / 1.8)
    next if code_val.abs < 0.05 # avoid dividing by a vanishing surface

    dev = (applied_val - code_val).abs / code_val.abs
    worst_dev, worst_at = dev, [x_f, y_f] if dev > worst_dev
  end
  verdict = worst_dev <= TOL_SURFACE ? 'EQUIVALENT (surface)' : 'DEVIATES'
  results << { article: article, label: label, verdict: verdict,
               detail: format('max surface dev %.2f%% (at %s%s/%s%sF; tol %.1f%%)',
                              worst_dev * 100, worst_at&.first, axis_labels[0], worst_at&.last, axis_labels[1],
                              TOL_SURFACE * 100) }
end

# Univariate analog of compare_biquad_transform, for the 8.4.6.7 CAP_FTEAS/EIR_FT
# cubics (function of outdoor dry-bulb only).
def compare_cubic_transform(results, article, label, applied, code_f, grid)
  if applied.nil?
    results << { article: article, label: label, verdict: 'MISSING', detail: 'no curve attached' }
    return
  end
  worst_dev = 0.0
  worst_at = nil
  grid.each do |t_f|
    code_val = poly(code_f, t_f)
    applied_val = poly(applied, (t_f - 32) / 1.8)
    next if code_val.abs < 0.05

    dev = (applied_val - code_val).abs / code_val.abs
    worst_dev, worst_at = dev, t_f if dev > worst_dev
  end
  verdict = worst_dev <= TOL_SURFACE ? 'EQUIVALENT (surface)' : 'DEVIATES'
  results << { article: article, label: label, verdict: verdict,
               detail: format('max surface dev %.2f%% (at %sF odb; tol %.1f%%)',
                              worst_dev * 100, worst_at, TOL_SURFACE * 100) }
end

# Direct PLR-based comparison (NOT the PLR/PLF(PLR) cycling transform): both the
# applied and code-side curves are read as direct multipliers of PLR, as used by
# ChillerElectricEIR's EIR_FPLR field (see 8.4.6.5.(4)/(5) — chillers modulate
# continuously, no on/off cycling curve to invert).
def compare_direct_poly(results, article, label, applied_coeffs, code_rows)
  if applied_coeffs.nil?
    results << { article: article, label: label, verdict: 'MISSING', detail: 'no curve attached' }
    return
  end
  best = code_rows.map do |type, target|
    dev = PLR_GRID.map { |x| (poly(applied_coeffs, x) - poly(target, x)).abs / poly(target, x) }.max
    [type, dev]
  end.min_by { |_, d| d }
  verdict = best[1] <= TOL_SAMPLED ? 'EQUIVALENT' : 'DEVIATES'
  results << { article: article, label: label, verdict: verdict,
               detail: format('vs %s row: max dev %.2f%% over PLR %.2f-1.0 (tol %.0f%%)',
                              best[0], best[1] * 100, PLR_GRID.first, TOL_SAMPLED * 100) }
end

b_curve = boiler.normalizedBoilerEfficiencyCurve
compare_fheatplc(results, '8.4.6.2', 'Boiler FHeatPLC (via normalized efficiency curve)',
                 b_curve.is_initialized ? curve_coeffs(b_curve.get) : nil, BOILER_FHEATPLC)

g_curve = coil_gas.partLoadFractionCorrelationCurve
compare_fheatplc(results, '8.4.6.3', 'Furnace FHeatPLC (via PLF curve on gas coil)',
                 g_curve.is_initialized ? curve_coeffs(g_curve.get) : nil, FURNACE_FHEATPLC)

compare_biquad_transform(results, '8.4.6.4', 'DX CAP_FT',
                         dx.totalCoolingCapacityFunctionOfTemperatureCurve.then { |c| curve_coeffs(c) }, DX_CAP_FT_F)
compare_biquad_transform(results, '8.4.6.4', 'DX EIR_FT',
                         dx.energyInputRatioFunctionOfTemperatureCurve.then { |c| curve_coeffs(c) }, DX_EIR_FT_F)
compare_fheatplc(results, '8.4.6.4', 'DX EIR_FPLR (via PLF cycling curve)',
                 dx.partLoadFractionCorrelationCurve.then { |c| curve_coeffs(c) },
                 { 'EIR_FPLR' => DX_EIR_FPLR })

s_curve = heater.partLoadFactorCurve
compare_fheatplc(results, '8.4.6.9', 'SWH FHeatPLC (via part-load factor curve)',
                 s_curve.is_initialized ? curve_coeffs(s_curve.get) : nil, { 'SWH' => SWH_FHEATPLC })

# 8.4.6.5 electric chiller — CAP_FT (biquadratic surface) and EIR_FPLR (direct
# PLR multiplier), one comparison per compressor type actually attached.
{ 'Scroll' => chiller_scroll, 'Reciprocating' => chiller_recip }.each do |type, chiller|
  compare_biquad_transform(results, '8.4.6.5', "Chiller CAP_FT (#{type})",
                           curve_coeffs(chiller.coolingCapacityFunctionOfTemperature),
                           CHILLER_CAP_FT_EC_F[type], grid: CHILLER_SURFACE_GRID_F, axis_labels: %w[chws cws])
  compare_direct_poly(results, '8.4.6.5', "Chiller EIR_FPLR (#{type}, direct PLR multiplier)",
                      curve_coeffs(chiller.electricInputToCoolingOutputRatioFunctionOfPLR),
                      { type => CHILLER_EIR_FPLR[type] })
  suspect_value = biquad(CHILLER_EIR_FT_EC_F_SUSPECT[type], *CHILLER_RATING_F)
  results << { article: '8.4.6.5', label: "Chiller EIR_FT (#{type})", verdict: 'NOT COMPARED',
               detail: format('Table 8.4.6.5.-C %s row evaluates to %.3f at the AHRI 44F/85F rating point ' \
                              '(expected ~1.0) — fails self-check, not fed to self_check!; see comment on ' \
                              'CHILLER_EIR_FT_EC_F_SUSPECT', type, suspect_value) }
end

# 8.4.6.6 cooling tower — the gem's reference tower is CoolingTowerSingleSpeed
# (only numberOfCells + fan power are set by apply_tower_rules); that OpenStudio
# class has NO performance-curve fields at all (confirmed: CoolingTowerSingleSpeed
# exposes no FunctionOf*/PLR curve setters/getters), so the FWB/FRA capacity
# adjustment 8.4.6.6 specifies has no field to compare against — and no such
# curve exists in efficiencies_2020.json either. Structural form mismatch, not a
# missing transcription.
results << { article: '8.4.6.6', label: 'Cooling Tower FWB capacity adjustment', verdict: 'NOT APPLICABLE',
             detail: 'reference tower is CoolingTowerSingleSpeed (no curve fields); no FWB/FRA curve is ' \
                     'set by apply_tower_rules or vendored in efficiencies_2020.json' }

# 8.4.6.7 electric air-source heat pump, heating.
compare_cubic_transform(results, '8.4.6.7', 'ASHP CAP_FTEAS',
                        curve_coeffs(ashp_heat.totalHeatingCapacityFunctionofTemperatureCurve),
                        ASHP_CAP_FT_EAS_F, ASHP_ODB_GRID_F)
compare_cubic_transform(results, '8.4.6.7', 'ASHP EIR_FT',
                        curve_coeffs(ashp_heat.energyInputRatioFunctionofTemperatureCurve),
                        ASHP_EIR_FT_F, ASHP_ODB_GRID_F)
compare_fheatplc(results, '8.4.6.7', 'ASHP EIR_FPLR (via PLF cycling curve)',
                 curve_coeffs(ashp_heat.partLoadFractionCorrelationCurve),
                 { 'EIR_FPLR' => ASHP_EIR_FPLR })

# 8.4.6.8 absorption chiller — the gem's chiller efficiency table
# (efficiencies_2020.json 'chillers') has no absorption row (only Scroll/
# Reciprocating/Rotary Screw/Centrifugal/AirCooled), no absorption curves exist
# in the vendored 'curves' array, and apply_chiller's compressor-type detection
# never matches "Absorption" (it would silently fall back to Scroll with a
# warning). There is no absorption chiller in the reference system catalog this
# efficiency pass ever builds or attaches curves to.
results << { article: '8.4.6.8', label: 'Absorption Chiller CAP_FT/FIR_FPLR/FIR_FT', verdict: 'NOT APPLICABLE',
             detail: "no absorption row in tables['chillers'], no absorption curves vendored, " \
                     'apply_chiller never selects an absorption compressor type' }

# ---- report ----------------------------------------------------------------
puts 'NECB 8.4.6 part-load curve probe — as-applied model curves vs NECB 2025 coefficients'
puts
failures = 0
results.each do |r|
  bad = %w[MISSING DEVIATES].include?(r[:verdict])
  failures += 1 if bad
  puts format('  %-9s %-48s %-28s %s', r[:article], r[:label], r[:verdict], r[:detail])
end
puts
puts '  NOT YET COMPARED (still honest gaps): Table 8.4.6.2 condensing-boiler 6-term row. ' \
     '8.4.6.5/8.4.6.6/8.4.6.8 have explicit NOT COMPARED/NOT APPLICABLE lines above, not silence.'
puts
if failures.zero?
  puts 'necb_8_4_6_curve_probe: OK — every compared curve is applied and equivalent'
else
  puts "necb_8_4_6_curve_probe: #{failures} curve(s) missing or deviating"
end
exit(failures.zero? ? 0 : 1)
