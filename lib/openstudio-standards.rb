require 'singleton'
require 'open3'
require_relative 'openstudio-standards/version'

module OpenstudioStandards
  require 'json' # Used to load standards JSON files

  # Load Modules

  # Geometry Module
  require_relative 'openstudio-standards/geometry/create'
  require_relative 'openstudio-standards/geometry/create_bar'
  require_relative 'openstudio-standards/geometry/create_shape'
  require_relative 'openstudio-standards/geometry/group'
  require_relative 'openstudio-standards/geometry/information'
  require_relative 'openstudio-standards/geometry/modify'

  # Construction Module
  require_relative 'openstudio-standards/constructions/create'
  require_relative 'openstudio-standards/constructions/information'
  require_relative 'openstudio-standards/constructions/modify'
  require_relative 'openstudio-standards/constructions/materials/information'
  require_relative 'openstudio-standards/constructions/materials/modify'

  # Equipment Module
  require_relative 'openstudio-standards/equipment/create_typical_equipment'
  require_relative 'openstudio-standards/equipment/create_transformer'

  # Infiltration Module
  require_relative 'openstudio-standards/infiltration/infiltration'
  require_relative 'openstudio-standards/infiltration/nist_infiltration'

  # Interior Lighting Module
  require_relative 'openstudio-standards/interior_lighting/create_lights'
  require_relative 'openstudio-standards/interior_lighting/create_typical_interior_lighting'

  # Daylighting Module
  require_relative 'openstudio-standards/daylighting/space'

  # Exterior Lighting Module
  require_relative 'openstudio-standards/exterior_lighting/create'
  require_relative 'openstudio-standards/exterior_lighting/information'

  # Refrigeration Module
  require_relative 'openstudio-standards/refrigeration/create_case'
  require_relative 'openstudio-standards/refrigeration/create_compressor'
  require_relative 'openstudio-standards/refrigeration/create_compressor_rack'
  require_relative 'openstudio-standards/refrigeration/create_refrigeration_system'
  require_relative 'openstudio-standards/refrigeration/create_typical_refrigeration'
  require_relative 'openstudio-standards/refrigeration/create_walkin'
  require_relative 'openstudio-standards/refrigeration/information'

  # Schedules Module
  require_relative 'openstudio-standards/schedules/create'
  require_relative 'openstudio-standards/schedules/modify'
  require_relative 'openstudio-standards/schedules/information'
  require_relative 'openstudio-standards/schedules/parametric'

  # ServiceWaterHeating Module
  require_relative 'openstudio-standards/service_water_heating/create_piping_losses'
  require_relative 'openstudio-standards/service_water_heating/create_typical'
  require_relative 'openstudio-standards/service_water_heating/create_water_heater'
  require_relative 'openstudio-standards/service_water_heating/create_water_heating_loop'
  require_relative 'openstudio-standards/service_water_heating/create_water_use'
  require_relative 'openstudio-standards/service_water_heating/information'

  # Space Module
  require_relative 'openstudio-standards/space/space'

  # Space Type Module
  require_relative 'openstudio-standards/space_type/standards_space_type'

  # Thermal Zone Module
  require_relative 'openstudio-standards/thermal_zone/information'
  require_relative 'openstudio-standards/thermal_zone/thermostat_schedules'

  # HVAC Module
  require_relative 'openstudio-standards/hvac/air_loop/information'
  require_relative 'openstudio-standards/hvac/cbecs_hvac'
  require_relative 'openstudio-standards/hvac/curves'
  require_relative 'openstudio-standards/hvac/components/air_conditioner_vrf'
  require_relative 'openstudio-standards/hvac/components/air_terminal'
  require_relative 'openstudio-standards/hvac/components/boiler_hot_water'
  require_relative 'openstudio-standards/hvac/components/central_air_source_heat_pump'
  require_relative 'openstudio-standards/hvac/components/chiller'
  require_relative 'openstudio-standards/hvac/components/coil'
  require_relative 'openstudio-standards/hvac/components/coil_cooling_dx_single_speed'
  require_relative 'openstudio-standards/hvac/components/coil_cooling_dx_two_speed'
  require_relative 'openstudio-standards/hvac/components/coil_cooling_dx_multi_speed'
  require_relative 'openstudio-standards/hvac/components/coil_cooling_water_to_air_heat_pump_equation_fit'
  require_relative 'openstudio-standards/hvac/components/coil_cooling_water'
  require_relative 'openstudio-standards/hvac/components/coil_heating_dx_single_speed'
  require_relative 'openstudio-standards/hvac/components/coil_heating_electric'
  require_relative 'openstudio-standards/hvac/components/coil_heating_gas'
  require_relative 'openstudio-standards/hvac/components/coil_heating_gas_multi_stage'
  require_relative 'openstudio-standards/hvac/components/coil_heating_water_to_air_heat_pump_equation_fit'
  require_relative 'openstudio-standards/hvac/components/coil_heating_water'
  require_relative 'openstudio-standards/hvac/components/component'
  require_relative 'openstudio-standards/hvac/components/fan'
  require_relative 'openstudio-standards/hvac/components/heat_exchanger_air_to_air'
  require_relative 'openstudio-standards/hvac/components/pump'
  require_relative 'openstudio-standards/hvac/controls/radiant_system_controls'
  require_relative 'openstudio-standards/hvac/conversions'
  require_relative 'openstudio-standards/hvac/helpers'
  require_relative 'openstudio-standards/hvac/exhaust/create_exhaust_fan'
  require_relative 'openstudio-standards/hvac/setpoint_managers/information'

  # CreateTypical Module
  require_relative 'openstudio-standards/create_typical/enumerations'
  require_relative 'openstudio-standards/create_typical/space_type_ratios'
  require_relative 'openstudio-standards/create_typical/create_typical'
  require_relative 'openstudio-standards/create_typical/space_type_blend'
  require_relative 'openstudio-standards/create_typical/space_type_information'

  # QAQC Module
  require_relative 'openstudio-standards/qaqc/calibration'
  require_relative 'openstudio-standards/qaqc/envelope'
  require_relative 'openstudio-standards/qaqc/eui'
  require_relative 'openstudio-standards/qaqc/hvac'
  require_relative 'openstudio-standards/qaqc/internal_loads'
  require_relative 'openstudio-standards/qaqc/schedules'
  require_relative 'openstudio-standards/qaqc/service_water_heating'
  require_relative 'openstudio-standards/qaqc/weather_files'
  require_relative 'openstudio-standards/qaqc/zone_conditions'
  require_relative 'openstudio-standards/qaqc/create_results'
  require_relative 'openstudio-standards/qaqc/reporting'

  # SQL File Module
  require_relative 'openstudio-standards/sql_file/sql_file'
  require_relative 'openstudio-standards/sql_file/unmet_hours'
  require_relative 'openstudio-standards/sql_file/energy_use'
  require_relative 'openstudio-standards/sql_file/fenestration'

  # Weather Module
  require_relative 'openstudio-standards/weather/information'
  require_relative 'openstudio-standards/weather/modify'
  require_relative 'openstudio-standards/weather/stat_file'

  # HVAC standards
  require_relative 'openstudio-standards/standards/Standards.Model'

  # BTAP (Natural Resources Canada)
  require_relative 'openstudio-standards/btap/btap'
  require_relative 'openstudio-standards/btap/common_paths'
  require_relative 'openstudio-standards/btap/costing/btap_costing'
  require_relative 'openstudio-standards/btap/carbon/btap_carbon'
  require_relative 'openstudio-standards/btap/costing/ventilation_costing'
  require_relative 'openstudio-standards/btap/costing/envelope_costing'
  require_relative 'openstudio-standards/btap/costing/lighting_costing'
  require_relative 'openstudio-standards/btap/costing/heating_cooling_costing'
  require_relative 'openstudio-standards/btap/costing/shw_costing'
  require_relative 'openstudio-standards/btap/costing/dcv_costing'
  require_relative 'openstudio-standards/btap/costing/daylighting_sensor_control_costing'
  require_relative 'openstudio-standards/btap/costing/led_lighting_costing'
  require_relative 'openstudio-standards/btap/costing/pv_ground_costing'
  require_relative 'openstudio-standards/btap/costing/nv_costing'

  # Utilities
  require_relative 'openstudio-standards/utilities/logging'
  require_relative 'openstudio-standards/utilities/simulation'
  require_relative 'openstudio-standards/utilities/hash'
  require_relative 'openstudio-standards/utilities/schedule_translator'
  require_relative 'openstudio-standards/utilities/array'
  require_relative 'openstudio-standards/utilities/object_info'
  require_relative 'openstudio-standards/utilities/assertion'
  require_relative 'openstudio-standards/utilities/ruleset_check'

  stds = 'openstudio-standards/standards'
  proto = 'openstudio-standards/prototypes'

  ### Standards ###
  # Standards classes
  require_relative "#{stds}/standard"
  # NECB2011 Code
  require_relative "#{stds}/necb/NECB2011/system_fuels"
  require_relative "#{stds}/necb/NECB2011/necb_2011"
  require_relative "#{stds}/necb/NECB2011/building_envelope"
  require_relative "#{stds}/necb/NECB2011/lighting"
  require_relative "#{stds}/necb/NECB2011/hvac_systems"
  require_relative "#{stds}/necb/NECB2011/autozone"
  require_relative "#{stds}/necb/NECB2011/hvac_system_1_single_speed"
  require_relative "#{stds}/necb/NECB2011/hvac_system_1_multi_speed"
  require_relative "#{stds}/necb/NECB2011/hvac_system_2_and_5"
  require_relative "#{stds}/necb/NECB2011/hvac_system_3_and_8_single_speed"
  require_relative "#{stds}/necb/NECB2011/hvac_system_3_and_8_multi_speed"
  require_relative "#{stds}/necb/NECB2011/hvac_system_4"
  require_relative "#{stds}/necb/NECB2011/hvac_system_6"
  require_relative "#{stds}/necb/NECB2011/hvac_namer"
  require_relative "#{stds}/necb/NECB2011/service_water_heating"
  require_relative "#{stds}/necb/NECB2011/electrical_power_systems_and_motors"
  require_relative "#{stds}/necb/NECB2011/beps_compliance_path"
  # NECB2015 Code
  require_relative "#{stds}/necb/NECB2015/necb_2015"
  require_relative "#{stds}/necb/NECB2015/lighting"
  require_relative "#{stds}/necb/NECB2015/hvac_systems"
  # NECB2017 Code
  require_relative "#{stds}/necb/NECB2017/necb_2017"
  require_relative "#{stds}/necb/NECB2017/hvac_systems"
  # NECB2020 Code
  require_relative "#{stds}/necb/NECB2020/necb_2020"
  require_relative "#{stds}/necb/NECB2020/building_envelope"
  require_relative "#{stds}/necb/NECB2020/service_water_heating"

  # BTAPPRE1980
  require_relative "#{stds}/necb/BTAPPRE1980/btap_pre1980"
  require_relative "#{stds}/necb/BTAPPRE1980/building_envelope"
  require_relative "#{stds}/necb/BTAPPRE1980/hvac_systems"
  require_relative "#{stds}/necb/BTAPPRE1980/hvac_system_3_and_8_single_speed"
  require_relative "#{stds}/necb/BTAPPRE1980/hvac_system_4"
  require_relative "#{stds}/necb/BTAPPRE1980/hvac_system_6"

  # BTAP1980TO2010
  require_relative "#{stds}/necb/BTAP1980TO2010/btap_1980to2010"

  # NECB QAQC
  require_relative "#{stds}/necb/NECB2011/qaqc/necb_qaqc.rb"
  require_relative "#{stds}/necb/NECB2015/qaqc/necb_2015_qaqc.rb"
  require_relative "#{stds}/necb/common/btap_analysis.rb"
  require_relative "#{stds}/necb/common/btap_data.rb"
  require_relative "#{stds}/necb/common/btap_datapoint.rb"

  # ECM development
  require_relative "#{stds}/necb/ECMS/ecms.rb"
  require_relative "#{stds}/necb/ECMS/erv.rb"
  require_relative "#{stds}/necb/ECMS/hvac_systems.rb"
  require_relative "#{stds}/necb/ECMS/nv.rb"
  require_relative "#{stds}/necb/ECMS/pv_ground.rb"
  require_relative "#{stds}/necb/ECMS/loads.rb"

  require_relative "#{stds}/ashrae_90_1/ashrae_90_1"
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980"
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/comstock_doe_ref_pre_1980/comstock_doe_ref_pre_1980"
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004"
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/comstock_doe_ref_1980_2004/comstock_doe_ref_1980_2004"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/comstock_ashrae_90_1_2004/comstock_ashrae_90_1_2004"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/comstock_ashrae_90_1_2007/comstock_ashrae_90_1_2007"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/comstock_ashrae_90_1_2010/comstock_ashrae_90_1_2010"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/comstock_ashrae_90_1_2013/comstock_ashrae_90_1_2013"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/comstock_ashrae_90_1_2016/comstock_ashrae_90_1_2016"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/comstock_ashrae_90_1_2019/comstock_ashrae_90_1_2019"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily"

  require_relative "#{stds}/deer/deer"
  require_relative "#{stds}/deer/deer_pre_1975/deer_pre_1975"
  require_relative "#{stds}/deer/deer_pre_1975/comstock_deer_pre_1975/comstock_deer_pre_1975"
  require_relative "#{stds}/deer/deer_1985/deer_1985"
  require_relative "#{stds}/deer/deer_1985/comstock_deer_1985/comstock_deer_1985"
  require_relative "#{stds}/deer/deer_1996/deer_1996"
  require_relative "#{stds}/deer/deer_1996/comstock_deer_1996/comstock_deer_1996"
  require_relative "#{stds}/deer/deer_2003/deer_2003"
  require_relative "#{stds}/deer/deer_2003/comstock_deer_2003/comstock_deer_2003"
  require_relative "#{stds}/deer/deer_2007/deer_2007"
  require_relative "#{stds}/deer/deer_2007/comstock_deer_2007/comstock_deer_2007"
  require_relative "#{stds}/deer/deer_2011/deer_2011"
  require_relative "#{stds}/deer/deer_2011/comstock_deer_2011/comstock_deer_2011"
  require_relative "#{stds}/deer/deer_2014/deer_2014"
  require_relative "#{stds}/deer/deer_2014/comstock_deer_2014/comstock_deer_2014"
  require_relative "#{stds}/deer/deer_2015/deer_2015"
  require_relative "#{stds}/deer/deer_2015/comstock_deer_2015/comstock_deer_2015"
  require_relative "#{stds}/deer/deer_2017/deer_2017"
  require_relative "#{stds}/deer/deer_2017/comstock_deer_2017/comstock_deer_2017"
  require_relative "#{stds}/deer/deer_2020/deer_2020"
  require_relative "#{stds}/deer/deer_2020/comstock_deer_2020/comstock_deer_2020"
  require_relative "#{stds}/deer/deer_2025/deer_2025"
  require_relative "#{stds}/deer/deer_2025/comstock_deer_2025/comstock_deer_2025"
  require_relative "#{stds}/deer/deer_2030/deer_2030"
  require_relative "#{stds}/deer/deer_2030/comstock_deer_2030/comstock_deer_2030"
  require_relative "#{stds}/deer/deer_2035/deer_2035"
  require_relative "#{stds}/deer/deer_2035/comstock_deer_2035/comstock_deer_2035"
  require_relative "#{stds}/deer/deer_2040/deer_2040"
  require_relative "#{stds}/deer/deer_2040/comstock_deer_2040/comstock_deer_2040"
  require_relative "#{stds}/deer/deer_2045/deer_2045"
  require_relative "#{stds}/deer/deer_2045/comstock_deer_2045/comstock_deer_2045"
  require_relative "#{stds}/deer/deer_2050/deer_2050"
  require_relative "#{stds}/deer/deer_2050/comstock_deer_2050/comstock_deer_2050"
  require_relative "#{stds}/deer/deer_2055/deer_2055"
  require_relative "#{stds}/deer/deer_2055/comstock_deer_2055/comstock_deer_2055"
  require_relative "#{stds}/deer/deer_2060/deer_2060"
  require_relative "#{stds}/deer/deer_2060/comstock_deer_2060/comstock_deer_2060"
  require_relative "#{stds}/deer/deer_2065/deer_2065"
  require_relative "#{stds}/deer/deer_2065/comstock_deer_2065/comstock_deer_2065"
  require_relative "#{stds}/deer/deer_2070/deer_2070"
  require_relative "#{stds}/deer/deer_2070/comstock_deer_2070/comstock_deer_2070"
  require_relative "#{stds}/deer/deer_2075/deer_2075"
  require_relative "#{stds}/deer/deer_2075/comstock_deer_2075/comstock_deer_2075"

  require_relative "#{stds}/oeesc/oeesc"
  require_relative "#{stds}/oeesc/oeesc_2014/oeesc_2014"

  require_relative "#{stds}/icc_iecc/icc_iecc"
  require_relative "#{stds}/icc_iecc/icc_iecc_2015/icc_iecc_2015"

  require_relative "#{stds}/cbes/cbes"
  require_relative "#{stds}/cbes/cbes_pre_1978/cbes_pre_1978"
  require_relative "#{stds}/cbes/cbes_t24_1978/cbes_t24_1978"
  require_relative "#{stds}/cbes/cbes_t24_1992/cbes_t24_1992"
  require_relative "#{stds}/cbes/cbes_t24_2001/cbes_t24_2001"
  require_relative "#{stds}/cbes/cbes_t24_2005/cbes_t24_2005"
  require_relative "#{stds}/cbes/cbes_t24_2008/cbes_t24_2008"

  # Base Model Objects
  require_relative "#{stds}/Standards.CoilDX"
  require_relative "#{stds}/Standards.CoolingTower"
  require_relative "#{stds}/Standards.Fan"
  require_relative "#{stds}/Standards.Pump"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.Fan"

  # Model Objects
  require_relative "#{stds}/Standards.AirConditionerVariableRefrigerantFlow"
  require_relative "#{stds}/Standards.AirLoopHVAC"
  require_relative "#{stds}/Standards.AirTerminalSingleDuctParallelPIUReheat"
  require_relative "#{stds}/Standards.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/Standards.BoilerHotWater"
  require_relative "#{stds}/Standards.ChillerElectricEIR"
  require_relative "#{stds}/Standards.CoilCoolingDXMultiSpeed"
  require_relative "#{stds}/Standards.CoilCoolingDXSingleSpeed"
  require_relative "#{stds}/Standards.CoilCoolingDXTwoSpeed"
  require_relative "#{stds}/Standards.CoilCoolingWaterToAirHeatPumpEquationFit"
  require_relative "#{stds}/Standards.CoilHeatingDXMultiSpeed"
  require_relative "#{stds}/Standards.CoilHeatingDXSingleSpeed"
  require_relative "#{stds}/Standards.CoilHeatingGasMultiStage"
  require_relative "#{stds}/Standards.CoilHeatingGas"
  require_relative "#{stds}/Standards.CoilHeatingWaterToAirHeatPumpEquationFit"
  require_relative "#{stds}/Standards.CoolingTowerSingleSpeed"
  require_relative "#{stds}/Standards.CoolingTowerTwoSpeed"
  require_relative "#{stds}/Standards.CoolingTowerVariableSpeed"
  require_relative "#{stds}/Standards.FanVariableVolume"
  require_relative "#{stds}/Standards.FluidCooler"
  require_relative "#{stds}/Standards.HeatExchangerSensLat"
  require_relative "#{stds}/Standards.Model"
  require_relative "#{stds}/Standards.Motor"
  require_relative "#{stds}/Standards.People"
  require_relative "#{stds}/Standards.PlanarSurface"
  require_relative "#{stds}/Standards.PlantLoop"
  require_relative "#{stds}/Standards.Pump"
  require_relative "#{stds}/Standards.PumpVariableSpeed"
  require_relative "#{stds}/Standards.ScheduleRuleset"
  require_relative "#{stds}/Standards.ServiceWaterHeating"
  require_relative "#{stds}/Standards.Space"
  require_relative "#{stds}/Standards.SpaceType"
  require_relative "#{stds}/Standards.SubSurface"
  require_relative "#{stds}/Standards.Surface"
  require_relative "#{stds}/Standards.ThermalZone"
  require_relative "#{stds}/Standards.Ventilation"
  require_relative "#{stds}/Standards.WaterHeaterMixed"
  require_relative "#{stds}/Standards.ZoneHVACComponent"
  # 90.1 Common
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1.Standards.FanVariableVolume"
  # 90.1-2004
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.PlantLoop"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.ThermalZone"
  # 90.1-2007
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.ThermalZone"
  # 90.1-2010
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.Space"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.ThermalZone"
  # 90.1-2013
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.Motor"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.PlantLoop"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.Space"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.ThermalZone"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.WaterHeaterMixed"
  # 90.1-2016
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.Motor"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.Space"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.ThermalZone"
  # 90.1-2019
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.CoilHeatingGas"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Model"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Motor"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Pump"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.PumpVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Space"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.ThermalZone"
  require_relative "#{stds}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.WaterHeaterMixed"
  # 90.1-PRM Common
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.Model"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.Space"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.AirTerminalSingleDuctParallelPIUReheat"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.ZoneHVACComponent"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.PlantLoop"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.CoilDX"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.CoilCoolingDXSingleSpeed"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.CoilCoolingDXTwoSpeed"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.CoilHeatingDXSingleSpeed"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.CoilHeatingGas"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.BoilerHotWater"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.ChillerElectricEIR"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.HeatExchangerSensLat"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.PlanarSurface"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.ThermalZone"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.SpaceType"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.Surface"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm.DesignSpecificationOutdoorAir"
  require_relative "#{stds}/ashrae_90_1_prm/userdata_csv/userdata_enums.rb"
  require_relative "#{stds}/ashrae_90_1_prm/userdata_csv/ashrae_90_1_prm.UserData"
  # 90.1-PRM-2019
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm_2019/ashrae_90_1_prm_2019"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm_2019/ashrae_90_1_prm_2019.Model"
  require_relative "#{stds}/ashrae_90_1_prm/ashrae_90_1_prm_2019/ashrae_90_1_prm_2019_WaterHeaterMixed"
  # DOE 1980-2004
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.AirConditionerVariableRefrigerantFlow"
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.Model"
  require_relative "#{stds}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.PlantLoop"
  # DOE Pre-1980
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.AirConditionerVariableRefrigerantFlow"
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.Model"
  require_relative "#{stds}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.PlantLoop"
  # NREL ZNE Ready 2017
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.HeatExchangerSensLat"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.Model"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.PlantLoop"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.Space"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.ThermalZone"
  require_relative "#{stds}/ashrae_90_1/nrel_zne_ready_2017/nrel_zne_ready_2017.ZoneHVACComponent"
  # ZE AEDG Multifamily
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.AirLoopHVAC"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.AirTerminalSingleDuctVAVReheat"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.CoolingTower"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.CoolingTowerSingleSpeed"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.CoolingTowerTwoSpeed"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.CoolingTowerVariableSpeed"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.FanVariableVolume"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.HeatExchangerSensLat"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.Model"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.PlantLoop"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.Space"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.ThermalZone"
  require_relative "#{stds}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.ZoneHVACComponent"
  # DEER Common
  require_relative "#{stds}/deer/deer.Model"
  require_relative "#{stds}/deer/deer.AirLoopHVAC"
  require_relative "#{stds}/deer/deer.PlanarSurface"
  # DEER 2003
  require_relative "#{stds}/deer/deer_2003/deer_2003.ThermalZone"
  # DEER 2007
  require_relative "#{stds}/deer/deer_2007/deer_2007.ThermalZone"
  # DEER 2011
  require_relative "#{stds}/deer/deer_2011/deer_2011.ThermalZone"
  # DEER 2014
  require_relative "#{stds}/deer/deer_2014/deer_2014.Space"
  require_relative "#{stds}/deer/deer_2014/deer_2014.ThermalZone"
  # DEER 2015
  require_relative "#{stds}/deer/deer_2015/deer_2015.Space"
  require_relative "#{stds}/deer/deer_2015/deer_2015.ThermalZone"
  # DEER 2017
  require_relative "#{stds}/deer/deer_2017/deer_2017.Space"
  require_relative "#{stds}/deer/deer_2017/deer_2017.ThermalZone"
  # DEER 2020
  require_relative "#{stds}/deer/deer_2020/deer_2020.AirLoopHVAC"
  require_relative "#{stds}/deer/deer_2020/deer_2020.FanVariableVolume"
  require_relative "#{stds}/deer/deer_2020/deer_2020.Space"
  require_relative "#{stds}/deer/deer_2020/deer_2020.ThermalZone"
  # CBES Common
  require_relative "#{stds}/cbes/cbes.AirLoopHVAC"
  require_relative "#{stds}/cbes/cbes.Model"
  require_relative "#{stds}/cbes/cbes.PlantLoop"

  ### Prototypes ###
  # Mapping Old Standards Space Types
  require_relative "#{proto}/common/prototype_space_type_map"

  # Building Types
  require_relative "#{proto}/common/buildings/Prototype.FullServiceRestaurant"
  require_relative "#{proto}/common/buildings/Prototype.HighRiseApartment"
  require_relative "#{proto}/common/buildings/Prototype.Hospital"
  require_relative "#{proto}/common/buildings/Prototype.LargeHotel"
  require_relative "#{proto}/common/buildings/Prototype.LargeOffice"
  require_relative "#{proto}/common/buildings/Prototype.MediumOffice"
  require_relative "#{proto}/common/buildings/Prototype.MidriseApartment"
  require_relative "#{proto}/common/buildings/Prototype.Outpatient"
  require_relative "#{proto}/common/buildings/Prototype.PrimarySchool"
  require_relative "#{proto}/common/buildings/Prototype.QuickServiceRestaurant"
  require_relative "#{proto}/common/buildings/Prototype.RetailStandalone"
  require_relative "#{proto}/common/buildings/Prototype.RetailStripmall"
  require_relative "#{proto}/common/buildings/Prototype.SecondarySchool"
  require_relative "#{proto}/common/buildings/Prototype.SmallHotel"
  require_relative "#{proto}/common/buildings/Prototype.SmallOffice"
  require_relative "#{proto}/common/buildings/Prototype.SuperMarket"
  require_relative "#{proto}/common/buildings/Prototype.Warehouse"
  require_relative "#{proto}/common/buildings/Prototype.SmallDataCenterLowITE"
  require_relative "#{proto}/common/buildings/Prototype.SmallDataCenterHighITE"
  require_relative "#{proto}/common/buildings/Prototype.LargeDataCenterLowITE"
  require_relative "#{proto}/common/buildings/Prototype.LargeDataCenterHighITE"
  require_relative "#{proto}/common/buildings/Prototype.LargeOfficeDetailed"
  require_relative "#{proto}/common/buildings/Prototype.MediumOfficeDetailed"
  require_relative "#{proto}/common/buildings/Prototype.SmallOfficeDetailed"
  require_relative "#{proto}/common/buildings/Prototype.Laboratory"
  require_relative "#{proto}/common/buildings/Prototype.College"
  require_relative "#{proto}/common/buildings/Prototype.TallBuilding"
  require_relative "#{proto}/common/buildings/Prototype.SuperTallBuilding"
  require_relative "#{proto}/common/buildings/Prototype.Courthouse"

  # NECB Building Types
  require_relative "#{proto}/common/prototype_metaprogramming.rb"
  create_meta_classes

  # Model Objects
  require_relative "#{proto}/common/objects/Prototype.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/common/objects/Prototype.CoolingTower"
  require_relative "#{proto}/common/objects/Prototype.Fan"
  require_relative "#{proto}/common/objects/Prototype.FanConstantVolume"
  require_relative "#{proto}/common/objects/Prototype.FanOnOff"
  require_relative "#{proto}/common/objects/Prototype.FanVariableVolume"
  require_relative "#{proto}/common/objects/Prototype.FanZoneExhaust"
  require_relative "#{proto}/common/objects/Prototype.HeatExchangerAirToAirSensibleAndLatent"
  require_relative "#{proto}/common/objects/Prototype.hvac_systems"
  require_relative "#{proto}/common/objects/Prototype.Model.elevators"
  require_relative "#{proto}/common/objects/Prototype.Model.hvac"
  require_relative "#{proto}/common/objects/Prototype.Model"
  require_relative "#{proto}/common/objects/Prototype.refrigeration"
  require_relative "#{proto}/common/objects/Prototype.SizingSystem"
  # 90.1-2004
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2004/ashrae_90_1_2004.AirTerminalSingleDuctVAVReheat"
  # 90.1-2007
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2007/ashrae_90_1_2007.AirTerminalSingleDuctVAVReheat"
  # 90.1-2010
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.Model"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2010/ashrae_90_1_2010.AirTerminalSingleDuctVAVReheat"
  # 90.1-2013
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.Model"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.hvac_systems"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2013/ashrae_90_1_2013.AirTerminalSingleDuctVAVReheat"
  # 90.1-2016
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.Model"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.hvac_systems"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2016/ashrae_90_1_2016.AirTerminalSingleDuctVAVReheat"
  # 90.1-2019
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Model"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.hvac_systems"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.Space"
  # DOE Ref 1980-2004
  require_relative "#{proto}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/ashrae_90_1/doe_ref_1980_2004/doe_ref_1980_2004.Model.elevators"
  # DOE Ref Pre-1980
  require_relative "#{proto}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.CoilHeatingGas"
  require_relative "#{proto}/ashrae_90_1/doe_ref_pre_1980/doe_ref_pre_1980.Model.elevators"
  # NREL ZNE Ready 2017
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.HeatExchangerAirToAirSensibleAndLatent"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/nrel_nze_ready_2017/nrel_zne_ready_2017.hvac_systems"
  # ZE AEDG Multifamily
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.AirTerminalSingleDuctVAVReheat"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.FanConstantVolume"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.FanOnOff"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.FanVariableVolume"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.HeatExchangerAirToAirSensibleAndLatent"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.Model"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.Model.elevators"
  require_relative "#{proto}/ashrae_90_1/ze_aedg_multifamily/ze_aedg_multifamily.hvac_systems"
  # DEER
  require_relative "#{proto}/deer/deer.Model"
  # CBES Common
  require_relative "#{proto}/cbes/cbes.Model.elevators"
  # CBES T24 2008
  require_relative "#{proto}/cbes/cbes_t24_2008/cbes_t24_2008.FanConstantVolume"
  require_relative "#{proto}/cbes/cbes_t24_2008/cbes_t24_2008.FanOnOff"
  require_relative "#{proto}/cbes/cbes_t24_2008/cbes_t24_2008.FanVariableVolume"

  # DLM: not sure where this code should go
  def self.get_run_env
    # blank out bundler and gem path modifications, will be re-setup by new call
    new_env = {}
    new_env['BUNDLER_ORIG_MANPATH'] = nil
    new_env['BUNDLER_ORIG_PATH'] = nil
    new_env['BUNDLER_VERSION'] = nil
    new_env['BUNDLE_BIN_PATH'] = nil
    new_env['RUBYLIB'] = nil
    new_env['RUBYOPT'] = nil

    # DLM: preserve GEM_HOME and GEM_PATH set by current bundle because we are not supporting bundle
    # requires to ruby gems will work, will fail if we require a native gem
    new_env['GEM_PATH'] = nil
    new_env['GEM_HOME'] = nil

    # DLM: for now, ignore current bundle in case it has binary dependencies in it
    # bundle_gemfile = ENV['BUNDLE_GEMFILE']
    # bundle_path = ENV['BUNDLE_PATH']
    # if bundle_gemfile.nil? || bundle_path.nil?
    new_env['BUNDLE_GEMFILE'] = nil
    new_env['BUNDLE_PATH'] = nil
    new_env['BUNDLE_WITHOUT'] = nil
    # else
    #   new_env['BUNDLE_GEMFILE'] = bundle_gemfile
    #   new_env['BUNDLE_PATH'] = bundle_path
    # end

    return new_env
  end

  def self.run_command(command)
    stdout_str, stderr_str, status = Open3.capture3(get_run_env, command)
    if status.success?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.command', "Successfully ran command: '#{command}'")
      # puts "stdout: #{stdout_str}"
      # puts "stderr: #{stderr_str}"
      return true
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.command', "Error running command: '#{command}'")
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.command', "stdout: #{stdout_str}")
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.command', "stderr: #{stderr_str}")

      # Print the ENV for debugging
      final_env = []
      env_changes = get_run_env
      ENV.each do |env_var, val|
        next if env_changes.key?(env_var) && env_changes[env_var].nil?

        final_env << "#{env_var} = #{val}"
      end
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.command', "command's modified ENV: \n #{final_env.join("\n")}")

      # List the gems available to openstudio at this point
      cli_path = OpenStudio.getOpenStudioCLI
      cmd = "\"#{cli_path}\" gem_list"
      stdout_str_2, stderr_str_2, status_2 = Open3.capture3(get_run_env, cmd)
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.command', "Gems available to openstudio cli according to (openstudio gem_list): \n #{stdout_str_2}")

      return false
    end
  end
end
