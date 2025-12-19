require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'

class TestDOEPrototypesRegression < CreateDOEPrototypeBuildingTest
   @building_types = [
     'SmallOffice',
     'MediumOffice',
     # 'LargeOffice',
     'RetailStandalone',
     'RetailStripmall',
     'PrimarySchool',
     'SecondarySchool',
     'Outpatient',
     'Hospital',
     'SmallHotel',
     'LargeHotel',
     'QuickServiceRestaurant',
     'FullServiceRestaurant',
     'MidriseApartment',
     'HighriseApartment',
     'Warehouse']
   @climate_zones = [
#     'ASHRAE 169-2013-1A',
#     'ASHRAE 169-2013-1B',
#     'ASHRAE 169-2013-2A',
#     'ASHRAE 169-2013-2B',
#     'ASHRAE 169-2013-3A',
#     'ASHRAE 169-2013-3B',
#     'ASHRAE 169-2013-3C',
     'ASHRAE 169-2013-4A']#,
#     'ASHRAE 169-2013-4B',
#     'ASHRAE 169-2013-4C',
#     'ASHRAE 169-2013-5A',
#     'ASHRAE 169-2013-5B',
#     'ASHRAE 169-2013-5C',
#     'ASHRAE 169-2013-6A',
#     'ASHRAE 169-2013-6B',
#     'ASHRAE 169-2013-7A',
#     'ASHRAE 169-2013-7B',
#     'ASHRAE 169-2013-8A',
#     'ASHRAE 169-2013-8B']
   @templates = [
     '90.1-2004',
    #  '90.1-2007',
    #  '90.1-2010',
     '90.1-2013',
     '90.1-2016',
     '90.1-2019'
    ]

  all_comp =  @building_types.product @templates, @climate_zones
  all_comp.sort.each do |building_type, template, climate_zone|
    result, msg = TestDOEPrototypesRegression.create_building(building_type, template, climate_zone, nil, true, false, false, false, 'annual', true, 'regression-')
  end
end
