require_relative '../../../helpers/minitest_helper'

class TestHVACCentralAirSourceHeatPump < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_central_air_source_heat_pump
    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)

    hp = @hvac.create_central_air_source_heat_pump(model, plant_loop)
    assert(hp.is_a?(OpenStudio::Model::PlantComponentUserDefined), 'Expected hp to be an PlantComponentUserDefined object')
  end
end
