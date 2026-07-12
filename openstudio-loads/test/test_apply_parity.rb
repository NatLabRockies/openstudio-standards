require_relative 'test_helper'

# P3 gate (parity half): per-object load values match legacy
# space_type_apply_internal_loads(set_lights: false) + schedule/thermostat applies
# on identically tagged models, across several space types (occupancy-heavy,
# ventilation-ACH, gas-equipment). Runs under the repo bundle.
class TestApplyParity < Minitest::Test
  include FixtureHelper

  PAIRS = [
    ['Space Function', 'Office enclosed > 25 m2'],
    ['Space Function', 'Corridor/Transition area other-sch-A'],
    ['Space Function', 'Dining area - family dining'],
    ['Space Function', 'Food preparation area'],
    ['Space Function', 'Warehouse storage area medium to bulky palletized items'],
    ['Space Function', 'Classroom/Lecture hall/Training room other'],
    ['Space Function', 'Computer/Server room-sch-A']
  ].freeze

  def self.legacy
    @legacy ||= begin
      require File.expand_path('../../lib/openstudio-standards', __dir__)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy
    skip 'openstudio-standards not loadable — parity gate runs from the monorepo' if std == :unavailable
    std
  end

  def existing_pairs
    PAIRS.select do |building_type, space_type|
      OpenStudioLoads::NECB::SpaceTypes.find(building_type: building_type, space_type: space_type)
    end
  end

  def tagged_model(pairs)
    model = OpenStudio::Model::Model.new
    pairs.each do |building_type, space_type|
      st = OpenStudio::Model::SpaceType.new(model)
      st.setName("#{building_type} #{space_type}")
      st.setStandardsBuildingType(building_type)
      st.setStandardsSpaceType(space_type)
    end
    model
  end

  def optional_f(value)
    value.is_initialized ? value.get.round(9) : nil
  end

  def signature(space_type)
    people = space_type.people.first
    equip = space_type.electricEquipment.first
    gas = space_type.gasEquipment.first
    dsoa = space_type.designSpecificationOutdoorAir
    infiltration = space_type.spaceInfiltrationDesignFlowRates.first
    schedule_set = space_type.defaultScheduleSet
    {
      people_per_m2: people ? optional_f(people.peopleDefinition.peopleperSpaceFloorArea) : nil,
      people_frac_radiant: people ? people.peopleDefinition.fractionRadiant.round(9) : nil,
      epd_w_m2: equip ? optional_f(equip.electricEquipmentDefinition.wattsperSpaceFloorArea) : nil,
      epd_frac_latent: equip ? equip.electricEquipmentDefinition.fractionLatent.round(9) : nil,
      epd_frac_radiant: equip ? equip.electricEquipmentDefinition.fractionRadiant.round(9) : nil,
      epd_frac_lost: equip ? equip.electricEquipmentDefinition.fractionLost.round(9) : nil,
      gas_w_m2: gas ? optional_f(gas.gasEquipmentDefinition.wattsperSpaceFloorArea) : nil,
      oa_method: dsoa.is_initialized ? dsoa.get.outdoorAirMethod : nil,
      oa_per_area: dsoa.is_initialized ? dsoa.get.outdoorAirFlowperFloorArea.round(9) : nil,
      oa_per_person: dsoa.is_initialized ? dsoa.get.outdoorAirFlowperPerson.round(9) : nil,
      oa_ach: dsoa.is_initialized ? dsoa.get.outdoorAirFlowAirChangesperHour.round(9) : nil,
      infil_per_ext: infiltration ? optional_f(infiltration.flowperExteriorSurfaceArea) : nil,
      infil_per_wall: infiltration ? optional_f(infiltration.flowperExteriorWallArea) : nil,
      infil_ach: infiltration ? optional_f(infiltration.airChangesperHour) : nil,
      occ_sch: schedule_set.is_initialized ? optional_name(schedule_set.get.numberofPeopleSchedule) : nil,
      act_sch: schedule_set.is_initialized ? optional_name(schedule_set.get.peopleActivityLevelSchedule) : nil,
      equip_sch: schedule_set.is_initialized ? optional_name(schedule_set.get.electricEquipmentSchedule) : nil
    }
  end

  def optional_name(optional)
    optional.is_initialized ? optional.get.nameString : nil
  end

  def test_per_object_parity
    std = legacy
    pairs = existing_pairs
    assert_operator pairs.size, :>=, 4, "enough real space types to compare (#{pairs.inspect})"

    gem_model = tagged_model(pairs)
    OpenStudioLoads::NECB.apply_loads(gem_model, vintage: '2020')

    legacy_model = tagged_model(pairs)
    legacy_model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      std.space_type_apply_internal_loads(space_type: space_type, set_lights: false)
      std.space_type_apply_internal_load_schedules(space_type, set_lights: false)
      std.space_type_apply_thermostat_schedules(space_type)
    end

    mismatches = []
    pairs.each do |building_type, space_type_name|
      full = "#{building_type} #{space_type_name}"
      gem_st = gem_model.getSpaceTypes.find { |s| s.nameString == full }
      legacy_st = legacy_model.getSpaceTypes.find { |s| s.nameString == full }
      gem_signature = signature(gem_st)
      legacy_signature = signature(legacy_st)
      next if gem_signature == legacy_signature

      diff = gem_signature.keys.select { |k| gem_signature[k] != legacy_signature[k] }
                          .map { |k| "#{k}: gem=#{gem_signature[k].inspect} legacy=#{legacy_signature[k].inspect}" }
      mismatches << "#{space_type_name}: #{diff.join('; ')}"
    end
    assert_empty mismatches, "per-object parity mismatches:\n#{mismatches.join("\n")}"

    # thermostat schedule parity
    pairs.each do |building_type, space_type_name|
      full = "#{building_type} #{space_type_name} Thermostat"
      gem_t = gem_model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == full }
      legacy_t = legacy_model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == full }
      refute_nil gem_t, full
      refute_nil legacy_t, full
      assert_equal optional_name(legacy_t.heatingSetpointTemperatureSchedule),
                   optional_name(gem_t.heatingSetpointTemperatureSchedule), full
      assert_equal optional_name(legacy_t.coolingSetpointTemperatureSchedule),
                   optional_name(gem_t.coolingSetpointTemperatureSchedule), full
    end
  end
end
