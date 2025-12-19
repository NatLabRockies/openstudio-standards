class UserData
  # Static method that retrieves the function constant values in a list
  def self.get_constant_values
    return constants.map(&method(:const_get))
  end

  # Static method to check if a user data matches to any of the constant value
  #
  # @param user_data [String] a user data
  # @return [Boolean] matched any, else false
  def self.matched_any?(user_data)
    userdata_constants = get_constant_values
    userdata_constants.each do |constant|
      return true if compare(user_data, constant)
    end
    return false
  end

  # Compare the two UserData enums are the same or not. Static method.
  # @param one [String] one UserData type enum
  # @param another [String] another UserDataType enum
  # @return [Boolean] if the two enums or strings are the same
  def self.compare(one, another)
    return false if one.nil? || another.nil?

    one_value = boolean_to_string(one)
    another_value = boolean_to_string(another)

    if one_value.is_a?(String) && another_value.is_a?(String)
      return one_value.strip.downcase == another_value.strip.downcase
    else
      return one_value == another_value
    end
  end

  def self.boolean_to_string(value)
    return value if value.nil? || value.is_a?(Numeric) # For consistency in further comparison

    value.is_a?(TrueClass) || value.is_a?(FalseClass) ? value.to_s : value
  end
end

class UserDataBoolean < UserData
  TRUE = true
  FALSE = false
end

class UserDataHVACBldgType < UserData
  HEATED_ONLY_STORAGE = 'heated only storage'.freeze
  HOSPITAL = 'hospital'.freeze
  PUBLIC_ASSEMBLY = 'public assembly'.freeze
  RETAIL = 'retail'.freeze
  OTHER_NONRESIDENTIAL = 'other nonresidential'.freeze
  RESIDENTIAL = 'residential'.freeze
  UNCONDITIONED = 'unconditioned'.freeze
end

class UserDataSHWBldgType < UserData
  WORKSHOP = 'Workshop'.freeze
  WAREHOUSE = 'Warehouse'.freeze
  TRANSPORTATION = 'Transportation'.freeze
  TOWN_HALL = 'Town hall'.freeze
  SPORT_ARENA = 'Sport arena'.freeze
  SCHOOL_UNIVERSITY = 'School/university'.freeze
  RETAIL = 'Retail'.freeze
  RELIGIOUS_FACILITY = 'Religious facility'.freeze
  POST_OFFICE = 'Post office'.freeze
  POLICE_STATION = 'Police station'.freeze
  PERFORMING_ARTS_THEATER = 'Performing arts theater'.freeze
  PENITENTIARY = 'Penitentiary'.freeze
  PARKING_GARAGE = 'Parking garage'.freeze
  OFFICE = 'Office'.freeze
  MUSEUM = 'Museum'.freeze
  MULTIFAMILY = 'Multifamily'.freeze
  MOTION_PICTURE_THEATHER = 'Motion picture theater'.freeze
  MOTEL = 'Motel'.freeze
  MANUFACTURING_FACILITY = 'Manufacturing_facility'.freeze
  LIBRARY = 'Library'.freeze
  HOTEL = 'Hotel'.freeze
  HOSPITAL_OUTPATIENT_SURGERY = 'Hospital and outpatient surgery center'.freeze
  HEALTH_CARE_CLINIC = 'Health-care clinic'.freeze
  GYMNASIUM = 'Gymnasium'.freeze
  GROCERY_STORE = 'Grocery store'.freeze
  FIRE_STATION = 'Fire station'.freeze
  EXERCISE_CENTER = 'Exercise center'.freeze
  DORMITORY = 'Domitory'.freeze
  DINING_FAMILY = 'Dining:Family'.freeze
  DINING_CAFETERIA = 'Dining: Cafeteria/fast food'.freeze
  DINING_BAR = 'Dining: Bar lounge/leisure'.freeze
  COURTHOUSE = 'Courthouse'.freeze
  CONVENTION_CENTER = 'Convention center'.freeze
  CONVENTION_STORE = 'Convention store'.freeze
  AUTOMOTIVE_FACILITY = 'Automotive facility'.freeze
  ALL_OTHER = 'All others'.freeze
