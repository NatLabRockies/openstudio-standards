require_relative '../coverage_helper'

class TestBuildingEnvelope < Minitest::Test

  def test_envelope_properties_by_climate_and_template
    climates = {
      'Vancouver'   => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Toronto'     => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    templates = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']
    results   = templates.map { |template| [template, {}] }.to_h

    climates.each do |city, epw_file|
      templates.each do |template|
        standard = Standard.build(template)
        model    = OpenStudio::Model::Model.new
        epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
        OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)
        hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
        results[template][city] = {
          fdwr:   standard.max_fwdr(hdd),
          u_wall: standard.max_u_necb("wall", "outdoors", hdd)
        }
      end
    end

    templates.each do |template|
      assert results[template]['Vancouver'][:fdwr] >= results[template]['Toronto'][:fdwr],
        "Vancouver FDWR (#{results[template]['Vancouver'][:fdwr]}) should be >= Toronto (#{results[template]['Toronto'][:fdwr]}) for #{template}"
      assert results[template]['Toronto'][:fdwr] >= results[template]['Yellowknife'][:fdwr],
        "Toronto FDWR (#{results[template]['Toronto'][:fdwr]}) should be >= Yellowknife (#{results[template]['Yellowknife'][:fdwr]}) for #{template}"
      assert results[template]['Vancouver'][:u_wall] >= results[template]['Toronto'][:u_wall],
        "Vancouver U-wall (#{results[template]['Vancouver'][:u_wall]}) should be >= Toronto (#{results[template]['Toronto'][:u_wall]}) for #{template}"
    end
  end
end
