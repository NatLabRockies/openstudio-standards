require_relative 'test_helper'

# Parity vs legacy: (1) auto-size arithmetic + water-use objects vs
# model_add_swh; (2) efficiency values across every bin vs the NECB2020
# water_heater_mixed_apply_efficiency. Repo bundle only.
class TestSHWParity < Minitest::Test
  include FixtureHelper

  def self.legacy
    @legacy ||= begin
      require File.expand_path('../../lib/openstudio-standards', __dir__)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy
    skip 'openstudio-standards not loadable — parity gate runs from the monorepo' if std == :unavailable
    std
  end

  def optional(value)
    value.is_initialized ? value.get : nil
  end

  def test_demand_and_tank_parity
    std = legacy
    legacy_model = tagged_model
    std.model_add_swh(model: legacy_model, swh_fueltype: 'NaturalGas', shw_scale: 1.0)

    gem_model = tagged_model
    OpenStudioSHW.apply_shw(gem_model, vintage: '2020', fuel: 'NaturalGas')

    legacy_heater = legacy_model.getWaterHeaterMixeds.first
    gem_heater = gem_model.getWaterHeaterMixeds.first
    refute_nil legacy_heater
    refute_nil gem_heater
    assert_in_delta optional(legacy_heater.tankVolume), optional(gem_heater.tankVolume), 1e-9,
                    'tank volume (legacy peak-hour rule)'
    assert_in_delta optional(legacy_heater.heaterMaximumCapacity), optional(gem_heater.heaterMaximumCapacity),
                    optional(legacy_heater.heaterMaximumCapacity) * 1e-6, 'tank capacity'
    assert_in_delta legacy_heater.onCycleParasiticFuelConsumptionRate,
                    gem_heater.onCycleParasiticFuelConsumptionRate, 1e-6, 'parasitic loss'
    assert_equal legacy_heater.heaterFuelType, gem_heater.heaterFuelType

    legacy_wue = legacy_model.getWaterUseEquipments.sort_by { |w| w.space.get.nameString }
    gem_wue = gem_model.getWaterUseEquipments.sort_by { |w| w.space.get.nameString }
    assert_equal legacy_wue.size, gem_wue.size, 'same demanding spaces'
    legacy_wue.zip(gem_wue).each do |l, g|
      assert_equal l.space.get.nameString, g.space.get.nameString
      assert_in_delta l.waterUseEquipmentDefinition.peakFlowRate,
                      g.waterUseEquipmentDefinition.peakFlowRate, 1e-12,
                      "peak flow for #{l.space.get.nameString}"
      assert_equal optional(l.flowRateFractionSchedule)&.nameString,
                   optional(g.flowRateFractionSchedule)&.nameString
    end
  end

  def test_efficiency_parity_every_bin
    std = legacy
    cases = [
      ['Electricity', 11_000, 0.200],   # electric small, low volume
      ['Electricity', 11_000, 0.300],   # electric small, >=270 L formula
      ['Electricity', 40_000, 0.300],   # electric large
      ['NaturalGas', 15_000, 0.100],    # gas 76-208 L (FHR 221 -> 193-284 bin)
      ['NaturalGas', 15_000, 0.150],    # gas 76-208 L (FHR 256)
      ['NaturalGas', 20_000, 0.300],    # gas 208-380 L (FHR 361 -> >=284 bin)
      ['NaturalGas', 25_000, 0.400],    # gas 22-30.5 kW row
      ['NaturalGas', 100_000, 0.500],   # large gas: Et + SL
      ['FuelOilNo2', 15_000, 0.150]     # oil follows the gas path (legacy)
    ]
    mismatches = []
    cases.each do |fuel, capacity_w, volume_m3|
      legacy_model = OpenStudio::Model::Model.new
      legacy_heater = OpenStudio::Model::WaterHeaterMixed.new(legacy_model)
      legacy_heater.setTankVolume(volume_m3)
      legacy_heater.setHeaterMaximumCapacity(capacity_w)
      legacy_heater.setHeaterFuelType(fuel)
      std.water_heater_mixed_apply_efficiency(legacy_heater)

      gem_model = OpenStudio::Model::Model.new
      gem_heater = OpenStudio::Model::WaterHeaterMixed.new(gem_model)
      gem_heater.setTankVolume(volume_m3)
      gem_heater.setHeaterMaximumCapacity(capacity_w)
      gem_heater.setHeaterFuelType(fuel)
      OpenStudioSHW::NECB.apply_water_heater_efficiency(gem_heater, vintage: '2020')

      eff_delta = (optional(legacy_heater.heaterThermalEfficiency) - optional(gem_heater.heaterThermalEfficiency)).abs
      ua_l = optional(legacy_heater.offCycleLossCoefficienttoAmbientTemperature)
      ua_g = optional(gem_heater.offCycleLossCoefficienttoAmbientTemperature)
      curve_l = legacy_heater.partLoadFactorCurve.is_initialized
      curve_g = gem_heater.partLoadFactorCurve.is_initialized
      next if eff_delta < 1e-9 && (ua_l - ua_g).abs < 1e-9 && curve_l == curve_g &&
              legacy_heater.offCycleParasiticHeatFractiontoTank == gem_heater.offCycleParasiticHeatFractiontoTank

      mismatches << "#{fuel} #{capacity_w}W #{volume_m3}m3: eff #{optional(legacy_heater.heaterThermalEfficiency)} vs " \
                    "#{optional(gem_heater.heaterThermalEfficiency)}; UA #{ua_l} vs #{ua_g}; curve #{curve_l}/#{curve_g}"
    end
    assert_empty mismatches, "efficiency parity mismatches:\n#{mismatches.join("\n")}"
  end
end
