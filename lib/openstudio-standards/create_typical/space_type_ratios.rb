module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # A lookup for space type ratios for typical building types

    # create hash of space types and generic ratios of building floor area.
    # some building type and template combination are incompatible
    #
    # @param building_type [String] standard building type
    # @param building_subtype [String] building subtype for large offices or warehouses
    # @param template [String] standard template
    # @param whole_building [Boolean] use a whole building space type for Office types
    # @return [Hash] hash of space types
    # @todo this method will be replaced with space type specific edits
    # @todo enable each building type and template combination
    def self.get_space_types_from_building_type(building_type,
                                                building_subtype: nil,
                                                template: nil,
                                                whole_building: true)
      hash = {}

      # DOE Prototypes
      case building_type
      when 'SecondarySchool'
        if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
          hash['Auditorium'] = { ratio: 0.0504, space_type_gen: true, default: false, story_height: 26.0 }
          hash['Cafeteria'] = { ratio: 0.0319, space_type_gen: true, default: false }
          hash['Classroom'] = { ratio: 0.3528, space_type_gen: true, default: true }
          hash['Corridor'] = { ratio: 0.2144, space_type_gen: true, default: false, circ: true }
          hash['Gym'] = { ratio: 0.1009, space_type_gen: true, default: false, story_height: 26.0 }
          hash['Gym - audience'] = { ratio: 0.0637, space_type_gen: true, default: false, story_height: 26.0 }
          hash['Kitchen'] = { ratio: 0.0110, space_type_gen: true, default: false }
          hash['Library'] = { ratio: 0.0429, space_type_gen: true, default: false }
          hash['Lobby'] = { ratio: 0.0214, space_type_gen: true, default: false }
          hash['Mechanical'] = { ratio: 0.0349, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0543, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.0214, space_type_gen: true, default: false }
        else
          hash['Auditorium'] = { ratio: 0.0504, space_type_gen: true, default: false, story_height: 26.0 }
          hash['Cafeteria'] = { ratio: 0.0319, space_type_gen: true, default: false }
          hash['Classroom'] = { ratio: 0.3041, space_type_gen: true, default: true }
          hash['ComputerRoom'] = { ratio: 0.0487, space_type_gen: true, default: true }
          hash['Corridor'] = { ratio: 0.2144, space_type_gen: true, default: false, circ: true }
          hash['Gym'] = { ratio: 0.1646, space_type_gen: true, default: false, story_height: 26.0 }
          hash['Kitchen'] = { ratio: 0.0110, space_type_gen: true, default: false }
          hash['Library'] = { ratio: 0.0429, space_type_gen: true, default: false }
          hash['Lobby'] = { ratio: 0.0214, space_type_gen: true, default: false }
          hash['Mechanical'] = { ratio: 0.0349, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0543, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.0214, space_type_gen: true, default: false }
        end
      when 'PrimarySchool'
        if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
          # updated to 2004 which includes library vs. pre-1980
          hash['Cafeteria'] = { ratio: 0.0458, space_type_gen: true, default: false }
          hash['Classroom'] = { ratio: 0.5610, space_type_gen: true, default: true }
          hash['Corridor'] = { ratio: 0.1633, space_type_gen: true, default: false, circ: true }
          hash['Gym'] = { ratio: 0.0520, space_type_gen: true, default: false }
          hash['Kitchen'] = { ratio: 0.0244, space_type_gen: true, default: false }
          hash['Library'] = { ratio: 0.0, space_type_gen: true, default: false } # no library in model
          hash['Lobby'] = { ratio: 0.0249, space_type_gen: true, default: false }
          hash['Mechanical'] = { ratio: 0.0367, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0642, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.0277, space_type_gen: true, default: false }
        else
          # updated to 2004 which includes library vs. pre-1980
          hash['Cafeteria'] = { ratio: 0.0458, space_type_gen: true, default: false }
          hash['Classroom'] = { ratio: 0.4793, space_type_gen: true, default: true }
          hash['ComputerRoom'] = { ratio: 0.0236, space_type_gen: true, default: true }
          hash['Corridor'] = { ratio: 0.1633, space_type_gen: true, default: false, circ: true }
          hash['Gym'] = { ratio: 0.0520, space_type_gen: true, default: false }
          hash['Kitchen'] = { ratio: 0.0244, space_type_gen: true, default: false }
          hash['Library'] = { ratio: 0.0581, space_type_gen: true, default: false }
          hash['Lobby'] = { ratio: 0.0249, space_type_gen: true, default: false }
          hash['Mechanical'] = { ratio: 0.0367, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0642, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.0277, space_type_gen: true, default: false }
        end
      when 'SmallOffice'
        # @todo populate Small, Medium, and Large office for whole_building false
        if whole_building
          hash['WholeBuilding - Sm Office'] = { ratio: 1.0, space_type_gen: true, default: true }
        else
          hash['SmallOffice - ClosedOffice'] = { ratio: 0.3325, space_type_gen: true, default: false }
          hash['SmallOffice - Conference'] = { ratio: 0.0818, space_type_gen: true, default: false }
          hash['SmallOffice - Corridor'] = { ratio: 0.1213, space_type_gen: true, default: false, circ: true }
          hash['SmallOffice - Elec/MechRoom'] = { ratio: 0.0201, space_type_gen: true, default: false }
          hash['SmallOffice - Lobby'] = { ratio: 0.0818, space_type_gen: true, default: false }
          hash['SmallOffice - OpenOffice'] = { ratio: 0.1659, space_type_gen: true, default: true }
          hash['SmallOffice - Restroom'] = { ratio: 0.0402, space_type_gen: true, default: false }
          hash['SmallOffice - Stair'] = { ratio: 0.0201, space_type_gen: true, default: false }
          hash['SmallOffice - Storage'] = { ratio: 0.1363, space_type_gen: true, default: false }
        end
      when 'MediumOffice'
        if whole_building
          hash['WholeBuilding - Md Office'] = { ratio: 1.0, space_type_gen: true, default: true }
        else
          hash['MediumOffice - Classroom'] = { ratio: 0.0060, space_type_gen: true, default: false }
          hash['MediumOffice - ClosedOffice'] = { ratio: 0.1866, space_type_gen: true, default: false }
          hash['MediumOffice - Conference'] = { ratio: 0.0519, space_type_gen: true, default: false }
          hash['MediumOffice - Corridor'] = { ratio: 0.0896, space_type_gen: true, default: false, circ: true }
          hash['MediumOffice - Dining'] = { ratio: 0.0138, space_type_gen: true, default: false }
          hash['MediumOffice - Elec/MechRoom'] = { ratio: 0.0300, space_type_gen: true, default: false }
          hash['MediumOffice - Lobby'] = { ratio: 0.0550, space_type_gen: true, default: false }
          hash['MediumOffice - OpenOffice'] = { ratio: 0.4255, space_type_gen: true, default: true }
          hash['MediumOffice - Restroom'] = { ratio: 0.0360, space_type_gen: true, default: false }
          hash['MediumOffice - Stair'] = { ratio: 0.0370, space_type_gen: true, default: false }
          hash['MediumOffice - Storage'] = { ratio: 0.0686, space_type_gen: true, default: false }
        end
      when 'LargeOffice'
        case building_subtype
        when 'largeoffice_datacenter'
          hash['WholeBuilding - Lg Office'] = { ratio: 0.9737, space_type_gen: true, default: true }
          hash['OfficeLarge Data Center'] = { ratio: 0.0094, space_type_gen: true, default: false }
          hash['OfficeLarge Main Data Center'] = { ratio: 0.0169, space_type_gen: true, default: false }
        when 'largeoffice_datacenteronly'
          hash['OfficeLarge Data Center'] = { ratio: 1.0, space_type_gen: true, default: false }
        when 'largeoffice_nodatacenter'
          hash['WholeBuilding - Lg Office'] = { ratio: 1.0, space_type_gen: true, default: true }
        else # 'largeoffice_default'
          if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
            if whole_building
              hash['WholeBuilding - Lg Office'] = { ratio: 1.0, space_type_gen: true, default: true }
            else
              hash['BreakRoom'] = { ratio: 0.0178, space_type_gen: true, default: false }
              hash['Classroom'] = { ratio: 0.0040, space_type_gen: true, default: false }
              hash['ClosedOffice'] = { ratio: 0.16, space_type_gen: true, default: false }
              hash['Conference'] = { ratio: 0.0153, space_type_gen: true, default: false }
              hash['Corridor'] = { ratio: 0.0460, space_type_gen: true, default: false, circ: true }
              hash['Dining'] = { ratio: 0.0161, space_type_gen: true, default: false }
              hash['Elec/MechRoom'] = { ratio: 0.0944, space_type_gen: true, default: false }
              hash['Lobby'] = { ratio: 0.0554, space_type_gen: true, default: false }
              hash['OpenOffice'] = { ratio: 0.5230, space_type_gen: true, default: true }
              hash['Restroom'] = { ratio: 0.0310, space_type_gen: true, default: false }
              hash['Stair'] = { ratio: 0.0180, space_type_gen: true, default: false }
              hash['Storage'] = { ratio: 0.0190, space_type_gen: true, default: false }
            end
          else
            if whole_building
              hash['WholeBuilding - Lg Office'] = { ratio: 0.9737, space_type_gen: true, default: true }
              hash['OfficeLarge Data Center'] = { ratio: 0.0094, space_type_gen: true, default: false }
              hash['OfficeLarge Main Data Center'] = { ratio: 0.0169, space_type_gen: true, default: false }
            else
              hash['BreakRoom'] = { ratio: 0.0167, space_type_gen: true, default: false }
              hash['Classroom'] = { ratio: 0.0038, space_type_gen: true, default: false }
              hash['ClosedOffice'] = { ratio: 0.1500, space_type_gen: true, default: false }
              hash['Conference'] = { ratio: 0.0144, space_type_gen: true, default: false }
              hash['Corridor'] = { ratio: 0.0431, space_type_gen: true, default: false, circ: true }
              hash['Dining'] = { ratio: 0.0151, space_type_gen: true, default: false }
              hash['Elec/MechRoom'] = { ratio: 0.0885, space_type_gen: true, default: false }
              hash['Lobby'] = { ratio: 0.0520, space_type_gen: true, default: false }
              hash['OfficeLarge Data Center'] = { ratio: 0.0077, space_type_gen: true, default: false }
              hash['OfficeLarge Main Data Center'] = { ratio: 0.0550, space_type_gen: true, default: false }
              hash['OpenOffice'] = { ratio: 0.4900, space_type_gen: true, default: true }
              hash['Restroom'] = { ratio: 0.0290, space_type_gen: true, default: false }
              hash['Stair'] = { ratio: 0.0169, space_type_gen: true, default: false }
              hash['Storage'] = { ratio: 0.0178, space_type_gen: true, default: false }
            end
          end
        end
      when 'SmallHotel'
        hash['Corridor'] = { ratio: 0.1313, space_type_gen: true, default: false, circ: true }
        hash['Elec/MechRoom'] = { ratio: 0.0038, space_type_gen: true, default: false }
        hash['ElevatorCore'] = { ratio: 0.0113, space_type_gen: true, default: false }
        hash['Exercise'] = { ratio: 0.0081, space_type_gen: true, default: false }
        hash['GuestLounge'] = { ratio: 0.0406, space_type_gen: true, default: false }
        hash['GuestRoom123Occ'] = { ratio: 0.4081, space_type_gen: true, default: true }
        hash['GuestRoom123Vac'] = { ratio: 0.2231, space_type_gen: true, default: false }
        hash['Laundry'] = { ratio: 0.0244, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0081, space_type_gen: true, default: false }
        hash['Meeting'] = { ratio: 0.0200, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0325, space_type_gen: true, default: false }
        hash['PublicRestroom'] = { ratio: 0.0081, space_type_gen: true, default: false }
        hash['StaffLounge'] = { ratio: 0.0081, space_type_gen: true, default: false }
        hash['Stair'] = { ratio: 0.0400, space_type_gen: true, default: false }
        hash['Storage'] = { ratio: 0.0325, space_type_gen: true, default: false }
      when 'LargeHotel'
        hash['Banquet'] = { ratio: 0.0585, space_type_gen: true, default: false }
        hash['Basement'] = { ratio: 0.1744, space_type_gen: false, default: false }
        hash['Cafe'] = { ratio: 0.0166, space_type_gen: true, default: false }
        hash['Corridor'] = { ratio: 0.1736, space_type_gen: true, default: false, circ: true }
        hash['GuestRoom'] = { ratio: 0.4099, space_type_gen: true, default: true }
        hash['Kitchen'] = { ratio: 0.0091, space_type_gen: true, default: false }
        hash['Laundry'] = { ratio: 0.0069, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.1153, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0145, space_type_gen: true, default: false }
        hash['Retail'] = { ratio: 0.0128, space_type_gen: true, default: false }
        hash['Storage'] = { ratio: 0.0084, space_type_gen: true, default: false }
      when 'Warehouse'
        case building_subtype
        when 'warehouse_bulk100'
          hash['Bulk'] = { ratio: 1.0, space_type_gen: true, default: true }
        when 'warehouse_fine100'
          hash['Fine'] = { ratio: 1.0, space_type_gen: true, default: true }
        when 'warehouse_bulk80'
          hash['Bulk'] = { ratio: 0.80, space_type_gen: true, default: true }
          hash['Fine'] = { ratio: 0.151, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0490, space_type_gen: true, default: false, wwr: 0.71, story_height: 14.0 }
        when 'warehouse_bulk40'
          hash['Bulk'] = { ratio: 0.40, space_type_gen: true, default: true }
          hash['Fine'] = { ratio: 0.551, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0490, space_type_gen: true, default: false, wwr: 0.71, story_height: 14.0 }
        when 'warehouse_bulk20'
          hash['Bulk'] = { ratio: 0.20, space_type_gen: true, default: true }
          hash['Fine'] = { ratio: 0.751, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0490, space_type_gen: true, default: false, wwr: 0.71, story_height: 14.0 }
        else # 'warehouse_default'
          hash['Bulk'] = { ratio: 0.6628, space_type_gen: true, default: true }
          hash['Fine'] = { ratio: 0.2882, space_type_gen: true, default: false }
          hash['Office'] = { ratio: 0.0490, space_type_gen: true, default: false, wwr: 0.71, story_height: 14.0 }
        end
      when 'RetailStandalone'
        hash['Back_Space'] = { ratio: 0.1656, space_type_gen: true, default: false }
        hash['Entry'] = { ratio: 0.0052, space_type_gen: true, default: false }
        hash['Point_of_Sale'] = { ratio: 0.0657, space_type_gen: true, default: false }
        hash['Retail'] = { ratio: 0.7635, space_type_gen: true, default: true }
      when 'RetailStripmall'
        hash['Strip mall - type 1'] = { ratio: 0.25, space_type_gen: true, default: false }
        hash['Strip mall - type 2'] = { ratio: 0.25, space_type_gen: true, default: false }
        hash['Strip mall - type 3'] = { ratio: 0.50, space_type_gen: true, default: true }
      when 'QuickServiceRestaurant'
        hash['Dining'] = { ratio: 0.5, space_type_gen: true, default: true }
        hash['Kitchen'] = { ratio: 0.5, space_type_gen: true, default: false }
      when 'FullServiceRestaurant'
        hash['Dining'] = { ratio: 0.7272, space_type_gen: true, default: true }
        hash['Kitchen'] = { ratio: 0.2728, space_type_gen: true, default: false }
      when 'MidriseApartment'
        hash['Apartment'] = { ratio: 0.8727, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.0991, space_type_gen: true, default: false, circ: true }
        hash['Office'] = { ratio: 0.0282, space_type_gen: true, default: false }
      when 'HighriseApartment'
        hash['Apartment'] = { ratio: 0.8896, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.0991, space_type_gen: true, default: false, circ: true }
        hash['Office'] = { ratio: 0.0113, space_type_gen: true, default: false }
      when 'Hospital'
        hash['Basement'] = { ratio: 0.1667, space_type_gen: false, default: false }
        hash['Corridor'] = { ratio: 0.1741, space_type_gen: true, default: false, circ: true }
        hash['Dining'] = { ratio: 0.0311, space_type_gen: true, default: false }
        hash['ER_Exam'] = { ratio: 0.0099, space_type_gen: true, default: false }
        hash['ER_NurseStn'] = { ratio: 0.0551, space_type_gen: true, default: false }
        hash['ER_Trauma'] = { ratio: 0.0025, space_type_gen: true, default: false }
        hash['ER_Triage'] = { ratio: 0.0050, space_type_gen: true, default: false }
        hash['ICU_NurseStn'] = { ratio: 0.0298, space_type_gen: true, default: false }
        hash['ICU_Open'] = { ratio: 0.0275, space_type_gen: true, default: false }
        hash['ICU_PatRm'] = { ratio: 0.0115, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0414, space_type_gen: true, default: false }
        hash['Lab'] = { ratio: 0.0236, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.0657, space_type_gen: true, default: false }
        hash['NurseStn'] = { ratio: 0.1723, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0286, space_type_gen: true, default: false }
        hash['OR'] = { ratio: 0.0273, space_type_gen: true, default: false }
        hash['PatCorridor'] = { ratio: 0.0, space_type_gen: true, default: false } # not in prototype
        hash['PatRoom'] = { ratio: 0.0845, space_type_gen: true, default: true }
        hash['PhysTherapy'] = { ratio: 0.0217, space_type_gen: true, default: false }
        hash['Radiology'] = { ratio: 0.0217, space_type_gen: true, default: false }
      when 'Outpatient'
        hash['Anesthesia'] = { ratio: 0.0026, space_type_gen: true, default: false }
        hash['BioHazard'] = { ratio: 0.0014, space_type_gen: true, default: false }
        hash['Cafe'] = { ratio: 0.0103, space_type_gen: true, default: false }
        hash['CleanWork'] = { ratio: 0.0071, space_type_gen: true, default: false }
        hash['Conference'] = { ratio: 0.0082, space_type_gen: true, default: false }
        hash['DressingRoom'] = { ratio: 0.0021, space_type_gen: true, default: false }
        hash['Elec/MechRoom'] = { ratio: 0.0109, space_type_gen: true, default: false }
        hash['ElevatorPumpRoom'] = { ratio: 0.0022, space_type_gen: true, default: false }
        hash['Exam'] = { ratio: 0.1029, space_type_gen: true, default: true }
        hash['Hall'] = { ratio: 0.1924, space_type_gen: true, default: false, circ: true }
        hash['IT_Room'] = { ratio: 0.0027, space_type_gen: true, default: false }
        hash['Janitor'] = { ratio: 0.0672, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.0152, space_type_gen: true, default: false }
        hash['LockerRoom'] = { ratio: 0.0190, space_type_gen: true, default: false }
        hash['Lounge'] = { ratio: 0.0293, space_type_gen: true, default: false }
        hash['MedGas'] = { ratio: 0.0014, space_type_gen: true, default: false }
        hash['MRI'] = { ratio: 0.0107, space_type_gen: true, default: false }
        hash['MRI_Control'] = { ratio: 0.0041, space_type_gen: true, default: false }
        hash['NurseStation'] = { ratio: 0.0189, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.1828, space_type_gen: true, default: false }
        hash['OR'] = { ratio: 0.0346, space_type_gen: true, default: false }
        hash['PACU'] = { ratio: 0.0232, space_type_gen: true, default: false }
        hash['PhysicalTherapy'] = { ratio: 0.0462, space_type_gen: true, default: false }
        hash['PreOp'] = { ratio: 0.0129, space_type_gen: true, default: false }
        hash['ProcedureRoom'] = { ratio: 0.0070, space_type_gen: true, default: false }
        hash['Reception'] = { ratio: 0.0365, space_type_gen: true, default: false }
        hash['Soil Work'] = { ratio: 0.0088, space_type_gen: true, default: false }
        hash['Stair'] = { ratio: 0.0146, space_type_gen: true, default: false }
        hash['Toilet'] = { ratio: 0.0193, space_type_gen: true, default: false }
        hash['Undeveloped'] = { ratio: 0.0835, space_type_gen: false, default: false }
        hash['Xray'] = { ratio: 0.0220, space_type_gen: true, default: false }
      when 'SuperMarket', 'GroceryStore'
        hash['Bakery'] = { ratio: 0.05, space_type_gen: true, default: false }
        hash['Deli'] = { ratio: 0.0537, space_type_gen: true, default: false }
        hash['DryStorage'] = { ratio: 0.1010, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0067, space_type_gen: true, default: false }
        hash['Produce'] = { ratio: 0.1701, space_type_gen: true, default: true }
        hash['Sales'] = { ratio: 0.5495, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.0118, space_type_gen: true, default: true }
        hash['Dining'] = { ratio: 0.0111, space_type_gen: true, default: true }
        hash['Elec/MechRoom'] = { ratio: 0.0133, space_type_gen: true, default: true }
        hash['Meeting'] = { ratio: 0.0111, space_type_gen: true, default: true }
        hash['Restroom'] = { ratio: 0.0150, space_type_gen: true, default: true }
        hash['Vestibule'] = { ratio: 0.0067, space_type_gen: true, default: true }
      when 'Laboratory'
        hash['Office'] = { ratio: 0.50, space_type_gen: true, default: true }
        hash['Open lab'] = { ratio: 0.35, space_type_gen: true, default: true }
        hash['Equipment corridor'] = { ratio: 0.05, space_type_gen: true, default: true }
        hash['Lab with fume hood'] = { ratio: 0.10, space_type_gen: true, default: true }
      when 'LargeDataCenterHighITE', 'LargeDataCenterLowITE'
        hash['StandaloneDataCenter'] = { ratio: 1.0, space_type_gen: true, default: true }
      when 'SmallDataCenterHighITE', 'SmallDataCenterLowITE'
        hash['ComputerRoom'] = { ratio: 1.0, space_type_gen: true, default: true }
      when 'Courthouse'
        hash['Break Room'] = { ratio: 0.0067, space_type_gen: true, default: false }
        hash['Cell'] = { ratio: 0.0731, space_type_gen: true, default: false }
        hash['Conference'] = { ratio: 0.0203, space_type_gen: true, default: false }
        hash['Corridor'] = { ratio: 0.0829, space_type_gen: true, default: false }
        hash['Courtroom'] = { ratio: 0.1137, space_type_gen: true, default: false }
        hash['Courtroom Waiting'] = { ratio: 0.051, space_type_gen: true, default: false }
        hash['Elevator Lobby'] = { ratio: 0.0085, space_type_gen: true, default: false }
        hash['Elevator Shaft'] = { ratio: 0.0047, space_type_gen: true, default: false }
        hash['Entrance Lobby'] = { ratio: 0.0299, space_type_gen: true, default: false }
        hash['Judges Chamber'] = { ratio: 0.0261, space_type_gen: true, default: false }
        hash['Jury Assembly'] = { ratio: 0.0355, space_type_gen: true, default: false }
        hash['Jury Deliberation'] = { ratio: 0.0133, space_type_gen: true, default: false }
        hash['Library'] = { ratio: 0.0302, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.1930, space_type_gen: true, default: true }
        hash['Parking'] = { ratio: 0.1083, space_type_gen: true, default: false }
        hash['Restrooms'] = { ratio: 0.04, space_type_gen: true, default: false }
        hash['Security Screening'] = { ratio: 0.0132, space_type_gen: true, default: false }
        hash['Service Shaft'] = { ratio: 0.0019, space_type_gen: true, default: false }
        hash['Stairs'] = { ratio: 0.0111, space_type_gen: true, default: false }
        hash['Storage'] = { ratio: 0.0882, space_type_gen: true, default: false }
        hash['Utility'] = { ratio: 0.0484, space_type_gen: true, default: false }
      when 'College'
        hash['Art Classroom'] = { ratio: 0.1868, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.2348, space_type_gen: true, default: true }
        hash['Conference'] = { ratio: 0.0215, space_type_gen: true, default: false }
        hash['Corridor'] = { ratio: 0.0716, space_type_gen: true, default: false }
        hash['Elevator Shaft'] = { ratio: 0.0074, space_type_gen: true, default: false }
        hash['Entrance Lobby'] = { ratio: 0.0117, space_type_gen: true, default: false }
        hash['Laboratory'] = { ratio: 0.0843, space_type_gen: true, default: false }
        hash['Lecture Hall'] = { ratio: 0.0421, space_type_gen: true, default: false }
        hash['Lounge'] = { ratio: 0.028, space_type_gen: true, default: false }
        hash['Media Center'] = { ratio: 0.0421, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.1894, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0363, space_type_gen: true, default: false }
        hash['Stairs'] = { ratio: 0.0272, space_type_gen: true, default: false }
        hash['Storage'] = { ratio: 0.0117, space_type_gen: true, default: false }
        hash['Utility'] = { ratio: 0.0051, space_type_gen: true, default: false }

      # DEER Prototypes
      when 'Asm'
        hash['Auditorium'] = { ratio: 0.7658, space_type_gen: true, default: true }
        hash['OfficeGeneral'] = { ratio: 0.2342, space_type_gen: true, default: false }
      when 'ECC'
        hash['Classroom'] = { ratio: 0.5558, space_type_gen: true, default: true }
        hash['CompRoomClassRm'] = { ratio: 0.0319, space_type_gen: true, default: false }
        hash['Shop'] = { ratio: 0.1249, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.0876, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0188, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.181, space_type_gen: true, default: false }
      when 'EPr'
        hash['Classroom'] = { ratio: 0.53, space_type_gen: true, default: true }
        hash['CorridorStairway'] = { ratio: 0.1, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.15, space_type_gen: true, default: false }
        hash['Gymnasium'] = { ratio: 0.15, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.07, space_type_gen: true, default: false }
      when 'ERC'
        hash['Classroom'] = { ratio: 0.5, space_type_gen: true, default: true }
      when 'ESe'
        hash['Classroom'] = { ratio: 0.488, space_type_gen: true, default: true }
        hash['CompRoomClassRm'] = { ratio: 0.021, space_type_gen: true, default: false }
        hash['CorridorStairway'] = { ratio: 0.1, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.15, space_type_gen: true, default: false }
        hash['Gymnasium'] = { ratio: 0.15, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.07, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.021, space_type_gen: true, default: true }
      when 'EUn'
        hash['Dining'] = { ratio: 0.0238, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.3056, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.3422, space_type_gen: true, default: true }
        hash['CompRoomClassRm'] = { ratio: 0.038, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0105, space_type_gen: true, default: false }
        hash['CorridorStairway'] = { ratio: 0.03, space_type_gen: true, default: false }
        hash['FacMaint'] = { ratio: 0.08, space_type_gen: true, default: false }
        hash['DormitoryRoom'] = { ratio: 0.1699, space_type_gen: true, default: false }
      when 'Gro'
        hash['GrocSales'] = { ratio: 0.800, space_type_gen: true, default: true }
        hash['OfficeGeneral'] = { ratio: 0.070, space_type_gen: true, default: false }
        hash['RefFoodPrep'] = { ratio: 0.073, space_type_gen: true, default: false }
        hash['IndLoadDock'] = { ratio: 0.057, space_type_gen: true, default: false }
      when 'Hsp'
        hash['HspSurgOutptLab'] = { ratio: 0.2317, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.0172, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0075, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.3636, space_type_gen: true, default: false }
        hash['PatientRoom'] = { ratio: 0.38, space_type_gen: true, default: true }
      when 'Htl'
        hash['Dining'] = { ratio: 0.004, space_type_gen: true, default: false }
        hash['BarCasino'] = { ratio: 0.005, space_type_gen: true, default: false }
        hash['HotelLobby'] = { ratio: 0.0411, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.0205, space_type_gen: true, default: false }
        hash['GuestRmCorrid'] = { ratio: 0.1011, space_type_gen: true, default: false }
        hash['Laundry'] = { ratio: 0.0205, space_type_gen: true, default: false }
        hash['GuestRmOcc'] = { ratio: 0.64224, space_type_gen: true, default: true }
        hash['GuestRmUnOcc'] = { ratio: 0.16056, space_type_gen: true, default: true }
        hash['Kitchen'] = { ratio: 0.005, space_type_gen: true, default: false }
      when 'MBT'
        hash['CompRoomData'] = { ratio: 0.02, space_type_gen: true, default: false }
        hash['Laboratory'] = { ratio: 0.4534, space_type_gen: true, default: true }
        hash['CorridorStairway'] = { ratio: 0.2, space_type_gen: true, default: false }
        hash['Conference'] = { ratio: 0.02, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.03, space_type_gen: true, default: false }
        hash['OfficeOpen'] = { ratio: 0.2666, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.01, space_type_gen: true, default: false }
      when 'MFm'
        hash['ResLiving'] = { ratio: 0.9297, space_type_gen: true, default: true }
        hash['ResPublicArea'] = { ratio: 0.0725, space_type_gen: true, default: false }
      when 'MLI'
        hash['StockRoom'] = { ratio: 0.2, space_type_gen: true, default: false }
        hash['Work'] = { ratio: 0.8, space_type_gen: true, default: true }
      when 'Mtl'
        hash['OfficeGeneral'] = { ratio: 0.02, space_type_gen: true, default: false }
        hash['GuestRmCorrid'] = { ratio: 0.649, space_type_gen: true, default: true }
        hash['Laundry'] = { ratio: 0.016, space_type_gen: true, default: false }
        hash['GuestRmOcc'] = { ratio: 0.25208, space_type_gen: true, default: false }
        hash['GuestRmUnOcc'] = { ratio: 0.06302, space_type_gen: true, default: false }
      when 'Nrs'
        hash['CorridorStairway'] = { ratio: 0.0555, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.105, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.045, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.35, space_type_gen: true, default: false }
        hash['PatientRoom'] = { ratio: 0.4445, space_type_gen: true, default: true }
      when 'OfL'
        hash['LobbyWaiting'] = { ratio: 0.0412, space_type_gen: true, default: false }
        hash['OfficeSmall'] = { ratio: 0.3704, space_type_gen: true, default: false }
        hash['OfficeOpen'] = { ratio: 0.5296, space_type_gen: true, default: true }
        hash['MechElecRoom'] = { ratio: 0.0588, space_type_gen: true, default: false }
      when 'OfS'
        hash['Hall'] = { ratio: 0.3141, space_type_gen: true, default: false }
        hash['OfficeSmall'] = { ratio: 0.6859, space_type_gen: true, default: true }
      when 'RFF'
        hash['Dining'] = { ratio: 0.3997, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.4, space_type_gen: true, default: true }
        hash['LobbyWaiting'] = { ratio: 0.1501, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0501, space_type_gen: true, default: false }
      when 'RSD'
        hash['Restroom'] = { ratio: 0.0357, space_type_gen: true, default: false }
        hash['Dining'] = { ratio: 0.5353, space_type_gen: true, default: true }
        hash['LobbyWaiting'] = { ratio: 0.1429, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.2861, space_type_gen: true, default: false }
      when 'Rt3'
        hash['RetailSales'] = { ratio: 1.0, space_type_gen: true, default: true }
      when 'RtL'
        hash['OfficeGeneral'] = { ratio: 0.0363, space_type_gen: true, default: false }
        hash['Work'] = { ratio: 0.0405, space_type_gen: true, default: false }
        hash['StockRoom'] = { ratio: 0.0920, space_type_gen: true, default: false }
        hash['RetailSales'] = { ratio: 0.8312, space_type_gen: true, default: true }
        # hash['Kitchen'] = { ratio: 0.0113, space_type_gen: true, default: false }
      when 'RtS'
        hash['RetailSales'] = { ratio: 0.8, space_type_gen: true, default: true }
        hash['StockRoom'] = { ratio: 0.2, space_type_gen: true, default: false }
      when 'SCn'
        hash['WarehouseCond'] = { ratio: 0.951, space_type_gen: true, default: true }
        hash['OfficeGeneral'] = { ratio: 0.049, space_type_gen: true, default: false }

      when 'SUn'
        hash['WarehouseUnCond'] = { ratio: 0.951, space_type_gen: true, default: true }
        hash['OfficeGeneral'] = { ratio: 0.049, space_type_gen: true, default: false }

      when 'WRf'
        hash['IndLoadDock'] = { ratio: 0.08, space_type_gen: true, default: false }
        hash['OfficeGeneral'] = { ratio: 0.02, space_type_gen: true, default: false }
        hash['RefStorFreezer'] = { ratio: 0.4005, space_type_gen: true, default: false }
        hash['RefStorCooler'] = { ratio: 0.4995, space_type_gen: true, default: true }
      else
        return false
      end

      return hash
    end
  end
end
