require_relative '../../helpers/minitest_helper'

# Tests for keeping an exhausted space type next to its makeup air source when the bar is
# sliced. Without this the pairing is an accident of the floor area ordering.
class TestSliceAdjacency < Minitest::Test
  def setup
    @geometry = OpenstudioStandards::Geometry
    @hvac = OpenstudioStandards::HVAC
  end

  # Space type areas of hospital 59051's middle story, in ft2, which is where the pairing broke.
  LEG_D_MID_STORY = {
    'corridor - hospital' => 62_679.0,
    'nurses station' => 49_739.0,
    'patient room' => 34_561.0,
    'lobby' => 23_653.0,
    'food preparation' => 14_905.0,
    'exam/treatment' => 13_465.0,
    'dining' => 11_196.0,
    'office' => 4089.0
  }.freeze

  def space_type(model, name)
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName(name)
    st.setStandardsSpaceType(name)
    st
  end

  # [key, hash] entries in the order the slicing methods build them: ascending floor area.
  def entries_for(model, areas)
    areas.sort_by { |_, area| area }
         .map { |name, area| [space_type(model, name), { floor_area: OpenStudio.convert(area, 'ft^2', 'm^2').get }] }
  end

  def names_of(entries)
    entries.map { |entry| @geometry.slice_space_type_name(entry[0]) }
  end

  def test_pairs_resolve_from_the_space_types_present
    pairs = @hvac.exhaust_makeup_air_pairs(LEG_D_MID_STORY.keys)
    assert_equal([['food preparation', 'dining']], pairs)

    # no dining space, no pair to make
    assert_empty(@hvac.exhaust_makeup_air_pairs(['food preparation', 'office', 'corridor']))
    # nothing exhausted, no pair to make
    assert_empty(@hvac.exhaust_makeup_air_pairs(['dining', 'office']))
    # a school kitchen takes its own cafeteria over general dining when both are present
    assert_equal([['food preparation - primary school', 'dining - primary school']],
                 @hvac.exhaust_makeup_air_pairs(['food preparation - primary school', 'dining', 'dining - primary school']))
    # and falls back to general dining when its own is absent
    assert_equal([['food preparation - primary school', 'dining']],
                 @hvac.exhaust_makeup_air_pairs(['food preparation - primary school', 'dining', 'office']))
  end

  # The regression itself: exam/treatment at 13,465 ft2 sorts between dining at 11,196 and food
  # preparation at 14,905, so the two end up two slices apart and makeup air is lost.
  def test_slice_order_puts_dining_next_to_the_kitchen
    model = OpenStudio::Model::Model.new
    entries = entries_for(model, LEG_D_MID_STORY)
    pairs = @hvac.exhaust_makeup_air_pairs(LEG_D_MID_STORY.keys)

    before = names_of(entries)
    assert_equal(2, (before.index('food preparation') - before.index('dining')).abs,
                 'expected the unordered case to separate the pair, or this test proves nothing')

    after = names_of(@geometry.order_slices_for_adjacency(entries, pairs))
    assert_equal(1, (after.index('food preparation') - after.index('dining')).abs)
    assert_equal(before.sort, after.sort, 'reordering must not add or drop a slice')
  end

  def test_slice_order_is_untouched_without_pairs
    model = OpenStudio::Model::Model.new
    entries = entries_for(model, LEG_D_MID_STORY)
    assert_equal(names_of(entries), names_of(@geometry.order_slices_for_adjacency(entries, nil)))
    assert_equal(names_of(entries), names_of(@geometry.order_slices_for_adjacency(entries, [])))
  end

  # The largest space type is deliberately moved to the front of the bar, where it forms the
  # bar's own end, so it cannot be pulled off index 0 to serve as a makeup source.
  def test_the_protected_first_slice_stays_first
    model = OpenStudio::Model::Model.new
    areas = { 'dining' => 90_000.0, 'office' => 1000.0, 'lobby' => 2000.0, 'food preparation' => 3000.0 }
    entries = entries_for(model, areas)
    entries.insert(0, entries.delete_at(entries.size - 1)) # what the caller does: largest to front
    assert_equal('dining', names_of(entries).first)
    pairs = @hvac.exhaust_makeup_air_pairs(areas.keys)

    ordered = @geometry.order_slices_for_adjacency(entries, pairs, protect_first: true)
    assert_equal('dining', names_of(ordered).first, 'the largest space type was moved off the bar end')
    assert_equal(names_of(entries), names_of(ordered), 'nothing should move when the only source is protected')

    # without the guard the same call is free to move it
    moved = @geometry.order_slices_for_adjacency(entries, pairs, protect_first: false)
    assert_equal(1, (names_of(moved).index('food preparation') - names_of(moved).index('dining')).abs)
  end

  # An exhausted space type at the front of the bar takes its makeup source at index 1.
  def test_exhaust_at_the_bar_end_gets_its_source_beside_it
    model = OpenStudio::Model::Model.new
    areas = { 'food preparation' => 90_000.0, 'office' => 1000.0, 'lobby' => 2000.0, 'dining' => 3000.0 }
    entries = entries_for(model, areas)
    entries.insert(0, entries.delete_at(entries.size - 1))
    pairs = @hvac.exhaust_makeup_air_pairs(areas.keys)

    ordered = names_of(@geometry.order_slices_for_adjacency(entries, pairs, protect_first: true))
    assert_equal('food preparation', ordered.first)
    assert_equal('dining', ordered[1])
  end

  def test_story_deferral_only_fires_when_the_partner_would_be_squeezed_out
    min_slice = 10.0

    # fits, and leaves the partner nothing: defer both to the next story
    assert(@geometry.defer_slice_for_adjacency?(95.0, 50.0, false, 100.0, min_slice, false))

    # fits, and leaves the partner room: place it
    refute(@geometry.defer_slice_for_adjacency?(50.0, 50.0, false, 100.0, min_slice, false))

    # overruns the story, so it continues onto the next one where the partner still follows it
    refute(@geometry.defer_slice_for_adjacency?(150.0, 50.0, false, 100.0, min_slice, false))

    # the partner is already on this story
    refute(@geometry.defer_slice_for_adjacency?(95.0, 50.0, true, 100.0, min_slice, false))

    # the partner has no area left to place anywhere
    refute(@geometry.defer_slice_for_adjacency?(95.0, 0.0, false, 100.0, min_slice, false))

    # the last story has nowhere to defer to
    refute(@geometry.defer_slice_for_adjacency?(95.0, 50.0, false, 100.0, min_slice, true))
  end

  # End to end through the story fill: both space types land on the same story and their slices
  # come out consecutive.
  def test_multi_story_slicing_keeps_the_pair_together
    model = OpenStudio::Model::Model.new
    space_types = {}
    entries_for(model, LEG_D_MID_STORY).each { |key, hash| space_types[key] = hash }
    pairs = @hvac.exhaust_makeup_air_pairs(LEG_D_MID_STORY.keys)

    length = OpenStudio.convert(300.0, 'ft', 'm').get
    width = OpenStudio.convert(100.0, 'ft', 'm').get
    story_area = length * width
    total = space_types.values.sum { |v| v[:floor_area] }
    story_hash = {}
    (total / story_area).ceil.times do |i|
      story_hash["story #{i}"] = { space_origin_z: i * 4.0, space_height: 4.0, multiplier: 1, partial_story_multiplier: 1.0 }
    end

    footprints = @geometry.create_sliced_bar_multi_polygons(deep_copy(space_types), length, width,
                                                           OpenStudio::Point3d.new(0.0, 0.0, 0.0), story_hash,
                                                           adjacency_pairs: pairs)

    story = footprints.find { |f| slice_names(f).include?('food preparation') }
    refute_nil(story, 'no story held the kitchen')
    names = slice_names(story)
    assert_includes(names, 'dining', 'dining did not land on the same story as the kitchen')
    assert_equal(1, (names.index('food preparation') - names.index('dining')).abs,
                 "kitchen and dining were not consecutive slices: #{names.inspect}")
  end

  # Same model, no pairs: the ordering is the floor area ordering, and the pair is split. This is
  # the behavior every existing caller gets, so it has to be preserved.
  def test_multi_story_slicing_without_pairs_is_unchanged
    model = OpenStudio::Model::Model.new
    space_types = {}
    entries_for(model, LEG_D_MID_STORY).each { |key, hash| space_types[key] = hash }

    length = OpenStudio.convert(300.0, 'ft', 'm').get
    width = OpenStudio.convert(100.0, 'ft', 'm').get
    total = space_types.values.sum { |v| v[:floor_area] }
    story_hash = {}
    (total / (length * width)).ceil.times do |i|
      story_hash["story #{i}"] = { space_origin_z: i * 4.0, space_height: 4.0, multiplier: 1, partial_story_multiplier: 1.0 }
    end

    footprints = @geometry.create_sliced_bar_multi_polygons(deep_copy(space_types), length, width,
                                                           OpenStudio::Point3d.new(0.0, 0.0, 0.0), story_hash)
    story = footprints.find { |f| slice_names(f).include?('food preparation') }
    names = slice_names(story)
    refute_equal(1, (names.index('food preparation') - names.index('dining')).abs) if names.include?('dining')
  end

  # the slicing methods consume the floor areas they are handed
  def deep_copy(space_types)
    space_types.each_with_object({}) { |(key, hash), copy| copy[key] = hash.dup }
  end

  # distinct space type names in slice order, from a footprint hash
  def slice_names(footprint)
    footprint.values.map { |v| v[:space_type].nil? ? nil : v[:space_type].name.to_s }.compact.uniq
  end
end
