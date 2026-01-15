# **************************************************************************** /
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
# *  Foundation Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
# **************************************************************************** /

require "csv"

module BTAP
  module DefaultData
    ##
    # @author: Denis Bourgeois
    #
    # Centralizes declarations/definitions of common BTAP/NECB parameters, e.g.
    # BTAP CLI run options, NECB's model_apply_standard. For now, this is in
    # CSV format: could instead be JSON or YAML (ideally requiring a schema).
    #
    # Information contained in the openstudio-standards/btap/defaults.csv has
    # been gathered by searching through multiple BTAP/NECB files. This is time
    # consuming and cumbersome for any novice (e.g. new employee, graduate
    # student), further justifying the need to centralize core BTAP/NECB
    # parameters. Similarly, many of these parameters are simply set to
    # "NECB_Default", the meaning of which varies from one BTAP/NECB method to
    # another. Most times this is simply a proxy for a nilled variable, e.g. to
    # safely exit a method. Again, cumbersome and time consuming to audit.
    #
    # The proposed solution is to centralize all key parameters in a single
    # file, with at a minimum:
    #   - the name of each parameter
    #   - its assigned default value
    #
    # The file also provides BTAP developers a means to optionally circumscribe
    # parameter attributes, such as defining its class, admissible variants or
    # numeric range, as well as a comment section. This hints at some sort of
    # data dictionary (similar to EnergyPlus' IDD file), but it is not meant to
    # be. It's up to individual BTAP developers to decide on how to proceed.
    file   = File.join(__dir__, "necb_defaults.csv")
    @@data = { param: {}, argh: {}, file: file }

    if File.exist?(@@data[:file])
      table = CSV.open(@@data[:file], headers: true).read
      #  5 columns: PARAMETER      variable name                required
      #             DEFAULT        default value                required
      #             CLASS          object class                 optional
      #             VARIANTS-RANGE admissible variants or range optional
      #             COMMENT        support text                 optional
      #
      #  examples (spaces added for clarity):
      #
      #  PARAMETER            DEFAULT       CLASS       VARIANTS-RANGE/COMMENT
      #  ____________________ _____________ ___________ ________________________
      #  btap_weather,        false,        boolean,    ,see necb_2011.rb
      #  daylighting_type,    nil,          string,     ,add_daylighting_controls
      #  fdwr_set,            nil,          float
      #  boiler_cap_ratio,    nil,          float,      0/1
      #  boiler_eff,          nil,          string/hash,,see hvac_systems.rb
      #  nv_opening_fraction, nil,          float,      0/1
      #  s3_bucket,           834599497928, string
      #
      # All items in the CSV file are parsed and stored as strings by default.
      # If CLASS is 'boolean', then either DEFAULT 'true' or 'false' is
      # converted as either boolean. If a PARAMETER holds a CLASS specification,
      # e.g. 'string' for 's3_bucket', then the DEFAULT '834599497928' is
      # maintained as a string. If CLASS is instead numeric (e.g. float or
      # integer), then the DEFAULT is converted accordingly.
      #
      # In 'model_apply_standard', the vast majority of its arguments are nilled,
      # as reflected in the examples above. If DEFAULT is set to 'nil', then the
      # the variable is actually nilled.
      #
      # If CLASS is left blank, it remains an empty string - deactivating any
      # subsequent validation. CLASS can also hold more than one class. In the
      # case of 'boiler_eff' for instance, CLASS is set as 'string/hash' - this
      # cancels any other validation, yet indicates what is admissible.
      #
      # VARIANTS helps BTAP developers and users to further circumscribe how
      # a PARAMETER may be set. For instance, only 'add_daylighting_controls' is
      # an admissible VARIANT for 'daylighting_type' (nilled by default). Yet in
      # many cases, the size of admissible VARIANTS may be too great or complex
      # to handle via this mecanism, e.g. all possible EPW files. Other examples
      # include admissible heating fuels or admissible 'boiler_eff' strings:
      #
      # - NECB 85% Efficient Condensing Boiler
      # - NECB 88% Efficient Condensing Boiler
      # - NECB 91% Efficient Condensing Boiler
      # - NECB 94% Efficient Condensing Boiler
      # - Viessmann Vitocrossal 300 CT3-17 96.2% Efficient Condensing Gas Boiler
      #
      # Some of these examples are currently held as admissible VARIANTS in the
      # draft CSV file for now, simply to demonstrate that the solution works as
      # is. If this were to become the main BTAP approach, a more suitable
      # format (like JSON or YAML) may be better suited for complex information
      # like hashes, references to specific files (e.g. admissible fuel types),
      # references to folders (e.g. EPW files),etc.
      #
      # RANGE is similar to VARIANTS, yet applies only to numeric PARAMETERS,
      # e.g. COP, efficiencies, U-factors. If a single digit is provided, it is
      # considered as a minimum (e.g. '0' means only positive values). If two
      # digits are provided, they're considered minimum & maximum (e.g. '0/1'
      # for 'boiler_cap_ratio' == any real number  between 0.0 and 1.0). Same
      # CSV column: either used to list VARIANTS or a numerical RANGE.
      #
      # COMMENTS may also point users to inline comments (e.g. see Line ~378
      # in necb_2011.rb), online README files, etc. Anything that may help users
      # get a better sense of a PARAMETER's use, scope, model limitations, etc.

      # Default data on file is stored as a hash of hashes, with each PARAMETER
      # as key to an individual hash entry (once converted as a symbol).
      table.each do |row|
        next unless row[0].respond_to?(:to_sym)

        key = row[0].downcase.to_sym

        @@data[:param][key]            = {}
        @@data[:param][key][:default ] = row[1].to_s
        @@data[:param][key][:class   ] = row[2].to_s.split("/")
        @@data[:param][key][:variants] = row[3].to_s.split("/")
        @@data[:param][key][:range   ] = row[3].to_s.split("/")
        @@data[:param][key][:comment ] = row[4].to_s
      end

      # Convert values if required.
      @@data[:param].values.each do |v|
        next unless v[:class].size == 1

        v[:class] = v[:class].first.downcase
        next if v[:class].empty?

        if v[:class] == "boolean"
          v[:default ] = v[:default].downcase
          v[:class   ] = v[:default] == "true" ? TrueClass : FalseClass
          v[:default ] = v[:default] == "true" ? true : false
          v[:variants] = []
          v[:range   ] = []
        elsif v[:default].downcase == "nil"
          v[:default ] = nil
        end

        if v[:class] == "string"
          v[:range] = []
        elsif v[:class] == "integer"
          unless v[:default].nil?
            val = Integer(v[:default], exception: false)
            v[:default] = val unless val.nil?
          end

          v[:variants] = []
          v[:range   ] = v[:range][0..1] if v[:range].size > 2

          rg = []

          v[:range].each do |rang|
            val = Integer(rang, exception: false)
            rg << val unless val.nil?
          end

          v[:range] = rg

          if v[:range].size == 1
            first = v[:range].first
            v[:default] = [v[:default], first].min unless v[:default].nil?
          elsif v[:range].size == 2
            first = v[:range].first
            last  = v[:range].last
            v[:default] = v[:default].clamp(first, last) unless v[:default].nil?
          end
        elsif v[:class] == "float"
          unless v[:default].nil?
            val = Float(v[:default], exception: false)
            v[:default] = val unless val.nil?
          end

          v[:variants] = []
          v[:range   ] = v[:range][0..1] if v[:range].size > 2

          rg = []

          v[:range].each do |rang|
            val = Float(rang, exception: false)
            rg << val unless val.nil?
          end

          v[:range] = rg

          if v[:range].size == 1
            first = v[:range].first
            v[:default] = [v[:default], first].min unless v[:default].nil?
          elsif v[:range].size == 2
            first = v[:range].first
            last  = v[:range].last
            v[:default] = v[:default].clamp(first, last) unless v[:default].nil?
          end
        end
      end

      # Prep more consise argument hash.
      @@data[:param].each { |k,v| @@data[:argh][k] = v[:default].freeze }

      # Freeze attributes on file.
      @@data[:param].values.each do |v|
        v[:default ].freeze
        v[:class   ].freeze
        v[:variants].freeze
        v[:range   ].freeze
        v[:comment ].freeze
      end
    end

    ##
    # Validates whether a parameter is indeed defaulted, and stored on file.
    #
    # @param parameter [#to_sym] a potential BTAP/NECB parameter
    #
    # @return [Boolean] whether a paremeter is indeed BTAP/NECB defaulted
    def defaulted?(parameter = nil)
      return false unless parameter.respond_to?(:to_sym)

      parameter = parameter.to_sym

      @@data[:param].include?(parameter)
    end

    ##
    # Returns the assigned default value for a BTAP/NECB core parameter.
    #
    # @param parameter [#to_sym] BTAP/NECB core parameter
    #
    # @return [] the assigned default value on file (nil if invalid or missing)
    def default(parameter = nil)
      return nil unless parameter.respond_to?(:to_sym)

      parameter = parameter.to_sym
      return nil unless @@data[:param].include?(parameter)

      @@data[:param][parameter][:default]
    end

    ##
    # Validates whether a parameter variant is admissible.
    #
    # @param parameter [#to_sym] BTAP/NECB core parameter
    # @param variant [#to_sym] potential variant
    #
    # @return [Boolean] true if admissible (false if missing or invalid)
    def admissible?(parameter = nil, variant = nil)
      return false unless variant.respond_to?(:to_s)
      return false     if variant.to_s.empty?
      return false unless parameter.respond_to?(:to_sym)

      parameter = parameter.to_sym
      return false unless @@data[:param].include?(parameter)

      classe   = @@data[:param][parameter][:class]
      default  = @@data[:param][parameter][:default]
      variants = @@data[:param][parameter][:variants]
      range    = @@data[:param][parameter][:range]

      if classe == "boolean"
        return variant == false if default == true
        return variant == true  if default == false
      elsif classe == "string"
        return false unless variant.respond_to?(:to_sym)

        variants.each do |var|
          return true if var.downcase == variant.to_s.downcase
        end

        return false
      end

      if ["integer", "float"].include?(classe)
        return false unless variant.is_a?(Numeric)

        range = range
        return false if variant < range.first
        return false if variant > range.last && range.size == 2
      end

      true
    end

    ##
    # Validates whether a parameter is voided. Any of the following are
    # considered voided: parameter is nilled, false, empty, "void" or "none".
    #
    # @param parameter [#to_sym] any parameter
    #
    # @return [Boolean] whether a parameter is considered voided
    def voided?(parameter = nil)
      return true     if parameter.nil?
      return true     if parameter == false
      return true     if parameter.respond_to?(:empty?) && parameter.empty?
      return true unless parameter.respond_to?(:to_s)
      return true     if parameter.to_s.downcase == "void"
      return true     if parameter.to_s.downcase == "none"

      false
    end

    ##
    # Returns Defaulted parameters.
    #
    # @return [Hash] Default data
    def data
      @@data
    end

    def self.extended(base)
      base.send(:include, self)
    end
  end

  class Defaults
    extend DefaultData

    # Complete BTAP/NECB default parameters and attributes
    attr_reader :param

    # Concise BTAP/NECB core arguments.
    attr_accessor :argh

    ##
    # Initialize BTAP Default parameters.
    #
    # @param model [OpenStudio::Model::Model] a model
    def initialize
      mth = "BTAP::Defaults::#{__callee__}"

      @param = data[:param]
      @argh  = data[:argh]
    end
  end
