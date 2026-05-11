require_relative '../../../helpers/minitest_helper'

class TestHVACCoil < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    @geo = OpenstudioStandards::Geometry
  end

  def test_coil_dx_subcategory
    model = OpenStudio::Model::Model.new
    coil = @hvac.create_coil_cooling_dx_two_speed(model)
    coil.setName('Single Package')
    assert('Single Package', @hvac.coil_dx_subcategory(coil))

    coil.setName('Minisplit System')
    assert('Minisplit System', @hvac.coil_dx_subcategory(coil))
  end

  def test_coil_dx_heat_pump?
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 25000.0
    args['bldg_type_a'] = 'SecondarySchool'
    @geo.create_bar_from_building_type_ratios(model, args)

    std = Standard.build('90.1-2013')
    std.model_add_hvac_system(model, 'PTHP', 'Electricity', 'Electricity', 'Electricity', model.getThermalZones)
    coil = model.getCoilCoolingDXSingleSpeedByName('Zone SecondarySchool Classroom A  - Story ground PTHP Clg Coil').get
    assert(@hvac.coil_dx_heat_pump?(coil))
  end

  def test_coil_dx_heating_type
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 25000.0
    args['bldg_type_a'] = 'SecondarySchool'
    @geo.create_bar_from_building_type_ratios(model, args)

    std = Standard.build('90.1-2013')
    std.model_add_hvac_system(model, 'PSZ-AC', 'Electricity', 'Electricity', 'Electricity', model.getThermalZones)
    coil = model.getCoilCoolingDXSingleSpeedByName('Zone SecondarySchool Classroom A end_a - Story ground PSZ-AC 1spd DX AC Clg Coil').get
    heating_type = @hvac.coil_dx_heating_type(coil)
    assert('Electric Resistance or None', heating_type)
  end

  def test_coil_heating_get_paired_coil_cooling_capacity
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 25000.0
    args['bldg_type_a'] = 'SecondarySchool'
    @geo.create_bar_from_building_type_ratios(model, args)

    std = Standard.build('90.1-2013')
    std.model_add_hvac_system(model, 'PSZ-AC', 'NaturalGas', nil, 'Electricity', model.getThermalZones)
    htg_coil = model.getCoilHeatingWaterByName('Zone SecondarySchool Classroom A end_a - Story ground PSZ-AC Water Htg Coil').get
    clg_coil = model.getCoilCoolingDXSingleSpeedByName('Zone SecondarySchool Classroom A end_a - Story ground PSZ-AC 1spd DX AC Clg Coil').get
    clg_coil.setRatedTotalCoolingCapacity(5000.0)
    assert_in_delta(5000.0, @hvac.coil_heating_get_paired_coil_cooling_capacity(htg_coil), 0.1)
  end
end
