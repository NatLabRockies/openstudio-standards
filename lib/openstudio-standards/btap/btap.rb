# *********************************************************************
# *  Copyright (c) 2008-2025, Natural Resources Canada
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


require 'fileutils'
require 'singleton'
require 'find'
require 'date'
require 'tbd'
require_relative 'attributes'
require_relative 'fileio'
require_relative 'activity'
require_relative 'constructions'
require_relative 'structure'
require_relative 'geometry'
require_relative 'envelope'
require_relative 'bridging'
require_relative 'schedules'
require_relative 'btap_result'
require_relative 'linear_regression'

class String
  # This method converts to Boolean.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_bool
    return true if self == true || self =~ (/^(true|t|yes|y|1)$/i)
    return false if self == false  || self =~ (/^(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end
end


class Integer
  # This method converts to Boolean.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_bool
    return true if self == 1
    return false if self == 0
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end
end

class TrueClass
  # This method converts to i.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_i; 1; end

  # This method converts to Boolean.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_bool; self; end
end

class FalseClass
  # This method converts to i.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_i; 0; end

  # This method converts to Boolean.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_bool; self; end
end

class NilClass
  # This method converts to Boolean.
  # @author phylroy.lopez@nrcan.gc.ca
  def to_bool; false; end
end


# A set of methods developed by NRCan to simplify building model creation and
# analysis. These methods are meant to compliment the OpenStudio classes and
# methods. For full access to the OpenStudio SDK please refer to the OpenStudio
# website: https://openstudio-sdk-documentation.s3.amazonaws.com/index.html
module BTAP

  #  A wrapper for outputing feedback to users and developers. Examples:
  #  BTAP::runner_register("InitialCondition", "Your Information Message Here", runner)
  #  BTAP::runner_register("Info",             "Your Information Message Here", runner)
  #  BTAP::runner_register("Warning",          "Your Information Message Here", runner)
  #  BTAP::runner_register("Error",            "Your Information Message Here", runner)
  #  BTAP::runner_register("Debug",            "Your Information Message Here", runner)
  #  BTAP::runner_register("FinalCondition",   "Your Information Message Here", runner)
  #  @params type [String]
  #  @params runner [OpenStudio::Ruleset::OSRunner] # or a nil.
  def self.runner_register(type, text, runner = nil)

    # Dump to console.
    puts "#{type.upcase}: #{text}"

    # Dump to runner.
    if runner.is_a?(OpenStudio::Ruleset::OSRunner)
      case type.downcase
      when "info"
        runner.registerInfo(text)
      when "warning"
        runner.registerWarning(text)
      when "error"
        runner.registerError(text)
      when "notapplicable"
        runner.registerAsNotApplicable(text)
      when "finalcondition"
        runner.registerFinalCondition(text)
      when "initialcondition"
        runner.registerInitialCondition(text)
      when "debug"
      when "macro"
      else
        raise("Runner Register type #{type.downcase} not info,warning,error,notapplicable,finalcondition,initialcondition,macro.")
      end
    end
  end

  module Reports

    # This method sets up some predetermined output variables. May take a while
    # to run with these settings.
    # @author Phylroy A. Lopez
    # @param model [OpenStudio::Model::Model]
    # @param frequency [Fixnum]
    # @param output_variable_array [Array<String>] A list of output variables
    # that you wish to report from the simulation.
    # @return [OpenStudio::Model::Model] The OpenStudio model object (self
    # reference).
    def self.set_output_variables(model,frequency, output_variable_array)
      raise("Frequency is not valid. Must by \"Hourly\" or \"Timestep\" but got #{frequency}.") unless ["Hourly","Timestep"].include?(frequency)
      output_variable_array.each do |variable|
        output = OpenStudio::Model::OutputVariable.new(variable,model)
        output.setKeyValue("*")
        output.setReportingFrequency(frequency)
      end
      return model
    end
  end

  # This contains methods for creation and querying object that deal with
  # Envelope, SpaceLoads,Schedules, and HVAC.
  module Common

    # This model checks to see if the obj_array passed is the object we require,
    # or if a string is given to search for a object of that strings name.
    # @author Phylroy A. Lopez
    # @param model [OpenStudio::Model::Model] A model object
    # @param obj_array <Object>
    # @param object_type [Object]
    def self.validate_array(model,obj_array,object_type)
      command =
        %Q^#make copy of argument to avoid side effect.
        object_array = obj_array
        new_object_array = Array.new()
        #check if it is not an array
        unless  obj_array.is_a?(Array)
          if object_array.is_a?(String)
            #if the arguement is a simple string, convert to an array.
            object_array = [object_array]
            #check if it is a single object_type
          elsif not object_array.to_#{object_type}.empty?()
            object_array = [object_array]
          else
            raise("Object passed is neither a #{object_type} or a name of a #{object_type}. Please choose a #{object_type} name that exists such as :\n\#{object_names.join("\n")}")
          end
        end

        object_array.each do |object|
          #if it is a string name of an object, try to find it and insert it into the
          # return array.
          if object.is_a?(String)
            if model.get#{object_type}ByName(object).empty?
               #if we could not find an exact match. raise an exception.
               object_names = Array.new
               model.get#{object_type}s.each { |object| object_names << object.name }
              raise("Object passed is neither  a #{object_type} or a name of a #{object_type}. Please choose a #{object_type} name that exists such as :\n\#{object_names.join("\n")}")
            else
            new_object_array << model.get#{object_type}ByName(object).get
            end
          elsif not object.to_#{object_type}.empty?
          #if it is already a #{object_type}. insert it into the array.
          new_object_array << object
          else
            raise("invalid object")
          end
        end
        return new_object_array
      ^
      eval(command)
    end

    # This method gets a date from a string.
    # @author phylroy.lopez@nrcan.gc.ca
    # @param datestring [String] a date string
    def self.get_date_from_string(datestring)
      month = datestring.split("-")[0].to_s
      day   = datestring.split("-")[1].to_i
      month_list = ["Jan", "Feb", "Mar", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
      raise ("Month given #{month} is not in format required please enter month with following 3 letter format#{month_list}.") unless month_list.include?(month)
      OpenStudio::Date.new(OpenStudio::MonthOfYear.new(month),day)
    end

    # This method gets a time from a string.
    # @author phylroy.lopez@nrcan.gc.ca
    # @param timestring [String] a time string
    def self.get_time_from_string(timestring)
      #ensure that it is in 0-24 hour format.
      hour = timestring.split(":")[0].to_i
      min = timestring.split(":")[1].to_i
      raise ("invalid time format #{timestring} please use 0-24 as a range for the hour and 0-59 for range for the minutes: Clock starts at 0:00 and stops at 24:00") if (hour < 0 or hour > 24) or ( min < 0 or min > 59 ) or (hour == 24 and min > 0)
      OpenStudio::Time.new(timestring)
    end
  end
end
