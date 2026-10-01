module OpenstudioStandards
  # The ServiceWaterHeating module provides methods to create, modify, and get information about service water heating
  module ServiceWaterHeating
    # @!group Create Typical

    # Hot water draw schedule named by a space type's parametric schedule set.
    #
    # The schedule set data carries a hot_water_equipment_schedule for the space types that
    # have one, named '<all-level space type> hot water equipment'. Sourcing the draw profile
    # from there keeps it consistent with the space type's other load schedules, instead of
    # inheriting whichever DOE prototype or DEER profile happened to ship alongside the flow
    # rate.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @return [String, nil] schedule name, or nil when the space type has no schedule set or
    #   its set defines no hot water schedule
    def self.space_type_hot_water_schedule_name(space_type)
      return nil unless space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized

      schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
      @parametric_schedule_sets ||= JSON.parse(
        File.read(File.join(__dir__, '..', 'schedules', 'data', 'default_parametric_schedule_set.json')),
        symbolize_names: true
      )
      record = @parametric_schedule_sets.find { |set| set[:schedule_set_name] == schedule_set_name }
      return nil if record.nil?

      schedule = record[:hot_water_equipment_schedule]
      return nil if schedule.nil? || schedule.to_s.empty? || schedule.to_s == 'None'

      schedule
    end
    # Methods to add typical service water heating depending on space types

    # add typical swh demand and supply to model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param water_heating_fuel [String] water heater fuel. Valid choices are NaturalGas, Electricity, and HeatPump.
    #   If not supplied, a smart default will be determined based on building type and loop type.
    # @param circulating [Boolean] determine whether the system is circulating (true), noncirculating (false).
    #   A nil value will default based on the standards building type
    # @return [Array<OpenStudio::Model::PlantLoop>] array of service hot water loops
    # @todo add support for other loop configurations, such as by space type, space type adjacent, or building type
    # Fields a service water heating override may set on one water use equipment entry
    SERVICE_WATER_OVERRIDE_FIELDS = %i[
      peak_flow_rate_gph peak_flow_rate_gph_per_floor_area_ft2 mixed_water_temperature_f
      sensible_fraction latent_fraction flow_rate_schedule
    ].freeze

    # Apply runtime service water heating overrides to a space type's water use equipment.
    #
    # A space type carries several pieces of equipment -- a kitchen has a dishwasher booster
    # at 180 F and a general draw at 120 F -- so an override names the equipment it means, or
    # uses '*' for all of it. A named entry wins over the wildcard, and the wildcard is the
    # only way to reach equipment the data leaves unnamed.
    #
    # This exists because a per-area flow rate is a property of the building as much as the
    # space: a restaurant kitchen draws 0.054 gph/ft2 and a hospital kitchen 0.009, six times
    # less, and the all-level space type 'food preparation' cannot say which. A model whose
    # kitchen is not a restaurant's states its own rate here.
    #
    # @param equipment [Array<Hash>] the record's water use equipment entries
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @param standards_space_type [String] all-level space type name
    # @param overrides [Array<Hash>, nil] override entries
    # @return [Array<Hash>] equipment entries with overrides applied
    def self.apply_service_water_heating_overrides(equipment, space_type, standards_space_type, overrides)
      return equipment if overrides.nil? || overrides.empty?

      matched = OpenstudioStandards::CreateTypical.resolve_overrides(overrides, space_type,
                                                                    section_keys: [:equipment],
                                                                    extra_names: [standards_space_type])[:equipment]
      return equipment if matched.nil? || matched.empty?

      equipment.map do |entry|
        name = entry[:equipment_name]
        fields = matched[:'*'] || {}
        fields = fields.merge(matched[name.to_sym]) if name && matched[name.to_sym].is_a?(Hash)
        next entry if fields.empty?

        applied = fields.select { |key, _| SERVICE_WATER_OVERRIDE_FIELDS.include?(key) }
        # a rate given one way clears the other, or the record's own value would win: the
        # expansion prefers an absolute gph and only falls back to the per-area rate
        applied[:peak_flow_rate_gph] = nil if applied.key?(:peak_flow_rate_gph_per_floor_area_ft2) && !applied.key?(:peak_flow_rate_gph)
        applied[:peak_flow_rate_gph_per_floor_area_ft2] = nil if applied.key?(:peak_flow_rate_gph) && !applied.key?(:peak_flow_rate_gph_per_floor_area_ft2)
        entry.merge(applied)
      end
    end

    # @param service_water_heating_overrides [Array<Hash>, nil] runtime overrides of the water
    #   use equipment a space type resolves to. Each entry is keyed by `space_type` (matched
    #   against the schedule set name or the standards space type) or `"*"`, with an
    #   `equipment` hash keyed by equipment name or `"*"`.
    def self.create_typical_service_water_heating(model,
                                                  water_heating_fuel: nil,
                                                  circulating: nil,
                                                  service_water_heating_overrides: nil)
      # array of service hot water loops
      swh_systems = []

      # water use equipment on the building loop
      shared_water_use_equipment = []
      booster_water_use_equipment = []

      # @todo remove once model_add_schedule is refactored
      std = Standard.build('90.1-2013')

      # loop through space types adding demand side of swh
      model.getSpaces.sort.each do |space|
        next unless space.spaceType.is_initialized

        total_space_floor_area_m2 = space.floorArea * space.multiplier
        total_space_floor_area_ft2 = OpenStudio.convert(total_space_floor_area_m2, 'm^2', 'ft^2').get
        space_type = space.spaceType.get

        next unless space_type.standardsSpaceType.is_initialized

        standards_space_type = space_type.standardsSpaceType.get
        standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil

        # load typical water use equipment data
        data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/typical_water_use_equipment.json"), symbolize_names: true)

        # All-level space type is the key. Water use is a property of what happens in the
        # space, not of the building that contains it, so the building type takes no part in
        # the lookup: a kitchen is a kitchen.
        #
        # This replaces a two-step lookup that keyed first on the DOE prototype
        # (space_type, building_type) pair and then fell back to the first record tagged with
        # the all-level name regardless of building type. That fallback selected records by
        # JSON order: an office resolved to a DEER assembly hall record with 70x the office
        # flow rate, which inflated service water heating by up to 278x on a large office.
        space_type_properties = data[:space_types].select do |hash|
          (hash[:all_level_space_types] || []).include?(standards_space_type)
        end

        # legacy key, for models still built from DOE prototype space type names
        if space_type_properties.empty? && !standards_building_type.nil?
          space_type_properties = data[:space_types].select do |hash|
            (hash[:space_type] == standards_space_type) && (hash[:building_type] == standards_building_type)
          end
        end

        # skip spaces with no equipment defined
        next if space_type_properties.empty?

        if space_type_properties.size > 1
          flows = space_type_properties.map { |hash| (hash[:water_use_equipment] || [{}]).first[:peak_flow_rate_gph_per_floor_area_ft2] }.compact.uniq
          if flows.size > 1
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating',
                               "Space type '#{standards_space_type}' matches #{space_type_properties.size} water use equipment records with differing peak flow rates (#{flows.map { |f| f.round(6) }.join(', ')} gph/ft2). Using the first. Give the all-level space type a single record to make this deterministic.")
          end
        end

        water_use_equipment = OpenstudioStandards::ServiceWaterHeating.apply_service_water_heating_overrides(
          space_type_properties[0][:water_use_equipment], space_type, standards_space_type, service_water_heating_overrides
        )

        # store one per unit equipment
        space_water_use_equipment = []

        if space.hasAdditionalProperties && space.additionalProperties.hasFeature('num_units')
          num_units = space.additionalProperties.getFeatureAsInteger('num_units').get
        else # assume 1 space is 1 unit
          num_units = space.multiplier
        end

        # loop through and add water use equipment to space
        water_use_equipment.each do |w|
          # get water use equipment properties
          water_use_name = w[:equipment_name]
          peak_flow_rate_gal_per_hr = w[:peak_flow_rate_gph].to_f
          peak_flow_rate_gal_per_hr_per_ft2 = w[:peak_flow_rate_gph_per_floor_area_ft2].to_f
          loop_type = w[:loop_type]
          temperature = w[:mixed_water_temperature_f]
          flow_rate_schedule = w[:flow_rate_schedule]
          sensible_fraction = w[:sensible_fraction]
          latent_fraction = w[:latent_fraction]

          # derived from equipment properties
          is_booster = water_use_name && water_use_name.downcase.include?('booster')
          water_use_name = water_use_name ? "#{space.name} #{water_use_name}" : "#{space.name} Water Use"
          mixed_water_temperature_c = OpenStudio.convert(temperature, 'F', 'C').get

          # Prefer the hot water schedule the space type's own parametric schedule set names,
          # so the draw profile follows the space type rather than whichever DOE prototype or
          # DEER record the flow rate came from. Falls back to the record's schedule when the
          # space type has no schedule set, which is the case for models built from prototype
          # space type names.
          schedule_set_schedule = OpenstudioStandards::ServiceWaterHeating.space_type_hot_water_schedule_name(space_type)
          flow_rate_schedule = schedule_set_schedule unless schedule_set_schedule.nil?

          # @todo replace this line once model_add_schedule is refactored to not require a standard
          flow_rate_schedule = std.model_add_schedule(model, flow_rate_schedule)

          # skip undefined equipment
          next unless peak_flow_rate_gal_per_hr > 0.0 || peak_flow_rate_gal_per_hr_per_ft2 > 0.0

          # If there is no SWH schedule, assume no SWH use for this space type.
          unless flow_rate_schedule
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', "No service water heating schedule was specified for space type #{space_type.name} with standards space type #{standards_space_type}. Assuming an always off schedule.")
            flow_rate_schedule = model.alwaysOffDiscreteSchedule
          end

          # Determine the peak flow rate and default water heating fuel
          case loop_type
          when 'One Per Unit'
            # calculate peak flow rate
            if peak_flow_rate_gal_per_hr.zero? && peak_flow_rate_gal_per_hr_per_ft2 > 0.0
              peak_flow_rate_gal_per_hr = num_units * peak_flow_rate_gal_per_hr_per_ft2 * total_space_floor_area_ft2
            else
              peak_flow_rate_gal_per_hr *= num_units
            end

            # update water use name
            water_use_name = "#{water_use_name} #{num_units} unit(s)"
          else
            # calculate peak flow rate
            if peak_flow_rate_gal_per_hr.zero? && peak_flow_rate_gal_per_hr_per_ft2 > 0.0
              peak_flow_rate_gal_per_hr = peak_flow_rate_gal_per_hr_per_ft2 * total_space_floor_area_ft2
            end
          end

          # convert to SI
          peak_flow_rate_m3_per_s = OpenStudio.convert(peak_flow_rate_gal_per_hr, 'gal/hr', 'm^3/s').get

          # create water use equipment
          water_use_equip = OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                                      name: water_use_name,
                                                                                      flow_rate: peak_flow_rate_m3_per_s,
                                                                                      flow_rate_fraction_schedule: flow_rate_schedule,
                                                                                      water_use_temperature: mixed_water_temperature_c,
                                                                                      sensible_fraction: sensible_fraction,
                                                                                      latent_fraction: latent_fraction,
                                                                                      space: space)

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added water use equipment #{water_use_equip.name}")

          # create service hot water loop for 'One Per Space' and 'One Per Unit' dedicated equipment
          case loop_type
          when 'Shared'
            if is_booster
              booster_water_use_equipment << water_use_equip
            else
              shared_water_use_equipment << water_use_equip
            end
          when 'One Per Space', 'One Per Unit'
            space_water_use_equipment << water_use_equip
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', "Water use equipment service loop type #{loop_type} not recognized. Cannot attach equipment to a loop.")
          end
        end

        # create water loop for 'One Per Space' and 'One Per Unit' equipment
        unless space_water_use_equipment.empty?
          water_heater_capacity_w = num_units * OpenStudio.convert(20.0, 'kBtu/hr', 'W').get
          water_heater_volume_m3 = num_units * OpenStudio.convert(50.0, 'gal', 'm^3').get
          num_water_heaters = num_units

          # default to electricity for single units
          dedicated_water_heating_fuel = water_heating_fuel || 'Electricity'

          # default to 140F
          service_water_loop_temperature_c = OpenStudio.convert(140.0, 'F', 'C').get

          # A dedicated point-of-use heater has no distribution piping, and modelling one here
          # was delivering ambient-temperature water. These loops carry the fixture's own peak
          # flow - 0.03 gpm for a strip mall tenant - and a 20 ft insulated Pipe:Indoor sized
          # from the space's floor area loses everything a trickle like that carries: on the
          # strip mall the tank sat at 59 C all year while its fixtures received 21 to
          # 47 C, logged "Target water temperature is greater than the hot water temperature"
          # 24 million times, and the per-space loops were the second largest warning class
          # in the fleet. With no pipe the fixtures receive the tank temperature.
          #
          # add service water loop with water heater
          swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                system_name: "#{space.name} Service Water Loop",
                                                                                                service_water_temperature: service_water_loop_temperature_c,
                                                                                                service_water_pump_head: 0.01,
                                                                                                service_water_pump_motor_efficiency: 1.0,
                                                                                                water_heater_capacity: water_heater_capacity_w,
                                                                                                water_heater_volume: water_heater_volume_m3,
                                                                                                water_heater_fuel: dedicated_water_heating_fuel,
                                                                                                number_of_water_heaters: num_water_heaters,
                                                                                                add_piping_losses: false,
                                                                                                floor_area: total_space_floor_area_m2,
                                                                                                number_of_stories: 1)

          # add loop to array
          swh_systems << swh_loop

          # Attach water use equipment to the loop
          space_water_use_equipment.each do |water_use_equip|
            swh_connection = water_use_equip.waterUseConnections
            swh_loop.addDemandBranchForComponent(swh_connection.get) if swh_connection.is_initialized
          end
        end
      end

      ############################################################################

      # default to gas for shared system types and booster systems
      shared_water_heating_fuel = water_heating_fuel || 'NaturalGas'
      booster_water_heating_fuel = water_heating_fuel || 'Electricity'

      # @todo get maximum service water temperature from shared_water_use_equipment
      water_heater_temp_f = 140.0
      water_heater_temp_c = OpenStudio.convert(water_heater_temp_f, 'F', 'C').get

      # defaults for circulating or noncirculating systems
      # @todo Remove hard-coded building-type-based lookups for circulating vs. non-circulating SWH systems
      if circulating.nil?
        if model.getBuilding.standardsBuildingType.is_initialized
          circulating = OpenstudioStandards::ServiceWaterHeating.circulating_building_type?(model.getBuilding.standardsBuildingType.get)
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', 'Unable to determine the standards building type. Assuming the building does not have a circulating service water heating loop.')
          circulating = false
        end
      end

      # create a shared water loop
      unless shared_water_use_equipment.empty? && booster_water_use_equipment.empty?
        if circulating
          # Table A.2 in PrototypeModelEnhancements_2014_0.pdf shows 10ft on everything except SecondarySchool which has 11.4ft
          service_water_pump_head_pa = OpenStudio.convert(10.0, 'ftH_{2}O', 'Pa').get
          service_water_pump_motor_efficiency = 0.3
        else
          service_water_pump_head_pa = 0.01
          service_water_pump_motor_efficiency = 1.0
        end

        # Size the shared water heater on every draw it actually serves, booster draws
        # included. The booster's heat exchanger goes on THIS loop's demand side below, so the
        # shared heater preheats every gallon the booster delivers from mains to 140 F and the
        # booster only adds the last 40 F. Sizing on shared_water_use_equipment alone left the
        # preheat unaccounted for: on a full service restaurant whose 180 F kitchen draw is
        # 1.5x its 120 F draw, the shared heater came out 2.5x too small, sat at part load
        # ratio 1.0 all year, and neither loop ever reached setpoint -- which starved the
        # booster in turn, since it was sized for a 140 F feed it never received.
        # Both sets take the same mains-to-140 F rise here, so they size as one population.
        water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(shared_water_use_equipment + booster_water_use_equipment)
        water_heater_capacity_w = water_heater_sizing[:water_heater_capacity]
        water_heater_volume_m3 = water_heater_sizing[:water_heater_volume]

        # Add a shared service water heating loop with water heater
        shared_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                     system_name: 'Shared Service Water Loop',
                                                                                                     service_water_temperature: water_heater_temp_c,
                                                                                                     service_water_pump_head: service_water_pump_head_pa,
                                                                                                     service_water_pump_motor_efficiency: service_water_pump_motor_efficiency,
                                                                                                     water_heater_capacity: water_heater_capacity_w,
                                                                                                     water_heater_volume: water_heater_volume_m3,
                                                                                                     water_heater_fuel: shared_water_heating_fuel,
                                                                                                     add_piping_losses: true)

        # Add loop to array
        swh_systems << shared_swh_loop

        # Attach all water use equipment to the shared loop
        shared_water_use_equipment.sort.each do |water_use_equip|
          OpenstudioStandards::ServiceWaterHeating.attach_water_use_to_loop(water_use_equip, shared_swh_loop)
        end

        # Attach booster water heater loop to shared loop
        unless booster_water_use_equipment.empty?
          # find_water_heater_capacity_volume_and_parasitic
          #
          # Size over the lift the booster actually performs. create_booster_water_heating_loop
          # runs the loop a deadband above the 180 F its fixtures target, so the tank's cycling
          # minimum still delivers 180 F, and the heater has to reach that higher setpoint.
          booster_setpoint_offset_k = 2.0
          booster_supply_temperature_f = 180.0 + OpenStudio.convert(booster_setpoint_offset_k, 'K', 'R').get
          booster_water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(booster_water_use_equipment,
                                                                                                                              water_heater_efficiency: 1.0,
                                                                                                                              inlet_temperature: 140.0,
                                                                                                                              supply_temperature: booster_supply_temperature_f)

          # Note that booster water heaters are always assumed to be electric resistance
          booster_water_loop_temperature_c = OpenStudio.convert(180.0, 'F', 'C').get
          swh_booster_loop = OpenstudioStandards::ServiceWaterHeating.create_booster_water_heating_loop(model,
                                                                                                        system_name: 'Booster Water Loop',
                                                                                                        water_heater_capacity: booster_water_heater_sizing[:water_heater_capacity],
                                                                                                        service_water_temperature: booster_water_loop_temperature_c,
                                                                                                        setpoint_offset: booster_setpoint_offset_k,
                                                                                                        service_water_loop: shared_swh_loop)

          # Add loop to array
          swh_systems << swh_booster_loop

          # Attach booster water use equipment to the booster loop
          booster_water_use_equipment.each do |booster_equip|
            OpenstudioStandards::ServiceWaterHeating.attach_water_use_to_loop(booster_equip, swh_booster_loop)
          end
        end
      end

      return swh_systems
    end

    # Check if the standards building type tends to have a circulating system by default
    #
    # @param standards_building_type [String] standard building type
    # @return [Boolean] return true if the building has a circulating system, false if not
    def self.circulating_building_type?(standards_building_type)
      circulating_bldg_types = [
        # DOE building types
        'Office',
        'PrimarySchool',
        'Outpatient',
        'Hospital',
        'SmallHotel',
        'LargeHotel',
        'FullServiceRestaurant',
        'HighriseApartment',
        # DEER building types
        'Asm', # 'Assembly'
        'ECC', # 'Education - Community College'
        'EPr', # 'Education - Primary School'
        'ERC', # 'Education - Relocatable Classroom'
        'ESe', # 'Education - Secondary School'
        'EUn', # 'Education - University'
        'Gro', # 'Grocery'
        'Hsp', # 'Health/Medical - Hospital'
        'Htl', # 'Lodging - Hotel'
        'MBT', # 'Manufacturing Biotech'
        'MFm', # 'Residential Multi-family'
        'Mtl', # 'Lodging - Motel'
        'Nrs', # 'Health/Medical - Nursing Home'
        'OfL', # 'Office - Large'
        # 'RFF', # 'Restaurant - Fast-Food'
        'RSD' # 'Restaurant - Sit-Down'
      ]

      return circulating_bldg_types.include?(standards_building_type)
    end
  end
end
