require_relative '../helpers/minitest_helper'

class ACM179dASHRAE901PRM2019Test < Minitest::Test
  attr_reader :standard

  def setup
    @standard = Standard.build('179D 2019')
  end

  def warehouse_model
    model = OpenStudio::Model::exampleModel
    model.getSpaceTypes.map(&:remove)
    model.getBuilding.setStandardsBuildingType('Warehouse')

    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Warehouse Bulk')
    space_type.setStandardsBuildingType('Warehouse')
    space_type.setStandardsSpaceType('Bulk')
    model.getSpaces.each { |space| space.setSpaceType(space_type) }

    return model
  end

  def test_standard_build_and_data_overlay
    assert_instance_of(ACM179dASHRAE901PRM2019, standard)
    assert_equal('179d-90.1-2019', standard.template)
    assert_includes(standard.standards_data.keys, 'prm_baseline_hvac')

    warehouse_bulk = standard.standards_data['space_types'].find do |row|
      row['template'] == standard.template &&
        row['building_type'] == 'Warehouse' &&
        row['space_type'] == 'Bulk'
    end
    refute_nil(warehouse_bulk)
    assert_in_delta(0.8, warehouse_bulk['lighting_per_area'], 0.001)

    warehouse_lights = standard.standards_data['schedules'].find do |row|
      row['template'] == standard.template && row['name'] == 'ACM2019 WarehouseLights'
    end
    refute_nil(warehouse_lights)
  end

  def test_space_type_get_standards_data_prefers_exact_acm_row
    model = warehouse_model
    space_type = model.getSpaceTypes.first
    data = standard.space_type_get_standards_data(space_type, throw_if_not_found: true)

    assert_equal('179d-90.1-2019', data['template'])
    assert_equal('Warehouse', data['building_type'])
    assert_equal('Bulk', data['space_type'])
    assert_in_delta(0.8, data['lighting_per_area'], 0.001)
    assert_equal('ACM2019 WarehouseLights', data['lighting_schedule'])

    model_data = standard.model_get_standards_data(model, throw_if_not_found: true)
    assert_equal('Bulk', model_data['space_type'])
    assert_equal('ACM2019 WarehouseHVACAvail', model_data['hvac_operation_schedule'])
  end

  def test_acm_lpd_and_schedule_are_applied_to_regulated_light
    model = warehouse_model
    space_type = model.getSpaceTypes.first

    standard.space_type_apply_internal_loads(space_type, false, true, false, false, false)
    assert_equal(1, space_type.lights.size)

    lights = space_type.lights.first
    expected_lpd_si = OpenStudio.convert(0.8, 'W/ft^2', 'W/m^2').get
    assert_in_delta(expected_lpd_si, lights.lightsDefinition.wattsperSpaceFloorArea.get, 0.001)
    assert(lights.schedule.is_initialized)
    assert_equal('ACM2019 WarehouseLights', lights.schedule.get.nameString)

    standard.space_type_light_sch_change(model)
    assert_equal('ACM2019 WarehouseLights', lights.schedule.get.nameString)
  end

  def test_acm_hvac_availability_schedule_is_applied_to_air_loop
    model = warehouse_model
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    assert(standard.model_apply_acm_hvac_availability_schedule(model))
    assert_equal('ACM2019 WarehouseHVACAvail', air_loop.availabilitySchedule.nameString)
    assert_equal('ACM2019 WarehouseHVACAvail', model.getBuilding.additionalProperties.getFeatureAsString('acm_fan_sch').get)
  end
end
