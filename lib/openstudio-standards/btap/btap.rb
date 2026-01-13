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
require_relative 'attributes'
require_relative 'fileio'
require_relative 'activity'
require_relative 'structure'
require_relative 'geometry'
require_relative 'envelope'
require_relative 'bridging'
require_relative 'schedules'
require_relative 'btap_result'

# require_relative 'analysis'
# require_relative 'simmanager'
# require_relative 'mpc'
# require_relative 'spaceloads'
# require_relative 'spacetypes'

# require_relative 'hvac'
# require_relative 'economics'
# require_relative 'measures'
# require_relative 'utilities'
# require_relative 'reporting'
# require_relative 'equest'
# require_relative 'btap_costing'
#require_relative 'btap.space'
#require_relative 'btap.model'
class String
  #This method converts to Boolean.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_bool
    return true if self == true || self =~ (/^(true|t|yes|y|1)$/i)
    return false if self == false  || self =~ (/^(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end
end


class Integer
  #This method converts to Boolean.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_bool
    return true if self == 1
    return false if self == 0
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end
end

class TrueClass
  #This method converts to i.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_i; 1; end
  #This method converts to Boolean.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_bool; self; end
end

class FalseClass
  #This method converts to i.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_i; 0; end
  #This method converts to Boolean.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_bool; self; end
end

class NilClass
  #This method converts to Boolean.
  #@author phylroy.lopez@nrcan.gc.ca
  def to_bool; false; end
end


# A set of methods developed by NRCan to simplify building model creation and
# analysis. These methods are meant to compliment the OpenStudio classes and methods
# For full access to the OpenStudio API please refer to the OpenStudio Website.
# http://openstudio.nrel.gov/latest-c-sdk-documentation/model
module BTAP
  #EnergyPlus version
  ENERGY_PLUS_MAJOR_VERSION = 8
  ENERGY_PLUS_MINOR_VERSION = 3

  #Path constants
  OS_RUBY_PATH = File.expand_path("..\\..\\..", __FILE__)
  TESTING_FOLDER = "C:\\test"

  #  A wrapper for outputing feedback to users and developers.
  #  BTAP::runner_register("InitialCondition",   "Your Information Message Here", runner)
  #  BTAP::runner_register("Info",    "Your Information Message Here", runner)
  #  BTAP::runner_register("Warning", "Your Information Message Here", runner)
  #  BTAP::runner_register("Error",   "Your Information Message Here", runner)
  #  BTAP::runner_register("Debug",   "Your Information Message Here", runner)
  #  BTAP::runner_register("FinalCondition",   "Your Information Message Here", runner)
  #  @params type [String]
  #  @params runner [OpenStudio::Ruleset::OSRunner] # or a nil.
  def self.runner_register(type,text,runner = nil)

    #dump to console.
    puts "#{type.upcase}: #{text}"
    #dump to runner.
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

  def self.runner_register_value(name,value,runner = nil)
    if runner.is_a?(OpenStudio::Ruleset::OSRunner)
      runner.registerValue( name,value.to_s)
      BTAP::runner_register("Info", "#{name} = #{value} has been registered in the runner", runner)
    end
  end

  def self.gut_building(model)
    #clean up any remaining items that we don't need for NECB.
    puts "Removing casual loads."
    BTAP::Resources::SpaceLoads::remove_all_casual_loads(model)
    puts "Removing space loads."
    BTAP::Resources::SpaceLoads::remove_all_SpaceLoads(model)
    puts "Removing OA loads."
    BTAP::Resources::SpaceLoads::remove_all_DesignSpecificationOutdoorAir(model)
    puts "Removing Envelope"
    BTAP::Resources::Envelope::remove_all_envelope_information(model)
    puts "Removing Infiltration"
    BTAP::Resources::SpaceLoads::remove_all_SpaceInfiltrationDesignFlowRate(model)
    puts "Removing all Schedules"
    BTAP::Resources::Schedules::remove_all_schedules( model )
    puts "Removing HVAC"
    BTAP::Resources::HVAC.clear_all_hvac_from_model( model )
  end


  class OpenStudioLibrary
    include Singleton
    attr_accessor :library
    #This method initializes the library.
    #@author phylroy.lopez@nrcan.gc.ca
    def initialize()
      #path to openstudio library
      @lib_path = "C:\\Program Files (x86)\\OpenStudio 1.2.0\\share\\openstudio\\OSApp\\hvaclibrary\\hvac_library.osm"
      @library = BTAP::FileIO::load_osm(@lib_path, "OpenStudio_Library")
    end
  end
  module SimulationSettings
    #This sets the simulation period for the model. All arguments are integers.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object {http://openstudio.nrel.gov/latest-c-sdk-documentation/model}
    #@param start_month [Integer] a list of output variables that you wish to report from the simulation.
    #@param start_day [Integer] a list of output variables that you wish to report from the simulation.
    #@param end_month [Integer] a list of output variables that you wish to report from the simulation.
    #@param end_day [Integer] a list of output variables that you wish to report from the simulation.
    #@param repeat [Integer = 1] Number of times the simulation period is run. 1 is default.
    #@return [OpenStudio::Model::Model] the OpenStudio model object (self reference).
    def self.set_run_period(model,start_month,start_day,end_month,end_day, repeat = 1)
      raise("Run Period is invalid") unless Date.valid_civil?(2001, start_month , start_day) and Date.valid_civil?(2001, end_month , end_day) and repeat > 0
      run_period = model.getRunPeriod
      run_period.setBeginMonth(start_month)
      run_period.setBeginDayOfMonth(start_day)
      run_period.setEndMonth(end_month)
      run_period.setEndDayOfMonth(end_day)
      run_period.setNumTimePeriodRepeats(repeat)
      return model
    end
  end
  module Reports
    #This method clears all the output variables to make simulations run faster or to
    #start fresh.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object {http://openstudio.nrel.gov/latest-c-sdk-documentation/model}
    #@return [OpenStudio::Model::Model] the OpenStudio model object (self reference).
    def self.clear_output_variables(model)
      #remove existing outputs
      model.getOutputVariables.sort.each do |object|
        object.remove
      end
      return model
    end

    #This turns all output on. Warning: Long runtimes will result.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object
    #@param frequency [Fixnum]
    #@return [OpenStudio::Model::Model] a copy of the OpenStudio model object (self reference).
    def self.all_output_variables(model,frequency)
      BTAP::Reports::set_output_variables(model, frequency, BTAP::Reports::get_possible_output_variables(model))
      return model
    end

    #This method returns a vector of the results that are available in the current
    #model.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object
    #@return [Array<String>] a list of all the possible output variables.
    def self.get_possible_output_variables( model )
      #Run simulation
      copy = BTAP::FileIO::deep_copy(model)
      copy.building.get.setName("rdd_run")
      BTAP::SimulationSettings::set_run_period(copy, 1, 1, 1, 1)
      BTAP::SimManager::run_simulation(copy,"C:\\temp\\rdd_maker")
      rdd_file_path = ""
      Find.find("C:\\temp\\rdd_maker") do |path|
        rdd_file_path = path if path =~ /.*\.rdd$/
      end
      contents = File.read(rdd_file_path)
      output_variables = Array.new()
      contents.each do |line|
        match = line.match /^\s*Output:Variable,\*,(.*),(.*);(.*)/
        if match
          output_variables.push(match[1])
        end
      end
      return output_variables
    end

    #This method sets up some predetermined output variables. May take a while to run with these settings.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object
    #@param frequency [Fixnum]
    #@param output_variable_array [Array<String>] a list of output variables that you wish to report from the simulation.
    #@return [OpenStudio::Model::Model] the OpenStudio model object (self reference).
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
  # This contains methods for creation and querying object that deal with Envelope, SpaceLoads,Schedules, and HVAC.

  module Common
    #This model checks to see if the obj_array passed is
    #the object we require, or if a string is given to search for a object of that strings name.
    #@author Phylroy A. Lopez
    #@param model [OpenStudio::Model::Model] A model object
    #@param obj_array <Object>
    #@param object_type [Object]
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

    #This method gets a date from a string.
    #@author phylroy.lopez@nrcan.gc.ca
    #@param datestring [String] a date string
    def self.get_date_from_string(datestring)
      month = datestring.split("-")[0].to_s
      day   = datestring.split("-")[1].to_i
      month_list = ["Jan","Feb","Mar","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
      raise ("Month given #{month} is not in format required please enter month with following 3 letter format#{month_list}.") unless month_list.include?(month)
      OpenStudio::Date.new(OpenStudio::MonthOfYear.new(month),day)
    end

    #This method gets a time from a string.
    #@author phylroy.lopez@nrcan.gc.ca
    #@param timestring [String] a time string
    def self.get_time_from_string(timestring)
      #ensure that it is in 0-24 hour format.
      hour = timestring.split(":")[0].to_i
      min = timestring.split(":")[1].to_i
      raise ("invalid time format #{timestring} please use 0-24 as a range for the hour and 0-59 for range for the minutes: Clock starts at 0:00 and stops at 24:00") if (hour < 0 or hour > 24) or ( min < 0 or min > 59 ) or (hour == 24 and min > 0)
      OpenStudio::Time.new(timestring)
    end
  end
end
#module BTAP
