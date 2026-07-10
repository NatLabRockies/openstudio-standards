module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group CBECS HVAC
    # Method to apply a typical CBECS HVAC system to thermal zones

    # Adds the HVAC system as derived from the combinations of CBECS 2012 MAINHT and MAINCL fields.
    # Mapping between combinations and HVAC systems per http://www.nrel.gov/docs/fy08osti/41956.pdf
    # Table C-31
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a built standard object, e.g. Standard.build('90.1-2013')
    # @param hvac_system_type [String] HVAC system type
    # @param zones [Array<OpenStudio::Model::ThermalZone>] Array of OpenStudio ThermalZone objects
    # @return [Boolean] returns true if successful, false if not
    def self.add_cbecs_hvac_system(model, standard, hvac_system_type, zones)
      # the 'zones' argument includes zones that have heating, cooling, or both
      # if the HVAC system type serves a single zone, handle zones with only heating separately by adding unit heaters
      # applies to system types PTAC, PTHP, PSZ-AC, and Window AC
      heated_and_cooled_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
      heated_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) }
      cooled_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
      cooled_only_zones = zones.select { |zone| !OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
      heated_only_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && !OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
      system_zones = heated_and_cooled_zones + cooled_only_zones

      # system type naming convention:
      # [ventilation strategy] [ cooling system and plant] [heating system and plant]

      case hvac_system_type

      when 'Baseboard electric'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Baseboard gas boiler'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Baseboard central air source heat pump'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)

      when 'Baseboard district hot water'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'Direct evap coolers with baseboard electric'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'Direct evap coolers with baseboard gas boiler'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'Direct evap coolers with baseboard central air source heat pump'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'Direct evap coolers with baseboard district hot water'
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'Direct evap coolers with forced air furnace', 'Direct evap coolers with gas unit heaters'
        # Using unit heater to represent forced air furnace to limit to one airloop per thermal zone.
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'Direct evap coolers with no heat'
        standard.model_add_hvac_system(model, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'DOAS with fan coil chiller with boiler'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil chiller with central air source heat pump'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil chiller with district hot water'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil chiller with baseboard electric'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil chiller with gas unit heaters'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil chiller with no heat'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil air-cooled chiller with boiler'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil air-cooled chiller with central air source heat pump'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil air-cooled chiller with district hot water'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil air-cooled chiller with baseboard electric'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil air-cooled chiller with gas unit heaters'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil air-cooled chiller with no heat'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled',
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil district chilled water with boiler'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil district chilled water with central air source heat pump'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil district chilled water with district hot water'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with fan coil district chilled water with baseboard electric'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil district chilled water with gas unit heaters'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'DOAS with fan coil district chilled water with no heat'
        standard.model_add_hvac_system(model, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with VRF'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones,
                                       air_loop_heating_type: 'DX',
                                       air_loop_cooling_type: 'DX')
        standard.model_add_hvac_system(model, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'DOAS with water source heat pumps fluid cooler with boiler'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       heat_pump_loop_cooling_type: 'FluidCooler',
                                       zone_equipment_ventilation: false)

      when 'DOAS with water source heat pumps cooling tower with boiler'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       heat_pump_loop_cooling_type: 'CoolingTower',
                                       zone_equipment_ventilation: false)

      when 'DOAS with water source heat pumps with ground source heat pump'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'Electricity', znht = nil, cl = 'Electricity', zones,
                                       air_loop_heating_type: 'DX',
                                       air_loop_cooling_type: 'DX')
        standard.model_add_hvac_system(model, 'Ground Source Heat Pumps', ht = 'Electricity', znht = nil, cl = 'Electricity', zones,
                                       zone_equipment_ventilation: false)

      when 'DOAS with water source heat pumps district chilled water with district hot water'
        standard.model_add_hvac_system(model, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones,
                                       zone_equipment_ventilation: false)

      # ventilation provided by zone fan coil unit in fan coil systems
      when 'Fan coil chiller with boiler'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)

      when 'Fan coil chiller with central air source heat pump'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones)

      when 'Fan coil chiller with district hot water'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones)

      when 'Fan coil chiller with baseboard electric'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Fan coil chiller with gas unit heaters'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Fan coil chiller with no heat'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)

      when 'Fan coil air-cooled chiller with boiler'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'Fan coil air-cooled chiller with central air source heat pump'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'Fan coil air-cooled chiller with district hot water'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'Fan coil air-cooled chiller with baseboard electric'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Fan coil air-cooled chiller with gas unit heaters'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Fan coil air-cooled chiller with no heat'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'Fan coil district chilled water with boiler'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)

      when 'Fan coil district chilled water with central air source heat pump'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones)

      when 'Fan coil district chilled water with district hot water'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)

      when 'Fan coil district chilled water with baseboard electric'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Fan coil district chilled water with gas unit heaters'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Fan coil district chilled water with no heat'
        standard.model_add_hvac_system(model, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)

      when 'Forced air furnace'
        # includes ventilation, whereas residential forced air furnace does not.
        standard.model_add_hvac_system(model, 'Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Gas unit heaters'
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PTAC with baseboard electric'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'PTAC with baseboard gas boiler'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PTAC with baseboard district hot water'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'PTAC with gas unit heaters'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PTAC with electric coil'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = 'Electricity', cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PTAC with gas coil'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = 'NaturalGas', cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use gas unit heaters for heated only zones
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PTAC with gas boiler'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = 'NaturalGas', znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use 'Baseboard gas boiler' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PTAC with central air source heat pump'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use 'Baseboard central air source heat pump' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

      when 'PTAC with district hot water'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use 'Baseboard district hot water heat' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

      when 'PTAC with no heat'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)

      when 'PTHP'
        # default to have no ventilation air
        standard.model_add_hvac_system(model, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones,
                                       zone_equipment_ventilation: false)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with baseboard electric'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC with baseboard gas boiler'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC with baseboard district hot water'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC with gas unit heaters'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC with electric coil'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = 'Electricity', cl = 'Electricity', system_zones)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with gas coil'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = 'NaturalGas', cl = 'Electricity', system_zones)
        # use gas unit heaters for heated only zones
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with gas boiler'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'NaturalGas', znht = nil, cl = 'Electricity', system_zones)
        # use 'Baseboard gas boiler' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with central air source heat pump'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', system_zones)
        # use 'Baseboard central air source heat pump' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with district hot water'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', system_zones)
        # use 'Baseboard district hot water' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC with no heat'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      when 'PSZ-AC district chilled water with baseboard electric'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC district chilled water with baseboard gas boiler'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC district chilled water with baseboard district hot water'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC district chilled water with gas unit heaters'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'PSZ-AC district chilled water with electric coil'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = 'Electricity', cl = 'DistrictCooling', system_zones)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC district chilled water with gas coil'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = 'NaturalGas', cl = 'DistrictCooling', system_zones)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC district chilled water with gas boiler'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', system_zones)
        # use 'Baseboard gas boiler' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC district chilled water with central air source heat pump'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', system_zones)
        # use 'Baseboard central air source heat pump' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC district chilled water with district hot water'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', system_zones)
        # use 'Baseboard district hot water' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

      when 'PSZ-AC district chilled water with no heat'
        standard.model_add_hvac_system(model, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', cooled_zones)

      when 'PSZ-HP'
        standard.model_add_hvac_system(model, 'PSZ-HP', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones)
        # use 'Baseboard electric' for heated only zones
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      # PVAV systems by default use a DX coil for cooling
      when 'PVAV with gas boiler reheat', 'Packaged VAV Air Loop with Boiler' # second enumeration for backwards compatibility with Tenant Star project
        standard.model_add_hvac_system(model, 'PVAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

      when 'PVAV with central air source heat pump reheat'
        standard.model_add_hvac_system(model, 'PVAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones)

      when 'PVAV with district hot water reheat'
        standard.model_add_hvac_system(model, 'PVAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones)

      when 'PVAV with PFP boxes'
        standard.model_add_hvac_system(model, 'PVAV PFP Boxes', ht = 'Electricity', znht = 'Electricity', cl = 'Electricity', system_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PVAV with gas heat with electric reheat', 'PVAV with gas coil heat with electric reheat'
        standard.model_add_hvac_system(model, 'PVAV Reheat', ht = 'Gas', znht = 'Electricity', cl = 'Electricity', system_zones,
                                       air_loop_heating_type: 'Gas')
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

      when 'PVAV with gas boiler heat with electric reheat'
        standard.model_add_hvac_system(model, 'PVAV Reheat', ht = 'Gas', znht = 'Electricity', cl = 'Electricity', zones)

      # all residential systems do not have ventilation
      when 'Residential AC with baseboard electric'
        standard.model_add_hvac_system(model, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Residential AC with baseboard gas boiler'
        standard.model_add_hvac_system(model, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Residential AC with baseboard central air source heat pump'
        standard.model_add_hvac_system(model, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)

      when 'Residential AC with baseboard district hot water'
        standard.model_add_hvac_system(model, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'Residential AC with residential forced air furnace'
        standard.model_add_hvac_system(model, 'Residential Forced Air Furnace with AC', ht = nil, znht = nil, cl = nil, zones)

      when 'Residential AC with no heat'
        standard.model_add_hvac_system(model, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)

      when 'Residential heat pump'
        standard.model_add_hvac_system(model, 'Residential Air Source Heat Pump', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'Residential heat pump with no cooling'
        standard.model_add_hvac_system(model, 'Residential Air Source Heat Pump', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Residential forced air furnace'
        standard.model_add_hvac_system(model, 'Residential Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, zones)

      when 'VAV chiller with gas boiler reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones)

      when 'VAV chiller with central air source heat pump reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones)

      when 'VAV chiller with district hot water reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones)

      when 'VAV chiller with PFP boxes'
        standard.model_add_hvac_system(model, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones)

      when 'VAV chiller with gas coil reheat'
        standard.model_add_hvac_system(model, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'Electricity', zones)

      when 'VAV chiller with no reheat with baseboard electric'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'VAV chiller with no reheat with gas unit heaters'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'VAV chiller with no reheat with zone heat pump'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
        # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
        standard.model_add_hvac_system(model, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'VAV air-cooled chiller with gas boiler reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'VAV air-cooled chiller with central air source heat pump reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'VAV air-cooled chiller with district hot water reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'VAV air-cooled chiller with PFP boxes'
        standard.model_add_hvac_system(model, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'VAV air-cooled chiller with gas coil reheat'
        standard.model_add_hvac_system(model, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')

      when 'VAV air-cooled chiller with no reheat with baseboard electric'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'VAV air-cooled chiller with no reheat with gas unit heaters'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'VAV air-cooled chiller with no reheat with zone heat pump'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       chilled_water_loop_cooling_type: 'AirCooled')
        # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
        standard.model_add_hvac_system(model, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'VAV district chilled water with gas boiler reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'DistrictCooling', zones)

      when 'VAV district chilled water with central air source heat pump reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'DistrictCooling', zones)

      when 'VAV district chilled water with district hot water reheat'
        standard.model_add_hvac_system(model, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'DistrictCooling', zones)

      when 'VAV district chilled water with PFP boxes'
        standard.model_add_hvac_system(model, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'DistrictCooling', zones)

      when 'VAV district chilled water with gas coil reheat'
        standard.model_add_hvac_system(model, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'DistrictCooling', zones)

      when 'VAV district chilled water with no reheat with baseboard electric'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'VAV district chilled water with no reheat with gas unit heaters'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'VAV district chilled water with no reheat with zone heat pump'
        standard.model_add_hvac_system(model, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
        # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
        standard.model_add_hvac_system(model, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'VRF'
        standard.model_add_hvac_system(model, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'Water source heat pumps fluid cooler with boiler'
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       heat_pump_loop_cooling_type: 'FluidCooler')

      when 'Water source heat pumps cooling tower with boiler'
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                       heat_pump_loop_cooling_type: 'CoolingTower')

      when 'Water source heat pumps with ground source heat pump'
        standard.model_add_hvac_system(model, 'Ground Source Heat Pumps', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

      when 'Water source heat pumps district chilled water with district hot water'
        standard.model_add_hvac_system(model, 'Water Source Heat Pumps', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)

      when 'Window AC with baseboard electric'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

      when 'Window AC with baseboard gas boiler'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Window AC with baseboard central air source heat pump'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)

      when 'Window AC with baseboard district hot water'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

      when 'Window AC with forced air furnace'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Window AC with unit heaters'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
        standard.model_add_hvac_system(model, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

      when 'Window AC with no heat'
        standard.model_add_hvac_system(model, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', "CBECS HVAC system type #{hvac_system_type} not recognized.")
        return false
      end
      return true
    end
  end
end
