require_relative '../helpers/minitest_helper'
require_relative '../helpers/hvac_system_test_helper'

class TestAddHVACSystems < Minitest::Test
  # @todo add support for additional variations of building type (office, multifamily), geometry (20, 60 wwr), and climate zone (2A, 5B, 7A)

  def test_add_hvac_systems_ideal_loads
    hvac_systems = [
      {system_type: 'Ideal Air Loads'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_residential
    hvac_systems = [
      {system_type: 'Window AC', cool_fuel: 'Electricity', zone_selection: 'cooled_zones', climate_zone: 'ASHRAE 169-2013-2B', unmet_hrs_htg: 3000.0},
      {system_type: 'Residential AC', cool_fuel: 'Electricity', zone_selection: 'cooled_zones', climate_zone: 'ASHRAE 169-2013-2B', unmet_hrs_htg: 3000.0},
      {system_type: 'Residential Forced Air Furnace', main_heat_fuel: 'NaturalGas', unmet_hrs_clg: 6000.0},
      {system_type: 'Residential Forced Air Furnace with AC', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity'},
      {system_type: 'Residential Air Source Heat Pump', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity'}
      # @todo couple with baseboards and other heating systems, e.g. window ac and forced air
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_sz_heating
    hvac_systems = [
      {model_test_name: 'Baseboards_elec', system_type: 'Baseboards', main_heat_fuel: 'Electricity', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {model_test_name: 'Baseboards_gas', system_type: 'Baseboards', main_heat_fuel: 'NaturalGas', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {model_test_name: 'Baseboards_ashp', system_type: 'Baseboards', main_heat_fuel: 'AirSourceHeatPump', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {model_test_name: 'Baseboards_district', system_type: 'Baseboards', main_heat_fuel: 'DistrictHeating', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {system_type: 'Unit Heaters', main_heat_fuel: 'NaturalGas', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {system_type: 'High Temp Radiant', main_heat_fuel: 'NaturalGas', zone_selection: 'heated_zones', unmet_hrs_clg: 6000.0},
      {system_type: 'Forced Air Furnace', main_heat_fuel: 'NaturalGas', zone_selection: 'heated_zones', unmet_hrs_htg: 1800.0, unmet_hrs_clg: 6000.0}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_sz_cooling
    hvac_systems = [
      {system_type: 'Evaporative Cooler', cool_fuel: 'Electricity', zones: 'cooled_zones', climate_zone: 'ASHRAE 169-2013-2B', unmet_hrs_htg: 6000.0, unmet_hrs_clg: 3500.0}
    ]
    # @todo debug evaporative cooler performance
    # @todo add more evaporative cooler tests, combine with baseboards
    # @todo add climate zone coverage
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_ptac_pthp
    hvac_systems = [
      {model_test_name: 'PTAC_elec', system_type: 'PTAC', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity'},
      {model_test_name: 'PTAC_gas', system_type: 'PTAC', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity'},
      # {model_test_name: 'PTAC_ashp', system_type: 'PTAC', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity'},
      # @todo this test is failing the sizing run
      {model_test_name: 'PTAC_district_heat', system_type: 'PTAC', main_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity'},
      {model_test_name: 'PTAC_no_heat', system_type: 'PTAC', main_heat_fuel: nil, cool_fuel: 'Electricity', unmet_hrs_htg: 6000.0},
      # @todo add PTAC and baseboard pairings
      {system_type: 'PTHP', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_pszac_pszhp
    hvac_systems = [
      {model_test_name: 'PSZAC_elec_elec', system_type: 'PSZ-AC', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', unmet_hrs_htg: 450.0},
      {model_test_name: 'PSZAC_elec_district', system_type: 'PSZ-AC', main_heat_fuel: 'Electricity', cool_fuel: 'DistrictCooling', unmet_hrs_htg: 450.0},
      {model_test_name: 'PSZAC_gas_elec', system_type: 'PSZ-AC', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 450.0},
      {model_test_name: 'PSZAC_gas_district', system_type: 'PSZ-AC', main_heat_fuel: 'NaturalGas', cool_fuel: 'DistrictCooling', unmet_hrs_htg: 450.0},
      # {model_test_name: 'PSZAC_ashp_elec', system_type: 'PSZ-AC', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity'},
      # {model_test_name: 'PSZAC_ashp_district', system_type: 'PSZ-AC', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'DistrictCooling'},
      # @todo this test is failing the sizing run
      {model_test_name: 'PSZAC_district_elec', system_type: 'PSZ-AC', main_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity', unmet_hrs_htg: 450.0},
      {model_test_name: 'PSZAC_district_district', system_type: 'PSZ-AC', main_heat_fuel: 'DistrictHeating', cool_fuel: 'DistrictCooling', unmet_hrs_htg: 450.0},
      {model_test_name: 'PSZAC_no_heat_elec', system_type: 'PSZ-AC', main_heat_fuel: nil, cool_fuel: 'Electricity', unmet_hrs_htg: 6000.0},
      {model_test_name: 'PSZAC_no_heat_district', system_type: 'PSZ-AC', main_heat_fuel: nil, cool_fuel: 'DistrictCooling', unmet_hrs_htg: 6000.0},
      # @todo add PSZ-AC and baseboard pairings
      {system_type: 'PSZ-HP', main_heat_fuel: ['Electricity'], cool_fuel: ['Electricity']}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_vrf
    hvac_systems = [
      {system_type: 'VRF', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', unmet_hrs_htg: 900.0},
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_fan_coil
    hvac_systems = [
      {model_test_name: 'Fancoil_elec_elec_water', system_type: 'Fan Coil', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
      {model_test_name: 'Fancoil_elec_elec_air', system_type: 'Fan Coil', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'AirCooled'},
      {model_test_name: 'Fancoil_elec_district', system_type: 'Fan Coil', main_heat_fuel: 'Electricity', cool_fuel: 'DistrictCooling'},
      {model_test_name: 'Fancoil_gas_elec_water', system_type: 'Fan Coil', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
      {model_test_name: 'Fancoil_gas_elec_air', system_type: 'Fan Coil', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'AirCooled'},
      {model_test_name: 'Fancoil_gas_district', system_type: 'Fan Coil', main_heat_fuel: 'NaturalGas', cool_fuel: 'DistrictCooling'},
      {model_test_name: 'Fancoil_ashp_elec_water', system_type: 'Fan Coil', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
      {model_test_name: 'Fancoil_ashp_elec_air', system_type: 'Fan Coil', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'AirCooled'},
      {model_test_name: 'Fancoil_ashp_district', system_type: 'Fan Coil', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'DistrictCooling'},
      {model_test_name: 'Fancoil_district_elec_water', system_type: 'Fan Coil', main_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
      {model_test_name: 'Fancoil_district_elec_air', system_type: 'Fan Coil', main_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'AirCooled'},
      {model_test_name: 'Fancoil_district_district', system_type: 'Fan Coil', main_heat_fuel: 'DistrictHeating', cool_fuel: 'DistrictCooling'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_wshp
    hvac_systems = [
      {model_test_name: 'WSHP_elec_elec_clg_twr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
      {model_test_name: 'WSHP_elec_elec_fld_clr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'FluidCooler'},
      {model_test_name: 'WSHP_gas_elec_clg_twr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
      # {model_test_name: 'WSHP_ashp_clg_twr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
      # @todo fix failing sizing run
      {model_test_name: 'WSHP_ambient_clg_twr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
      {model_test_name: 'WSHP_ambient_clg_twr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'AmbientLoop', cool_fuel: 'AmbientLoop', heat_pump_loop_cooling_type: 'CoolingTower'},
      # {model_test_name: 'WSHP_ambient_fld_clr', system_type: 'Water Source Heat Pumps', main_heat_fuel: 'AmbientLoop', cool_fuel: 'AmbientLoop', heat_pump_loop_cooling_type: 'FluidCooler'}
      # @todo this test is failing the sizing run
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_vav
    hvac_systems = [
      {model_test_name: 'PVAV_Reheat_gas_elec', system_type: 'PVAV Reheat', main_heat_fuel: 'NaturalGas', zone_heat_fuel: 'Electricity', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'PVAV_Reheat_gas_gas', system_type: 'PVAV Reheat', main_heat_fuel: 'NaturalGas', zone_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'PVAV_Reheat_ashp', system_type: 'PVAV Reheat', main_heat_fuel: 'AirSourceHeatPump', zone_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'PVAV_Reheat_district', system_type: 'PVAV Reheat', main_heat_fuel: 'DistrictHeating', zone_heat_fuel: 'DistrictHeating', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'PVAV_PFP_Boxes', system_type: 'PVAV PFP Boxes', main_heat_fuel: 'Electricity', zone_heat_fuel: 'Electricity', cool_fuel: 'Electricity'},
      {model_test_name: 'VAV_Reheat_gas_gas', system_type: 'VAV Reheat', main_heat_fuel: 'NaturalGas', zone_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 550.0},
      {model_test_name: 'VAV_Reheat_ashp_gas', system_type: 'VAV Reheat', main_heat_fuel: 'AirSourceHeatPump', zone_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 550.0},
      {model_test_name: 'VAV_Reheat_ashp_ashp', system_type: 'VAV Reheat', main_heat_fuel: 'AirSourceHeatPump', zone_heat_fuel: 'AirSourceHeatPump', cool_fuel: 'Electricity', unmet_hrs_htg: 550.0},
      {model_test_name: 'VAV_Reheat_district', system_type: 'VAV Reheat', main_heat_fuel: 'DistrictHeating', zone_heat_fuel: 'DistrictHeating', cool_fuel: 'DistrictCooling', unmet_hrs_htg: 550.0},
      {model_test_name: 'VAV_PFP_gas_elec', system_type: 'VAV PFP Boxes', main_heat_fuel: 'NaturalGas', zone_heat_fuel: 'Electricity', cool_fuel: 'Electricity'},
      {model_test_name: 'VAV_PFP_ashp_elec', system_type: 'VAV PFP Boxes', main_heat_fuel: 'AirSourceHeatPump', zone_heat_fuel: 'Electricity', cool_fuel: 'Electricity'},
      {model_test_name: 'VAV_PFP_district', system_type: 'VAV PFP Boxes', main_heat_fuel: 'DistrictHeating', zone_heat_fuel: 'Electricity', cool_fuel: 'DistrictCooling'},
      {model_test_name: 'VAV_Gas_Reheat_gas_gas', system_type: 'VAV Gas Reheat', main_heat_fuel: 'NaturalGas', zone_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'VAV_Gas_Reheat_ashp', system_type: 'VAV Gas Reheat', main_heat_fuel: 'AirSourceHeatPump', zone_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 1500.0},
      {model_test_name: 'VAV_Gas_Reheat_district', system_type: 'VAV Gas Reheat', main_heat_fuel: 'DistrictHeating', zone_heat_fuel: 'NaturalGas', cool_fuel: 'DistrictCooling', unmet_hrs_htg: 1500.0},
      {model_test_name: 'VAV_No_Reheat', system_type: 'VAV No Reheat', main_heat_fuel: 'NaturalGas', zone_heat_fuel: nil, cool_fuel: 'Electricity', zones: 'cooled_zones', unmet_hrs_htg: 3750.0}
      # @todo unmet hours are likely related to the different ventilation rate procedure/zone sum sizing criteria
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_doas
    hvac_systems = [
      {system_type: 'Fan Coil with DOAS', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
      {system_type: 'Water Source Heat Pumps with DOAS', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
      {system_type: 'Ground Source Heat Pumps with DOAS', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', air_loop_heating_type: 'DX', air_loop_cooling_type: 'DX'},
      {system_type: 'VRF with DOAS', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', air_loop_heating_type: 'DX', air_loop_cooling_type: 'DX', climate_zone: 'ASHRAE 169-2013-4A'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_doas_dcv
    hvac_systems = [
      {system_type: 'Fan Coil with DOAS with DCV', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_ervs
    hvac_systems = [
        {system_type: 'Fan Coil with ERVs', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'Water_Cooled'},
        {system_type: 'Water Source Heat Pumps with ERVs', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', heat_pump_loop_cooling_type: 'CoolingTower'},
        {system_type: 'Ground Source Heat Pumps with ERVs', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', air_loop_heating_type: 'DX', air_loop_cooling_type: 'DX'},
        {system_type: 'VRF with ERVs', main_heat_fuel: 'Electricity', cool_fuel: 'Electricity', air_loop_heating_type: 'DX', air_loop_cooling_type: 'DX', climate_zone: 'ASHRAE 169-2013-4A'}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_residential_ervs
    hvac_systems = [
      {system_type: 'Residential ERVs', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 3250.0, unmet_hrs_clg: 3000.0},
      {system_type: 'Residential Ventilators', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', unmet_hrs_htg: 3250.0, unmet_hrs_clg: 3000.0}
    ]
    group_hvac_test(hvac_systems)
  end

  def test_add_hvac_systems_radiant
    hvac_systems = [
      {system_type: 'Radiant Slab with DOAS', main_heat_fuel: 'NaturalGas', cool_fuel: 'Electricity',
       hot_water_loop_type: 'LowTemperature', climate_zone: 'ASHRAE 169-2013-5B', model_name: 'basic_2_story_office_no_hvac_20WWR',
       unmet_hrs_htg: 700.0, unmet_hrs_clg: 3500.0}
    ]
    group_hvac_test(hvac_systems)
  end
end
