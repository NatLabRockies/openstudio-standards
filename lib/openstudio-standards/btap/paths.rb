# BTAP Paths
#
# File paths related to the common folder.

module BTAP
  module Paths
    class << self

      # Costing paths are mutable in the `BTAP::Costing` constructor.
      attr_accessor :costs_path
      attr_accessor :costs_local_factors_path
    end
    btap_common               = Pathname(__dir__) / "common"
    necb_common               = Pathname(__dir__) / "common"
    @costs_path               = btap_common / "costs.csv"
    @costs_local_factors_path = btap_common / "costs_local_factors.csv"

    COSTING_DATA_PATHS = [
      btap_common / "locations.csv",
      btap_common / "materials_opaque.csv",
      btap_common / "materials_glazing.csv",
      btap_common / "lighting_sets.csv",
      btap_common / "lighting.csv",
      btap_common / "materials_lighting.csv",
      btap_common / "hvac_vent_ahu.csv",
      btap_common / "materials_hvac.csv"
    ]

    CONSTRUCTIONS_PATH        = btap_common / "constructions.json"
    CARBON_OPAQUE_PATH        = btap_common / "carbon_opaque.csv"
    CARBON_GLAZING_PATH       = btap_common / "carbon_glazing.csv"
    CARBON_FRAME_PATH         = btap_common / "carbon_frame.csv"
    THERMAL_BRIDGING_PATH     = btap_common / "thermal_bridging.csv"
    MECH_SIZING_PATH          = btap_common / "mech_sizing.json"
    NECB_BUILDING_TYPES_PATH  = btap_common / "necb_building_types.csv"
    NECB_SPACE_TYPES_PATH     = btap_common / "necb_space_types.csv"
    NEB_PRICES_PATH           = btap_common / "neb_end_use_prices.csv"

    # (Retrieved March 11, 2025)
    # ECCC's emissions factors for the current and future years for GHG "without
    # Biomass and RNG CO2 emissions":
    # https://data-donnees.az.ec.gc.ca/data/substances/monitor/canada-s-greenhouse-gas-emissions-projections/Current-Projections-Actuelles/Energy-Energie/AM%20Scenario%20AMS/Grid-O%26G-Intensities-Intensites-Reseau-Delectricite-P%26G?lang=en
    ECCC_GHG_ELECTRICITY_PATH = necb_common / "eccc_electric_grid_intensity_20250311.csv"
  end
end
