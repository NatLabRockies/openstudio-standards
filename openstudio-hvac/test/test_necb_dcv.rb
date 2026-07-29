require_relative 'test_helper'

# 8.4.4.15.(2) / 8.4.5.15.(2) (D-54): "where demand control ventilation strategies
# required by Article 5.2.3.4. are implemented in the proposed building, the
# reference building shall be modeled with those same strategies".
#
# The reference OA controller is REBUILT from scratch, so the strategy has to be
# carried across the teardown. The DCV-ON path is the one that matters: a test that
# only exercises the DCV-off path proves nothing, because the rebuilt controller is
# DCV-off by construction.
class TestNecbDcv < Minitest::Test
  include FixtureHelper

  PROPOSED = 'PSZ RTU Gas and DX Coils and Hot Water Baseboard'.freeze

  # A proposed model whose air loops actually carry DCV — the fixtures do not.
  def proposed(dcv: true, method: nil)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, PROPOSED, zones)
    model.getAirLoopHVACs.each do |air_loop|
      oa = air_loop.airLoopHVACOutdoorAirSystem
      next if oa.empty?

      mech = oa.get.getControllerOutdoorAir.controllerMechanicalVentilation
      mech.setDemandControlledVentilation(dcv)
      mech.setSystemOutdoorAirMethod(method) if method
    end
    model
  end

  def reference(model, vintage: '2020')
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, vintage: vintage,
      building: { storeys: 1, zone_types: model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] } },
      audit: audit
    )
    [result, audit]
  end

  def mech_controllers(model)
    model.getAirLoopHVACs.filter_map do |air_loop|
      oa = air_loop.airLoopHVACOutdoorAirSystem
      next if oa.empty?

      oa.get.getControllerOutdoorAir.controllerMechanicalVentilation
    end
  end

  # ---- the capture side ----

  def test_characterize_records_proposed_dcv
    facts = OpenStudioHVAC.characterize(proposed(dcv: true))
    air_groups = facts[:zone_groups].reject { |g| g[:air_loop].nil? }
    refute_empty air_groups
    assert(air_groups.all? { |g| g[:dcv] }, 'per-air-loop DCV captured in the facts schema')
    assert_equal ['ZoneSum'], air_groups.map { |g| g[:system_outdoor_air_method] }.uniq
  end

  def test_characterize_records_dcv_off
    facts = OpenStudioHVAC.characterize(proposed(dcv: false))
    air_groups = facts[:zone_groups].reject { |g| g[:air_loop].nil? }
    refute_empty air_groups
    refute(air_groups.any? { |g| g[:dcv] })
  end

  # ---- the copy side (the one that matters) ----

  def test_dcv_on_in_the_proposed_is_rebuilt_on_the_reference
    model = proposed(dcv: true)
    assert(mech_controllers(model).all?(&:demandControlledVentilation), 'precondition: proposed HAS DCV')

    result, audit = reference(model)
    controllers = mech_controllers(result.model)
    refute_empty controllers, 'reference builds air loops with OA systems'
    assert(controllers.all?(&:demandControlledVentilation),
           'the rebuilt reference OA controller carries the proposed DCV strategy')
    # sentence (1) convention is untouched: peak OA still determined by ZoneSum
    assert_equal ['ZoneSum'], controllers.map(&:systemOutdoorAirMethod).uniq

    entry = audit.entries.find { |e| e[:action].include?('demand-controlled ventilation strategy copied') }
    refute_nil entry, 'the copy is audited'
    assert_equal '8.4.4.15.(2)', entry[:article]
    assert_equal 'D-54', entry[:ruling]
    assert_equal :decision, entry[:level]
  end

  def test_no_dcv_in_the_proposed_leaves_the_reference_without_it
    result, audit = reference(proposed(dcv: false))
    refute(mech_controllers(result.model).any?(&:demandControlledVentilation))
    entry = audit.entries.find { |e| e[:action].include?('no demand-controlled ventilation') }
    refute_nil entry
    assert_equal '8.4.4.15.(2)', entry[:article]
    assert_equal 'D-54', entry[:ruling]
  end

  # A CO2-based strategy is a DIFFERENT strategy from occupancy-based DCV: copying
  # the flag alone would silently substitute one for the other.
  def test_co2_based_strategy_copies_the_method_and_warns_about_the_missing_balance
    result, audit = reference(proposed(dcv: true, method: 'IndoorAirQualityProcedure'))
    controllers = mech_controllers(result.model)
    assert(controllers.all?(&:demandControlledVentilation))
    assert_equal ['IndoorAirQualityProcedure'], controllers.map(&:systemOutdoorAirMethod).uniq

    warning = audit.entries.find { |e| e[:action].include?('NO carbon dioxide concentration balance') }
    refute_nil warning, 'an inert CO2 strategy is never silent'
    assert_equal :warning, warning[:level]
    assert_equal 'D-54', warning[:ruling]
  end

  # The peak-rate methods are sentence (1)'s subject, not a DCV strategy — copying
  # VRP would move the reference's peak outdoor air off the ZoneSum convention.
  def test_peak_rate_method_is_not_copied
    result, = reference(proposed(dcv: true, method: 'Standard62.1VentilationRateProcedure'))
    controllers = mech_controllers(result.model)
    assert(controllers.all?(&:demandControlledVentilation), 'the strategy IS copied')
    assert_equal ['ZoneSum'], controllers.map(&:systemOutdoorAirMethod).uniq,
                 'the peak-rate method is NOT copied'
  end

  def test_2025_cites_the_renumbered_article
    _, audit = reference(proposed(dcv: true), vintage: '2025')
    entry = audit.entries.find { |e| e[:action].include?('demand-controlled ventilation strategy copied') }
    refute_nil entry
    assert_equal '8.4.5.15.(2)', entry[:article]
  end

  # L-13: legacy guards DCV with a MISSPELLED sentinel ('NECB_Defualt' vs the
  # documented 'NECB_Default'), so the guard never fires. Filed as a legacy defect,
  # deliberately NOT ported.
  def test_legacy_misspelled_sentinel_is_not_ported
    hits = Dir.glob(File.expand_path('../lib/**/*.rb', __dir__)).select { |f| File.read(f).include?('NECB_Defualt') }
    assert_empty hits, "L-13's misspelled 'NECB_Defualt' guard must not be ported into this gem"
  end
end
