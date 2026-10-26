require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_necb_prototype_helper'

class TestNECBBldgCIMatrix < CreateNECBPrototypeBuildingTest
  building_types = [
    'FullServiceRestaurant',
    'HighriseApartment',
    'LargeHotel',
    'LargeOffice',
    'MediumOffice',
    'MidriseApartment',
    'PrimarySchool',
    'QuickServiceRestaurant',
    'RetailStandalone',
    'SecondarySchool',
    'SmallHotel',
    'Warehouse'
  ]

  hp_fuels = [
    'Electricity',
    'ElectricityHPElecBackup',
    'ElectricityHPGasBackupMixed',
    'NaturalGas',
    'NaturalGasHPElecBackupMixed',
    'NaturalGasHPGasBackup'
  ]

  # Combinatorial tests for NECB2017, NECB2020
  TestNECBBldgCIMatrix.create_run_model_tests(
    building_type:        building_types,
    template:             ['NECB2017', 'NECB2020'],
    primary_heating_fuel: hp_fuels,
    epw_file:             ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'],
    run_simulation:       [false]
  )

  # Combinatorial tests for BTAP1980TO2010
  TestNECBBldgCIMatrix.create_run_model_tests(
    building_type:        building_types,
    template:             ['BTAP1980TO2010'],
    primary_heating_fuel: ['Electricity', 'NaturalGas'],
    epw_file:             ['CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'],
    run_simulation:       [false]
  )
end
