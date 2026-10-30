require_relative '../../helpers/minitest_helper'

# Tests for the all-level space type crosswalk on typical exhaust: the rate lookup, the makeup
# air source lookup, and create_typical_exhaust end to end.
#
# The prototype (space_type, building_type) path is covered by test_hvac_exhaust.rb.
class TestHVACExhaustAllLevel < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def exhaust_records
    @hvac.typical_exhaust_data[:space_types]
  end

  # The lookup takes the first match, so two records sharing an all-level name would make the
  # rate depend on JSON order. That is the shape of the bug that inflated service water heating
  # by up to 278x, so assert it cannot happen here.
  def test_each_all_level_name_is_owned_by_one_record
    names = exhaust_records.flat_map { |r| r[:all_level_space_types] || [] }
    duplicates = names.tally.select { |_, count| count > 1 }.keys
    assert_empty(duplicates, "all-level space types claimed by more than one exhaust record: #{duplicates.join(', ')}")
  end

  # An untagged record is a deliberate exclusion, not an oversight, so it has to say why.
  def test_untagged_records_carry_a_reason
    exhaust_records.each do |record|
      next unless (record[:all_level_space_types] || []).empty?

      refute_nil(record[:all_level_exclusion_reason],
                 "#{record[:building_type]} #{record[:space_type]} has no all-level name and no exclusion reason")
    end
  end

  def test_rate_lookup_by_all_level_name
    # a kitchen is a kitchen: no building type takes part
    assert_in_delta(0.7, @hvac.space_type_exhaust_per_area('food preparation'), 1e-6)
    assert_in_delta(0.7, @hvac.space_type_exhaust_per_area('food preparation', 'Hospital'), 1e-6)
    assert_in_delta(0.7, @hvac.space_type_exhaust_per_area('food preparation - primary school'), 1e-6)
    assert_in_delta(0.29, @hvac.space_type_exhaust_per_area('restroom - primary school'), 1e-6)
    assert_in_delta(0.28, @hvac.space_type_exhaust_per_area('restroom - secondary school'), 1e-6)
    assert_in_delta(1.14, @hvac.space_type_exhaust_per_area('restroom'), 1e-6)
    assert_in_delta(1.0, @hvac.space_type_exhaust_per_area('imaging'), 1e-6)
    assert_in_delta(0.7, @hvac.space_type_exhaust_per_area('laundry/washing'), 1e-6)
    assert_in_delta(1.24, @hvac.space_type_exhaust_per_area('food preparation - deli'), 1e-6)
  end

  def test_rate_lookup_returns_nil_for_space_types_without_exhaust
    assert_nil(@hvac.space_type_exhaust_per_area('office'))
    assert_nil(@hvac.space_type_exhaust_per_area('corridor', 'Hospital'))
    # deliberately excluded: 'exam/treatment' is too broad to carry the anesthesia room rate
    assert_nil(@hvac.space_type_exhaust_per_area('exam/treatment'))
  end

  def test_rate_lookup_still_answers_prototype_names
    assert_in_delta(0.7, @hvac.space_type_exhaust_per_area('Kitchen', 'Hospital'), 1e-6)
    assert_in_delta(1.6666, @hvac.space_type_exhaust_per_area('Soil Work', 'Outpatient'), 1e-6)
    # the pair has to match, not just the space type
    assert_nil(@hvac.space_type_exhaust_per_area('Soil Work', 'Hospital'))
  end

  def test_makeup_air_lookup_by_all_level_name
    makeup = @hvac.exhaust_makeup_air_source('food preparation')
    assert_equal(['dining', 'dining - cafeteria/fast food'], makeup[:space_types])
    assert_nil(makeup[:building_type], 'the all-level path does not constrain the building type')
    assert_in_delta(0.5, makeup[:fraction], 1e-6)

    # a school kitchen prefers its own cafeteria, then falls back to general dining
    assert_equal(['dining - primary school', 'dining'], @hvac.exhaust_makeup_air_source('food preparation - primary school')[:space_types])

    assert_nil(@hvac.exhaust_makeup_air_source('restroom'), 'restrooms have no makeup air source')
  end

  def test_makeup_air_lookup_still_answers_prototype_pairs
    makeup = @hvac.exhaust_makeup_air_source('Kitchen', 'LargeHotel')
    assert_equal(['Cafe'], makeup[:space_types])
    assert_equal('LargeHotel', makeup[:building_type], 'the legacy path constrains the source building type')

    assert_equal(['Cafeteria'], @hvac.exhaust_makeup_air_source('Kitchen', 'SecondarySchool')[:space_types])
    assert_nil(@hvac.exhaust_makeup_air_source('Kitchen', 'SmallHotel'), 'no prototype pair, no makeup air')
  end

  # Relabel the primary school's kitchen and cafeteria with all-level names, leaving the rest of
  # the building on prototype names, and check that both lookups reach their record.
  def test_create_typical_exhaust_finds_adjacent_makeup_air
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")

    kitchen_zone = model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get
    cafeteria_zone = model.getThermalZoneByName('TZ-Cafeteria_ZN_1_FLR_1').get
    kitchen_zone.spaces.first.spaceType.get.setStandardsSpaceType('food preparation - primary school')
    cafeteria_zone.spaces.first.spaceType.get.setStandardsSpaceType('dining - primary school')

    fans = @hvac.create_typical_exhaust(model, std, makeup_source: 'Adjacent')

    kitchen_fan = fans.find { |f| f.thermalZone.get == kitchen_zone }
    refute_nil(kitchen_fan, 'the kitchen got no exhaust fan from its all-level name')
    assert(kitchen_fan.balancedExhaustFractionSchedule.is_initialized, 'makeup air was not found in the adjacent cafeteria')

    mixing = model.getZoneMixings.select { |zm| zm.zoneOrSpace.to_ThermalZone.get == kitchen_zone }
    assert_equal(1, mixing.size, 'expected one zone mixing object moving transfer air into the kitchen')
    assert_equal(cafeteria_zone, mixing.first.sourceZone.get)

    # the transfer air source fan lands in the cafeteria, and is not one of the returned fans
    transfer = model.getFanZoneExhausts.select { |f| f.name.to_s.include?('Transfer Air Source') }
    assert_equal(1, transfer.size)
    assert_equal(cafeteria_zone, transfer.first.thermalZone.get)

    # restrooms still resolve through the prototype pair, so the rest of the building is intact
    restroom_zone = model.getThermalZoneByName('TZ-Restroom_ZN_1_FLR_1')
    if restroom_zone.is_initialized
      refute_nil(fans.find { |f| f.thermalZone.get == restroom_zone.get }, 'the prototype-named restroom lost its exhaust fan')
    end
  end

  # Without makeup air the kitchen still gets its exhaust, and nothing gets zone mixing.
  def test_create_typical_exhaust_without_makeup_air
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    kitchen_zone = model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get
    kitchen_zone.spaces.first.spaceType.get.setStandardsSpaceType('food preparation - primary school')

    fans = @hvac.create_typical_exhaust(model, std, makeup_source: 'None')

    refute_nil(fans.find { |f| f.thermalZone.get == kitchen_zone })
    assert_empty(model.getZoneMixings)
    assert_empty(model.getFanZoneExhausts.select { |f| f.name.to_s.include?('Transfer Air Source') })
    fans.each { |f| assert(f.pressureRise > 0.0, "#{f.name} did not get a prototype pressure rise") }
  end

  def override_space_type(model, name)
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName(name)
    st.setStandardsSpaceType(name)
    st
  end

  def test_override_replaces_the_space_type_rate
    model = OpenStudio::Model::Model.new
    st = override_space_type(model, 'imaging')
    overrides = [{ space_type: 'imaging', exhaust: { exhaust_per_area: 0.0 } }]

    assert_in_delta(0.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', overrides), 1e-9)
    # a rate can be raised as well as zeroed
    assert_in_delta(2.5, @hvac.apply_exhaust_overrides(1.0, st, 'imaging',
                                                       [{ space_type: 'imaging', exhaust: { exhaust_per_area: 2.5 } }]), 1e-9)
  end

  def test_override_reaches_a_space_type_the_data_gives_no_rate
    model = OpenStudio::Model::Model.new
    st = override_space_type(model, 'exam/treatment')
    overrides = [{ space_type: 'exam/treatment', exhaust: { exhaust_per_area: 1.3333 } }]
    assert_in_delta(1.3333, @hvac.apply_exhaust_overrides(nil, st, 'exam/treatment', overrides), 1e-9)
  end

  def test_override_precedence_and_non_matches
    model = OpenStudio::Model::Model.new
    st = override_space_type(model, 'imaging')

    # a specific entry wins over the wildcard
    both = [{ space_type: '*', exhaust: { exhaust_per_area: 0.5 } },
            { space_type: 'imaging', exhaust: { exhaust_per_area: 0.0 } }]
    assert_in_delta(0.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', both), 1e-9)

    # the wildcard alone still applies
    assert_in_delta(0.5, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', [both.first]), 1e-9)

    # entries for other space types, and no entries at all, leave the rate alone
    assert_in_delta(1.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging',
                                                       [{ space_type: 'food preparation', exhaust: { exhaust_per_area: 0.0 } }]), 1e-9)
    assert_in_delta(1.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', nil), 1e-9)
    assert_in_delta(1.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', []), 1e-9)
  end

  def test_string_keyed_overrides_apply
    model = OpenStudio::Model::Model.new
    st = override_space_type(model, 'imaging')
    parsed = OpenstudioStandards::CreateTypical.parse_overrides_argument(
      [{ 'space_type' => 'imaging', 'exhaust' => { 'exhaust_per_area' => 0.0 } }], 'exhaust_overrides'
    )
    assert_in_delta(0.0, @hvac.apply_exhaust_overrides(1.0, st, 'imaging', parsed), 1e-9)
  end

  # A zeroed rate means no fan, not a zero-flow fan.
  def test_zeroed_override_removes_the_fan
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get.spaces.first.spaceType.get.setStandardsSpaceType('food preparation')

    with_kitchen = @hvac.create_typical_exhaust(model, std, makeup_source: 'None')
    without = @hvac.create_typical_exhaust(model, std, makeup_source: 'None',
                                           exhaust_overrides: [{ space_type: 'food preparation', exhaust: { exhaust_per_area: 0.0 } }])

    assert_equal(with_kitchen.size - 1, without.size, 'zeroing the kitchen rate should remove exactly one fan')
    kitchen_zone = model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get
    assert_nil(without.find { |f| f.thermalZone.get == kitchen_zone })
  end

  # Standard#model_add_exhaust delegates here now, so the prototype entry point has to still
  # find its makeup air through the legacy pairs.
  def test_model_add_exhaust_still_works_through_the_standard
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")

    fans = std.model_add_exhaust(model, makeup_source: 'Adjacent')

    kitchen_zone = model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get
    kitchen_fan = fans.find { |f| f.thermalZone.get == kitchen_zone }
    refute_nil(kitchen_fan, 'the prototype-named kitchen got no exhaust fan')
    assert(kitchen_fan.balancedExhaustFractionSchedule.is_initialized, 'the legacy PrimarySchool Kitchen -> Cafeteria pair did not resolve')
    assert_equal(1, model.getZoneMixings.size)
  end

  # Exhaust fans are built before any HVAC exists, so they come out always on. Left that way
  # they keep pulling air from a zone whose air handler has cycled off, which EnergyPlus
  # reports as an unbalanced air loop and then fails to converge around -- on secondary school
  # 50444 that turned an 8 minute simulation into 78.
  def test_exhaust_fans_follow_the_air_loop_availability
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')

    fans = @hvac.create_typical_exhaust(model, std, makeup_source: 'None')
    refute_empty(fans)
    fans.each do |fan|
      assert_equal(model.alwaysOnDiscreteSchedule, fan.availabilitySchedule.get,
                   'a fan built before HVAC should start out always on')
    end

    # give the exhausted zones an air loop with a schedule of its own
    schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 1.0, name: 'Test HVAC Availability')
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test Air Loop')
    air_loop.setAvailabilitySchedule(schedule)
    served = fans.first(2).map { |f| f.thermalZone.get }
    served.each { |zone| air_loop.addBranchForZone(zone) }

    retimed = @hvac.exhaust_fans_follow_hvac_availability(model)

    assert_equal(served.size, retimed, 'only the fans in zones with an air loop should be retimed')
    fans.each do |fan|
      if served.include?(fan.thermalZone.get)
        assert_equal(schedule, fan.availabilitySchedule.get, "#{fan.name} did not follow its air loop")
      else
        assert_equal(model.alwaysOnDiscreteSchedule, fan.availabilitySchedule.get,
                     "#{fan.name} has no air loop and should have been left alone")
      end
    end
  end

  def test_retiming_a_model_with_no_exhaust_is_a_no_op
    model = OpenStudio::Model::Model.new
    assert_equal(0, @hvac.exhaust_fans_follow_hvac_availability(model))
  end

  # One fan per zone, whichever pass adds it.
  def test_create_typical_exhaust_does_not_double_up
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    model.getThermalZoneByName('TZ-Kitchen_ZN_1_FLR_1').get.spaces.first.spaceType.get.setStandardsSpaceType('food preparation - primary school')

    first = @hvac.create_typical_exhaust(model, std, makeup_source: 'Adjacent')
    second = @hvac.create_typical_exhaust(model, std, makeup_source: 'Adjacent')

    assert_equal(first.size, second.size, 'a second call should replace the fans, not add to them')
    exhaust_zones = second.map { |f| f.thermalZone.get }
    assert_equal(exhaust_zones.size, exhaust_zones.uniq.size, 'a zone received more than one exhaust fan')
  end
end
