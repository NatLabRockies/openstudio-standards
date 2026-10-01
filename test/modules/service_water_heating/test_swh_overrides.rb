require_relative '../../helpers/minitest_helper'

# Tests for runtime service water heating overrides: naming one piece of equipment, using
# the wildcard for all of it, and the precedence between them.
class TestServiceWaterHeatingOverrides < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  # a kitchen's two draws, as the shipped data carries them: a named booster at 180 F and an
  # unnamed general draw at 120 F
  def kitchen_equipment
    [
      { equipment_name: 'Dishwasher Booster', peak_flow_rate_gph: nil,
        peak_flow_rate_gph_per_floor_area_ft2: 0.054, mixed_water_temperature_f: 180.0,
        sensible_fraction: 0.2, latent_fraction: 0.05 },
      { equipment_name: nil, peak_flow_rate_gph: nil,
        peak_flow_rate_gph_per_floor_area_ft2: 0.036, mixed_water_temperature_f: 120.0,
        sensible_fraction: 0.2, latent_fraction: 0.05 }
    ]
  end

  def space_type(model, name = 'food preparation')
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName(name)
    st.setStandardsSpaceType(name)
    st
  end

  def test_wildcard_applies_to_every_piece_of_equipment
    model = OpenStudio::Model::Model.new
    overrides = [{ space_type: 'food preparation',
                   equipment: { :'*' => { peak_flow_rate_gph_per_floor_area_ft2: 0.009 } } }]

    result = @swh.apply_service_water_heating_overrides(kitchen_equipment, space_type(model), 'food preparation', overrides)
    assert_equal([0.009, 0.009], result.map { |e| e[:peak_flow_rate_gph_per_floor_area_ft2] })
    # untouched fields survive
    assert_equal([180.0, 120.0], result.map { |e| e[:mixed_water_temperature_f] })
  end

  def test_named_equipment_wins_over_the_wildcard
    model = OpenStudio::Model::Model.new
    overrides = [{ space_type: 'food preparation',
                   equipment: { :'*' => { peak_flow_rate_gph_per_floor_area_ft2: 0.006 },
                                :'Dishwasher Booster' => { peak_flow_rate_gph_per_floor_area_ft2: 0.009 } } }]

    result = @swh.apply_service_water_heating_overrides(kitchen_equipment, space_type(model), 'food preparation', overrides)
    assert_equal(0.009, result[0][:peak_flow_rate_gph_per_floor_area_ft2], 'the named booster takes its own rate')
    assert_equal(0.006, result[1][:peak_flow_rate_gph_per_floor_area_ft2], 'unnamed equipment takes the wildcard')
  end

  # The expansion prefers an absolute gph and only falls back to the per-area rate, so an
  # override that sets one has to clear the other or the record's own value would win.
  def test_setting_one_rate_clears_the_other
    model = OpenStudio::Model::Model.new
    absolute = [{ equipment_name: 'Booster', peak_flow_rate_gph: nil,
                  peak_flow_rate_gph_per_floor_area_ft2: 0.054, mixed_water_temperature_f: 180.0 }]

    result = @swh.apply_service_water_heating_overrides(
      absolute, space_type(model), 'food preparation',
      [{ space_type: '*', equipment: { :'*' => { peak_flow_rate_gph: 40.0 } } }]
    )
    assert_equal(40.0, result[0][:peak_flow_rate_gph])
    assert_nil(result[0][:peak_flow_rate_gph_per_floor_area_ft2], 'the per-area rate must be cleared')
  end

  def test_no_override_leaves_the_equipment_alone
    model = OpenStudio::Model::Model.new
    st = space_type(model)
    assert_equal(kitchen_equipment, @swh.apply_service_water_heating_overrides(kitchen_equipment, st, 'food preparation', nil))
    assert_equal(kitchen_equipment, @swh.apply_service_water_heating_overrides(kitchen_equipment, st, 'food preparation', []))

    # an entry keyed to another space type does not apply
    other = [{ space_type: 'office', equipment: { :'*' => { peak_flow_rate_gph_per_floor_area_ft2: 0.9 } } }]
    assert_equal(kitchen_equipment, @swh.apply_service_water_heating_overrides(kitchen_equipment, st, 'food preparation', other))
  end

  # entries arriving with string keys, as a spec assembled by a measure carries
  def test_string_keyed_overrides_apply
    model = OpenStudio::Model::Model.new
    parsed = OpenstudioStandards::CreateTypical.parse_overrides_argument(
      [{ 'space_type' => 'food preparation',
         'equipment' => { 'Dishwasher Booster' => { 'peak_flow_rate_gph_per_floor_area_ft2' => 0.009 } } }],
      'service_water_heating_overrides'
    )
    result = @swh.apply_service_water_heating_overrides(kitchen_equipment, space_type(model), 'food preparation', parsed)
    assert_equal(0.009, result[0][:peak_flow_rate_gph_per_floor_area_ft2])
  end
end
