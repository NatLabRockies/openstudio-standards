# frozen_string_literal: true

# Workaround for the standards 0.8.x small-SWH-pump pathology.
#
# `pump_apply_standard_minimum_motor_efficiency` lowers motor efficiency
# based on a fractional-hp lookup (Standards.Motor.rb -
# `motor_fractional_hp_efficiencies`) but does NOT adjust the pump's
# rated head or power. For Service Water Loop circulator pumps in small
# buildings the rated flow is autosized to a tiny value (~3e-5 m3/s for
# a SmallOffice). The fixture/upstream sizing path picks a rated head of
# 29891 Pa (~100 ft, the default for circulating SWH) and a rated power
# such that total efficiency = (V * H / P) ~ 64%. When the standards
# function then drops motor efficiency to 52.9% (PSC table lookup for
# 0.002 hp), EnergyPlus computes pump_efficiency = total / motor =
# 64.4% / 52.9% = 121.7% > 100% and rejects the pump as non-physical.
#
# Fix: after `super` applies the motor efficiency lookup, check whether
# the resulting pump_efficiency would be non-physical and, if so, lower
# `RatedPumpHead` so total_efficiency = motor_efficiency *
# TARGET_PUMP_EFFICIENCY_179D. The 100-ft default head on a circulating
# SWH pump is arbitrary (no real loop-loss calculation drives it), so
# dropping it is more physical than inflating the rated power.
class ACM179dASHRAE9012007
  TARGET_PUMP_EFFICIENCY_179D = 0.70

  def pump_apply_standard_minimum_motor_efficiency(pump)
    result = super
    fix_pump_rated_head_for_consistent_efficiency(pump)
    result
  end

  def fix_pump_rated_head_for_consistent_efficiency(pump)
    return unless pump.respond_to?(:ratedPowerConsumption)
    return unless pump.respond_to?(:ratedPumpHead)
    return unless pump.respond_to?(:motorEfficiency)

    motor_eff = pump.motorEfficiency
    return if motor_eff <= 0

    rated_head = pump.ratedPumpHead
    return if rated_head <= 0

    rated_flow = if pump.respond_to?(:ratedFlowRate) && pump.ratedFlowRate.is_initialized
                   pump.ratedFlowRate.get
                 elsif pump.respond_to?(:autosizedRatedFlowRate) && pump.autosizedRatedFlowRate.is_initialized
                   pump.autosizedRatedFlowRate.get
                 end
    return if rated_flow.nil? || rated_flow <= 0

    return unless pump.ratedPowerConsumption.is_initialized

    rated_power = pump.ratedPowerConsumption.get
    return if rated_power <= 0

    total_eff = (rated_flow * rated_head) / rated_power
    return if total_eff <= motor_eff # already physical

    # Non-physical: pump_eff = total / motor > 1. Lower rated_head so
    # total_eff = motor_eff * TARGET_PUMP_EFFICIENCY_179D.
    new_head = (motor_eff * TARGET_PUMP_EFFICIENCY_179D * rated_power) / rated_flow
    pump.setRatedPumpHead(new_head)
    OpenStudio.logFree(OpenStudio::Info, '179d.standards.Pump',
                       "For #{pump.name}: lowered RatedPumpHead #{rated_head.round(0)}Pa -> #{new_head.round(0)}Pa " \
                       "to keep pump_efficiency physical after motor_efficiency dropped to #{(motor_eff * 100).round(1)}% " \
                       "(rated_flow=#{rated_flow.round(7)} m3/s, rated_power=#{rated_power.round(3)} W).")
  end
end
