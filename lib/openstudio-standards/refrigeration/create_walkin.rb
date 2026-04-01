module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Create Walkin
    # Methods to add refrigerated walkins

    # Adds a refrigerated walkin to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] Name of the refrigeration walkin
    # @param template [String] Technology or standards level, either 'old', 'new', or 'advanced'
    # @param walkin_type [String] The walkin type. See refrigerated_walkins data for valid options under walkin_type.
    # @param defrost_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object with boolean values for the defrost schedule
    # @param defrost_start_hour [Double] Start hour between 0 and 24 for. Used if defrost_schedule not specified.
    # @param dripdown_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object with boolean values for the dripdown schedule
    # @param restocking_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the restocking schedule.
    #   If nil, will use the schedule from the refrigerated_walkins data. If that is not available, it will default to a constant 21 W schedule.
    # @param door_opening_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the stocking door opening schedule. If nil, will use the schedule from the refrigerated_walkins data. If that is not available, it will default to 0.0625 fraction open between 6:00 and 22:00.
    # @param door_protection_type [String] Stocking door opening protection type. Options are 'None', 'AirCurtain', or 'StripCurtain'. If nil, it will use the value from the refrigerated_walkins data.
    #   If nil, uses the value from lookup properties.
    # @param thermal_zone [OpenStudio::Model::ThermalZone] Thermal zone with the walkin. If nil, will look up from the model.
    # @return [OpenStudio::Model::RefrigerationWalkIn] the refrigeration walkin
    def self.create_walkin(model,
                           name: nil,
                           template: 'new',
                           walkin_type: 'Walk-in Cooler - 120SF with no glass door',
                           defrost_schedule: nil,
                           defrost_start_hour: 0,
                           dripdown_schedule: nil,
                           restocking_schedule: nil,
                           door_opening_schedule: nil,
                           door_protection_type: nil,
                           thermal_zone: nil)
      # get thermal zone if not provided
      if thermal_zone.nil?
        # Find the thermal zones most suited for holding the walkin
        thermal_zone = OpenstudioStandards::Refrigeration.refrigeration_walkin_zone(model)
        if thermal_zone.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', 'Attempted to add walkins to the model, but could find no thermal zone to put them into.')
          return nil
        end
      end

      # load refrigeration walkin data
      walkins_csv = "#{File.dirname(__FILE__)}/data/refrigerated_walkins.csv"
      unless File.file?(walkins_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{walkins_csv}")
        return nil
      end
      walkins_tbl = CSV.table(walkins_csv, encoding: 'ISO8859-1:utf-8')
      walkins_hsh = walkins_tbl.map(&:to_hash)

      # get walkin properties
      walkins_properties = walkins_hsh.select { |r| (r[:template] == template) && (r[:walkin_name] == walkin_type) }
      if walkins_properties.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find walkin properties for walkin #{template} #{walkin_type}.")
        return nil
      end
      walkins_properties = walkins_properties[0]

      if name.nil?
        name = "#{walkin_type} #{template}"
      end

      # add walkin
      ref_walkin = OpenStudio::Model::RefrigerationWalkIn.new(model, model.alwaysOnDiscreteSchedule)
      ref_walkin.setName(name)
      ref_walkin.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      ref_walkin.setRatedCoilCoolingCapacity(walkins_properties[:rated_capacity])
      ref_walkin.setOperatingTemperature(walkins_properties[:operating_temperature])
      ref_walkin.setRatedCoolingSourceTemperature(walkins_properties[:rated_cooling_source_temperature])
      ref_walkin.setRatedTotalHeatingPower(walkins_properties[:rated_total_heating_power])
      ref_walkin.setRatedCirculationFanPower(0.0)
      ref_walkin.setRatedCoolingCoilFanPower(walkins_properties[:rated_cooling_fan_power])
      ref_walkin.setRatedTotalLightingPower(walkins_properties[:lighting_power])
      ref_walkin.setLightingSchedule(model.alwaysOnDiscreteSchedule)
      ref_walkin.setDefrostType(walkins_properties[:defrost_type])
      ref_walkin.setDefrostControlType(walkins_properties[:defrost_control_type])
      ref_walkin.setDefrostPower(walkins_properties[:defrost_power])
      ref_walkin.setTemperatureTerminationDefrostFractiontoIce(walkins_properties[:temperature_termination_defrost_fraction_to_ice])
      ref_walkin.setInsulatedFloorSurfaceArea(walkins_properties[:insulated_floor_area])
      ref_walkin.setInsulatedFloorUValue(walkins_properties[:insulated_floor_uvalue])
      ref_walkin.setZoneBoundaryTotalInsulatedSurfaceAreaFacingZone(walkins_properties[:total_insulatedsurface_area_facing_zone])
      ref_walkin.setZoneBoundaryInsulatedSurfaceUValueFacingZone(walkins_properties[:insulated_surface_uvalue_facing_zone])
      ref_walkin.setZoneBoundaryAreaofGlassReachInDoorsFacingZone(walkins_properties[:area_of_glass_reachin_doors_facing_zone])
      ref_walkin.setZoneBoundaryGlassReachInDoorUValueFacingZone(walkins_properties[:reachin_door_uvalue]) unless walkins_properties[:reachin_door_uvalue].nil?
      ref_walkin.setZoneBoundaryAreaofStockingDoorsFacingZone(walkins_properties[:area_of_stocking_doors_facing_zone])
      ref_walkin.setZoneBoundaryHeightofStockingDoorsFacingZone(walkins_properties[:height_of_stocking_doors_facing_zone])
      # replace with glass height property when added
      ref_walkin.setZoneBoundaryHeightofGlassReachInDoorsFacingZone(walkins_properties[:height_of_stocking_doors_facing_zone])
      ref_walkin.setZoneBoundaryStockingDoorUValueFacingZone(walkins_properties[:stocking_door_u])
      # Use door_protection_type argument if provided, otherwise use value from lookup properties
      protection_type = door_protection_type.nil? ? walkins_properties[:stocking_door_opening_protection] : door_protection_type
      ref_walkin.zoneBoundaries.each { |zb| zb.setStockingDoorOpeningProtectionTypeFacingZone(protection_type) }
      ref_walkin.setZoneBoundaryThermalZone(thermal_zone)

      # only add defrost schedules if not OffCycle
      unless walkins_properties[:defrost_type] == 'OffCycle'
        # defrost properties, default to two 45 minute defrost cycles per day followed by a 5 minute dripdown duration
        defrost_duration = walkins_properties[:defrost_duration].nil? ? 45 : walkins_properties[:defrost_duration]
        defrosts_per_day = walkins_properties[:defrosts_per_day].nil? ? 2 : walkins_properties[:defrosts_per_day]
        dripdown_duration = walkins_properties[:dripdown_duration].nil? ? 5 : walkins_properties[:dripdown_duration]

        # defrost hours are calculated from the start hour and number of defrosts per day
        defrost_interval = (24 / defrosts_per_day).floor
        defrost_hours = (1..defrosts_per_day).map { |i| defrost_start_hour + ((i - 1) * defrost_interval) }
        defrost_hours.map! { |hr| hr > 23 ? hr - 24 : hr }
        defrost_hours.sort!

        # Defrost schedule
        if defrost_schedule.nil?
          defrost_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
          defrost_schedule.setName("#{ref_walkin.name} Defrost")
          defrost_schedule.defaultDaySchedule.setName("#{ref_walkin.name} Defrost Default")
          defrost_hours.each do |defrost_hour|
            defrost_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, defrost_hour, 0, 0), 0)
            defrost_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, defrost_hour, defrost_duration, 0), 1)
          end
          defrost_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        else
          unless defrost_schedule.to_Schedule.is_initialized
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Input for defrost_schedule #{defrost_schedule} is not a valid OpenStudio::Model::Schedule object")
            return nil
          end
        end
        ref_walkin.setDefrostSchedule(defrost_schedule)

        # Dripdown schedule, synced with defrost schedule
        if dripdown_schedule.nil?
          dripdown_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
          dripdown_schedule.setName("#{ref_walkin.name} Dripdown")
          dripdown_schedule.defaultDaySchedule.setName("#{ref_walkin.name} Dripdown Default")
          defrost_hours.each do |defrost_hour|
            dripdown_hour = (defrost_duration + dripdown_duration) > 59 ? defrost_hour + 1 : defrost_hour
            dripdown_hour = dripdown_hour > 23 ? dripdown_hour - 24 : dripdown_hour
            dripdown_end_min = (defrost_duration + dripdown_duration) > 59 ? defrost_duration + dripdown_duration - 60 : defrost_duration + dripdown_duration
            dripdown_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, defrost_hour, defrost_duration, 0), 0)
            dripdown_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, dripdown_hour, dripdown_end_min, 0), 1)
          end
          dripdown_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        else
          unless dripdown_schedule.to_Schedule.is_initialized
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Input for dripdown_schedule #{dripdown_schedule} is not a valid OpenStudio::Model::Schedule object")
            return nil
          end
        end
        ref_walkin.setDefrostDripDownSchedule(dripdown_schedule)
      end

      # restocking schedule
      # default calculated from 100 kg * 5 deg C * 3.65 kJ/kg*C / 24 hours = ~21 W
      std = Standard.build('90.1-2013')
      if !restocking_schedule.nil?
        unless restocking_schedule.to_Schedule.is_initialized
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Input for restocking_schedule #{restocking_schedule} is not a valid OpenStudio::Model::Schedule object")
          return nil
        end
      elsif !walkins_properties[:restocking_schedule].nil?
        restocking_schedule = std.model_add_schedule(model, walkins_properties[:restocking_schedule])
      else
        restocking_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 21, name: "#{ref_walkin.name} Restocking")
      end
      ref_walkin.setRestockingSchedule(restocking_schedule)

      # door opening schedule
      if !door_opening_schedule.nil?
        unless door_opening_schedule.to_Schedule.is_initialized
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Input for door_opening_schedule #{door_opening_schedule} is not a valid OpenStudio::Model::Schedule object")
          return nil
        end
      elsif !walkins_properties[:stocking_door_schedule].nil?
        door_opening_schedule = std.model_add_schedule(model, walkins_properties[:stocking_door_schedule])
      else
        door_opening_options = {
          'name' => 'Walk-In Door Opening Schedule',
          'winter_time_value_pairs' => { 6.0 => 0.0, 22.0 => 0.0625, 24.0 => 0.0 },
          'summer_time_value_pairs' => { 6.0 => 0.0, 22.0 => 0.0625, 24.0 => 0.0 },
          'default_time_value_pairs' => { 6.0 => 0.0, 22.0 => 0.0625, 24.0 => 0.0 }
        }
        door_opening_schedule = OpenstudioStandards::Schedules.create_simple_schedule(model, door_opening_options)
      end
      ref_walkin.setZoneBoundaryStockingDoorOpeningScheduleFacingZone(door_opening_schedule)

      insulated_floor_area_ft2 = OpenStudio.convert(walkins_properties[:insulated_floor_area], 'm^2', 'ft^2').get
      rated_cooling_capacity_btu_per_hr = OpenStudio.convert(walkins_properties[:rated_capacity], 'W', 'Btu/hr').get
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Added #{insulated_floor_area_ft2.round} ft2 walkin called #{walkin_type} with a capacity of #{rated_cooling_capacity_btu_per_hr.round} Btu/hr to #{thermal_zone&.name}.")

      return ref_walkin
    end
  end
end
