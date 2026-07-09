# *********************************************************************
# *  Copyright (c) 2008-2015, Natural Resources Canada
# *  All rights reserved.
# *
# *  This library is free software; you can redistribute it and/or
# *  modify it under the terms of the GNU Lesser General Public
# *  License as published by the Free Software Foundation; either
# *  version 2.1 of the License, or (at your option) any later version.
# *
# *  This library is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *  Lesser General Public License for more details.
# *
# *  You should have received a copy of the GNU Lesser General Public
# *  License along with this library; if not, write to the Free Software
# *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# **********************************************************************/

module BTAP
  module Resources #Resources

    # This module contains methods that relate to Materials, Constructions and Construction Sets
    module Schedules # BTAP::Resources::Schedules
      module StandardScheduleTypeLimits
        def self.get_fraction(model)
          name = "FRACTION"
          fraction_schedule_type_limits = model.getScheduleTypeLimitsByName(name)
          if fraction_schedule_type_limits.empty?
            #fraction
            fraction_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            fraction_schedule_type_limits.setName(name)
            fraction_schedule_type_limits.setNumericType("CONTINUOUS")
            fraction_schedule_type_limits.setUnitType("Dimensionless")
            fraction_schedule_type_limits.setLowerLimitValue(0.0)
            fraction_schedule_type_limits.setUpperLimitValue(1.0)
            return fraction_schedule_type_limits
          else
            return fraction_schedule_type_limits.get
          end
        end

        def self.get_on_off(model)
          name = "ON_OFF"
          onoff_schedule_type_limits = model.getScheduleTypeLimitsByName(name)
          if onoff_schedule_type_limits.empty?
            #onoff
            onoff_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            onoff_schedule_type_limits.setName(name)
            onoff_schedule_type_limits.setNumericType("DISCRETE")
            onoff_schedule_type_limits.setUnitType("Dimensionless")
            onoff_schedule_type_limits.setLowerLimitValue(0)
            onoff_schedule_type_limits.setUpperLimitValue(1)
            return onoff_schedule_type_limits
          else
            return onoff_schedule_type_limits.get
          end
        end

        def self.get_temperature(model)
          name = "TEMPERATURE"

          #temperature
          temperature_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
          temperature_schedule_type_limits.setName(name)
          temperature_schedule_type_limits.setNumericType("Continuous")
          temperature_schedule_type_limits.setUnitType("Temperature")
          #temperature_schedule_type_limits.setLowerLimitValue(-200.0)
          #temperature_schedule_type_limits.setUpperLimitValue(200.0)
          return temperature_schedule_type_limits

        end

        def self.get_activity(model)
          name = "ACTIVITY"
          temperature_schedule_type_limits = model.getScheduleTypeLimitsByName(name)
          if temperature_schedule_type_limits.empty?
            #temperature
            temperature_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            temperature_schedule_type_limits.setName(name)
            temperature_schedule_type_limits.setNumericType("Continuous")
            temperature_schedule_type_limits.setUnitType("W/person")
            temperature_schedule_type_limits.setLowerLimitValue(70.0)
            temperature_schedule_type_limits.setUpperLimitValue(1000.0)
            return temperature_schedule_type_limits
          else
            return temperature_schedule_type_limits.get
          end
        end
      end

      module StandardSchedules
        module ON_OFF
          def self.always_off(model)
            on_off_always_off = "ON_OFF_ALWAYS_OFF"
            schedule = model.getScheduleRulesetByName(on_off_always_off)
            if schedule.empty?
              return BTAP::Resources::Schedules::create_annual_constant_ruleset_schedule(
                model,
                on_off_always_off,
                "ON_OFF",
                0)
            else
              return schedule.get
            end
          end
        end
      end

      #Creates a new ruleset schedule object. This is the basic schedule component
      #used in openstudio.
      #name = string: name of schedule
      #type = TEMPERATURE, ON_OFF, FRACTION
      #hourArrayValues = a 3 x 24 array representing week, sat and sun hours.
      #examples:
      #hourArrayValues =
      #    [
      #      [18,18,18,18,21,21,21,21,23,23,23,23,23,23,21,21,21,18,18,18,18,18,18,18],#Weekday
      #      [18,18,18,18,21,21,21,21,23,23,23,23,23,23,21,21,21,18,18,18,18,18,18,18],#Saturday
      #      [18,18,18,18,21,21,21,21,23,23,23,23,23,23,21,21,21,18,18,18,18,18,18,18] #Sun
      #    ]
      # or if you need a constant temperature you can use this shorthand method.
      #    heat_setpoint_array =
      #      [
      #      Array.new(24){21}, #Weekday
      #      Array.new(24){21}, #Sat
      #      Array.new(24){21}, #Sun
      #    ]
      def self.create_annual_ruleset_schedule(model,name,type,hourArrayValues,start_date = "Jan-1",end_date = "Dec-31" )
        raise("array size not 3x24. Please verify your hourly array") if hourArrayValues.size != 3 or hourArrayValues[0].size != 24 or hourArrayValues[1].size != 24 or hourArrayValues[2].size != 24
        start_date = BTAP::Common::get_date_from_string(start_date)
        end_date   = BTAP::Common::get_date_from_string(end_date)


        #create new ruleset
        ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
        ruleset.setName(name)



        #set types limits
        case type.downcase
        when "FRACTION".downcase
          scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_fraction(model)
        when "ON_OFF".downcase
          scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_on_off(model)
        when "TEMPERATURE".downcase
          scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_temperature(model)

        when "ACTIVITY".downcase
          scheduletype = BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_activity(model)
        else
          #if schedule type could not be found raise an exception.
          raise "could  not find schedule limits type :" + type
        end



        #Add days
        weekday = OpenStudio::Model::ScheduleDay.new(model)
        saturday = OpenStudio::Model::ScheduleDay.new(model)
        sunday = OpenStudio::Model::ScheduleDay.new(model)

        weekday.setName(  "wkd" + name )
        saturday.setName( "sat" + name )
        sunday.setName(   "sun" + name )
        if not weekday.setScheduleTypeLimits(scheduletype) or
            not saturday.setScheduleTypeLimits(scheduletype) or
            not sunday.setScheduleTypeLimits(scheduletype)
          raise "unable to set ScheduleDay type limits"
        end

        (0..23).each do|hour|
          weekday.addValue(OpenStudio::Time.new(0,hour+1), hourArrayValues[0][hour] )
          saturday.addValue(OpenStudio::Time.new(0,hour+1), hourArrayValues[1][hour] )
          sunday.addValue(OpenStudio::Time.new(0,hour+1), hourArrayValues[2][hour] )
        end

        #create weekday rule
        weekday_rule = OpenStudio::Model::ScheduleRule.new(ruleset,weekday)
        weekday_rule.setName("wkd" + name + " rule")
        weekday_rule.setApplySunday(false)
        weekday_rule.setApplyMonday(true)
        weekday_rule.setApplyTuesday(true)
        weekday_rule.setApplyWednesday(true)
        weekday_rule.setApplyThursday(true)
        weekday_rule.setApplyFriday(true)
        weekday_rule.setApplySaturday(false)
        weekday_rule.setStartDate(start_date)
        weekday_rule.setEndDate(end_date)

        saturday_rule = OpenStudio::Model::ScheduleRule.new(ruleset,saturday)
        saturday_rule.setName("sat" + name + "rule" )
        saturday_rule.setApplySunday(false)
        saturday_rule.setApplyMonday(false)
        saturday_rule.setApplyTuesday(false)
        saturday_rule.setApplyWednesday(false)
        saturday_rule.setApplyThursday(false)
        saturday_rule.setApplyFriday(false)
        saturday_rule.setApplySaturday(true)
        saturday_rule.setStartDate(start_date)
        saturday_rule.setEndDate(end_date)

        sunday_rule = OpenStudio::Model::ScheduleRule.new(ruleset,sunday)
        sunday_rule.setName("sun" + name + "rule")
        sunday_rule.setApplySunday(true)
        sunday_rule.setApplyMonday(false)
        sunday_rule.setApplyTuesday(false)
        sunday_rule.setApplyWednesday(false)
        sunday_rule.setApplyThursday(false)
        sunday_rule.setApplyFriday(false)
        sunday_rule.setApplySaturday(false)
        sunday_rule.setStartDate(start_date)
        sunday_rule.setEndDate(end_date)

        #set default schedule to be the same as the week schedule.
        default_day =  ruleset.defaultDaySchedule
        default_day.clearValues()
        weekday.times.each_index {|counter| default_day.addValue(weekday.times[counter],weekday.values[counter])}


        return ruleset
      end


      # This method will create a detailed schedule using a "compact format"
      # @param model [OpenStudio::Model::Model]  The building model you wish to add the schedule to.
      # @param name  [String]                    The name of the schedule (Can be left as a blank string "" if you wish.
      # @param type  [String] either "TEMPERATURE", "ON_OFF", "FRACTION"
      # @param schedule_struct [Array<Array>] This is a complex nested array to contain the minimal information required for a detailed schedule.
      [
        [
          #Start and stop date of schedule in gregorian format.
          ["Jan-01","May-31"],
          # Days of the week that it applies
          ["M","T","W","TH","F","S","SN"],# Days of the week are "M","T","W","TH","F","S","SN", or wild cards for weekend and weekdays "WKD","WKE"
          # value up until the hour and minute for each block.
          [
            [ "9:00",  13.0 ], #time, value_until_this_time
            [ "17:00", 21.0 ],  #time, value_until_this_time
            [ "24:00", 13.0 ]  #time, value_until_this_time
          ]
        ],
        [
          #Start and stop date of schedule in gregorian format.
          ["Jun-01","Sep-30"],
          # Days of the week that it applies
          ["M","T","W","TH","F","S","SN"], # Days of the week are "M","T","W","TH","F","S","SN", or wild cards for weekend and weekdays "WKD","WKE"
          # value up until the hour and minute for each block.
          [
            ["24:00", 13.0]  #time, value_until_this_time
          ]
        ],
        [
          #Period for schedule in gregorian format.
          [ "Oct-01","Dec-31"],
          # Days of the week that it applies
          ["M","T","W","TH","F","S","SN"], # Days of the week are "M","T","W","TH","F","S","SN", or wild cards for weekend and weekdays "WKD","WKE"
          # value up until the hour and minute for each block.
          [
            [ "9:00",  13.0], #time, value_until_this_time
            [ "17:00", 22.0], #time, value_until_this_time
            [ "24:00", 13.0]  #time, value_until_this_time
          ]
        ]
      ]

      # This method creates a new dual setpoint schedule using pre-created heating and cooling schedules.
      # name - name of schedule.
      # type - type of schedule (FRACTION, ON_OFF, TEMPERATURE)
      # heating_schedule - an heating schedule ruleset object.
      # cooling_schedule - a cooling schedule ruleset object
      def self.create_annual_thermostat_setpoint_dual_setpoint(model,name,heating_schedule,cooling_schedule)

        heating_schedule = BTAP::Common::validate_array(model,heating_schedule,"ScheduleRuleset").first
        cooling_schedule = BTAP::Common::validate_array(model,cooling_schedule,"ScheduleRuleset").first
        dual_setpoint = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
        dual_setpoint.setName(name)
        unless dual_setpoint.setCoolingSchedule(cooling_schedule) and dual_setpoint.setHeatingSchedule(heating_schedule)
          raise "dual setpoint could not be created"
        end
        return dual_setpoint
      end

      # This method creates a new constant schedule.
      # name - name of schedule.
      # type - type of schedule (FRACTION, ON_OFF, TEMPERATURE)
      # value - value to be used over 24 hours.
      def self.create_annual_constant_ruleset_schedule(model, name,type,value)
        return create_annual_ruleset_schedule(model, name,type, [Array.new(24){value}, Array.new(24){value},Array.new(24){value}])
      end

      # Creates TimeSeries from ScheduleRuleset
      # @author david.goldwasser@nrel.gov
      # @param model [OpenStudio::Model::Model] A model object
      # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] A schedule ruleset
      # @return [OpenStudio::TimeSeries] A TimeSeries object
      def self.create_timeseries_from_schedule_ruleset(model, schedule_ruleset)
        yd = model.getYearDescription
        start_date = yd.makeDate(1, 1)
        end_date = yd.makeDate(12, 31)

        values = OpenStudio::DoubleVector.new
        day = OpenStudio::Time.new(1.0)
        interval = OpenStudio::Time.new(1.0 / 48.0)
        day_schedules = schedule_ruleset.to_ScheduleRuleset.get.getDaySchedules(start_date, end_date)
        day_schedules.each do |day_schedule|
          time = interval
          while time < day
            values << day_schedule.getValue(time)
            time += interval
          end
        end
        time_series = OpenStudio::TimeSeries.new(start_date, interval, OpenStudio.createVector(values), "")
      end

      # Creates ScheduleVariableInterval from TimeSeries
      # @author david.goldwasser@nrel.gov
      # @param model [OpenStudio::Model::Model] A model object
      # @param time_series [OpenStudio::TimeSeries] A TimeSeries object
      # @return [OpenStudio::Model::ScheduleInterval] An interval schedule
      def self.create_schedule_variable_interval_from_time_series(model, time_series)
        result = OpenStudio::Model::ScheduleInterval.fromTimeSeries(time_series, model).get
      end
    end #module Schedules
  end #module Resources
end
