# frozen_string_literal: true

# Shared 179D -> PRM-2019 building-type categories for the baseline generator.
# Values must match the openstudio-standards PRM data tables exactly.
module ACM179dPRM2019BuildingTypeMap
  BUILDING_TYPE_MAP = {
    'MidriseApartment' => {
      hvac_building_type: 'residential',
      wwr_building_type: 'All others',
      swh_building_type: 'Multifamily',
      expected_baseline_system_type: { warm: 'PTHP', other: 'PTAC' },
    },
    'HighriseApartment' => {
      hvac_building_type: 'residential',
      wwr_building_type: 'All others',
      swh_building_type: 'Multifamily',
      expected_baseline_system_type: { warm: 'PTHP', other: 'PTAC' },
    },
    'SmallHotel' => {
      hvac_building_type: 'residential',
      wwr_building_type: 'Hotel/motel <= 75 rooms',
      swh_building_type: 'Motel',
      expected_baseline_system_type: { warm: 'PTHP', other: 'PTAC' },
    },
    'LargeHotel' => {
      hvac_building_type: 'residential',
      wwr_building_type: 'Hotel/motel > 75 rooms',
      swh_building_type: 'Hotel',
      expected_baseline_system_type: { warm: 'PTHP', other: 'PTAC' },
    },
    'SmallOffice' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Office <= 5,000 sq ft',
      swh_building_type: 'Office',
      expected_baseline_system_type: { warm: 'PSZ_HP', other: 'PSZ_AC' },
    },
    'MediumOffice' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Office 5,000 to 50,000 sq ft',
      swh_building_type: 'Office',
      expected_baseline_system_type: { warm: 'PVAV_PFP_Boxes', other: 'PVAV_Reheat' },
    },
    'LargeOffice' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Office > 50,000 sq ft',
      swh_building_type: 'Office',
      expected_baseline_system_type: { warm: 'VAV_PFP_Boxes', other: 'VAV_Reheat' },
    },
    'PrimarySchool' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'School (primary)',
      swh_building_type: 'School/university',
      expected_baseline_system_type: { warm: 'PVAV_PFP_Boxes', other: 'PVAV_Reheat' },
    },
    'SecondarySchool' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'School (secondary and university)',
      swh_building_type: 'School/university',
      expected_baseline_system_type: { warm: 'VAV_PFP_Boxes', other: 'VAV_Reheat' },
    },
    'RetailStandalone' => {
      hvac_building_type: 'retail',
      wwr_building_type: 'Retail (stand alone)',
      swh_building_type: 'Retail',
      expected_baseline_system_type: { warm: 'PSZ_HP', other: 'PSZ_AC' },
    },
    'RetailStripmall' => {
      hvac_building_type: 'retail',
      wwr_building_type: 'Retail (strip mall)',
      swh_building_type: 'Retail',
      expected_baseline_system_type: { warm: 'PSZ_HP', other: 'PSZ_AC' },
    },
    'QuickServiceRestaurant' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Restaurant (quick service)',
      swh_building_type: 'Dining: Cafeteria/fast food',
      expected_baseline_system_type: { warm: 'PSZ_HP', other: 'PSZ_AC' },
    },
    'FullServiceRestaurant' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Restaurant (full service)',
      swh_building_type: 'Dining: Family',
      expected_baseline_system_type: { warm: 'PSZ_HP', other: 'PSZ_AC' },
    },
    'Warehouse' => {
      # 'other nonresidential' (not 'heated-only storage'): gives the conditioned
      # office a cooled baseline while storage stays heated-only.
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Warehouse (nonrefrigerated)',
      swh_building_type: 'Warehouse',
      expected_baseline_system_type: { warm: 'Electric_Furnace', other: 'Gas_Furnace' },
    },
    'Hospital' => {
      hvac_building_type: 'hospital',
      wwr_building_type: 'Hospital',
      swh_building_type: 'Hospital and outpatient surgery center',
      expected_baseline_system_type: { warm: 'VAV_Reheat', other: 'VAV_Reheat' },
    },
    'Outpatient' => {
      hvac_building_type: 'other nonresidential',
      wwr_building_type: 'Healthcare (outpatient)',
      swh_building_type: 'Health-care clinic',
      expected_baseline_system_type: { warm: 'PVAV_PFP_Boxes', other: 'PVAV_Reheat' },
    },
  }.freeze

  def self.lookup(building_type)
    row = BUILDING_TYPE_MAP[building_type]
    return row if row

    raise ArgumentError, "No PRM-2019 building-type mapping for '#{building_type}'. Add it to ACM179dPRM2019BuildingTypeMap::BUILDING_TYPE_MAP."
  end
end
