

###### (Automatically generated documentation)

# BTAP Results

## Description
This measure creates BTAP result values used for NRCan analyses.

## Modeler Description
Grabs data from OS model and sql database and keeps them in the 

## Measure Type
ReportingMeasure

## Taxonomy


## Arguments


### Generate Hourly Report

**Name:** generate_hourly_report,
**Type:** String,
**Units:** ,
**Required:** false,
**Model Dependent:** false

### Reduce outputs

**Name:** output_diet,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Envelope Costing

**Name:** envelope_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Lighting Costing

**Name:** lighting_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Boiler Costing

**Name:** boilers_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Chiller Costing

**Name:** chillers_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Cooling Tower Costing

**Name:** cooling_towers_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Service Hot Water Costing

**Name:** shw_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Ventilation Costing

**Name:** ventilation_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Zone System Costing

**Name:** zone_system_costing,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Baseline Capital Costs ($/m2). This is used to calculate simple payback. -1 skips

**Name:** baseline_cost_equipment_total_cost_per_m_sq,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Baseline Energy (GJ/m2).  This is used to calculate baseline percent energy change. -1 skips

**Name:** baseline_energy_eui_total_gj_per_m_sq,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Baseline Energy Costs ($/m2).  This is used to calculate simple payback. -1 skips

**Name:** baseline_cost_utility_neb_total_cost_per_m_sq,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Net Present Value: start year

**Name:** npv_start_year,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Net Present Value: end year

**Name:** npv_end_year,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Net Present Value: discount rate

**Name:** npv_discount_rate,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false





## Outputs






































































































































































































baseline_capital_cost_difference_per_m_2, baseline_cost_utility_neb_difference_per_m_2_per_year, baseline_energy_percent_change, baseline_payback_yrs, bldg_conditioned_floor_area_m_sq, bldg_exterior_area_m_sq, bldg_fdwr, bldg_name, bldg_nominal_floor_to_ceiling_height, bldg_nominal_floor_to_floor_height, bldg_srr, bldg_standards_building_type, bldg_standards_number_of_above_ground_stories, bldg_standards_number_of_stories, bldg_standards_template, bldg_surface_to_volume_ratio, bldg_volume_m_cu, cost_equipment_envelope_total_cost_per_m_sq, cost_equipment_heating_and_cooling_total_cost_per_m_sq, cost_equipment_lighting_total_cost_per_m_sq, cost_equipment_shw_total_cost_per_m_sq, cost_equipment_total_cost_per_m_sq, cost_equipment_ventilation_total_cost_per_m_sq, cost_equipment_renewables_total_cost_per_m_sq, cost_city, cost_province_state, cost_utility_neb_electricity_cost_per_m_sq, cost_utility_neb_natural_gas_cost_per_m_sq, cost_utility_neb_oil_cost_per_m_sq, cost_utility_neb_total_cost_per_m_sq, energy_eui_additional_fuel_gj_per_m_sq, energy_eui_cooling_gj_per_m_sq, energy_eui_district_cooling_gj_per_m_sq, energy_eui_district_heating_gj_per_m_sq, energy_eui_electricity_gj_per_m_sq, energy_eui_fans_gj_per_m_sq, energy_eui_heating_gj_per_m_sq, energy_eui_interior_equipment_gj_per_m_sq, energy_eui_interior_lighting_gj_per_m_sq, energy_eui_natural_gas_gj_per_m_sq, energy_eui_total_gj_per_m_sq, energy_eui_water_systems_gj_per_m_sq, energy_peak_electric_w_per_m_sq, energy_peak_natural_gas_w_per_m_sq, energy_principal_heating_source, envelope_ground_floors_average_conductance_w_per_m_sq_k, envelope_ground_roofs_average_conductance_w_per_m_sq_k, envelope_ground_walls_average_conductance_w_per_m_sq_k, envelope_outdoor_doors_average_conductance_w_per_m_sq_k, envelope_outdoor_floors_average_conductance_w_per_m_sq_k, envelope_outdoor_overhead_doors_average_conductance_w_per_m_sq_k, envelope_outdoor_roofs_average_conductance_w_per_m_sq_k, envelope_outdoor_walls_average_conductance_w_per_m_sq_k, envelope_outdoor_windows_average_conductance_w_per_m_sq_k, envelope_skylights_average_conductance_w_per_m_sq_k, location_cdd, location_city, location_country, location_hdd, location_latitude, location_longitude, location_state_province_region, location_weather_file, location_zone, shw_additional_fuel_per_year, shw_electricity_per_day, shw_electricity_per_day_per_occupant, shw_electricity_per_year, shw_natural_gas_per_year, shw_total_nominal_occupancy, shw_water_m_cu_per_day, shw_water_m_cu_per_day_per_occupant, shw_water_m_cu_per_year, simulation_btap_data_version, simulation_date, simulation_os_standards_revision, simulation_os_standards_version, npv_total_per_m_sq, airloops_total_outdoor_air_mechanical_ventilation_ach_1_per_hr, airloops_total_outdoor_air_mechanical_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2, airloops_total_outdoor_air_mechanical_ventilation_flow_per_exterior_area_m3_per_s_m2, airloops_total_outdoor_air_mechanical_ventilation_m3, airloops_total_outdoor_air_natural_ventilation_ach_1_per_hr, airloops_total_outdoor_air_natural_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2, airloops_total_outdoor_air_natural_ventilation_flow_per_exterior_area_m3_per_s_m2, airloops_total_outdoor_air_natural_ventilation_m3, zones_total_outdoor_air_infiltration_ach_1_per_hr, zones_total_outdoor_air_infiltration_flow_per_conditioned_floor_area_m3_per_s_m2, zones_total_outdoor_air_infiltration_flow_per_exterior_area_m3_per_s_m2, zones_total_outdoor_air_infiltration_m3, zones_total_outdoor_air_mechanical_ventilation_ach_1_per_hr, zones_total_outdoor_air_mechanical_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2, zones_total_outdoor_air_mechanical_ventilation_flow_per_exterior_area_m3_per_s_m2, zones_total_outdoor_air_mechanical_ventilation_m3, zones_total_outdoor_air_natural_ventilation_ach_1_per_hr, zones_total_outdoor_air_natural_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2, zones_total_outdoor_air_natural_ventilation_flow_per_exterior_area_m3_per_s_m2, zones_total_outdoor_air_natural_ventilation_m3
