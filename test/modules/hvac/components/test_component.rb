require_relative '../../../helpers/minitest_helper'

class TestHVACComponents < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_hvac_component_get_thermal_zone
    # Create a model and add a thermal zone
    model = OpenStudio::Model::Model.new
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    thermal_zone.setName('Test Thermal Zone')

    # Create an HVAC component (e.g., a ZoneHVACComponent)
    hvac_component = OpenStudio::Model::FanZoneExhaust.new(model)
    hvac_component.setName('Test HVAC Component')
    hvac_component.addToThermalZone(thermal_zone)

    # Get the thermal zone from the HVAC component
    result_zone = @hvac.hvac_component_get_thermal_zone(hvac_component)

    # Assert that the returned zone is the same as the one we created
    assert_equal(thermal_zone, result_zone, 'Expected to get the correct thermal zone from the HVAC component')
  end
end
