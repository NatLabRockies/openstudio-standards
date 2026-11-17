require_relative '../../helpers/minitest_helper'

# EnergyPlus multiplies each water use equipment draw by its zone multiplier, so the water
# heater has to be sized for the multiplied flow. Measured on a hospital model, whose
# mid-story zones carry a multiplier of 5 and hold most of the service water draws: the
# shared heater was sized at 414 kBtu/hr for a building drawing ~190 kW average, ran at a
# 100.0% annual load factor - its annual heating energy was its nameplate times the year,
# to four significant figures - and the loop never reached its 60 C setpoint, logging the
# fixture target-temperature warning 5.6 million times per fixture.
class TestServiceWaterHeatingSizingZoneMultipliers < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  # One piece of water use equipment drawing 1 GPM at a flat 0.5 fraction, in a zone with
  # the given multiplier.
  def equipment_in_zone(model, multiplier:, name:)
    zone = OpenStudio::Model::ThermalZone.new(model)
    zone.setMultiplier(multiplier)
    space = OpenStudio::Model::Space.new(model)
    space.setThermalZone(zone)

    definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
    definition.setPeakFlowRate(OpenStudio.convert(1.0, 'gal/min', 'm^3/s').get)
    equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
    equipment.setName(name)
    equipment.setSpace(space)
    schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 0.5,
                                                                               name: "#{name} flow",
                                                                               schedule_type_limit: 'Fractional')
    equipment.setFlowRateFractionSchedule(schedule)
    equipment
  end

  def test_sizing_scales_with_the_zone_multiplier
    model = OpenStudio::Model::Model.new
    single = equipment_in_zone(model, multiplier: 1, name: 'single')
    multiplied = equipment_in_zone(model, multiplier: 5, name: 'multiplied')

    base = @swh.water_heater_sizing_from_water_use_equipment([single])
    scaled = @swh.water_heater_sizing_from_water_use_equipment([multiplied])

    assert_in_delta(5.0, scaled[:water_heater_capacity] / base[:water_heater_capacity], 0.001,
                    'a zone multiplier of 5 should size the heater 5x')
  end

  def test_sizing_sums_multiplied_and_unmultiplied_draws
    model = OpenStudio::Model::Model.new
    single = equipment_in_zone(model, multiplier: 1, name: 'single')
    multiplied = equipment_in_zone(model, multiplier: 5, name: 'multiplied')

    base = @swh.water_heater_sizing_from_water_use_equipment([single])
    both = @swh.water_heater_sizing_from_water_use_equipment([single, multiplied])

    assert_in_delta(6.0, both[:water_heater_capacity] / base[:water_heater_capacity], 0.001,
                    'the sum should weight each draw by its own multiplier')
  end

  def test_equipment_without_a_space_counts_once
    model = OpenStudio::Model::Model.new
    definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
    definition.setPeakFlowRate(OpenStudio.convert(1.0, 'gal/min', 'm^3/s').get)
    equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
    schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 0.5,
                                                                               name: 'spaceless flow',
                                                                               schedule_type_limit: 'Fractional')
    equipment.setFlowRateFractionSchedule(schedule)

    single = equipment_in_zone(model, multiplier: 1, name: 'single')
    in_space = @swh.water_heater_sizing_from_water_use_equipment([single])
    spaceless = @swh.water_heater_sizing_from_water_use_equipment([equipment])

    assert_in_delta(1.0, spaceless[:water_heater_capacity] / in_space[:water_heater_capacity], 0.001,
                    'equipment not assigned to a space takes a multiplier of 1')
  end
end
