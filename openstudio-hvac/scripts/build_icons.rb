require 'base64'
require 'open3'

BASE = 'https://raw.githubusercontent.com/openstudiocoalition/OpenStudioApplication/develop/src/openstudio_lib/images'
DIR  = File.expand_path('icons', __dir__)
Dir.mkdir(DIR) unless Dir.exist?(DIR)

# IDD object type valueName -> OS App icon file stem (from IconLibrary.cpp).
# Two HeatPump_PlantLoop_EIR types are absent from IconLibrary -> heat_pump3.
MAP = {
  'OS_AirLoopHVAC_OutdoorAirSystem' => 'OAMixer',
  'OS_AirTerminal_SingleDuct_ConstantVolume_NoReheat' => 'direct-air',
  'OS_AirTerminal_SingleDuct_ConstantVolume_Reheat' => 'cav_reheat',
  'OS_AirTerminal_SingleDuct_VAV_Reheat' => 'vav-reheat',
  'OS_Boiler_HotWater' => 'boiler',
  'OS_Chiller_Electric_EIR' => 'chiller_air',
  'OS_Coil_Cooling_DX_SingleSpeed' => 'dxcoolingcoil_singlespeed',
  'OS_Coil_Cooling_DX_TwoSpeed' => 'dxcoolingcoil_2speed',
  'OS_Coil_Cooling_DX_VariableSpeed' => 'cool_coil_dx_vari_speed',
  'OS_Coil_Cooling_Water' => 'cool_coil',
  'OS_Coil_Cooling_WaterToAirHeatPump_EquationFit' => 'wahpDXCC',
  'OS_Coil_Heating_DX_SingleSpeed' => 'coil_ht_dx_singlespeed',
  'OS_Coil_Heating_DX_VariableSpeed' => 'ht_coil_dx_vari',
  'OS_Coil_Heating_Electric' => 'electric_furnace',
  'OS_Coil_Heating_Gas' => 'furnace',
  'OS_Coil_Heating_Water' => 'heat_coil',
  'OS_Coil_Heating_WaterToAirHeatPump_EquationFit' => 'wahpDXHC',
  'OS_Coil_Heating_Water_Baseboard' => 'coilheatingwater_baseboard',
  'OS_CoolingTower_SingleSpeed' => 'cooling_tower',
  'OS_DistrictCooling' => 'districtcooling',
  'OS_DistrictHeating_Water' => 'districtheating',
  'OS_EvaporativeCooler_Direct_ResearchSpecial' => 'directEvap',
  'OS_EvaporativeFluidCooler_SingleSpeed' => 'evap_fluid_cooler',
  'OS_Fan_ConstantVolume' => 'fan_constant',
  'OS_Fan_VariableVolume' => 'fan_variable',
  'OS_GroundHeatExchanger_Vertical' => 'ground_heat_exchanger_vertical',
  'OS_HeatPump_PlantLoop_EIR_Cooling' => 'heat_pump3',
  'OS_HeatPump_PlantLoop_EIR_Heating' => 'heat_pump3',
  'OS_HeatPump_WaterToWater_EquationFit_Heating' => 'heatpump_watertowater_equationfit_heating',
  'OS_Pump_ConstantSpeed' => 'pump_constant',
  'OS_Pump_VariableSpeed' => 'pump_variable',
  'OS_ThermalZone' => 'zone',
  'OS_ZoneHVAC_Baseboard_Convective_Electric' => 'baseboard_electric',
  'OS_ZoneHVAC_Baseboard_Convective_Water' => 'baseboard_water',
  'OS_ZoneHVAC_EnergyRecoveryVentilator' => 'energy_recov_vent',
  'OS_ZoneHVAC_FourPipeFanCoil' => 'four_pipe_fan_coil',
  'OS_ZoneHVAC_PackagedTerminalAirConditioner' => 'system_type_1',
  'OS_ZoneHVAC_PackagedTerminalHeatPump' => 'system_type_2',
  'OS_ZoneHVAC_TerminalUnit_VariableRefrigerantFlow' => 'vrf_unit',
  'OS_ZoneHVAC_UnitHeater' => 'heat_coil-uht',
  'OS_ZoneHVAC_WaterToAirHeatPump' => 'watertoairHP'
}.freeze

def png_dims(bytes)
  # IHDR width/height are big-endian uint32 at byte offsets 16 and 20.
  w = bytes[16, 4].unpack1('N')
  h = bytes[20, 4].unpack1('N')
  [w, h]
end

def fetch(stem)
  ['%s@2x' % stem, stem].each do |name|
    path = File.join(DIR, "#{name}.png")
    unless File.exist?(path) && File.size(path) > 100
      out, = Open3.capture2('curl', '-sfL', "#{BASE}/#{name}.png", '-o', path)
    end
    return File.binread(path) if File.exist?(path) && File.size(path) > 100 && File.binread(path)[0, 8].bytes == [137, 80, 78, 71, 13, 10, 26, 10]
  end
  raise "could not download #{stem}"
end

stems = MAP.values.uniq.sort
icons = {}   # stem -> { data:, w:, h: }
stems.each do |stem|
  bytes = fetch(stem)
  w, h = png_dims(bytes)
  icons[stem] = { b64: Base64.strict_encode64(bytes), w: w, h: h }
  warn "#{stem}: #{w}x#{h} #{bytes.size}B"
end

# Emit the Ruby data file.
out = +"# frozen_string_literal: true\n\n"
out << "# GENERATED — do not edit by hand. Component icons extracted from the\n"
out << "# OpenStudio Application (openstudiocoalition/OpenStudioApplication,\n"
out << "# BSD-3-Clause). Retina @2x PNGs, base64-embedded ONCE and referenced by\n"
out << "# every component cell via <use href=\"#icon-...\">. See THIRD_PARTY_NOTICES.md.\n"
out << "# Regenerate with scripts/build_icons.rb.\n"
out << "module OpenStudioHVAC\n  module CatalogReport\n"
out << "    # IDD object type valueName -> icon stem (from IconLibrary.cpp).\n"
out << "    ICON_FOR_IDD = {\n"
MAP.each { |idd, stem| out << "      #{idd.inspect} => #{stem.inspect},\n" }
out << "    }.freeze\n\n"
out << "    # icon stem -> { data: base64 PNG data-URI, w:, h: } (natural pixel size).\n"
out << "    ICON_DATA = {\n"
icons.each do |stem, info|
  out << "      #{stem.inspect} => { w: #{info[:w]}, h: #{info[:h]},\n"
  out << "        data: 'data:image/png;base64,#{info[:b64]}' },\n"
end
out << "    }.freeze\n  end\nend\n"

dest = '/workspaces/openstudio-standards/openstudio-hvac/lib/openstudio_hvac/catalog_icons.rb'
File.write(dest, out)
warn "\nWrote #{dest} (#{out.bytesize} bytes, #{icons.size} icons, #{MAP.size} idd mappings)"
