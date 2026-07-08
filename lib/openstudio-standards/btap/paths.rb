# BTAP Paths
#
# File paths related to the common resources folder.

module BTAP
  module Paths
    class << self

      # Costing paths are mutable in the `BTAP::Costing` constructor.
      attr_accessor :costs_path
      attr_accessor :costs_local_factors_path
    end
    resources                 = Pathname(__dir__) / "common_resources"
    @costs_path               = resources / "costs.csv"
    @costs_local_factors_path = resources / "costs_local_factors.csv"

    COSTING_DATA_PATHS = [
      resources / "locations.csv",
      resources / "materials_opaque.csv",
      resources / "materials_glazing.csv",
      resources / "lighting_sets.csv",
      resources / "lighting.csv",
      resources / "materials_lighting.csv",
      resources / "hvac_vent_ahu.csv",
      resources / "materials_hvac.csv"
    ]

    CONSTRUCTIONS_PATH       = resources / "constructions.json"
    CARBON_OPAQUE_PATH       = resources / "carbon_opaque.csv"
    CARBON_GLAZING_PATH      = resources / "carbon_glazing.csv"
    CARBON_FRAME_PATH        = resources / "carbon_frame.csv"
    THERMAL_BRIDGING_PATH    = resources / "thermal_bridging.csv"
    MECH_SIZING_PATH         = resources / "mech_sizing.json"
    NECB_BUILDING_TYPES_PATH = resources / "necb_building_types.csv"
    NECB_SPACE_TYPES_PATH    = resources / "necb_space_types.csv"
  end
end
