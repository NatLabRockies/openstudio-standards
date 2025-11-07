require 'singleton'

class CommonPaths
  include Singleton

  # Raw data
  attr_reader :raw_paths

  attr_reader :locations_path
  attr_reader :construction_sets_path
  attr_reader :constructions_opaque_path
  attr_reader :materials_opaque_path
  attr_reader :constructions_glazing_path
  attr_reader :materials_glazing_path
  attr_reader :constructions_path
  attr_reader :construction_properties_path
  attr_reader :lighting_sets_path
  attr_reader :lighting_path
  attr_reader :materials_lighting_path
  attr_reader :hvac_vent_ahu_path
  attr_reader :materials_hvac_path

  # Costing data
  attr_accessor :costs_path
  attr_accessor :costs_local_factors_path

  # Embodied carbon data
  attr_reader :carbon_opaque_path
  attr_reader :carbon_glazing_path
  attr_reader :carbon_frame_path

  # Thermal bridging data
  attr_reader :thermal_bridging_path

  # Other
  attr_reader :error_log
  attr_reader :cost_output_file
  attr_reader :mech_sizing_data_file

  def initialize
    dir_database                  = "#{__dir__}/common_resources"

    @locations_path               = "#{dir_database}/locations.csv"
    @construction_sets_path       = "#{dir_database}/construction_sets.csv"
    @constructions_opaque_path    = "#{dir_database}/constructions_opaque.csv"
    @materials_opaque_path        = "#{dir_database}/materials_opaque.csv"
    @constructions_glazing_path   = "#{dir_database}/constructions_glazing.csv"
    @materials_glazing_path       = "#{dir_database}/materials_glazing.csv"
    @constructions_path           = "#{dir_database}/Constructions.csv"
    @construction_properties_path = "#{dir_database}/ConstructionProperties.csv"
    @lighting_sets_path           = "#{dir_database}/lighting_sets.csv"
    @lighting_path                = "#{dir_database}/lighting.csv"
    @materials_lighting_path      = "#{dir_database}/materials_lighting.csv"
    @hvac_vent_ahu_path           = "#{dir_database}/hvac_vent_ahu.csv"
    @materials_hvac_path          = "#{dir_database}/materials_hvac.csv"

    @raw_paths = [
      @locations_path,
      @construction_sets_path,
      @constructions_opaque_path,
      @materials_opaque_path,
      @constructions_glazing_path,
      @materials_glazing_path,
      @constructions_path,
      @construction_properties_path,
      @lighting_sets_path,
      @lighting_path,
      @materials_lighting_path,
      @hvac_vent_ahu_path,
      @materials_hvac_path
    ]

    @costs_path               = "#{dir_database}/costs.csv"
    @costs_local_factors_path = "#{dir_database}/costs_local_factors.csv"

    @carbon_opaque_path  = "#{dir_database}/carbon_opaque.csv"
    @carbon_glazing_path = "#{dir_database}/carbon_glazing.csv"
    @carbon_frame_path   = "#{dir_database}/carbon_frame.csv"

    @thermal_bridging_path = "#{__dir__}/../../../data/inventory/thermal_bridging.csv"
    
    @error_log             = "#{__dir__}/errors.json"
    @cost_output_file      = "#{__dir__}/cost_output.json"
    @mech_sizing_data_file = "#{__dir__}/costing/mech_sizing.json"
  end
end
