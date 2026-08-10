module OpenStudioSHW
  module NECB
    # SHW demand + plant — port of legacy model_add_swh / auto_size_shw_capacity:
    # per-space peak flows from the NECB space-type records (US gal/hr/ft2 x area x
    # scale), the weekly hourly demand profile from the NECB-<letter> SWH schedules
    # (Default|Wkdy / Sat / Sun|Hol rows), the peak-hour + next-hour tank sizing
    # rule, and a WaterHeaterMixed loop with per-space WaterUseEquipment.
    #
    # DEVIATION (audited): pump head uses the legacy DEFAULT (179532 Pa, the
    # OpenStudio constant-speed default) — the legacy geometric mech-room
    # piping-run head calculation is a documented future.
    module Demand
      module_function

      DAY_KEYS = ['Default|Wkdy', 'Sat', 'Sun|Hol'].freeze
      NEXT_DAY = { 'Default|Wkdy' => 'Sat', 'Sat' => 'Sun|Hol', 'Sun|Hol' => 'Default|Wkdy' }.freeze

      # Auto-size the SHW tank/plant from the space-type demand (legacy-exact).
      # @return [Hash] tank volume/capacity (SI), max temp, loop peak flow,
      #   parasitic loss, spaces_w_dhw
      def auto_size(model, vintage: '2020', shw_scale: 1.0, audit: nil)
        rules = NECB.rules(vintage)['autosize']
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        schedules = OpenStudioLoads::NECB.table(data_vintage, 'schedules')
        shw_scale = 1.0 if shw_scale.nil? || shw_scale == 'none' || shw_scale == 'NECB_Default'
        shw_scale = shw_scale.to_s.strip.to_f if shw_scale.is_a?(String)

        weekly = DAY_KEYS.to_h { |k| [k, Array.new(24, 0.0)] }
        total_peak = 0.0
        peak_sched = 0.0
        spaces = []

        model.getSpaces.sort_by(&:nameString).each do |space|
          next if space.spaceType.empty? || space.spaceType.get.standardsSpaceType.empty? ||
                  space.spaceType.get.standardsBuildingType.empty?

          record = OpenStudioLoads::NECB::SpaceTypes.find(
            building_type: space.spaceType.get.standardsBuildingType.get,
            space_type: space.spaceType.get.standardsSpaceType.get, vintage: data_vintage)
          next if record.nil? || OpenStudioLoads::NECB::SpaceTypes.undefined?(record)
          next if record['service_water_heating_peak_flow_per_area'].to_f.zero? &&
                  record['service_water_heating_peak_flow_rate'].to_f.zero?
          next if record['service_water_heating_schedule'].nil?

          area_ft2 = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get
          peak_ind = record['service_water_heating_peak_flow_per_area'].to_f * area_ft2 * shw_scale
          peak = peak_ind * space.multiplier
          total_peak += peak

          temperature = record['service_water_heating_target_temperature']
          temperature = 60 if temperature.nil? || temperature.to_f <= 16
          spaces << { 'space' => space,
                      'peak_flow_si' => OpenStudio.convert(peak, 'gal/hr', 'm^3/s').get,
                      'peak_flow_ind_si' => OpenStudio.convert(peak_ind, 'gal/hr', 'm^3/s').get,
                      'temperature_c' => temperature.to_f,
                      'schedule' => record['service_water_heating_schedule'] }

          DAY_KEYS.each do |day|
            row = schedules.find { |r| r['name'] == record['service_water_heating_schedule'] && r['day_types'] == day }
            raise(ArgumentError, "SWH schedule #{record['service_water_heating_schedule']} lacks a '#{day}' row") if row.nil? || row['values'].size != 24

            row['values'].each_with_index do |fraction, hour|
              weekly[day][hour] += fraction.to_f * peak
              peak_sched = weekly[day][hour] if weekly[day][hour] > peak_sched
            end
          end
        end

        if spaces.empty?
          return { 'tank_volume_si' => 0, 'tank_capacity_si' => 0, 'max_temp_c' => 60,
                   'loop_peak_flow_si' => 0, 'parasitic_loss_w' => 0, 'spaces_w_dhw' => [] }
        end

        # the hour AFTER the peak hour(s) with the highest demand — LEGACY-EXACT.
        # Hours are iterated in HOUR ORDER (true adjacency). Legacy history: the
        # original auto_size_shw_capacity iterated the SORTED hourly array while
        # indexing the UNSORTED one for "next hour" (an arbitrary hour, smaller
        # tanks); upstream PR #2119 (merged 2026-07-15) fixed it to hour order,
        # and this gem flipped with it (D-68) — the parity gate compares live.
        next_hour_flow = 0.0
        DAY_KEYS.each do |day|
          weekly[day].each_with_index do |flow, hour_index|
            next unless flow == peak_sched

            next_day = hour_index == 23 ? NEXT_DAY[day] : day
            next_hour = hour_index == 23 ? 0 : hour_index + 1
            candidate = weekly[next_day][next_hour]
            next_hour_flow = candidate if candidate > next_hour_flow
          end
        end

        tank_volume_gal = peak_sched
        peak_time_fraction = 1 - (peak_sched / total_peak)
        if peak_time_fraction <= 0.2
          tank_volume_gal += next_hour_flow
          peak_time_fraction = 1
        end
        tank_volume_si = OpenStudio.convert(tank_volume_gal, 'gal', 'm^3').get
        max_temp = spaces.map { |s| s['temperature_c'] }.max
        tank_capacity_si = tank_volume_si * 1000 * 4180 * (max_temp - rules['cold_water_inlet_c']) /
                           (3600 * peak_time_fraction)
        radius = (tank_volume_si / (rules['tank_height_to_radius'] * Math::PI))**(1.0 / 3)
        area = 2 * (1 + rules['tank_height_to_radius']) * Math::PI * radius**2
        room_c = OpenStudio.convert(rules['ambient_f'], 'F', 'C').get
        parasitic = rules['tank_u_w_per_m2k'] * area * (max_temp - room_c)

        audit&.decision(:shw, 'SHW plant auto-sized from space-type demand (legacy tank rule: peak hour ' \
                              '+ next hour when recovery time is short)',
                        inputs: { spaces_with_dhw: spaces.size,
                                  total_peak_gal_hr: total_peak.round(2),
                                  peak_hour_gal: peak_sched.round(2),
                                  tank_volume_l: (tank_volume_si * 1000).round(1),
                                  tank_capacity_kw: (tank_capacity_si / 1000).round(2),
                                  supply_c: max_temp, parasitic_w: parasitic.round(1) },
                        article: '8.4.3.2. (SWH loads); 6.2.2.1.')
        { 'tank_volume_si' => tank_volume_si, 'tank_capacity_si' => tank_capacity_si,
          'max_temp_c' => max_temp, 'loop_peak_flow_si' => OpenStudio.convert(total_peak, 'gal/hr', 'm^3/s').get,
          'parasitic_loss_w' => parasitic, 'spaces_w_dhw' => spaces }
      end

      # Build the full SHW system: auto-size, create the loop + water heater +
      # pump, one WaterUseConnections/WaterUseEquipment per demanding space, apply
      # Part 6 efficiency on the sized heater.
      # @param fuel ['NaturalGas', 'Electricity', 'FuelOilNo2', 'HeatPump'] —
      #   'HeatPump' builds an air-source WaterHeaterHeatPump (pumped condenser)
      #   around the tank, with the code EF/UEF floor as the coil's rated COP
      def apply_shw(model, vintage: '2020', fuel: 'NaturalGas', shw_scale: 1.0, audit: nil)
        audit ||= AuditLog.new
        sizing = auto_size(model, vintage: vintage, shw_scale: shw_scale, audit: audit)
        if sizing['loop_peak_flow_si'].zero?
          audit.info(:shw, 'no space calls for service hot water — no SHW loop added (legacy behavior)')
          return nil
        end

        rules = NECB.rules(vintage)['autosize']
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        heat_pump = fuel.to_s == 'HeatPump'
        loop = build_loop(model, sizing, heat_pump ? 'Electricity' : fuel, rules, audit)

        sizing['spaces_w_dhw'].each do |entry|
          add_water_use(model, loop, entry, data_vintage, audit)
        end

        tank = loop.supplyComponents(OpenStudio::Model::WaterHeaterMixed.iddObjectType)
                   .map { |c| c.to_WaterHeaterMixed.get }.first
        if heat_pump
          hpwh = wrap_heat_pump(model, tank, sizing, audit)
          Efficiency.apply_heat_pump_efficiency(hpwh, vintage: vintage, audit: audit)
        else
          Efficiency.apply_efficiency(tank, vintage: vintage, audit: audit)
        end
        audit.decision(:shw, 'service water heating added',
                       inputs: { fuel: fuel, spaces: sizing['spaces_w_dhw'].size },
                       article: '8.4.3.2. (SWH loads)')
        loop
      end

      # Air-source heat-pump water heater (8.4.4.20.(2) energy type): a pumped-
      # condenser WaterHeaterHeatPump wrapping the loop tank, placed in the zone
      # of the largest demanding space (the compressor draws from and rejects to
      # that zone's air). The legacy family only ever COSTED HPWH tanks; the
      # detailed stratified-tank/EMS recipe upstream is deliberately not ported —
      # this is the bounded SDK construction, audited.
      def wrap_heat_pump(model, tank, sizing, audit)
        hpwh = OpenStudio::Model::WaterHeaterHeatPump.new(model)
        hpwh.setName("#{(sizing['tank_volume_si'] * 1000).round}L HPWH")
        default_tank = hpwh.tank
        hpwh.setTank(tank)
        default_tank.remove

        zone_space = sizing['spaces_w_dhw'].max_by { |e| e['space'].floorArea }['space']
        if zone_space.thermalZone.is_initialized
          hpwh.addToThermalZone(zone_space.thermalZone.get)
          audit.info(:shw, 'HPWH compressor placed in the largest demanding space\'s zone',
                     target: zone_space.thermalZone.get.nameString)
        else
          audit.warn(:shw, 'HPWH has no zone (largest demanding space is unzoned) — ambient defaults apply')
        end
        hpwh
      end

      def build_loop(model, sizing, fuel, rules, audit)
        loop = OpenStudio::Model::PlantLoop.new(model)
        loop.setName('Main Service Water Loop')
        loop.setMaximumLoopTemperature(60.0)
        sizing_plant = loop.sizingPlant
        sizing_plant.setLoopType('Heating')
        sizing_plant.setDesignLoopExitTemperature(sizing['max_temp_c'])
        sizing_plant.setLoopDesignTemperatureDifference(5.0)

        setpoint = constant_schedule(model, "SHW Temp #{sizing['max_temp_c']}C", sizing['max_temp_c'])
        manager = OpenStudio::Model::SetpointManagerScheduled.new(model, setpoint)
        manager.setName('Main Service Water Loop Setpoint Manager')
        manager.addToNode(loop.supplyOutletNode)

        pump = OpenStudio::Model::PumpConstantSpeed.new(model)
        pump.setName('Main Service Water Loop Pump')
        pump.setRatedPumpHead(rules['pump_head_pa'])
        pump.setMotorEfficiency(rules['pump_motor_efficiency'])
        pump.setPumpControlType('Intermittent')
        pump.addToNode(loop.supplyInletNode)
        audit.info(:shw, "pump head set to the OpenStudio constant-speed default #{rules['pump_head_pa']} Pa " \
                         '(the legacy geometric piping-run head calculation is a documented future)')

        heater = OpenStudio::Model::WaterHeaterMixed.new(model)
        heater.setName("#{sizing['tank_volume_si'].round(3)}m3 #{fuel} Water Heater")
        heater.setTankVolume(sizing['tank_volume_si'])
        heater.setHeaterMaximumCapacity(sizing['tank_capacity_si'])
        heater.setHeaterFuelType(fuel)
        heater.setSetpointTemperatureSchedule(setpoint)
        heater.setDeadbandTemperatureDifference(2.0)
        heater.setHeaterControlType('Cycle')
        heater.setOnCycleParasiticFuelConsumptionRate(sizing['parasitic_loss_w'])
        heater.setOffCycleParasiticFuelConsumptionRate(sizing['parasitic_loss_w'])
        ambient = constant_schedule(model, 'SHW Ambient Temp 22C', 22.0)
        heater.setAmbientTemperatureIndicator('Schedule')
        heater.setAmbientTemperatureSchedule(ambient)
        loop.addSupplyBranchForComponent(heater)
        loop
      end

      def add_water_use(model, loop, entry, data_vintage, audit)
        space = entry['space']
        definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
        definition.setName("#{space.nameString.capitalize} Water Use Def")
        definition.setPeakFlowRate(entry['peak_flow_ind_si'])
        target = constant_schedule(model, "SHW Target #{entry['temperature_c']}C", entry['temperature_c'])
        definition.setTargetTemperatureSchedule(target)

        equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
        equipment.setName(space.nameString.capitalize.to_s)
        equipment.setSpace(space)
        schedule = OpenStudioLoads::Schedules.add(model, entry['schedule'], vintage: data_vintage, audit: audit)
        equipment.setFlowRateFractionSchedule(schedule)

        connections = OpenStudio::Model::WaterUseConnections.new(model)
        connections.setName("#{space.nameString.capitalize} WUC")
        connections.addWaterUseEquipment(equipment)
        loop.addDemandBranchForComponent(connections)
        audit.info(:shw, 'water use equipment added',
                   target: space.nameString,
                   inputs: { peak_flow_m3_s: entry['peak_flow_ind_si'].round(9),
                             temperature_c: entry['temperature_c'], schedule: entry['schedule'] },
                   article: '8.4.3.2. (SWH loads)')
      end

      def constant_schedule(model, name, value)
        existing = model.getScheduleRulesetByName(name)
        return existing.get if existing.is_initialized

        schedule = OpenStudio::Model::ScheduleRuleset.new(model)
        schedule.setName(name)
        schedule.defaultDaySchedule.setName("#{name} Default")
        schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), value)
        schedule
      end

      # ---- internals (not API) ----
      private_class_method :auto_size, :wrap_heat_pump, :build_loop,
                           :add_water_use, :constant_schedule
    end
  end
end
