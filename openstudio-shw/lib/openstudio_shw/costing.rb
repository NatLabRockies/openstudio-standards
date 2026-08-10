begin
  require 'openstudio_hvac'
rescue LoadError
  require File.expand_path('../../../openstudio-hvac/lib/openstudio_hvac', __dir__)
end

module OpenStudioSHW
  # SHW costing — port of legacy shw_costing.rb on top of the openstudio-hvac
  # costing engine (Database/materials_hvac, Ledger with per-item regional
  # factors, Geometry.building_data distances): tanks by fuel/efficiency class
  # with the largest-row multiplier rule, power vents for high-efficiency tanks,
  # flues (galvanized for regular fuel tanks incl. 20 ft headers; PVC for HE),
  # electric utility runs, gas/oil fuel lines, pumps (+VFD for variable), and the
  # 10 ft-per-pump tank piping BOM. Distribution costing was never enabled in
  # legacy (shw_distribution_costing exists but is not called) — same here.
  #
  # LEGACY DEFECT (fixed, audited; also fixed upstream by #2119): legacy gated the
  # gas fuel-line branch on `num_reg_gas_tanks + num_reg_gas_tanks` (the same
  # variable twice), so buildings whose ONLY gas tanks are high-efficiency got no
  # fuel line; both this port and the upstream legacy fix now use regular +
  # high-efficiency as intended, so behavior matches on both sides.
  module Costing
    Report = Struct.new(:total, :shw, :warnings, :city, :province_state, :audit, keyword_init: true)

    module_function

    def cost(model, city: nil, province_state: nil, costs_csv: nil, audit: nil)
      audit ||= AuditLog.new
      database = OpenStudioHVAC::Costing::Database.new(costs_csv: costs_csv)
      if city.nil? || province_state.nil?
        site = model.getSite
        location = database.closest_location(site.latitude, site.longitude)
        city ||= location['city']
        province_state ||= location['province_state']
      end

      ledger = OpenStudioHVAC::Costing::Ledger.new
      quantifier = OpenStudioHVAC::Costing::EquipmentQuantifier.new(database, ledger, audit: audit)
      geo = OpenStudioHVAC::Costing::Geometry.building_data(model)
      counts = { tanks: 0, hphw: 0, reg_gas: 0, he_gas: 0, reg_oil: 0, he_oil: 0, elec: 0, pumps: 0 }

      model.getPlantLoops.sort_by(&:nameString).each do |loop|
        next unless loop.nameString =~ /Main Service Water Loop/i

        loop.supplyComponents.each do |component|
          if component.to_WaterHeaterMixed.is_initialized
            cost_tank(component.to_WaterHeaterMixed.get, quantifier, counts, audit)
          elsif component.to_PumpConstantSpeed.is_initialized || component.to_PumpVariableSpeed.is_initialized
            cost_pump(component, quantifier, counts, audit)
          end
        end
      end

      if counts[:tanks].positive?
        cost_site_work(quantifier, counts, geo, audit)
        cost_pump_piping(quantifier, counts, audit)
      else
        audit.info(:costing_shw, 'no Main Service Water Loop tanks found — nothing costed')
      end

      priced = ledger.price(database, province_state: province_state, city: city)
      database.warnings.each { |w| audit.warn(:costing_shw, w) }
      quantifier.warnings.each { |w| audit.warn(:costing_shw, w) }
      total = priced['total']
      audit.decision(:costing_shw, 'service water heating costed',
                     inputs: counts.merge(city: city), value: "$#{total.round(2)}")
      Report.new(total: total.round(2),
                 shw: counts.merge('items' => priced['items'].size),
                 warnings: audit.warnings.map { |w| w[:action] },
                 city: city, province_state: province_state, audit: audit)
    end

    def cost_tank(tank, quantifier, counts, audit)
      capacity_kw = (tank.heaterMaximumCapacity.is_initialized ? tank.heaterMaximumCapacity.get : 0.0) / 1000.0
      volume_gal = OpenStudio.convert(tank.tankVolume.is_initialized ? tank.tankVolume.get : 0.0, 'm^3', 'gal').get
      efficiency = tank.heaterThermalEfficiency.is_initialized ? tank.heaterThermalEfficiency.get : 0.0
      high_efficiency = efficiency >= 0.85

      hphw_tanks = tank.model.getWaterHeaterHeatPumps.map { |hp| hp.tank.nameString } +
                   tank.model.getWaterHeaterHeatPumpWrappedCondensers.map { |hp| hp.tank.nameString }
      lookup, count_key =
        case tank.heaterFuelType
        when /Electric/i
          hphw_tanks.include?(tank.nameString) ? %w[HPHW_Heater hphw] : %w[WaterElec elec]
        when /NaturalGas/i then high_efficiency ? %w[WaterGas_HE he_gas] : %w[WaterGas reg_gas]
        when /Oil/i then high_efficiency ? %w[WaterOil_HE he_oil] : %w[WaterOil reg_oil]
        else
          audit.warn(:costing_shw, "tank fuel '#{tank.heaterFuelType}' not costable — skipped", target: tank.nameString)
          return
        end

      units = quantifier.add(lookup, capacity_kw, %w[SHW], "SHW tank #{tank.nameString}") || 0
      counts[count_key.to_sym] += units
      counts[:tanks] += units
      return unless high_efficiency && units.positive?

      vent_size = capacity_kw < 200 ? 0.125 : 0.5
      quantifier.add('Waterheater_power_vent', vent_size, %w[SHW],
                     "power vent for HE tank #{tank.nameString}", count: units)
      _ = volume_gal # volume participates in legacy elec/oil row selection via the Size column
    end

    def cost_pump(component, quantifier, counts, audit)
      pump = component.to_PumpConstantSpeed.is_initialized ? component.to_PumpConstantSpeed.get : component.to_PumpVariableSpeed.get
      watts = if pump.ratedPowerConsumption.is_initialized
                pump.ratedPowerConsumption.get
              elsif pump.respond_to?(:autosizedRatedPowerConsumption) && pump.autosizedRatedPowerConsumption.is_initialized
                pump.autosizedRatedPowerConsumption.get
              else
                audit.warn(:costing_shw, "pump #{pump.nameString} has no rated power (unsized) — costed at the smallest row")
                0.0
              end
      quantifier.add('Pumps', watts, %w[SHW], "SHW pump #{pump.nameString}")
      quantifier.add('VFD', watts, %w[SHW], "VFD for #{pump.nameString}") if component.to_PumpVariableSpeed.is_initialized
      counts[:pumps] += 1
    end

    def cost_site_work(quantifier, counts, geo, audit)
      if geo.nil?
        audit.warn(:costing_shw, 'building geometry unresolved — utility runs and flues NOT costed')
        return
      end
      util = geo[:util_dist_ft]
      ht_roof = geo[:ht_roof_ft]

      non_hphw = counts[:tanks] - counts[:hphw]
      if non_hphw.positive? # legacy: HPHW tanks are excluded from the electric utility run
        quantifier.add('Conduit', nil, %w[SHW], 'SHW electric utility conduit', count: util * non_hphw)
        quantifier.add('Wiring', 14, %w[SHW], 'SHW electric utility wire', count: util / 100.0 * non_hphw)
      end

      reg_fuel = counts[:reg_gas] + counts[:reg_oil]
      he_fuel = counts[:he_gas] + counts[:he_oil]
      if reg_fuel.positive?
        quantifier.add('Venting', 6, %w[SHW], 'SHW flue', count: ht_roof)
        quantifier.add('VentingElbow', 6, %w[SHW], 'SHW flue elbow')
        quantifier.add('VentingTop', 6, %w[SHW], 'SHW flue top')
        if reg_fuel > 1
          quantifier.add('Venting', 6, %w[SHW], 'SHW flue header (20 ft per extra tank)', count: 20.0 * (reg_fuel - 1))
          quantifier.add('VentingElbow', 6, %w[SHW], 'SHW flue header elbow', count: (reg_fuel - 1).to_f)
        end
      end
      if he_fuel.positive?
        quantifier.add('Vent_pvc', 6, %w[SHW], 'SHW PVC flue (HE)', count: 20.0 * he_fuel)
        quantifier.add('Vent_pvc_coupling', 6, %w[SHW], 'SHW PVC flue coupling', count: he_fuel.to_f)
        quantifier.add('Vent_pvc_elbow', 6, %w[SHW], 'SHW PVC flue elbow', count: he_fuel.to_f)
      end

      gas = counts[:reg_gas] + counts[:he_gas] # legacy defect fixed (both sides since #2119): HE-only gas got no fuel line
      oil = counts[:reg_oil] + counts[:he_oil]
      if gas.positive?
        quantifier.add('GasLine', nil, %w[SHW], 'SHW fuel line', count: util * gas)
        quantifier.add('GasLine', 4, %w[SHW], 'SHW fuel line fitting', count: gas.to_f)
      elsif oil.positive?
        quantifier.add('OilLine', nil, %w[SHW], 'SHW oil filtering system')
        quantifier.add('OilTanks', 2000, %w[SHW], 'SHW oil storage tank (2000 USG)')
        quantifier.add('GasLine', nil, %w[SHW], 'SHW oil fuel line', count: util * oil)
        quantifier.add('GasLine', 4, %w[SHW], 'SHW oil fuel line fitting', count: oil.to_f)
      end
    end

    def cost_pump_piping(quantifier, counts, _audit)
      pumps = counts[:pumps]
      return unless pumps.positive?

      quantifier.add('SteelPipe', 1, %w[SHW], 'SHW tank-to-pump piping (10 ft/pump)', count: 10.0 * pumps)
      quantifier.add('PipeInsulation', 1, %w[SHW], 'SHW pipe insulation', count: 10.0 * pumps)
      quantifier.add('SteelPipeElbow', 1, %w[SHW], 'SHW pipe elbows', count: 2.0 * pumps)
      quantifier.add('ValvesGate', 1, %w[SHW], 'SHW gate valves', count: 1.0 * pumps)
    end
  end

  # Cost the model's service water heating (legacy shw_costing port on the
  # openstudio-hvac costing engine).
  def self.cost(model, **kwargs)
    Costing.cost(model, **kwargs)
  end
end