end

class UserDataNonTradableLightsCategory < UserData
  GENERAL = 'nontradeable_general'.freeze
  BUILDING_FACADE_AREA = 'building_facades_area'.freeze
  BUILDING_FACADE_PERIM = 'building_facades_perim'.freeze
  AUTOMATED_TELLER_MACHINES_PER_LOCATION = 'automated_teller_machines_per_location'.freeze
  AUTOMATED_TELLER_MACHINES_PER_MACHINE = 'automated_teller_machines_per_machine'.freeze
  ENTRIES_AND_GATES = 'entries_and_gates'.freeze
  LOADING_AREAS_FOR_EMERGENCY_VEHICLES = 'loading_areas_for_emergency_vehicles'.freeze
  DRIVE_THROUGH = 'drive_through_windows_and_doors'.freeze
  PARKING_ENTRANCES = 'parking_near_24_hour_entrances'.freeze
  PARKING_ROADWAY = 'roadway_parking'.freeze
end

class UserDataWWRBldgType < UserData
  WAREHOUSE = 'Warehouse (nonrefrigerated)'.freeze
  SCHOOL_SECONDARY = 'School (secondary and university)'.freeze
  SCHOOL_PRIMARY = 'School (primary)'.freeze
  RETAIL_STRIP_MALL = 'Retail (strip mall)'.freeze
  RETAIL_STAND_ALONE = 'Retail (stand alone)'.freeze
  RESTAURANT_QUICK_SERVICE = 'Restaurant (quick service)'.freeze
  RESTAURANT_FULL_SERVICE = 'Restaurant (full serivce)'.freeze
  OFFICE_SMALL = 'Office <= 5,000 sq ft'.freeze
  OFFICE_MEDIUM = 'Office 5,000 to 50,000 sq ft'.freeze
  OFFICE_LARGE = 'Office > 50,000 sq ft'.freeze
  HOTEL_LARGE = 'Hotel/motel > 75 rooms'.freeze
  HOTEL_SMALL = 'Hotel/motel <= 75 rooms'.freeze
  HOSPITAL = 'Hospital'.freeze
  HEALTHCARE = 'Healthcare (outpatient)'.freeze
  GROCERY = 'Grocery store'.freeze
  ALL_OTHER = 'All other'.freeze
end

class UserDataFiles < UserData
  AIRLOOP_HVAC = 'userdata_airloop_hvac'.freeze
  AIRLOOP_HVAC_DOAS = 'userdata_airloop_hvac_doas'.freeze
  BUILDING = 'userdata_building'.freeze
  DESIGN_SPECIFICATION_OUTDOOR_AIR = 'userdata_design_specification_outdoor_air'.freeze
  ELECTRIC_EQUIPMENT = 'userdata_electric_equipment'.freeze
  EXTERIOR_LIGHTS = 'userdata_exterior_lights'.freeze
  GAS_EQUIPMENT = 'userdata_gas_equipment'.freeze
  LIGHTS = 'userdata_lights'.freeze
  SPACE = 'userdata_space'.freeze
  SPACETYPE = 'userdata_spacetype'.freeze
  THERMAL_ZONE = 'userdata_thermal_zone'.freeze
  WATERUSE_CONNECTIONS = 'userdata_wateruse_connections'.freeze
  WATERUSE_EQUIPMENT = 'userdata_wateruse_equipment'.freeze
  WATERUSE_EQUIPMENT_DEFINITION = 'userdata_wateruse_equipment_definition'.freeze
  ZONE_HVAC = 'userdata_zone_hvac'.freeze
  ZONE_INFILTRATION = 'userdata_zone_infiltration'.freeze
end
