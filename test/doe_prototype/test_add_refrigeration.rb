require_relative '../helpers/minitest_helper'

class TestAddRefrigeration < Minitest::Test

  def test_add_refrigeration_case
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{File.dirname(__FILE__)}/models/MultiStoryRetail.osm")
    model = translator.loadModel(path)
    model = model.get
    puts "Test building area is #{OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get.round} ft^2."

    template = '90.1-2010'
    standard = Standard.build(template)

    add_case = standard.model_add_refrigeration_case(model, model.getThermalZones[0], 'Prepared Foods Cases', '>50k ft2')

    # Check case length
    assert_in_delta(OpenStudio.convert(56.0, 'ft', 'm').get, add_case.caseLength, 1.0)
    # Check case operating temperature
    assert_in_delta(OpenStudio.convert(33.0, 'F', 'C').get, add_case.caseOperatingTemperature, 1.0) # kBtu/hr
  end

  def test_add_refrigeration_walkin
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{File.dirname(__FILE__)}/models/SecondarySchool_6A_1980-2004.osm")
    model = translator.loadModel(path)
    model = model.get
    puts "Test building area is #{OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get.round} ft^2."

    template = 'DOE Ref 1980-2004'
    standard = Standard.build(template)
    add_walkin = standard.model_add_refrigeration_walkin(model, model.getThermalZones[0], '<35k ft2', 'Beer Cooler')

    # Check case length
    assert_in_delta(475.2, add_walkin.ratedTotalLightingPower, 1.0)
    # Check case operating temperature
    assert_in_epsilon(add_walkin.operatingTemperature,OpenStudio.convert(35, 'F', 'C').get, 0.5) # kBtu/hr
  end

  def test_add_refrigeration_compressor
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new("#{File.dirname(__FILE__)}/models/MultiStoryRetail.osm")
    model = translator.loadModel(path)
    model = model.get
    puts "Test building area is #{OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get.round} ft^2."

    template = 'DEER 1996'
    standard = Standard.build(template)
    assert(standard.model_add_refrigeration_compressor(model, 'LT compressor_SmallandOld'))
  end
end
