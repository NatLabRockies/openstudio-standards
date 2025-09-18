class Standard
    # add typical swh demand and supply to model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param water_heater_fuel [String] water heater fuel. Valid choices are NaturalGas, Electricity, and HeatPump.
  #   If not supplied, a smart default will be determined based on building type.
  # @param pipe_insul_in [Double] thickness of the pipe insulation, in inches.
  # @param circulating [String] whether the (circulating, noncirculating, nil) nil is smart
  # @return [Array<OpenStudio::Model::PlantLoop>] hot water loops
  # @todo - add in losses from tank and pipe insulation, etc.
  def model_add_typical_swh(model,
                            water_heater_fuel: nil,
                            pipe_insul_in: nil,
                            circulating: nil)
    # array of hot water loops
    swh_systems = []

    # hash of general water use equipment awaiting loop
    water_use_equipment_hash = {} # key is standards building type value is array of water use equipment

    # create space type hash (need num_units for MidriseApartment and RetailStripmall)
    space_type_hash = model_create_space_type_hash(model, trust_effective_num_spaces = false)

    # loop through space types adding demand side of swh
    model.getSpaceTypes.sort.each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized
      next unless space_type_hash.key?(space_type) # this is used for space types without any floor area

      stds_bldg_type = space_type.standardsBuildingType.get

      # lookup space_type_properties
      space_type_properties = space_type_get_standards_data(space_type)
      peak_flow_rate_gal_per_hr_per_ft2 = space_type_properties['service_water_heating_peak_flow_per_area'].to_f
      peak_flow_rate_gal_per_hr = space_type_properties['service_water_heating_peak_flow_rate'].to_f
      swh_system_type = space_type_properties['service_water_heating_system_type']
      flow_rate_fraction_schedule = model_add_schedule(model, space_type_properties['service_water_heating_schedule'])
      service_water_temperature_f = space_type_properties['service_water_heating_target_temperature'].to_f
      service_water_temperature_c = OpenStudio.convert(service_water_temperature_f, 'F', 'C').get
      booster_water_temperature_f = space_type_properties['booster_water_heating_target_temperature'].to_f
      booster_water_temperature_c = OpenStudio.convert(booster_water_temperature_f, 'F', 'C').get
      booster_water_heater_fraction = space_type_properties['booster_water_heater_fraction'].to_f
      service_water_fraction_sensible = space_type_properties['service_water_heating_fraction_sensible']
      service_water_fraction_latent = space_type_properties['service_water_heating_fraction_latent']
      floor_area_m2 = space_type_hash[space_type][:floor_area]
      floor_area_ft2 = OpenStudio.convert(floor_area_m2, 'm^2', 'ft^2').get

      # next if no service water heating demand
      next unless peak_flow_rate_gal_per_hr_per_ft2 > 0.0 || peak_flow_rate_gal_per_hr > 0.0

      # If there is no SWH schedule specified, assume
      # that there should be no SWH consumption for this space type.
      unless flow_rate_fraction_schedule
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "No service water heating schedule was specified for #{space_type.name}, an always off schedule will be used and no water will be used.")
        flow_rate_fraction_schedule = model.alwaysOffDiscreteSchedule
      end

      # Determine flow rate
      case swh_system_type
      when 'One Per Unit'
        water_heater_fuel = 'Electricity' if water_heater_fuel.nil?
        num_units = space_type_hash[space_type][:num_units].round # First try number of units
        num_units = space_type_hash[space_type][:effective_num_spaces].round if num_units.zero? # Fall back on number of spaces
        peak_flow_rate_gal_per_hr = num_units * peak_flow_rate_gal_per_hr
        peak_flow_rate_m3_per_s = OpenStudio.convert(peak_flow_rate_gal_per_hr, 'gal/hr', 'm^3/s').get
        use_name = "#{space_type.name} #{num_units} units"
      else
        # @todo add building type or sice specific logic or just assume Gas?
        #   (SmallOffice and Warehouse are only non unit prototypes with Electric heating)
        water_heater_fuel = 'NaturalGas' if water_heater_fuel.nil?
        num_units = 1
        peak_flow_rate_gal_per_hr = peak_flow_rate_gal_per_hr_per_ft2 * floor_area_ft2
        peak_flow_rate_m3_per_s = OpenStudio.convert(peak_flow_rate_gal_per_hr, 'gal/hr', 'm^3/s').get
        use_name = space_type.name.to_s
      end

      # Split flow rate between main and booster uses if specified
      booster_water_use_equip = nil
      if booster_water_heater_fraction > 0.0
        booster_peak_flow_rate_m3_per_s = peak_flow_rate_m3_per_s * booster_water_heater_fraction
        peak_flow_rate_m3_per_s -= booster_peak_flow_rate_m3_per_s

        # Add booster water heater equipment and connections
        booster_water_use_equip = OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                                            name: "Booster #{use_name}",
                                                                                            flow_rate: booster_peak_flow_rate_m3_per_s,
                                                                                            flow_rate_fraction_schedule: flow_rate_fraction_schedule,
                                                                                            water_use_temperature: booster_water_temperature_c,
                                                                                            sensible_fraction: service_water_fraction_sensible,
                                                                                            latent_fraction: service_water_fraction_latent)
      end

      # Add water use equipment and connections
      water_use_equip = OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                                  name: use_name,
                                                                                  flow_rate: peak_flow_rate_m3_per_s,
                                                                                  flow_rate_fraction_schedule: flow_rate_fraction_schedule,
                                                                                  water_use_temperature: service_water_temperature_c,
                                                                                  sensible_fraction: service_water_fraction_sensible,
                                                                                  latent_fraction: service_water_fraction_latent)

      # Water heater sizing
      case swh_system_type
      when 'One Per Unit'
        water_heater_capacity_w = num_units * OpenStudio.convert(20.0, 'kBtu/hr', 'W').get
        water_heater_volume_m3 = num_units * OpenStudio.convert(50.0, 'gal', 'm^3').get
        num_water_heaters = num_units
      else
        water_use_equips = [water_use_equip]
        water_use_equips << booster_water_use_equip unless booster_water_use_equip.nil? # Include booster in sizing since flows will be preheated by main water heater
        water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(water_use_equips)
        water_heater_capacity_w = water_heater_sizing[:water_heater_capacity]
        water_heater_volume_m3 = water_heater_sizing[:water_heater_volume]
        num_water_heaters = 1
      end

      # Add either a dedicated SWH loop or save to add to shared SWH loop
      case swh_system_type
      when 'Shared'

        # Store water use equip by building type to add to shared building hot water loop
        if water_use_equipment_hash.key?(stds_bldg_type)
          water_use_equipment_hash[stds_bldg_type] << water_use_equip
        else
          water_use_equipment_hash[stds_bldg_type] = [water_use_equip]
        end

      when 'One Per Unit', 'Dedicated'
        pipe_insul_in = 0.0 if pipe_insul_in.nil?

        # Add service water loop with water heater
        swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                              system_name: "#{space_type.name} Service Water Loop",
                                                                                              service_water_temperature: service_water_temperature_c,
                                                                                              service_water_pump_head: 0.01,
                                                                                              service_water_pump_motor_efficiency: 1.0,
                                                                                              water_heater_capacity: water_heater_capacity_w,
                                                                                              water_heater_volume: water_heater_volume_m3,
                                                                                              water_heater_fuel: water_heater_fuel,
                                                                                              number_of_water_heaters: num_water_heaters,
                                                                                              add_piping_losses: true,
                                                                                              pipe_insulation_thickness: OpenStudio.convert(pipe_insul_in, 'in', 'm').get,
                                                                                              floor_area: OpenStudio.convert(950, 'ft^2', 'm^2').get,
                                                                                              number_of_stories: 1)

        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "In model_add_typical, num_water_heaters = #{num_water_heaters}")
        # Add loop to list
        swh_systems << swh_loop

        # Attach water use equipment to the loop
        swh_connection = water_use_equip.waterUseConnections
        swh_loop.addDemandBranchForComponent(swh_connection.get) if swh_connection.is_initialized

        # If a booster fraction is specified, some percentage of the water
        # is assumed to be heated beyond the normal temperature by a separate
        # booster water heater.  This booster water heater is fed by the
        # main water heater, so the booster is responsible for a smaller delta-T.
        if booster_water_heater_fraction > 0
          # find_water_heater_capacity_volume_and_parasitic
          booster_water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment([booster_water_use_equip],
                                                                                                                              water_heater_efficiency: 1.0,
                                                                                                                              inlet_temperature: service_water_temperature_f,
                                                                                                                              supply_temperature: booster_water_temperature_f)

          # Add service water booster loop with water heater
          # Note that booster water heaters are always assumed to be electric resistance
          swh_booster_loop = OpenstudioStandards::ServiceWaterHeating.create_booster_water_heating_loop(model,
                                                                                                        water_heater_capacity: booster_water_heater_sizing[:water_heater_capacity],
                                                                                                        service_water_temperature: booster_water_temperature_c,
                                                                                                        service_water_loop: swh_loop)

          # Rename the service water booster loop
          swh_booster_loop.setName("#{space_type.name} Service Water Booster Loop")

          # Attach booster water use equipment to the booster loop
          booster_swh_connection = booster_water_use_equip.waterUseConnections
          swh_booster_loop.addDemandBranchForComponent(booster_swh_connection.get) if booster_swh_connection.is_initialized
        end

      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "'#{swh_system_type}' is not a valid Service Water Heating System Type, cannot add SWH to #{space_type.name}.  Valid choices are One Per Unit, Dedicated, and Shared.")
      end
    end

    # get building floor area and effective number of stories
    bldg_floor_area_m2 = model.getBuilding.floorArea
    bldg_effective_num_stories_hash = model_effective_num_stories(model)
    bldg_effective_num_stories = bldg_effective_num_stories_hash[:below_grade] + bldg_effective_num_stories_hash[:above_grade]

    # add non-dedicated system(s) here. Separate systems for water use equipment from different building types
    water_use_equipment_hash.sort.each do |stds_bldg_type, water_use_equipment_array|
      # @todo find the water use equipment with the highest temperature
      water_heater_temp_f = 140.0
      water_heater_temp_c = OpenStudio.convert(water_heater_temp_f, 'F', 'C').get

      # find pump values
      # Table A.2 in PrototypeModelEnhancements_2014_0.pdf shows 10ft on everything except SecondarySchool which has 11.4ft
      # @todo Remove hard-coded building-type-based lookups for circulating vs. non-circulating SWH systems
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
      if circulating_bldg_types.include?(stds_bldg_type)
        service_water_pump_head_pa = OpenStudio.convert(10.0, 'ftH_{2}O', 'Pa').get
        service_water_pump_motor_efficiency = 0.3
        circulating = true if circulating.nil?
        pipe_insul_in = 0.5 if pipe_insul_in.nil?
      else # values for non-circulating pump
        service_water_pump_head_pa = 0.01
        service_water_pump_motor_efficiency = 1.0
        circulating = false if circulating.nil?
        pipe_insul_in = 0.0 if pipe_insul_in.nil?
      end

      bldg_type_floor_area_m2 = 0.0
      space_type_hash.sort.each do |space_type, space_type_props|
        bldg_type_floor_area_m2 += space_type_props[:floor_area] if space_type_props[:stds_bldg_type] == stds_bldg_type
      end

      # Calculate the number of stories covered by this building type
      num_stories = bldg_effective_num_stories * (bldg_type_floor_area_m2 / bldg_floor_area_m2)

      # Water heater sizing
      water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(water_use_equipment_array)
      water_heater_capacity_w = water_heater_sizing[:water_heater_capacity]
      water_heater_volume_m3 = water_heater_sizing[:water_heater_volume]

      # Add a shared service water heating loop with water heater
      shared_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                   system_name: "#{stds_bldg_type} Shared Service Water Loop",
                                                                                                   service_water_temperature: water_heater_temp_c,
                                                                                                   service_water_pump_head: service_water_pump_head_pa,
                                                                                                   service_water_pump_motor_efficiency: service_water_pump_motor_efficiency,
                                                                                                   water_heater_capacity: water_heater_capacity_w,
                                                                                                   water_heater_volume: water_heater_volume_m3,
                                                                                                   water_heater_fuel: water_heater_fuel,
                                                                                                   add_piping_losses: true,
                                                                                                   pipe_insulation_thickness: OpenStudio.convert(pipe_insul_in, 'in', 'm').get,
                                                                                                   floor_area: bldg_type_floor_area_m2,
                                                                                                   number_of_stories: num_stories)

      # Attach all water use equipment to the shared loop
      water_use_equipment_array.sort.each do |water_use_equip|
        swh_connection = water_use_equip.waterUseConnections
        shared_swh_loop.addDemandBranchForComponent(swh_connection.get) if swh_connection.is_initialized
      end

      # add to list of systems
      swh_systems << shared_swh_loop

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Adding shared water heating loop for #{stds_bldg_type}.")
    end

    return swh_systems
  end
end
