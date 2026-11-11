# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Schedules

    # Check that the lighting, equipment, and HVAC setpoint schedules coordinate with the occupancy schedules.
    # This is defined as having start and end times within the specified number of hours away from the occupancy schedule.
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_hrs [Double] threshold for throwing an error for schedule coordination
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_schedule_coordination(category, target_standard, max_hrs: 2.0, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Schedule Coordination')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that lighting, equipment, and HVAC schedules coordinate with occupancy.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        # Convert max hr limit to OpenStudio Time
        max_hrs = OpenStudio::Time.new(0, max_hrs.to_i, 0, 0)

        # Check schedules in each space
        @model.getSpaces.sort.each do |space|
          # Occupancy, Lighting, and Equipment Schedules
          coord_schs = []
          occ_schs = []
          # Get the space type (optional)
          space_type = space.spaceType

          # Occupancy
          occs = []
          occs += space.people # From space directly
          occs += space_type.get.people if space_type.is_initialized # Inherited from space type
          occs.each do |occ|
            occ_schs << occ.numberofPeopleSchedule.get if occ.numberofPeopleSchedule.is_initialized
          end

          # Lights
          lts = []
          lts += space.lights # From space directly
          lts += space_type.get.lights if space_type.is_initialized # Inherited from space type
          lts.each do |lt|
            coord_schs << lt.schedule.get if lt.schedule.is_initialized
          end

          # Equip
          plugs = []
          plugs += space.electricEquipment # From space directly
          plugs += space_type.get.electricEquipment if space_type.is_initialized # Inherited from space type
          plugs.each do |plug|
            coord_schs << plug.schedule.get if plug.schedule.is_initialized
          end

          # HVAC Schedule (airloop-served zones only)
          if space.thermalZone.is_initialized
            zone = space.thermalZone.get
            if zone.airLoopHVAC.is_initialized
              coord_schs << zone.airLoopHVAC.get.availabilitySchedule
            end
          end

          # Cannot check spaces with no occupancy schedule to compare against
          next if occ_schs.empty?

          # Get start and end occupancy times from the first occupancy schedule
          times = OpenstudioStandards::Schedules.schedule_ruleset_get_start_and_end_times(occ_schs[0])
          occ_start_time = times['start_time']
          occ_end_time = times['end_time']

          # Cannot check a space where the occupancy start time or end time cannot be determined
          next if occ_start_time.nil? || occ_end_time.nil?

          # Check all schedules against occupancy

          # Lights should have a start and end within X hrs of the occupancy start and end
          coord_schs.each do |coord_sch|
            # Get start and end time of load/HVAC schedule
            times = OpenstudioStandards::Schedules.schedule_ruleset_get_start_and_end_times(coord_sch)
            start_time = times['start_time']
            end_time = times['end_time]']

            if start_time.nil?
              check_elems << OpenStudio::Attribute.new('flag', "Could not determine start time of a schedule called #{coord_sch.name}, cannot determine if schedule coordinates with occupancy schedule.")
              next
            elsif end_time.nil?
              check_elems << OpenStudio::Attribute.new('flag', "Could not determine end time of a schedule called #{coord_sch.name}, cannot determine if schedule coordinates with occupancy schedule.")
              next
            end

            # Check start time
            if (occ_start_time - start_time) > max_hrs || (start_time - occ_start_time) > max_hrs
              check_elems << OpenStudio::Attribute.new('flag', "The start time of #{coord_sch.name} is #{start_time}, which is more than #{max_hrs} away from the occupancy schedule start time of #{occ_start_time} for #{occ_schs[0].name} in #{space.name}.  Schedules do not coordinate.")
            end

            # Check end time
            if (occ_end_time - end_time) > max_hrs || (end_time - occ_end_time) > max_hrs
              check_elems << OpenStudio::Attribute.new('flag', "The end time of #{coord_sch.name} is #{end_time}, which is more than #{max_hrs} away from the occupancy schedule end time of #{occ_end_time} for #{occ_schs[0].name} in #{space.name}.  Schedules do not coordinate.")
            end
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
  end
end
