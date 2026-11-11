# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Internal Loads

    # Check the internal loads against a standard
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_internal_loads(category, target_standard, min_pass_pct: 0.2, max_pass_pct: 0.2, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Internal Loads')
      check_elems << OpenStudio::Attribute.new('category', category)
      if target_standard == 'ICC IECC 2015'
        check_elems << OpenStudio::Attribute.new('description', 'Check internal loads against Table R405.5.2(1) in ICC IECC 2015 Residential Provisions.')
      else
        if target_standard.include?('90.1')
          display_standard = "ASHRAE #{target_standard}"
        else
          display_standard = target_standard
        end
        check_elems << OpenStudio::Attribute.new('description', "Check LPD, ventilation rates, occupant density, plug loads, and equipment loads against #{display_standard} and DOE Prototype buildings.")
      end

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        if target_standard == 'ICC IECC 2015'

          num_people = 0.0
          @model.getSpaceTypes.each do |space_type|
            next if !space_type.standardsSpaceType.is_initialized
            next if space_type.standardsSpaceType.get != 'Apartment' # currently only supports midrise apt space type

            space_type_floor_area = space_type.floorArea
            space_type_num_people = space_type.getNumberOfPeople(space_type_floor_area)
            num_people += space_type_num_people
          end

          # lookup iecc internal loads for the building
          bedrooms_per_unit = 2.0 # assumption
          num_units = num_people / 2.5 # Avg 2.5 units per person.
          target_loads_hash = std.model_find_icc_iecc_2015_internal_loads(@model, num_units, bedrooms_per_unit)

          # get model internal gains for lights, elec equipment, and gas equipment
          model_internal_gains_si = 0.0
          query_eleint_lights = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' and TableName='End Uses' and RowName= 'Interior Lighting' and ColumnName= 'Electricity'"
          query_elec_equip = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' and TableName='End Uses' and RowName= 'Interior Equipment' and ColumnName= 'Electricity'"
          query_gas_equip = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' and TableName='End Uses' and RowName= 'Interior Equipment' and ColumnName= 'Natural Gas'"
          model_internal_gains_si += results_elec = @sql.execAndReturnFirstDouble(query_eleint_lights).get
          model_internal_gains_si += results_elec = @sql.execAndReturnFirstDouble(query_elec_equip).get
          model_internal_gains_si += results_elec = @sql.execAndReturnFirstDouble(query_gas_equip).get
          model_internal_gains_si_kbtu_per_day = OpenStudio.convert(model_internal_gains_si, 'GJ', 'kBtu').get / 365.0 # assumes annual run

          # get target internal loads
          target_igain_btu_per_day = target_loads_hash['igain_btu_per_day']
          target_igain_kbtu_per_day = OpenStudio.convert(target_igain_btu_per_day, 'Btu', 'kBtu').get

          # check internal loads
          if model_internal_gains_si_kbtu_per_day < target_igain_kbtu_per_day * (1.0 - min_pass_pct)
            check_elems << OpenStudio::Attribute.new('flag', "The model average of #{OpenStudio.toNeatString(model_internal_gains_si_kbtu_per_day, 2, true)} (kBtu/day) is more than #{min_pass_pct * 100} % below the expected value of #{OpenStudio.toNeatString(target_igain_kbtu_per_day, 2, true)} (kBtu/day) for #{target_standard}.")
          elsif model_internal_gains_si_kbtu_per_day > target_igain_kbtu_per_day * (1.0 + max_pass_pct)
            check_elems << OpenStudio::Attribute.new('flag', "The model average of #{OpenStudio.toNeatString(model_internal_gains_si_kbtu_per_day, 2, true)} (kBtu/day) is more than #{max_pass_pct * 100} % above the expected value of #{OpenStudio.toNeatString(target_igain_kbtu_per_day, 2, true)} k(Btu/day) for #{target_standard}.")
          end

          # get target mech vent
          target_mech_vent_cfm = target_loads_hash['mech_vent_cfm']

          # get model mech vent
          model_mech_vent_si = 0
          @model.getSpaceTypes.each do |space_type|
            next if space_type.floorArea <= 0

            # get necessary space type information
            floor_area = space_type.floorArea
            num_people = space_type.getNumberOfPeople(floor_area)

            # get volume for space type for use with ventilation and infiltration
            space_type_volume = 0.0
            space_type_exterior_area = 0.0
            space_type_exterior_wall_area = 0.0
            space_type.spaces.each do |space|
              space_type_volume += space.volume * space.multiplier
              space_type_exterior_area = space.exteriorArea * space.multiplier
              space_type_exterior_wall_area = space.exteriorWallArea * space.multiplier
            end

            # get design spec OA object
            if space_type.designSpecificationOutdoorAir.is_initialized
              oa = space_type.designSpecificationOutdoorAir.get
              oa_method = oa.outdoorAirMethod
              oa_per_person = oa.outdoorAirFlowperPerson * num_people
              oa_ach = oa.outdoorAirFlowAirChangesperHour * space_type_volume
              oa_per_area = oa.outdoorAirFlowperFloorArea * floor_area
              oa_flow_rate = oa.outdoorAirFlowRate
              oa_space_type_total = oa_per_person + oa_ach + oa_per_area + oa_flow_rate

              value_count = 0
              if oa_per_person > 0 then value_count += 1 end
              if oa_ach > 0 then value_count += 1 end
              if oa_per_area > 0 then value_count += 1 end
              if oa_flow_rate > 0 then value_count += 1 end
              if (oa_method != 'Sum') && (value_count > 1)
                check_elems << OpenStudio::Attribute.new('flag', "Outdoor Air Method for #{space_type.name} was #{oa_method}. Expected value was Sum.")
              end
            else
              oa_space_type_total = 0.0
            end
            # add to building total oa
            model_mech_vent_si += oa_space_type_total
          end

          # check oa
          model_mech_vent_cfm = OpenStudio.convert(model_mech_vent_si, 'm^3/s', 'cfm').get
          if model_mech_vent_cfm < target_mech_vent_cfm * (1.0 - min_pass_pct)
            check_elems << OpenStudio::Attribute.new('flag', "The model mechanical ventilation of  #{OpenStudio.toNeatString(model_mech_vent_cfm, 2, true)} cfm is more than #{min_pass_pct * 100} % below the expected value of #{OpenStudio.toNeatString(target_mech_vent_cfm, 2, true)} cfm for #{target_standard}.")
          elsif model_mech_vent_cfm > target_mech_vent_cfm * (1.0 + max_pass_pct)
            check_elems << OpenStudio::Attribute.new('flag', "The model mechanical ventilation of #{OpenStudio.toNeatString(model_mech_vent_cfm, 2, true)} cfm is more than #{max_pass_pct * 100} % above the expected value of #{OpenStudio.toNeatString(target_mech_vent_cfm, 2, true)} cfm for #{target_standard}.")
          end

        else

          # loop through all space types used in the model
          @model.getSpaceTypes.sort.each do |space_type|
            next if space_type.floorArea <= 0
            next if space_type.name.to_s == 'Plenum'

            # get necessary space type information
            floor_area = space_type.floorArea
            num_people = space_type.getNumberOfPeople(floor_area)

            # load in standard info for this space type
            data = std.space_type_get_standards_data(space_type)

            if data.nil? || data.empty?

              # skip if all spaces using this space type are plenums
              all_spaces_plenums = true
              space_type.spaces.each do |space|
                unless OpenstudioStandards::Space.space_plenum?(space)
                  all_spaces_plenums = false
                  next
                end
              end

              unless all_spaces_plenums
                check_elems << OpenStudio::Attribute.new('flag', "Unexpected standards type for #{space_type.name}, can't validate internal loads.")
              end

              next
            end

            # check lpd for space type
            model_lights_si = space_type.getLightingPowerPerFloorArea(floor_area, num_people)
            data['lighting_per_area'].nil? ? (target_lights_ip = 0.0) : (target_lights_ip = data['lighting_per_area'])
            source_units = 'W/m^2'
            target_units = 'W/ft^2'
            load_type = 'Lighting Power Density'
            model_ip = OpenStudio.convert(model_lights_si, source_units, target_units).get
            target_ip = target_lights_ip.to_f
            model_ip_neat = OpenStudio.toNeatString(model_ip, 2, true)
            target_ip_neat = OpenStudio.toNeatString(target_ip, 2, true)
            if model_ip < target_ip * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif model_ip > target_ip * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end

            # check electric equipment
            model_elec_si = space_type.getElectricEquipmentPowerPerFloorArea(floor_area, num_people)
            data['electric_equipment_per_area'].nil? ? (target_elec_ip = 0.0) : (target_elec_ip = data['electric_equipment_per_area'])
            source_units = 'W/m^2'
            target_units = 'W/ft^2'
            load_type = 'Electric Power Density'
            model_ip = OpenStudio.convert(model_elec_si, source_units, target_units).get
            target_ip = target_elec_ip.to_f
            model_ip_neat = OpenStudio.toNeatString(model_ip, 2, true)
            target_ip_neat = OpenStudio.toNeatString(target_ip, 2, true)
            if model_ip < target_ip * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif model_ip > target_ip * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end

            # check gas equipment
            model_gas_si = space_type.getGasEquipmentPowerPerFloorArea(floor_area, num_people)
            data['gas_equipment_per_area'].nil? ? (target_gas_ip = 0.0) : (target_gas_ip = data['gas_equipment_per_area'])
            source_units = 'W/m^2'
            target_units = 'Btu/hr*ft^2'
            load_type = 'Gas Power Density'
            model_ip = OpenStudio.convert(model_gas_si, source_units, target_units).get
            target_ip = target_gas_ip.to_f
            model_ip_neat = OpenStudio.toNeatString(model_ip, 2, true)
            target_ip_neat = OpenStudio.toNeatString(target_ip, 2, true)
            if model_ip < target_ip * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif model_ip > target_ip * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end

            # check people
            model_occ_si = space_type.getPeoplePerFloorArea(floor_area)
            data['occupancy_per_area'].nil? ? (target_occ_ip = 0.0) : (target_occ_ip = data['occupancy_per_area'])
            source_units = '1/m^2' # people/m^2
            target_units = '1/ft^2' # people per ft^2 (can't add *1000) to the bottom, need to do later
            load_type = 'Occupancy per Area'
            model_ip = OpenStudio.convert(model_occ_si, source_units, target_units).get * 1000.0
            target_ip = target_occ_ip.to_f
            model_ip_neat = OpenStudio.toNeatString(model_ip, 2, true)
            target_ip_neat = OpenStudio.toNeatString(target_ip, 2, true)
            # for people need to update target units just for display. Can't be used for converstion.
            target_units = 'People/1000 ft^2'
            if model_ip < target_ip * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif model_ip > target_ip * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end

            # get volume for space type for use with ventilation and infiltration
            space_type_volume = 0.0
            space_type_exterior_area = 0.0
            space_type_exterior_wall_area = 0.0
            space_type.spaces.each do |space|
              space_type_volume += space.volume * space.multiplier
              space_type_exterior_area = space.exteriorArea * space.multiplier
              space_type_exterior_wall_area = space.exteriorWallArea * space.multiplier
            end

            # get design spec OA object
            if space_type.designSpecificationOutdoorAir.is_initialized
              oa = space_type.designSpecificationOutdoorAir.get
              oa_method = oa.outdoorAirMethod
              oa_per_person = oa.outdoorAirFlowperPerson
              oa_ach = oa.outdoorAirFlowAirChangesperHour * space_type_volume
              oa_per_area = oa.outdoorAirFlowperFloorArea * floor_area
              oa_flow_rate = oa.outdoorAirFlowRate
              oa_total = oa_ach + oa_per_area + oa_flow_rate

              value_count = 0
              if oa_per_person > 0 then value_count += 1 end
              if oa_ach > 0 then value_count += 1 end
              if oa_per_area > 0 then value_count += 1 end
              if oa_flow_rate > 0 then value_count += 1 end
              if (oa_method != 'Sum') && (value_count > 1)
                check_elems << OpenStudio::Attribute.new('flag', "Outdoor Air Method for #{space_type.name} was #{oa_method}. Expected value was Sum.")
              end
            else
              oa_per_person = 0.0
            end

            # get target values for OA
            target_oa_per_person_ip = data['ventilation_per_person'].to_f # ft^3/min*person
            target_oa_ach_ip = data['ventilation_air_changes'].to_f # ach
            target_oa_per_area_ip = data['ventilation_per_area'].to_f # ft^3/min*ft^2
            if target_oa_per_person_ip.nil?
              target_oa_per_person_si = 0.0
            else
              target_oa_per_person_si = OpenStudio.convert(target_oa_per_person_ip, 'cfm', 'm^3/s').get
            end
            if target_oa_ach_ip.nil?
              target_oa_ach_si = 0.0
            else
              target_oa_ach_si = target_oa_ach_ip * space_type_volume
            end
            if target_oa_per_area_ip.nil?
              target_oa_per_area_si = 0.0
            else
              target_oa_per_area_si = OpenStudio.convert(target_oa_per_area_ip, 'cfm/ft^2', 'm^3/s*m^2').get * floor_area
            end
            target_oa_total = target_oa_ach_si + target_oa_per_area_si

            # check oa per person
            source_units = 'm^3/s'
            target_units = 'cfm'
            load_type = 'Outdoor Air Per Person'
            model_ip_neat = OpenStudio.toNeatString(OpenStudio.convert(oa_per_person, source_units, target_units).get, 2, true)
            target_ip_neat = OpenStudio.toNeatString(target_oa_per_person_ip, 2, true)
            if oa_per_person < target_oa_per_person_si * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif oa_per_person > target_oa_per_person_si * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end

            # check other oa
            source_units = 'm^3/s'
            target_units = 'cfm'
            load_type = 'Outdoor Air (Excluding per Person Value)'
            model_ip_neat = OpenStudio.toNeatString(OpenStudio.convert(oa_total, source_units, target_units).get, 2, true)
            target_ip_neat = OpenStudio.toNeatString(OpenStudio.convert(target_oa_total, source_units, target_units).get, 2, true)
            if oa_total < target_oa_total * (1.0 - min_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            elsif oa_total > target_oa_total * (1.0 + max_pass_pct)
              check_elems << OpenStudio::Attribute.new('flag', "#{load_type} of #{model_ip_neat} (#{target_units}) for #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_ip_neat} (#{target_units}) for #{display_standard}.")
            end
          end

          # warn if there are spaces in model that don't use space type unless they appear to be plenums
          @model.getSpaces.sort.each do |space|
            next if OpenstudioStandards::Space.space_plenum?(space)

            if !space.spaceType.is_initialized
              check_elems << OpenStudio::Attribute.new('flag', "#{space.name} doesn't have a space type assigned, can't validate internal loads.")
            end
          end

          # @todo need to address internal loads where fuel is variable like cooking and laundry
          # @todo For now we are not going to loop through spaces looking for loads beyond what comes from space type
          # @todo space infiltration

        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the internal load schedules against template prototypes
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_internal_loads_schedules(category, target_standard, min_pass_pct: 0.2, max_pass_pct: 0.2, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Schedules')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check schedules for lighting, ventilation, occupant density, plug loads, and equipment based on DOE reference building schedules in terms of full load hours per year.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        # loop through all space types used in the model
        @model.getSpaceTypes.each do |space_type|
          next if space_type.floorArea <= 0

          # load in standard info for this space type
          data = std.space_type_get_standards_data(space_type)

          if data.nil? || data.empty?

            # skip if all spaces using this space type are plenums
            all_spaces_plenums = true
            space_type.spaces.each do |space|
              unless OpenstudioStandards::Space.space_plenum?(space)
                all_spaces_plenums = false
                break
              end
            end

            unless all_spaces_plenums
              check_elems << OpenStudio::Attribute.new('flag', "Unexpected standards type for #{space_type.name}, can't validate schedules.")
            end

            next
          end

          # temp model to hold schedules to check
          model_temp = OpenStudio::Model::Model.new

          # check lighting schedules
          data['lighting_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['lighting_per_area'])
          if target_ip.to_f > 0
            schedule_target = std.model_add_schedule(model_temp, data['lighting_schedule'])
            if !schedule_target
              check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['lighting_schedule']} in standards json.")
            elsif !schedule_target.to_ScheduleRuleset.is_initialized
              check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule.")
            else
              schedule_target = schedule_target.to_ScheduleRuleset.get
              # loop through and test individual load instances
              expected_hours = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_target)
              space_type.lights.each do |space_load_instance|
                inst_sch_check = OpenstudioStandards::QAQC.space_load_instance_schedule_check(space_load_instance, expected_hours, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
                if inst_sch_check then check_elems << inst_sch_check end
              end

            end
          end

          # check electric equipment schedules
          data['electric_equipment_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['electric_equipment_per_area'])
          if target_ip.to_f > 0
            schedule_target = std.model_add_schedule(model_temp, data['electric_equipment_schedule'])
            if !schedule_target
              check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['electric_equipment_schedule']} in standards json.")
            elsif !schedule_target.to_ScheduleRuleset.is_initialized
              check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule.")
            else
              schedule_target = schedule_target.to_ScheduleRuleset.get
              # loop through and test individual load instances
              expected_hours = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_target)
              space_type.electricEquipment.each do |space_load_instance|
                inst_sch_check = OpenstudioStandards::QAQC.space_load_instance_schedule_check(space_load_instance, expected_hours, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
                if inst_sch_check then check_elems << inst_sch_check end
              end
            end
          end

          # check gas equipment schedules
          # @todo - update measure test to with space type to check this
          data['gas_equipment_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['gas_equipment_per_area'])
          if target_ip.to_f > 0
            schedule_target = std.model_add_schedule(model_temp, data['gas_equipment_schedule'])
            if !schedule_target
              check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['gas_equipment_schedule']} in standards json.")
            elsif !schedule_target.to_ScheduleRuleset.is_initialized
              check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule.")
            else
              schedule_target = schedule_target.to_ScheduleRuleset.get
              # loop through and test individual load instances
              expected_hours = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_target)
              space_type.gasEquipment.each do |space_load_instance|
                inst_sch_check = OpenstudioStandards::QAQC.space_load_instance_schedule_check(space_load_instance, expected_hours, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
                if inst_sch_check then check_elems << inst_sch_check end
              end
            end
          end

          # check occupancy schedules
          data['occupancy_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['occupancy_per_area'])
          if target_ip.to_f > 0
            schedule_target = std.model_add_schedule(model_temp, data['occupancy_schedule'])
            if !schedule_target
              check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['occupancy_schedule']} in standards json.")
            elsif !schedule_target.to_ScheduleRuleset.is_initialized
              check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule.")
            else
              schedule_target = schedule_target.to_ScheduleRuleset.get
              # loop through and test individual load instances
              expected_hours = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_target)
              space_type.people.each do |space_load_instance|
                inst_sch_check = OpenstudioStandards::QAQC.space_load_instance_schedule_check(space_load_instance, expected_hours, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
                if inst_sch_check then check_elems << inst_sch_check end
              end

            end
          end

          # @todo: check ventilation schedules
          # if objects are in the model should they just be always on schedule, or have a 8760 annual equivalent value
          # oa_schedule should not exist, or if it does shoudl be always on or have 8760 annual equivalent value
          if space_type.designSpecificationOutdoorAir.is_initialized
            oa = space_type.designSpecificationOutdoorAir.get
            if oa.outdoorAirFlowRateFractionSchedule.is_initialized
              # @todo: update measure test to check this
              expected_hours = 8760
              inst_sch_check = OpenstudioStandards::QAQC.space_load_instance_schedule_check(oa, expected_hours, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
              if inst_sch_check then check_elems << inst_sch_check end
            end
          end

          # notes
          # current logic only looks at 8760 values and not design days
          # when multiple instances of a type currently check every schedule by itself. In future could do weighted avgerage merge
          # not looking at infiltration schedules
          # not looking at luminaires
          # not looking at space loads, only loads at space type
          # only checking schedules where standard shows non zero load value
          # model load for space type where standards doesn't have one wont throw flag about mis-matched schedules
        end

        # warn if there are spaces in model that don't use space type unless they appear to be plenums
        @model.getSpaces.sort.each do |space|
          next if OpenstudioStandards::Space.space_plenum?(space)

          if !space.spaceType.is_initialized
            check_elems << OpenStudio::Attribute.new('flag', "#{space.name} doesn't have a space type assigned, can't validate schedules.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check the schedule for a space load instance
    # will return false or a single attribute
    #
    # @param space_load_instance [OpenStudio::Model::SpaceLoadInstance] Openstudio SpaceLoadInstance object
    # @param expected_hours [Double] expected number of equivalent full load hours
    # @param std [String] openstudio-standards Standard Class
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @return [OpenStudio::Attribute, false] OpenStudio Attribute object containing check results, or false if no error
    def self.space_load_instance_schedule_check(space_load_instance, expected_hours, std: nil, min_pass_pct: 0.2, max_pass_pct: 0.2)
      if std.nil?
        std = Standard.build('90.1-2013')
      end

      if space_load_instance.spaceType.is_initialized
        space_type = space_load_instance
      end

      # get schedule
      if space_load_instance.instance_of?(OpenStudio::Model::People) && space_load_instance.numberofPeopleSchedule.is_initialized
        schedule_inst = space_load_instance.numberofPeopleSchedule.get
      elsif space_load_instance.instance_of?(OpenStudio::Model::DesignSpecificationOutdoorAir) && space_load_instance.outdoorAirFlowRateFractionSchedule.is_initialized
        schedule_inst = space_load_instance.outdoorAirFlowRateFractionSchedule.get
      elsif space_load_instance.schedule.is_initialized
        schedule_inst = space_load_instance.schedule.get
      else
        return OpenStudio::Attribute.new('flag', "#{space_load_instance.name} in #{space_type.name} doesn't have a schedule assigned.")
      end

      # get annual equiv for model schedule
      inst_hrs = OpenstudioStandards::Schedules.schedule_get_equivalent_full_load_hours(schedule_inst)
      if inst_hrs.nil?
        return OpenStudio::Attribute.new('flag', "#{schedule_inst.name} isn't a Ruleset or Constant schedule. Can't calculate annual equivalent full load hours.")
      end

      # check instance against target
      if inst_hrs < expected_hours * (1.0 - min_pass_pct)
        return OpenStudio::Attribute.new('flag', "#{inst_hrs.round} annual equivalent full load hours for #{schedule_inst.name} in #{space_type.name} is more than #{min_pass_pct * 100} (%) below the typical value of #{expected_hours.round} hours from the DOE Prototype building.")
      elsif inst_hrs > expected_hours * (1.0 + max_pass_pct)
        return OpenStudio::Attribute.new('flag', "#{inst_hrs.round} annual equivalent full load hours for #{schedule_inst.name} in #{space_type.name}  is more than #{max_pass_pct * 100} (%) above the typical value of #{expected_hours.round} hours DOE Prototype building.")
      end

      # will get to this if no flag was thrown
      return false
    end
  end
end
