require_relative 'test_helper'

class TestCatalog < Minitest::Test
  def test_list_all
    rows = OpenStudioHVAC.systems
    assert_operator rows.size, :>=, 8
    assert(rows.all? { |r| r['name'] && r['family'] })
  end

  def test_list_filtered
    gas = OpenStudioHVAC.systems(filter: 'Gas')
    assert gas.any?
    assert(gas.all? { |r| r['name'].include?('Gas') })

    psz = OpenStudioHVAC.systems(family: 'psz')
    assert psz.any?
    assert(psz.all? { |r| r['family'] == 'psz' })
  end

  def test_resolve_merges_sizing_block
    config = OpenStudioHVAC::Catalog.resolve('PSZ RTU Gas and DX Coils and Hot Water Baseboard')
    assert_equal 'psz', config['family']
    assert_equal 'Gas', config['heating_coil_type']
    assert_equal true, config['needs_boiler']
    assert_kind_of Hash, config['sizing']
    assert_equal 'TemperatureDifference', config['sizing']['zone_cooling_design_supply_air_temperature_input_method']
    assert_equal 1.1, config['sizing']['zone_cooling_sizing_factor']
  end

  def test_unknown_name_raises_with_suggestions
    err = assert_raises(ArgumentError) { OpenStudioHVAC::Catalog.resolve('PSZ Gas Rooftop Thing') }
    assert_match(/unknown system name/, err.message)
    assert_match(/PSZ RTU/, err.message) # suggestions included
  end
end
