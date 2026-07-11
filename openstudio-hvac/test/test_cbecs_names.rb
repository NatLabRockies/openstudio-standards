require_relative 'test_helper'

# CBECS descriptive names mapped onto the gem's families (first increment: the
# clean-topology matches). Zone partitioning (heated-only vs cooled, unit heaters
# for leftovers) remains the caller's job, as in openstudio-standards cbecs_hvac.
class TestCbecsNames < Minitest::Test
  include FixtureHelper

  def test_baseboard_electric
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'Baseboard electric', zones)

    assert_empty result.air_loops, 'baseboards-only: no air system'
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_empty model.getAirLoopHVACs
    assert_empty model.getPlantLoops
  end

  def test_baseboard_gas_boiler
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)

    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_equal 2, model.getBoilerHotWaters.size
    assert(model.getBoilerHotWaters.all? { |b| b.fuelType == 'NaturalGas' })
  end

  def test_psz_ac_gas_coil_builds_one_unit_per_zone
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'PSZ-AC with gas coil', zones)

    # CBECS/90.1 convention: one packaged unit per zone
    assert_equal zones.size, result.air_loops.size
    assert(result.air_loops.all? { |al| al.thermalZones.size == 1 })
    assert_equal zones.size, model.getCoilCoolingDXSingleSpeeds.size
    assert_equal zones.size, model.getCoilHeatingGass.size
    assert_equal zones.size, model.getSetpointManagerSingleZoneReheats.size
    # each unit controls its own zone
    model.getSetpointManagerSingleZoneReheats.each do |spm|
      al = spm.airLoopHVAC.get
      assert_equal al.thermalZones.first.handle.to_s, spm.controlZone.get.handle.to_s
    end
    assert_empty model.getZoneHVACBaseboardConvectiveElectrics, "baseboard_type 'None'"
  end

  def test_psz_ac_electric_coil
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ-AC with electric coil', zones)
    assert_equal zones.size, model.getCoilHeatingElectrics.size
    assert_empty model.getCoilHeatingGass
  end

  def test_catalog_filter_by_origin
    cbecs = OpenStudioHVAC.systems.select { |r| r['origin'] == 'cbecs' }
    assert_operator cbecs.size, :>=, 4
  end
end