end

# dfts = BTAP::Defaults.new
#
# puts
# puts dfts.param[:nv_opening_fraction][:default].nil?      # true
# puts dfts.param[:nv_opening_fraction][:class]             # float
# puts dfts.param[:nv_opening_fraction][:variants].empty?   # true
# puts dfts.param[:nv_opening_fraction][:range].class       # Array
# puts dfts.param[:nv_opening_fraction][:range].size        # 2
# puts dfts.param[:nv_opening_fraction][:range].first.class # Float
# puts dfts.param[:nv_opening_fraction][:range].last.class  # Float
# puts dfts.param[:nv_opening_fraction][:range].first       # 0.0
# puts dfts.param[:nv_opening_fraction][:range].last        # 1.0
# puts dfts.param[:nv_opening_fraction][:comment].empty?    # true
#
# puts
# puts dfts.param[:npv_end_year][:default].class            # Integer
# puts dfts.param[:npv_end_year][:default]                  # 2041
# puts dfts.default("npv_end_year")                         # 2041
# puts dfts.default(:npv_end_year)                          # 2041
# puts dfts.param[:npv_end_year][:variants].empty?          # true
# puts dfts.param[:npv_end_year][:range].class              # Array
# puts dfts.param[:npv_end_year][:range].empty?             # true
# puts dfts.param[:npv_end_year][:comment].empty?           # true
#
# puts
# puts dfts.admissible?(:chiller_type, "Rotary Screw")      # true
# puts dfts.admissible?(:chiller_type, "Heat Pump")         # false
# puts dfts.admissible?(:nv_opening_fraction,0)             # true
# puts dfts.admissible?(:nv_opening_fraction,1)             # true
# puts dfts.admissible?(:nv_opening_fraction,-1)            # false
# puts dfts.admissible?(:nv_opening_fraction,10)            # false
#
# puts
# puts dfts.voided?(nil)                                    # true
# puts dfts.voided?(false)                                  # true
# puts dfts.voided?(true)                                   # false
# puts dfts.voided?("")                                     # true
# puts dfts.voided?([])                                     # true
# puts dfts.voided?({})                                     # true
# puts dfts.voided?("void")                                 # true
# puts dfts.voided?("none")                                 # true
#
# puts
# dfts.argh.each do |k,v|
#   puts "#{k}: #{v}" unless v.nil?
#   puts "#{k}: nil"      if v.nil?
# end
#
# puts
# puts "done!"

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- #
# NOTES:
#
# A handful of parameters are unsued, mispelled (i.e. not caught), etc., e.g.:
#
#   analysis_name,test_analysis_para,string,,deprecated?
#   compute_environment,local,string,,deprecated?
#
# ... are specified in both:
#     - utilities/btap_cli/tests/run_options.yml
#     - utilities/btap_cli/tests/run_options_local_osm.yml
#
# ... yet never used in BTAP/NECB.
#
# Another example (necb_2011.rb):
#
#   def model_enable_demand_controlled_ventilation(model, dcv_type = 'No_DCV')
#     return if dcv_type == 'NECB_Defualt'
#
# The intention is to clearly bail out of the method if set to NECB_Default, yet
# the exit condition is ignored given the typo. Luckily, the subsequent sections
# of the same method appear sufficiently robust to handle the typo, but that's
# something to fix (@todo).
#
# BTAP/NECB documentation also suggests the following admissible VARIANTS:
#   - No_DCV
#   - No DCV
#   - Occupancy_based_DCV
#   - Occupancy-based DCV
#   - CO2_based_DCV
#   - CO2-based DCV
#
# For instance, in unit test 'test_daylighting_sensor_control.rb':
#
#   @dcv_types = ['No DCV']
#
# ... is likely inactive ?!
