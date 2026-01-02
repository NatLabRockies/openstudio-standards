require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateCompressor < Minitest::Test
  def setup
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_create_compressor
    model = OpenStudio::Model::Model.new

    # default case
    compressor1 = @refrig.create_compressor(model)

    # old case
    compressor2 = @refrig.create_compressor(model,
                                            template: 'old',
                                            operation_type: 'MT')

    # advanced case
    compressor3 = @refrig.create_compressor(model,
                                            template: 'advanced',
                                            operation_type: 'LT')
  end
end
