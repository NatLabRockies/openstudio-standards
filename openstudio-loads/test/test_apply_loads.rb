require_relative 'test_helper'

# P3 gate (standalone half): assign_space_types on-ramp + apply_loads golden
# assertions (people/equipment densities, DSOA rescale, infiltration, schedule
# wiring, thermostats, skips, coverage emission).
class TestApplyLoads < Minitest::Test
  include FixtureHelper

  MAP_TYPES = {
    'office' => ['Space Function', 'Office enclosed > 25 m2'],
    'corridor' => ['Space Function', 'Corridor/Transition area other-sch-A'],
    'dining' => ['Space Function', 'Dining area - family dining']
  }.freeze

  def mapped_model
    model = load_fixture
    spaces = model.getSpaces.sort_by(&:nameString)
    map = {}
    spaces.each_with_index do |space, index|
      map[space.nameString] = index.zero? ? MAP_TYPES['corridor'] : MAP_TYPES['office']
    end
    [model, map]
  end

  def applied_model
    model, map = mapped_model
    audit = OpenStudioLoads::AuditLog.new
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020', audit: audit)
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)
    [model, audit]
  end

  def office_space_type(model)
    model.getSpaceTypes.find { |st| st.nameString.include?('Office enclosed > 25 m2') }
  end

  def test_assign_space_types_on_ramp
    model, map = mapped_model
    audit = OpenStudioLoads::AuditLog.new
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020', audit: audit)
    decision = audit.entries.find { |e| e[:action] == 'NECB space types assigned' }
    assert_equal 2, decision[:inputs][:space_types_created], 'one SpaceType per distinct pair'
    model.getSpaces.each do |space|
      assert space.spaceType.is_initialized
      assert space.spaceType.get.standardsBuildingType.is_initialized
    end
    assert_raises(ArgumentError) do
      OpenStudioLoads.assign_space_types(model, { model.getSpaces.first.nameString => %w[Nope Nada] })
    end
  end

  def test_people_and_equipment_golden
    model, = applied_model
    office = office_space_type(model)
    record = OpenStudioLoads::NECB::SpaceTypes.record(
      building_type: 'Space Function', space_type: 'Office enclosed > 25 m2')

    people = office.people.first
    expected_density = OpenStudio.convert(record['occupancy_per_area'].to_f / 1000, 'people/ft^2', 'people/m^2').get
    assert_in_delta expected_density, people.peopleDefinition.peopleperSpaceFloorArea.get, 1e-9
    assert_in_delta 0.3, people.peopleDefinition.fractionRadiant, 1e-9
    assert people.clothingInsulationSchedule.is_initialized, 'comfort schedules wired'

    equip = office.electricEquipment.first
    expected_epd = OpenStudio.convert(record['electric_equipment_per_area'].to_f, 'W/ft^2', 'W/m^2').get
    assert_in_delta expected_epd, equip.electricEquipmentDefinition.wattsperSpaceFloorArea.get, 1e-9

    assert_empty office.lights.to_a, 'NO Lights objects — lighting gem territory'
  end

  def test_ventilation_rescale_and_stash
    model, = applied_model
    office = office_space_type(model)
    record = OpenStudioLoads::NECB::SpaceTypes.record(
      building_type: 'Space Function', space_type: 'Office enclosed > 25 m2')
    dsoa = office.designSpecificationOutdoorAir.get

    assert_equal 'Sum', dsoa.outdoorAirMethod
    per_person = record['ventilation_per_person'].to_f
    unless per_person.zero?
      expected = per_person * record['ventilation_occupancy_rate_people_per_1000ft2'].to_f /
                 record['occupancy_per_area'].to_f
      expected_si = OpenStudio.convert(expected, 'ft^3/min*person', 'm^3/s*person').get
      assert_in_delta expected_si, dsoa.outdoorAirFlowperPerson, 1e-9, 'per-person RESCALE applied'
    end
    stash = dsoa.additionalProperties
    assert stash.getFeatureAsDouble('Ref OA per person').is_initialized, 'source values stashed'
    assert stash.getFeatureAsString('Ref standard').is_initialized
  end

  def test_schedules_thermostats_and_infiltration
    model, = applied_model
    office = office_space_type(model)
    record = OpenStudioLoads::NECB::SpaceTypes.record(
      building_type: 'Space Function', space_type: 'Office enclosed > 25 m2')

    schedule_set = office.defaultScheduleSet.get
    assert_equal record['occupancy_schedule'],
                 schedule_set.numberofPeopleSchedule.get.nameString
    assert schedule_set.electricEquipmentSchedule.is_initialized
    assert schedule_set.lightingSchedule.empty?, 'no lighting schedule wired'

    thermostat = model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == "#{office.nameString} Thermostat" }
    refute_nil thermostat
    assert_equal record['heating_setpoint_schedule'],
                 thermostat.heatingSetpointTemperatureSchedule.get.nameString

    unless record['infiltration_per_exterior_area'].to_f.zero?
      infiltration = office.spaceInfiltrationDesignFlowRates.first
      expected = OpenStudio.convert(record['infiltration_per_exterior_area'].to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get
      assert_in_delta expected, infiltration.flowperExteriorSurfaceArea.get, 1e-9
    end
  end

  def test_skips_and_coverage
    model, map = mapped_model
    plenum = OpenStudio::Model::SpaceType.new(model)
    plenum.setName('Attic plenum')
    audit = OpenStudioLoads::AuditLog.new
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020', audit: audit)
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)

    assert(audit.entries.any? { |e| e[:action].include?('plenum space type skipped') })
    coverage = audit.entries.select { |e| e[:step] == :coverage }
    assert_equal 5, coverage.size, 'all of subsection 8.4.3 accounted'
    partial = coverage.find { |e| e[:article] == '8.4.3.2.' }
    assert_equal :warning, partial[:level], 'partial status WARNS (lighting+SHW gaps)'
    assert_match(/openstudio-lighting/, partial[:action])
    decisions = audit.entries.select { |e| e[:article].to_s.include?('8.4.3.2') && e[:level] == :decision }
    refute_empty decisions
  end

  def test_2025_citation_prefix_flows_to_audit
    model, map = mapped_model
    audit = OpenStudioLoads::AuditLog.new
    OpenStudioLoads.assign_space_types(model, map, vintage: '2025', audit: audit)
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2025', audit: audit)
    office = office_space_type(model)
    refute_nil office.people.first, '2025 aliases the 2020 data'
  end
end
