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
# envelope; report the worst relative deviation.
def compare_biquad_transform(results, article, label, applied, code_f)
  if applied.nil?
    results << { article: article, label: label, verdict: 'MISSING', detail: 'no curve attached' }
    return
  end
  worst_dev = 0.0
  worst_at = nil
  SURFACE_GRID_F.each do |wb_f, db_f|
    code_val = biquad(code_f, wb_f, db_f)
    applied_val = biquad(applied, (wb_f - 32) / 1.8, (db_f - 32) / 1.8)
    next if code_val.abs < 0.05 # avoid dividing by a vanishing surface

    dev = (applied_val - code_val).abs / code_val.abs
    worst_dev, worst_at = dev, [wb_f, db_f] if dev > worst_dev
  end
  verdict = worst_dev <= TOL_SURFACE ? 'EQUIVALENT (surface)' : 'DEVIATES'
  results << { article: article, label: label, verdict: verdict,
               detail: format('max surface dev %.2f%% (at %swb/%sF odb; tol %.1f%%)',
                              worst_dev * 100, worst_at&.first, worst_at&.last, TOL_SURFACE * 100) }
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
puts '  NOT YET COMPARED (still honest gaps): 8.4.6.5 electric chiller (per-type tables -A/-B/-C), ' \
     '8.4.6.6 cooling tower, 8.4.6.7 air-source heat pump, 8.4.6.8 absorption chiller, ' \
     'Table 8.4.6.2 condensing-boiler 6-term row.'
puts
if failures.zero?
  puts 'necb_8_4_6_curve_probe: OK — every compared curve is applied and equivalent'
else
  puts "necb_8_4_6_curve_probe: #{failures} curve(s) missing or deviating"
end
exit(failures.zero? ? 0 : 1)
