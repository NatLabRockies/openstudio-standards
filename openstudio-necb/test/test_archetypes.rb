require_relative 'test_helper'

# The NECB 2025 8.4.4 archetype machinery: space mapping with model-derived
# areas (8.4.4.1.(3)), pro-rata distribution (8.4.4.1.(4)), applicability
# refusals, the Table 8.4.4.2 conformance check and the normalization
# transform. All CLI-free (SDK only — the EUI path's model work needs no
# EnergyPlus until the annual run).
class TestArchetypes < Minitest::Test
  include FixtureHelper

  A = OpenStudioNECB::Archetypes

  def quiet
    OpenStudioNECB::AuditLog.new
  end

  # -- mapping / areas -------------------------------------------------------

  def test_resolve_all_and_explicit_lists
    model = load_fixture
    resolved = A.resolve!(model, { 'Office' => :all }, audit: quiet)
    assert_equal 5, resolved[:archetypes]['Office'][:spaces].size
    assert_in_delta model.getBuilding.floorArea, resolved[:archetypes]['Office'][:area_m2], 0.01,
                    'areas come from the model, not the caller'
    assert_equal 0.0, resolved[:unmapped][:area_m2]

    core = model.getSpaces.map(&:nameString).find { |n| n.include?('Core') }
    resolved = A.resolve!(model, { 'School (K-12)' => [core], 'Office' => :all }, audit: quiet)
    assert_equal 1, resolved[:archetypes]['School (K-12)'][:spaces].size
    assert_equal 4, resolved[:archetypes]['Office'][:spaces].size, ':all takes the unclaimed remainder'
  end

  def test_resolve_rejects_bad_input
    model = load_fixture
    assert_raises(ArgumentError) { A.resolve!(model, { 'Casino' => :all }, audit: quiet) }
    assert_raises(ArgumentError) { A.resolve!(model, { 'Office' => ['No Such Space'] }, audit: quiet) }
    assert_raises(ArgumentError) { A.resolve!(model, { 'Office' => :all, 'School (K-12)' => :all }, audit: quiet) }
    core = model.getSpaces.map(&:nameString).find { |n| n.include?('Core') }
    error = assert_raises(ArgumentError) do
      A.resolve!(model, { 'Office' => [core], 'School (K-12)' => [core] }, audit: quiet)
    end
    assert_includes error.message, 'mapped to both'
  end

  # 8.4.4.1.(4): unmapped area distributed pro-rata; over-assignment is
  # impossible by construction (areas come from disjoint space sets).
  def test_bet_areas_pro_rata_sums_to_model_total
    model = load_fixture
    names = model.getSpaces.sort_by { |s| -s.floorArea }.map(&:nameString)
    resolved = A.resolve!(model, { 'Office' => names.first(4) }, audit: quiet) # 1 space unmapped
    assert_operator resolved[:unmapped][:area_m2], :>, 0
    areas = A.bet_areas(resolved, audit: quiet)
    assert_in_delta resolved[:total_area_m2], areas.values.sum, 1e-6,
                    'BET areas sum to the model total after pro-rata (8.4.4.1.(4))'
  end

  def test_applicability_refusals
    model = load_fixture
    all = A.resolve!(model, { 'Office' => :all }, audit: quiet)
    assert_raises(ArgumentError) { A.applicability!(all, hdd: 9500, audit: quiet) }

    smallest = model.getSpaces.min_by(&:floorArea).nameString
    sparse = A.resolve!(model, { 'Office' => [smallest] }, audit: quiet)
    error = assert_raises(ArgumentError) { A.applicability!(sparse, hdd: 3890, audit: quiet) }
    assert_includes error.message, '8.4.4.1.(1)'
  end

  # -- conformance + normalization ------------------------------------------

  def test_bare_model_is_not_conformant_with_named_mismatches
    model = load_fixture
    resolved = A.resolve!(model, { 'Office' => :all }, audit: quiet)
    check = A.conformance(model, resolved, vintage: '2025', audit: quiet)
    refute check[:conformant]
    assert(check[:mismatches].any? { |m| m.include?('occupant density') }, 'names the density gap')
    assert(check[:mismatches].any? { |m| m.include?('receptacle') }, 'names the receptacle gap')
  end

  # The strong one: normalize! then conformance must agree — the check and the
  # transform are two views of the same Table 8.4.4.2 contract, and this pins
  # them together (a drift in either direction fails here).
  def test_normalize_then_check_round_trip
    model = proposed_with_hvac
    # seed SWH equipment so the L/h/occupant normalization has something to set
    model.getSpaces.each do |space|
      definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
      equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
      equipment.setName("#{space.nameString} SWH")
      equipment.setSpace(space)
    end
    audit = quiet
    resolved = A.resolve!(model, { 'Office' => :all }, audit: audit)
    A.normalize!(model, resolved, vintage: '2025', audit: audit)

    check = A.conformance(model, A.resolve!(model, { 'Office' => :all }, audit: audit),
                          vintage: '2025', audit: audit)
    assert check[:conformant], "normalize->check round trip failed: #{check[:mismatches].first(5).join(' | ')}"

    # spot-check the physical values against Table 8.4.4.2 (Office row)
    space = model.getSpaces.first
    assert_in_delta 1.0 / 25.0, space.numberOfPeople / space.floorArea, 1e-4, 'Office: 25 m2/person'
    assert_in_delta 7.5, space.electricEquipmentPowerPerFloorArea, 0.01, 'Office: 7.5 W/m2 receptacle'
    zone = space.thermalZone.get
    refute zone.thermostatSetpointDualSetpoint.empty?, 'zone thermostat forced to the letter-A setpoints'
  end

  def test_lighting_power_is_never_touched
    model = load_fixture
    space_type = model.getSpaceTypes.find { |st| st.spaces.any? }
    definition = OpenStudio::Model::LightsDefinition.new(model)
    definition.setWattsperSpaceFloorArea(99.0)
    lights = OpenStudio::Model::Lights.new(definition)
    lights.setSpaceType(space_type)

    space = model.getSpaces.first
    before = space.lightingPowerPerFloorArea # fixture lights + the hostile 99
    resolved = A.resolve!(model, { 'Office' => :all }, audit: quiet)
    A.normalize!(model, resolved, vintage: '2025', audit: quiet)

    assert_in_delta before, space.lightingPowerPerFloorArea, 0.01,
                    'lighting power is the design under evaluation — normalization must not touch it'
  end

  # -- pipeline integration (CLI-free) ---------------------------------------

  def test_eui_path_none_mode_normalizes_without_mutating_caller
    model = proposed_with_hvac
    people_before = model.getPeoples.size
    result = OpenStudioNECB.performance_compliance(
      model, vintage: '2025', path: :eui, simulate: :none, hdd: 3890,
      archetypes: { 'Office' => :all }, run_dir: Dir.mktmpdir('osnecb-euinone-'))

    assert_equal people_before, model.getPeoples.size, 'caller model never mutated'
    assert result.report['eui']['normalized']
    assert_operator result.proposed_model.getPeoples.size, :>, 0, 'the RUN model carries the Table loads'
    assert_in_delta result.proposed_model.getBuilding.floorArea * 175,
                    result.report['reference']['building_energy_target_kwh'], 1.0
    assert_nil result.compliant, 'no determination without an annual run'
  end

  # The supplement's not-computed contract, unit-level (no E+): a proposed that
  # does not conform, without run_normalized, must yield an explicit
  # not-computed result with the mismatch list — never a verdict.
  def test_supplement_not_computed_without_run_normalized
    model = proposed_with_hvac
    audit = quiet
    report = { 'proposed' => { 'total_site_kwh' => 100_000.0 } }
    out = OpenStudioNECB::Compliance.eui_supplement_verdict(
      model, { archetypes: { 'Office' => :all } }, 3890, report, Dir.mktmpdir('osnecb-sup-'),
      nil, '2025', audit)
    assert_equal false, out['computed']
    assert_includes out['reason'], 'does not conform'
    refute_empty out['mismatches']
    assert(audit.warnings.any? { |w| w[:action].include?('NOT COMPUTED') })
  end
end
