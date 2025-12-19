class BTAPData
  attr_accessor :osa_file
  attr_accessor :osw_file
  attr_accessor :osm_file
  attr_accessor :sqlite_file
  attr_accessor :btap_data

  def initialize(
    model:, 
    runner: nil, 
    cost_result:, 
    carbon_result:,
    baseline_cost_equipment_total_cost_per_m_sq: -1.0,
    baseline_cost_utility_neb_total_cost_per_m_sq: -1.0, 
    baseline_energy_eui_total_gj_per_m_sq: -1.0, 
    qaqc:,
    npv_start_year: 2022, 
    npv_end_year: 2041, 
    npv_discount_rate: 0.03, 
    npv_discount_rate_carbon: 0.03, 
    oerd_utility_pricing: nil,
    utility_pricing_year: 2020)

    @model = model
    @error_warning = []
    # sets sql file.
    set_sql_file(model.sqlFile)
    @standard = Standard.build('NECB2011')
    @standards_data = @standard.load_standards_database_new()
    @btap_data = {}
    @btap_results_version = 1.00
    @neb_prices_csv_file_name = File.join(__dir__, 'neb_end_use_prices.csv')
    @neb_prices_csv_file_name = File.join(__dir__, 'utility_pricing_2025-02-20.csv') if oerd_utility_pricing.to_bool
    @necb_reference_runs_csv_file_name = File.join(__dir__, 'necb_reference_runs.csv')
    @eccc_ghg_electricity = File.join(__dir__, 'eccc_electric_grid_intensity_20250311.csv') #REF (Retrieved March 11, 2025) for ECCC's emissions factors for the current and future years for GHG "without Biomass and RNG CO2 emissions": https://data-donnees.az.ec.gc.ca/data/substances/monitor/canada-s-greenhouse-gas-emissions-projections/Current-Projections-Actuelles/Energy-Energie/AM%20Scenario%20AMS/Grid-O%26G-Intensities-Intensites-Reseau-Delectricite-P%26G?lang=en
    @nir_ghg_gas = File.join(__dir__, 'nir_gas_grid_intensity_20250311.csv') #REF (Retrieved March 11, 2025) for Year 2022 of "Table A6.1–1 CO2 Emission Factors for Marketable Natural Gas" of National Inventory Report: https://data-donnees.az.ec.gc.ca/api/file?path=%2Fsubstances%2Fmonitor%2Fcanada-s-official-greenhouse-gas-inventory%2FD-Emission-Factors%2FEN_Annex6_Emission_Factors.pdf

    # Conditioned floor area is used so much. May as well make it a object variable.
    # setup the queries
    command = "SELECT Value
                  FROM TabularDataWithStrings
                  WHERE ReportName='AnnualBuildingUtilityPerformanceSummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Building Area'
                  AND RowName = 'Net Conditioned Building Area'
                  AND ColumnName='Area'"
    area = @sqlite_file.get.execAndReturnFirstDouble(command)
    # make sure all the data are available
   if area.empty?
     @conditioned_floor_area_m_sq = 0.0
   else
     @conditioned_floor_area_m_sq = area.get
   end


    @btap_data['simulation_btap_data_version'] = '0.1'
    # @btap_data["simulation_openstudio_version"] = open("| \"#{OpenStudio.getOpenStudioCLI}\" openstudio_version").read().strip
    # @btap_data["simulation_energyplus_version"] = open("| \"#{OpenStudio.getOpenStudioCLI}\" energyplus_version").read().strip
    @btap_data['simulation_os_standards_revision'] = OpenstudioStandards.git_revision
    @btap_data['simulation_os_standards_version'] = OpenstudioStandards::VERSION
    @btap_data['simulation_date'] = Time.now
    @btap_data.merge!(building_data)
    @btap_data.merge!(building_costing_data(cost_result)) unless cost_result.nil?
    @btap_data.merge!(climate_data)
    @btap_data.merge!(service_water_heating_data)
    @btap_data.merge!(energy_eui_data(model))
    @btap_data.merge!(energy_peak_data)
    @btap_data.merge!(utility(model: model, utility_pricing_year: utility_pricing_year))
    @btap_data.merge!(unmet_hours(model))
    @btap_data.merge!outdoor_air_data(model)

    # Data in tables...
    @btap_data.merge!('measures_data_table' => measures_data_table(runner)) unless runner.nil?
    @btap_data.merge!('envelope_exterior_surface_table' => envelope_exterior_surface_table)
    @btap_data.merge!('space_table' => space_table(model, cost_result))
    @btap_data.merge!('space_type_table' => space_type_table(model))
    # This does not work with the new VRF or CCASHP systems. Commenting it for now.
    # @btap_data.merge!({'zone_table' => thermal_zones_table(model, cost_result)['table']})
    @btap_data.merge!('zone_equip_table' => thermal_zones_equipment_table(model))
    # This does not work with the new VRF or CCASHP systems. Commenting it for now.
    # @btap_data.merge!({'air_loop_table' => air_loops_table(model, cost_result)})
    # @btap_data.merge!({'sql_raw_data' => sql_data_tables(model)})
    @btap_data.merge!('eplusout_err_table' => eplusout_err_table(model))

    # Remainder of costing data in separate tables:
    @btap_data.merge!('envelope_construction_cost_table' => cost_result['envelope']['construction_costs']) unless cost_result.nil?
    @btap_data.merge!('lighting_fixture_cost_table' => cost_result['lighting']['fixture_report']) unless cost_result.nil?
    ideal_air = true
    model.getThermalZones.each do |zone|
      ideal_air = false if zone.useIdealAirLoads == false
    end
    unless ideal_air
      @btap_data.merge!('h_and_c_plant_equipment_cost_table' => cost_result['heating_and_cooling']['plant_equipment']) unless cost_result.nil?
      @btap_data.merge!('h_and_c_plant_zonal_systems_cost_table' => cost_result['heating_and_cooling']['zonal_systems']) unless cost_result.nil?
      # This does not work with the new VRF or CCASHP systems. Commenting it for now.
      # @btap_data.merge!('system_coils_cost_table' => coil_cost_table(cost_result))
      # This does not work with the new VRF or CCASHP systems. Commenting it for now.
      # @btap_data.merge!('terminal_VAV_cost_table' => terminal_VAV_cost_table(cost_result))
      # This does not work with the new VRF or CCASHP systems. Commenting it for now.
      # @btap_data.merge!('trunk_ducts_cost_table' => trunk_ducts_cost_table(cost_result))
    end
    # calculate energy demands and peak loads calculations as per PHIUS and NECB and compare them
    phius_performance_indicators(model)
    # The below method calculates energy performance indicators (i.e. TEDI and MEUI) as per BC Energy Step Code
    bc_energy_step_code_performance_indicators
        # calculates annual peak electricity cost (dollar)
    annual_peak_kW_per_m_sq = oerd_electricity_cost(model: model, utility_pricing_year: utility_pricing_year, oerd_utility_pricing: oerd_utility_pricing)
    # calculate net present value
    net_present_value(npv_start_year: npv_start_year, npv_end_year: npv_end_year, npv_discount_rate: npv_discount_rate, npv_discount_rate_carbon: npv_discount_rate_carbon, oerd_utility_pricing: oerd_utility_pricing, annual_peak_kW_per_m_sq: annual_peak_kW_per_m_sq) unless cost_result.nil?

    measure_metrics(qaqc)
    @btap_data
  end

  # Oct-2019 JTB: This function must be passed a hash and will flatten mixtures of hashes
  # and arrays of hashes. Embedded arrays are enumerated (starting at 1).
  def flatten_mix(hash)
    hash.each_with_object({}) do |(k, v), h|
      if v.is_a?(Hash)
        flatten_mix(v).map do |h_k, h_v|
          h["#{k}.#{h_k}".to_sym] = h_v
        end
      elsif v.is_a?(Array)
        v.map.with_index do |e, ndx|
          if e.is_a?(Hash)
            flatten_mix(e).map do |e_k, e_v|
              h["#{k}.#{e_k}.#{ndx + 1}".to_sym] = e_v
            end
            # if there is another array within the array v, flatten more
            # but this is as deep as we go with embedded arrays!
          elsif e.is_a?(Array)
            e.map.with_index do |e1, ndx1|
              if e1.is_a?(Hash)
                flatten_mix(e1).map do |e1_k, e1_v|
                  h["#{k}.#{e1_k}.#{ndx1 + 1}".to_sym] = e1_v
                end
              else
                # Stop flattening here!
                h[k] = v
              end
            end
          else
            h[k] = v
          end
        end
      else
        h[k] = v
      end
    end
  end

  # General Building Data that there is alway either zero of 1 of.
  def building_data
    # Store Building data.
    building_data = {}
    building_data['bldg_name'] = @model.building.get.name.get
    building_data['bldg_conditioned_floor_area_m_sq'] = @conditioned_floor_area_m_sq
    building_data['bldg_exterior_area_m_sq'] = @model.building.get.exteriorSurfaceArea # m_sq
    building_data['bldg_volume_m_cu'] = @model.building.get.airVolume # m_cu
    building_data['bldg_standards_template'] = @model.building.get.standardsTemplate.empty? ? nil : @model.building.get.standardsTemplate.get
    building_data['bldg_standards_building_type'] = @model.building.get.standardsBuildingType.empty? ? nil : @model.building.get.standardsBuildingType.get
    building_data['bldg_standards_number_of_stories'] = @model.building.get.standardsNumberOfStories.empty? ? nil : @model.building.get.standardsNumberOfStories.get
    building_data['bldg_standards_number_of_above_ground_stories'] = @model.building.get.standardsNumberOfAboveGroundStories.empty? ? nil : @model.building.get.standardsNumberOfAboveGroundStories.get
    building_data['bldg_standards_number_of_living_units'] = @model.building.get.standardsNumberOfLivingUnits.empty? ? nil : @model.building.get.standardsNumberOfAboveGroundStories.get
    building_data['bldg_nominal_floor_to_ceiling_height'] = @model.building.get.nominalFloortoCeilingHeight.empty? ? nil : @model.building.get.nominalFloortoCeilingHeight.get
    building_data['bldg_nominal_floor_to_floor_height'] = @model.building.get.nominalFloortoFloorHeight.empty? ? nil : @model.building.get.nominalFloortoFloorHeight.get
    building_data['bldg_surface_to_volume_ratio'] = @model.building.get.exteriorSurfaceArea / @model.building.get.airVolume
    building_data['bldg_fdwr'] = (BTAP::Geometry.get_fwdr(@model) * 100.0).round(1)
    building_data['bldg_srr'] = (BTAP::Geometry.get_srr(@model) * 100.0).round(1)

    return building_data
  end

  def building_costing_data(cost_result)
    building_data = {}
    building_data['cost_province_state'] = cost_result['province_state']
    building_data['cost_city'] = cost_result['city']
    building_data['cost_equipment_envelope_total_cost_per_m_sq'] = (cost_result['totals']['envelope']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_thermal_bridging_total_cost_per_m_sq'] = (cost_result['totals']['thermal_bridging']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_lighting_total_cost_per_m_sq'] = (cost_result['totals']['lighting']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_heating_and_cooling_total_cost_per_m_sq'] = (cost_result['totals']['heating_and_cooling']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_shw_total_cost_per_m_sq'] = (cost_result['totals']['shw']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_ventilation_total_cost_per_m_sq'] = (cost_result['totals']['ventilation']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_renewables_total_cost_per_m_sq'] = (cost_result['totals']['renewables']) / @conditioned_floor_area_m_sq
    building_data['cost_equipment_total_cost_per_m_sq'] = (cost_result['totals']['grand_total']) / @conditioned_floor_area_m_sq
    # building_data.merge!(cost_result['envelope'].select{|k,v| k!='construction_costs' && k!='total_envelope_cost'})
    # building_data.merge!(cost_result['shw'].select{|k,v| k!='shw_total'})
    # building_data.merge!(flatten_mix(cost_result['ventilation'].select{|k,v| k=='mech_to_roof'.to_sym}))
    return building_data
  end

  def net_present_value(npv_start_year: 2022, npv_end_year: 2041, npv_discount_rate: 0.03, npv_discount_rate_carbon: 0.03, oerd_utility_pricing: false, annual_peak_kW_per_m_sq: nil)

    # Find end year in the neb data
    neb_header = CSV.read(@neb_prices_csv_file_name, headers: true).headers
    neb_header.delete_if { |item| ["building_type", "province", "fuel_type"].include?(item) } # remove "building_type", "province", "fuel_type" from neb_header in order to have only years in neb_header
    neb_header.delete_if { |item| ["rate_class", "units", "references", "links"].include?(item) } if oerd_utility_pricing # remove additional headers if the OERD data is used
    neb_header.map(&:to_f)  #convert years to float
    year_max = neb_header.max

    # Convert a string to a float
    if npv_start_year.instance_of?(String) && npv_start_year != 'NECB_Default' && npv_start_year != 'none' && !npv_start_yeay.nil?
      npv_start_year = npv_start_year.to_f
    end
    if npv_end_year.instance_of?(String) && npv_end_year != 'NECB_Default' && npv_end_year != 'none' && !npv_end_year.nil?
      npv_end_year = npv_end_year.to_f
    end
    if npv_discount_rate.instance_of?(String) && npv_discount_rate != 'NECB_Default' && npv_discount_rate != 'none' && !npv_discount_rate.nil?
      npv_discount_rate = npv_discount_rate.to_f
    end
    if npv_discount_rate_carbon.instance_of?(String) && npv_discount_rate_carbon != 'NECB_Default' && npv_discount_rate_carbon != 'none' && !npv_discount_rate_carbon.nil?
      npv_discount_rate_carbon = npv_discount_rate_carbon.to_f
    end


    # Set default npv_start_year as 2022, npv_end_year as 2041, npv_discount_rate as 3%
    if npv_start_year == 'NECB_Default' || npv_start_year.nil? || npv_start_year == 'none'
      npv_start_year = 2022
    end
    if npv_end_year == 'NECB_Default' || npv_end_year.nil? || npv_end_year == 'none'
      npv_end_year = 2041
    end
    if npv_discount_rate == 'NECB_Default' || npv_discount_rate.nil? || npv_discount_rate == 'none'
      npv_discount_rate = 0.03
    end
    if npv_discount_rate_carbon == 'NECB_Default' || npv_discount_rate_carbon.nil? || npv_discount_rate_carbon == 'none'
      npv_discount_rate_carbon = 0.03
    end

    # Set npv_end_year as year_max if users' input > neb's end year
    if npv_end_year > year_max.to_f
      npv_end_year = year_max.to_f
      warn "WARNING: Your npv_end_year for the calculation of net present value is larger than that in Canada Energy Regulator (CER) (i.e. #{year_max}). So, npv_end_year has been reset as #{year_max}."
    end
    # puts "npv_start_year is #{npv_start_year}"
    # puts "npv_end_year is #{npv_end_year}"
    # puts "npv_discount_rate is #{npv_discount_rate}"

    # Get energy end-use prices (CER data from https://apps.cer-rec.gc.ca/ftrppndc/dflt.aspx?GoCTemplateCulture=en-CA)
    # @neb_prices_csv_file_name = "#{File.dirname(__FILE__)}/neb_end_use_prices.csv"

    # Create a hash of the neb data.
    neb_data = CSV.parse(File.read(@neb_prices_csv_file_name), headers: true, converters: :numeric).map(&:to_h)

    # Create a hash of the ECCC's electricity emissions factors for the current and future years for GHG "without Biomass and RNG CO2 emissions".
    eccc_ghg_elec_emission_factors = CSV.parse(File.read(@eccc_ghg_electricity), headers: true, converters: :numeric).map(&:to_h)

    # Find which province the proposed building is located in
    building_type = 'Commercial'
    geography_data = climate_data
    province_abbreviation = geography_data['location_state_province_region']
    province = @standards_data['province_map'][province_abbreviation]

    # Note: If there is on-site energy generation (e.g. PV), it should be considered in the calculation of EUI for the calculation of energy use cost and NPV.
    # To do so, it has been assumed that on-site energy generation is only for electricity.
    # Electricity EUI of a building is re-calculated for NPV. It will be: ['energy_eui_electricity_gj_per_m_sq' - ('total_site_eui_gj_per_m_sq' - 'net_site_eui_gj_per_m_sq')]
    # Note that if there is no on-site energy generation, 'total_site_eui_gj_per_m_sq' and 'net_site_eui_gj_per_m_sq' will be equal.
    # Note: 'total_site_eui_gj_per_m_sq' is the gross energy consumed by the building (REF: https://unmethours.com/question/25416/what-is-the-difference-between-site-energy-and-source-energy/)
    # Note: 'net_site_eui_gj_per_m_sq' is the final energy consumed by the building after accounting for on-site energy generations (e.g. PV) (REF: https://unmethours.com/question/25416/what-is-the-difference-between-site-energy-and-source-energy/)

    # Calculate npv of electricity
    onsite_elec_generation = @btap_data['total_site_eui_gj_per_m_sq'] - @btap_data['net_site_eui_gj_per_m_sq']
    if onsite_elec_generation > 0.0
      eui_elec = @btap_data['energy_eui_electricity_gj_per_m_sq'] - onsite_elec_generation
    else
      eui_elec = @btap_data['energy_eui_electricity_gj_per_m_sq']
    end
    # Find the appropriate row for electricity GHG emmission factors
    row_emm_factor = eccc_ghg_elec_emission_factors.detect do |data|
      (data['province'] == province)
    end
    # Find the appropriate row for electricity pricing
    row = neb_data.detect do |data|
      (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Electricity')
    end
    row_peak = nil
    if oerd_utility_pricing && !annual_peak_kW_per_m_sq.nil?
      row_peak = neb_data.detect do |data|
        (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Electricity Peak')
      end
    end
    npv_elec = 0.0
    year_index = 1.0
    npv_elec_ghg = 0.0
    npv_elec_peak = 0.0
    emm_factor_conv = 3600.0 #GWH to GJ
    if eui_elec > 0.0
      for year in npv_start_year.to_int..npv_end_year.to_int
        npv_elec += (eui_elec * row[year.to_s]) / (1+npv_discount_rate)**year_index
        npv_elec_ghg += (((eui_elec * row_emm_factor[year.to_i.to_s].to_f) / emm_factor_conv) * get_national_ghg_cost(year: year.to_i)) / (1+npv_discount_rate_carbon)**year_index
        npv_elec_peak += (annual_peak_kW_per_m_sq * row_peak[year.to_i.to_s]).to_f / (1+npv_discount_rate)**year_index unless row_peak.nil? || annual_peak_kW_per_m_sq.nil?
        year_index += 1.0
      end
    end

    # Calculate npv of natural gas
    eui_ngas= @btap_data['energy_eui_natural_gas_gj_per_m_sq']
    # Convert to tonnes of ghg/m^2
    ghg_ngas = @btap_data['cost_utility_ghg_natural gas_kg_per_m_sq'].to_f/1000.0
    row = neb_data.detect do |data|
      (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Natural Gas')
    end
    npv_ngas = 0.0
    npv_ngas_ghg = 0.0
    year_index = 1.0
    for year in npv_start_year.to_int..npv_end_year.to_int
      npv_ngas += (eui_ngas * row[year.to_s]) / (1+npv_discount_rate)**year_index
      npv_ngas_ghg += (ghg_ngas * get_national_ghg_cost(year: year.to_i)) / (1+npv_discount_rate_carbon)**year_index
      year_index += 1.0
    end
    # puts "npv_ngas is #{npv_ngas}"

    # Calculate npv of oil
    eui_oil= @btap_data['energy_eui_additional_fuel_gj_per_m_sq']
    # Convert to tonnes of ghg/m^2
    ghg_oil = @btap_data['cost_utility_ghg_oil_kg_per_m_sq'].to_f/1000.0
    row = neb_data.detect do |data|
      (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Oil')
    end
    npv_oil = 0.0
    npv_oil_ghg = 0.0
    year_index = 1.0
    for year in npv_start_year.to_int..npv_end_year.to_int
      npv_oil += (eui_oil * row[year.to_s]) / (1+npv_discount_rate)**year_index
      npv_oil_ghg += (ghg_oil * get_national_ghg_cost(year: year.to_i)) / (1+npv_discount_rate_carbon)**year_index
      year_index += 1.0
    end
    # puts "npv_oil is #{npv_oil}"

    # Calculate total npv
    npv_total = @btap_data['cost_equipment_total_cost_per_m_sq'] + npv_elec + npv_ngas + npv_oil
    npv_ghg_total = npv_elec_ghg + npv_ngas_ghg + npv_oil_ghg
    npv_total_with_ghg_and_peak = npv_ghg_total + npv_total + npv_elec_peak
    @btap_data.merge!('npv_total_per_m_sq' => npv_total)
    @btap_data.merge!('npv_carbon_pricing_per_m_sq' => npv_ghg_total)
    @btap_data.merge!('npv_peak_elec_per_m_sq' => npv_elec_peak)
    @btap_data.merge!('npv_with_carbon_and_peak_pricing_total_per_m_sq' => npv_total_with_ghg_and_peak)
  end

  def envelope(model)
    data = {}
    # Get OSM surface information
    surfaces = model.getSurfaces.sort
    interior_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(surfaces, ['Surface', 'Adiabatic'])
    interior_floors = BTAP::Geometry::Surfaces.filter_by_surface_types(interior_surfaces, 'Floor')
    outdoor_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(surfaces, 'Outdoors')
    outdoor_walls = BTAP::Geometry::Surfaces.filter_by_surface_types(outdoor_surfaces, 'Wall')
    outdoor_roofs = BTAP::Geometry::Surfaces.filter_by_surface_types(outdoor_surfaces, 'RoofCeiling')
    outdoor_floors = BTAP::Geometry::Surfaces.filter_by_surface_types(outdoor_surfaces, 'Floor')
    outdoor_subsurfaces = outdoor_surfaces.flat_map(&:subSurfaces)
    ground_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(surfaces, ['Ground', 'Foundation'])
    ground_walls = BTAP::Geometry::Surfaces.filter_by_surface_types(ground_surfaces, 'Wall')
    ground_roofs = BTAP::Geometry::Surfaces.filter_by_surface_types(ground_surfaces, 'RoofCeiling')
    ground_floors = BTAP::Geometry::Surfaces.filter_by_surface_types(ground_surfaces, 'Floor')
    windows = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(outdoor_subsurfaces, ['FixedWindow', 'OperableWindow'])
    skylights = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(outdoor_subsurfaces, ['Skylight', 'TubularDaylightDiffuser', 'TubularDaylightDome'])
    doors = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(outdoor_subsurfaces, ['Door', 'GlassDoor'])
    overhead_doors = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(outdoor_subsurfaces, ['OverheadDoor'])

    # Get Areas
    data['outdoor_walls_area_m_sq'] = outdoor_walls.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['outdoor_roofs_area_m_sq'] = outdoor_roofs.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['outdoor_floors_area_m_sq'] = outdoor_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['ground_walls_area_m_sq'] = ground_walls.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['ground_roofs_area_m_sq'] = ground_roofs.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['ground_floors_area_m_sq'] = ground_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    data['interior_floors_area_m_sq'] = interior_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }

    # Subsurface areas
    data['windows_area_m_sq'] = windows.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    data['skylights_area_m_sq'] = skylights.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    data['doors_area_m_sq'] = doors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    data['overhead_doors_area_m_sq'] = overhead_doors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }

    # Total Building Ground Surface Area.
    data['total_ground_area_m_sq'] = data['ground_walls_area_m_sq'] +
                                     data['ground_roofs_area_m_sq'] +
                                     data['ground_floors_area_m_sq']
    # Total Building Outdoor Surface Area.
    data['total_outdoor_area_m_sq'] = data['outdoor_walls_area_m_sq'] +
                                      data['outdoor_roofs_area_m_sq'] +
                                      data['outdoor_floors_area_m_sq'] +
                                      data['windows_area_m_sq'] +
                                      data['skylights_area_m_sq'] +
                                      data['doors_area_m_sq'] +
                                      data['overhead_doors_area_m_sq']

    # Average Conductances by surface Type
    data['outdoor_walls_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_walls).round(4) if !outdoor_walls.empty?
    data['outdoor_roofs_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_roofs).round(4) if !outdoor_roofs.empty?
    data['outdoor_floors_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_floors).round(4) if !outdoor_floors.empty?
    data['ground_walls_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_walls).round(4) if !ground_walls.empty?
    data['ground_roofs_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_roofs).round(4) if !ground_roofs.empty?
    data['ground_floors_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_floors).round(4) if !ground_floors.empty?
    data['windows_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(windows).round(4) if !windows.empty?
    data['skylights_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(skylights).round(4) if !skylights.empty?
    data['doors_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(doors).round(4) if !doors.empty?
    data['overhead_doors_average_conductance_w_per_m_sq_k'] = OpenstudioStandards::Constructions.surfaces_get_conductance(overhead_doors).round(4) if !overhead_doors.empty?

    # #Average Conductances for building whole weight factors
    !outdoor_walls.empty? ? o_wall_cond_weight = data['outdoor_walls_average_conductance_w_per_m_sq_k'] * data['outdoor_walls_area_m_sq'] : o_wall_cond_weight = 0
    !outdoor_roofs.empty? ? o_roof_cond_weight = data['outdoor_roofs_average_conductance_w_per_m_sq_k'] * data['outdoor_roofs_area_m_sq'] : o_roof_cond_weight = 0
    !outdoor_floors.empty? ? o_floor_cond_weight = data['outdoor_floors_average_conductance_w_per_m_sq_k'] * data['outdoor_floors_area_m_sq'] : o_floor_cond_weight = 0
    !ground_walls.empty? ? g_wall_cond_weight = data['ground_walls_average_conductance_w_per_m_sq_k'] * data['ground_walls_area_m_sq'] : g_wall_cond_weight = 0
    !ground_roofs.empty? ? g_roof_cond_weight = data['ground_roofs_average_conductance_w_per_m_sq_k'] * data['ground_roofs_area_m_sq'] : g_roof_cond_weight = 0
    !ground_floors.empty? ? g_floor_cond_weight = data['ground_floors_average_conductance_w_per_m_sq_k'] * data['ground_floors_area_m_sq'] : g_floor_cond_weight = 0
    !windows.empty? ? win_cond_weight = data['windows_average_conductance_w_per_m_sq_k'] * data['windows_area_m_sq'] : win_cond_weight = 0
    # doors.size > 0 ? sky_cond_weight = data["skylights_average_conductance_w_per_m_sq_k"] * data["skylights_area_m_sq"] : sky_cond_weight = 0
    if !doors.empty? && !data['skylights_average_conductance_w_per_m_sq_k'].nil? && !data['skylights_area_m_sq'].nil?
      sky_cond_weight = data['skylights_average_conductance_w_per_m_sq_k'] * data['skylights_area_m_sq']
    else
      sky_cond_weight = 0
    end
    !overhead_doors.empty? ? door_cond_weight = data['doors_average_conductance_w_per_m_sq_k'] * data['doors_area_m_sq'] : door_cond_weight = 0
    !overhead_doors.empty? ? overhead_door_cond_weight = data['overhead_doors_average_conductance_w_per_m_sq_k'] * data['overhead_doors_area_m_sq'] : overhead_door_cond_weight = 0

    # Building Average Conductance
    data['outdoor_average_conductance_w_per_m_sq_k'] = (
    o_floor_cond_weight +
        o_roof_cond_weight +
        o_wall_cond_weight +
        win_cond_weight +
        sky_cond_weight +
        door_cond_weight +
        overhead_door_cond_weight) / data['total_outdoor_area_m_sq']

    # Building Average Ground Conductance
    data['ground_average_conductance_w_per_m_sq_k'] = (
    g_floor_cond_weight +
        g_roof_cond_weight +
        g_wall_cond_weight) / data['total_ground_area_m_sq']

    # Building Average Conductance
    data['average_conductance_w_per_m_sq_k'] = (
    (data['average_conductance_w_per_m_sq_k'] * data['total_ground_area_m_sq']) +
        (data['outdoor_average_conductance_w_per_m_sq_k'] * data['total_outdoor_area_m_sq'])
  ) /
                                               (data['total_ground_area_m_sq'] + data['total_outdoor_area_m_sq'])
    prefix = 'envel_'
    return Hash[data.map { |k, v| ["#{prefix}_#{k}", v] }]
  end

  def envelope_summary(qaqc)
    @btap_data['envelope-outdoor_walls_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k]
    @btap_data['envelope-outdoor_roofs_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k]
    @btap_data['envelope-outdoor_floors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k]
    @btap_data['envelope-ground_walls_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k]
    @btap_data['envelope-ground_roofs_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k]
    @btap_data['envelope-ground_floors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k]
    @btap_data['envelope-outdoor_windows_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:windows_average_conductance_w_per_m2_k]
    @btap_data['envelope-outdoor_doors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:doors_average_conductance_w_per_m2_k]
    @btap_data['envelope-outdoor_overhead_doors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k]
    @btap_data['envelope-skylights_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:skylights_average_conductance_w_per_m2_k]
  end

  def envelope_exterior_surface_table
    surfaces = @model.getSurfaces.sort
    outdoor_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(surfaces, 'Outdoors')
    ground_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(surfaces, ['Ground', 'Foundation'])
    exterior_opaque_surfaces = outdoor_surfaces + ground_surfaces
    # outdoor_surfaces.each { |surface| puts surface.name}
    # get surface table from sql
    table = get_sql_table_to_json(@model, 'EnvelopeSummary', 'Entire Facility', 'Opaque Exterior')
    raise('Could not get opaque surface table from E+ sql') if table.empty?

    # add space name to table.
    table['table'].each do |row|
      surface = exterior_opaque_surfaces.detect { |curr_surface| curr_surface.name.get.downcase == row['name'].downcase }
      raise("Could not find surface  #{row['name'].downcase} in #{outdoor_surfaces.map { |curr_surface| curr_surface.name.get.downcase }}") if surface.nil?

      row['os_type'] = surface.surfaceType
      row['boundary_condition'] = surface.outsideBoundaryCondition
      space_includes_surface = @model.getSpaces.detect { |space| space.surfaces.include?(surface) }
      row['space_name'] = space_includes_surface.nil? || !space_includes_surface.name.is_initialized ? 'NA' : space_includes_surface.name.get
    end
    opaque = table

    # Fenestrations
    fenestrations = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(@model.getSubSurfaces.sort, ['GlassDoor', 'FixedWindow', 'OperableWindow', 'Skylight', 'TubularDaylightDiffuser', 'TubularDaylightDome'])
    # get surface table from sql
    table = get_sql_table_to_json(@model, 'EnvelopeSummary', 'Entire Facility', 'Exterior Fenestration')
    # Exclude totals and averages by deleting row with that in their name.
    table['table'].delete_if { |row| !!(row['name'] =~ /Total|Average/) }
    raise('Could not get fenestration surface table from E+ sql') if table.empty?

    # add space name to table.
    table['table'].each do |row|
      subsurface = fenestrations.detect { |surface| surface.name.get.downcase == row['name'].downcase }
      raise("Could not find surface  #{row['name'].downcase} in #{fenestrations.map { |surface| surface.name.get.downcase }}") if subsurface.nil?

      row['os_type'] = subsurface.subSurfaceType
      row['boundary_condition'] = subsurface.outsideBoundaryCondition
      parent_surface = subsurface.surface.get
      space_includes_surface = @model.getSpaces.detect { |space| space.surfaces.include?(parent_surface) }
      row['space_name'] = space_includes_surface.nil? || !space_includes_surface.name.is_initialized ? 'NA' : space_includes_surface.name.get
    end
    glazing = table

    # return as a single table.

    return glazing['table'] + opaque['table']
  end

  def space_table(model, cost_result)
    # Store Space data.
    table = []
    model.getSpaces.sort.each do |space|
      spaceinfo = {}
      table << spaceinfo
      spaceinfo['thermal_zone_name'] = space.thermalZone.empty? ? 'None' : space.thermalZone.get.name.get # should be assigned a thermalzone name.
      spaceinfo['space_name'] = space.name.get # name should be defined test
      spaceinfo['multiplier'] = space.multiplier
      spaceinfo['volume'] = space.volume # should be greater than zero
      spaceinfo['exterior_wall_area'] = space.exteriorWallArea # just for information.
      spaceinfo['space_type_name'] = space.spaceType.get.name.get unless space.spaceType.empty? # should have a space types name defined.
      spaceinfo['breathing_zone_outdoor_airflow_vbz'] = -1
      spaceinfo['infiltration_flow_per_m_sq'] = space.infiltrationDesignFlowPerExteriorSurfaceArea
      spaceinfo['floor_area_m2'] = space.floorArea
      spaceinfo['building_type'] = space.spaceType.get.standardsBuildingType.empty? ? 'None' : space.spaceType.get.standardsBuildingType.get
      spaceinfo['is_conditioned'] = space.thermalZone.get.isConditioned.get unless space.thermalZone.empty? or space.thermalZone.get.isConditioned.empty?
      # shw
      spaceinfo['shw_peak_flow_rate_m_cu_per_s'] = 0
      spaceinfo['shw_peak_flow_rate_per_floor_area_m_cu_per_s_per_m_sq'] = 0
      space.waterUseEquipment.each do |equipment|
        spaceinfo['shw_peak_flow_rate_m_cu_per_s'] += equipment.waterUseEquipmentDefinition.peakFlowRate
        spaceinfo['shw_peak_flow_rate_per_floor_area_m_cu_per_s_per_m_sq'] += equipment.waterUseEquipmentDefinition.peakFlowRate / space.floorArea
        area_per_occ = space.spaceType.get.getFloorAreaPerPerson(space.floorArea)
        #                             Watt per person =             m_cu/s/m_cu                * 1000W/kW * (specific heat * dT) * m_sq/person
        spaceinfo['shw_watts_per_person'] = spaceinfo['shw_peak_flow_rate_per_floor_area_m_cu_per_s_per_m_sq'] * 1000 * (4.19 * 44.4) * 1000 * area_per_occ
      end
      unless cost_result.nil?
        # Including space level lighting costs in the existing space table...
        spaceLgtInfo = cost_result['lighting']['space_report'].detect { |curr_spaceLgtInfo| curr_spaceLgtInfo['zone'].downcase == spaceinfo['thermal_zone_name'].downcase }
        raise("Could not find zone name \"#{spaceinfo['thermal_zone_name']}\" in lighting space_report") if spaceLgtInfo.nil?

        spaceinfo['space_type'] = spaceLgtInfo['space_type']
        spaceinfo['fixture_type'] = spaceLgtInfo['fixture_type']
        # Note spelling mistake of "description" in cost_result hash fixed below in copy
        spaceinfo['fixture_description'] = spaceLgtInfo['fixture_desciption']
        spaceinfo['height_avg_ft'] = spaceLgtInfo['height_avg_ft']
        spaceinfo['floor_area_ft2'] = spaceLgtInfo['floor_area_ft2']
        spaceinfo['lighting_cost'] = spaceLgtInfo['cost']
        spaceinfo['lighting_cost_per_ft2'] = spaceLgtInfo['cost_per_ft2']
        spaceinfo['lighting_note'] = spaceLgtInfo['note']
      end
    end
    table.sort_by! { |spaceinfo| [spaceinfo['thermal_zone_name'], spaceinfo['space_name']] }
    return table
  end

  def climate_data
    # Store Geography Data
    geography_data = {}
    geography_data['location_necb_hdd'] = @standard.get_necb_hdd18(model: @model, necb_hdd: true)
    geography_data['location_weather_file'] = File.basename(@model.getWeatherFile.path.get.to_s)
    weather_file_path = @model.weatherFile.get.path.get.to_s
    stat_file_path = weather_file_path.gsub('.epw', '.stat')
    stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
    geography_data['location_epw_cdd'] = stat_file.cdd18
    geography_data['location_epw_hdd'] = stat_file.hdd18
    geography_data['location_necb_climate_zone'] = @standard.get_climate_zone_name(geography_data['location_necb_hdd'])
    geography_data['location_city'] = @model.getWeatherFile.city
    geography_data['location_state_province_region'] = @model.getWeatherFile.stateProvinceRegion
    geography_data['location_country'] = @model.getWeatherFile.country
    geography_data['location_latitude'] = @model.getWeatherFile.latitude
    geography_data['location_longitude'] = @model.getWeatherFile.longitude
    return geography_data
  end

  ### The 'annual_peak_electricity_cost_dollar' function calculates annual peak electricity cost (dollar)
  ### for OEE-Electrification project using the OERD's electricity rates for commercial buildings
  ### that Danielle Krauel of OEE provided to CE-O
  def oerd_electricity_cost(model:, utility_pricing_year: 2020, oerd_utility_pricing: false)
    unless oerd_utility_pricing
      @btap_data.merge!('cost_utility_oerd_electricity_peak_annual_cost_per_m_sq' => 0.00) unless oerd_utility_pricing
      @btap_data.merge!('cost_utility_oerd_electricity_energy_annual_cost_per_m_sq' => 0.00) unless oerd_utility_pricing
      return 0.00
    end

    #===================================================================================================================
    ### OERD's electricity rates for commercial buildings
    neb_data = CSV.parse(File.read(@neb_prices_csv_file_name), headers: true, converters: :numeric).map(&:to_h)
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    ##################### Calculate annual electricity peak cost using OERD's electricity rate #########################
    #===================================================================================================================
    #===================================================================================================================
    ### Find index for hourly data of 'ElectricityNet:Facility' (J)
    query = "
        SELECT ReportDataDictionaryIndex
        FROM ReportDataDictionary
        WHERE Name=='ElectricityNet:Facility' AND ReportingFrequency == 'Hourly' AND Units == 'J'
        "
    index_timestep_electricity = model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
    number_of_timesteps_per_hour = 1
    puts "Trying hourly ElectricityNet:Facility"

    ### Find index for timestep data of 'Electricity:Facility' (J) if 'ElectricityNet:Facility' data is not available
    if index_timestep_electricity.nil?
      query = "
        SELECT ReportDataDictionaryIndex
        FROM ReportDataDictionary
        WHERE Name=='Electricity:Facility' AND ReportingFrequency == 'Zone Timestep' AND Units == 'J'
        "
      index_timestep_electricity = model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
      number_of_timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour
      puts "Trying timestep Electricity:Facility"
    end

    ### Find index for hourly data of 'Electricity:Facility' (J) if timestep data is not available
    if index_timestep_electricity.nil?
      query = "
        SELECT ReportDataDictionaryIndex
        FROM ReportDataDictionary
        WHERE Name=='Electricity:Facility' AND ReportingFrequency == 'Hourly' AND Units == 'J'
        "
      index_timestep_electricity = model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
      number_of_timesteps_per_hour = 1
      puts "Trying hourly Electricity:Facility"
    end

    if index_timestep_electricity.nil?
      puts "No hourly or timestep data available.  Peak data not available"
      @btap_data.merge!('cost_utility_oerd_electricity_peak_annual_cost_per_m_sq' => 0.00) unless oerd_utility_pricing
      @btap_data.merge!('cost_utility_oerd_electricity_energy_annual_cost_per_m_sq' => 0.00) unless oerd_utility_pricing
      return 0.00
    end
    ### Get number of timesteps from the model
    timestep_second = 3600 / number_of_timesteps_per_hour
    #===================================================================================================================
    ### Calculate number of timesteps of the whole year, and create dates/times for the whole year
    number_of_timesteps_of_year = 365 * 24 * number_of_timesteps_per_hour
    timesteps_of_year = []
    d = Time.new(2006, 1, 1, 0)
    (0...number_of_timesteps_of_year).each do |increment|
      timesteps_of_year << (d + (60 * 60 / number_of_timesteps_per_hour) * increment).strftime('%Y-%m-%d %H:%M')
    end
    #===================================================================================================================

    #===================================================================================================================
    ### Get timestep output for Electricity:Facility output.
    query = "
      Select VariableValue
      FROM ReportVariableData
      WHERE
      ReportVariableDataDictionaryIndex = #{index_timestep_electricity}
    "
    timestep_values = model.sqlFile.get.execAndReturnVectorOfDouble(query).get
    #===================================================================================================================
    ### Calculate electricity peak (J) for each month of the year
    # Find month of each timestep
    keys_month = timesteps_of_year.map{ |timestep| DateTime.parse(timestep).to_date.month }
    # Create a hash where its keys are months and values for eahc month are electricity energy use (J) of all timesteps for that month
    hash_months_electricity = keys_month.zip(timestep_values).group_by(&:first).map{|key, value| [key, value.map(&:last)]}.to_h
    # Find maximum of electricity energy use (J) among all timesteps for each month of the year
    monthly_peak_J = hash_months_electricity.map { |key, value| [key, value.max()] }.to_h
    #===================================================================================================================
    ### Convert J to kW of maximum electricity energy use (J)
    monthly_peak_kW = monthly_peak_J.map { |key, value| [key, value * 0.001 / timestep_second] }.to_h
    ### Normalize by building floor area
    annual_peak_kW_per_m_sq = monthly_peak_kW.values.sum / @btap_data['bldg_conditioned_floor_area_m_sq'].to_f
    #===================================================================================================================
    ### Get province of the model and find its peak electricity price from the utility_pricing_2025-02-20.csv
    province = @btap_data['location_state_province_region']
    # Find which province the proposed building is located in
    building_type = 'Commercial'
    geography_data = climate_data
    province_abbreviation = geography_data['location_state_province_region']
    province = @standards_data['province_map'][province_abbreviation]
    row_peak = neb_data.detect do |data|
      (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Electricity Peak')
    end
    province_dollar_kW_month = row_peak[utility_pricing_year.to_i.to_s]
    #===================================================================================================================
    ### Calculate cost of peak electricity for each month
    monthly_peak_cost = monthly_peak_kW.map { |key, value| [key, value * province_dollar_kW_month] }.to_h
    #===================================================================================================================
    ### Calculate cost of peak electricity for the whole year in dollar
    annual_peak_cost_dollar = monthly_peak_cost.values.sum
    #===================================================================================================================
    ### Calculate cost of peak electricity for the whole year in dollar normalized by floor area
    annual_peak_cost_dollar_per_m_sq = annual_peak_cost_dollar / @btap_data['bldg_conditioned_floor_area_m_sq']
    #===================================================================================================================
    ### Merge the calculated value to @btap_data
    @btap_data.merge!('cost_utility_oerd_electricity_peak_annual_cost_per_m_sq' => annual_peak_cost_dollar_per_m_sq.round(2))
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    #===================================================================================================================
    ################### Calculate annual electricity energy use cost using OERD's electricity rate #####################
    #===================================================================================================================
    ### Get province of the model and find its peak electricity price from the pricing_2025-02-20.csv
    row_elec = neb_data.detect do |data|
      (data['building_type'] == building_type) && (data['province'] == province) && (data['fuel_type'] == 'Electricity')
    end
    province_dollar_kWh = row_elec[utility_pricing_year.to_i.to_s]
    #===================================================================================================================
    # Calculate cost of energy electricity for the whole year in dollar normalized by floor area
    annual_energy_cost_dollar_per_m_sq = @btap_data['energy_eui_electricity_gj_per_m_sq'] * 277.778 * province_dollar_kWh
    #===================================================================================================================
    ### Merge the calculated value to @btap_data
    @btap_data.merge!('cost_utility_oerd_electricity_energy_annual_cost_per_m_sq' => annual_energy_cost_dollar_per_m_sq.round(2))
    #===================================================================================================================
    return annual_peak_kW_per_m_sq
  end

  def utility(model:, utility_pricing_year: 2020)
    economics_data = {}
    building_type = 'Commercial'
    province = @standards_data['province_map'][model.getWeatherFile.stateProvinceRegion]
    neb_eplus_fuel_map = {'Natural Gas' => {eplus_fuel_name: 'NaturalGas',
                                            eplus_table_name: 'Annual and Peak Values - Natural Gas',
                                            eplus_row_name: 'NaturalGas:Facility',
                                            eplus_column_name: 'Natural Gas Annual Value'},
                          'Electricity' => {eplus_fuel_name: 'Electricity',
                                            eplus_table_name: 'Annual and Peak Values - Electricity',
                                            eplus_row_name: 'Electricity:Facility',
                                            eplus_column_name: 'Electricity Annual Value'},
                          'Oil' => {eplus_fuel_name: 'FuelOilNo2',
                                    eplus_table_name: 'Annual and Peak Values - Other',
                                    eplus_row_name: 'FuelOilNo2:Facility',
                                    eplus_column_name: 'Annual Value'}
                          }
    economics_data['cost_utility_neb_total_cost_per_m_sq'] = 0.0
    economics_data['cost_utility_ghg_total_kg_per_m_sq'] = 0.0
    # Create a hash of the neb data.
    neb_data = CSV.parse(File.read(@neb_prices_csv_file_name), headers: true, converters: :numeric).map(&:to_h)

    neb_eplus_fuel_map.each do |neb_fuel, ep_fuel|
      next if neb_fuel.to_s.downcase == 'electricity peak'
      row = neb_data.detect do |data|
        (data['building_type'].to_s == building_type) &&
          (data['province'].to_s == province) &&
          (data['fuel_type'].to_s == neb_fuel)
      end
      utility_pricing_year_s = utility_pricing_year.to_i.to_s
      neb_fuel_cost = row[utility_pricing_year_s]
      fuel_consumption_gj = 0.0
      sql_command = "SELECT Value FROM tabulardatawithstrings
                     WHERE ReportName='EnergyMeters'
                     AND ReportForString='Entire Facility'
                     AND TableName='#{ep_fuel[:eplus_table_name]}'
                     AND RowName='#{ep_fuel[:eplus_row_name]}'
                     AND ColumnName='#{ep_fuel[:eplus_column_name]}'
                     AND Units='GJ'"
      fuel_consumption_gj = model.sqlFile.get.execAndReturnFirstDouble(sql_command).is_initialized ? model.sqlFile.get.execAndReturnFirstDouble(sql_command).get : 0.0

      # Determine costs in $$
      economics_data["cost_utility_neb_#{neb_fuel.downcase}_cost_per_m_sq"] = fuel_consumption_gj * neb_fuel_cost.to_f / @conditioned_floor_area_m_sq
      economics_data['cost_utility_neb_total_cost_per_m_sq'] += economics_data["cost_utility_neb_#{neb_fuel.downcase}_cost_per_m_sq"]
      # Determine cost in GHG kg of CO2
      if neb_fuel.downcase == 'electricity' # Use ECCC data for utility emission factors rather than NEB data.
        # Create a hash of the ECCC's electricity emissions factors for the current and future years for GHG "without Biomass and RNG CO2 emissions".
        eccc_ghg_elec_emission_factors = CSV.parse(File.read(@eccc_ghg_electricity), headers: true, converters: :numeric).map(&:to_h)
        # Find the appropriate row for electricity GHG emmission factors
        row_emm_factor = eccc_ghg_elec_emission_factors.detect { |data| (data['province'] == province) }
        emm_factor_conv = 3600.0
        economics_data["cost_utility_ghg_#{neb_fuel.downcase}_kg_per_m_sq"] = ((fuel_consumption_gj * row_emm_factor[utility_pricing_year.to_i.to_s].to_f) / emm_factor_conv) * 1000 / @conditioned_floor_area_m_sq
      else
        economics_data["cost_utility_ghg_#{neb_fuel.downcase}_kg_per_m_sq"] = fuel_consumption_gj * get_utility_ghg_kg_per_gj(province: model.getWeatherFile.stateProvinceRegion, fuel_type: ep_fuel[:eplus_fuel_name]) / @conditioned_floor_area_m_sq
      end
      economics_data['cost_utility_ghg_total_kg_per_m_sq'] += economics_data["cost_utility_ghg_#{neb_fuel.downcase}_kg_per_m_sq"]
    end
    # Commenting out block charge rates for now....

    # Fuel cost based local utility rates
    #    sql_command = "SELECT RowName FROM TabularDataWithStrings
    #                    WHERE ReportName='LEEDsummary'
    #                    AND ReportForString='Entire Facility'
    #                    AND TableName='EAp2-7. Energy Cost Summary'
    #                    AND ColumnName='Total Energy Cost'"
    #    costing_rownames = model.sqlFile().get().execAndReturnVectorOfString(sql_command)

    #==> ["Electricity", "Natural Gas", "Additional", "Total"]
    #    costing_rownames = validate_optional(costing_rownames, model, "N/A")
    #    unless costing_rownames == "N/A"
    #      costing_rownames.each do |rowname|
    #        sql_command = "SELECT Value FROM TabularDataWithStrings
    #                        WHERE ReportName='LEEDsummary'
    #                        AND ReportForString='Entire Facility'
    #                        AND TableName='EAp2-7. Energy Cost Summary'
    #                        AND ColumnName='Total Energy Cost'
    #                        AND RowName='#{rowname}'"
    #        case rowname
    #        when "Electricity"
    #          economics_data["cost_utility_block_electricity_cost_per_m_sq"] = model.sqlFile().get().execAndReturnFirstDouble(sql_command).get / @conditioned_floor_area_m_sq
    #        when "Natural Gas"
    #          economics_data["cost_utility_block_natural_gas_cost_per_m_sq"] = model.sqlFile().get().execAndReturnFirstDouble(sql_command).get / @conditioned_floor_area_m_sq
    #        when "Additional"
    #          economics_data["cost_utility_block_additional_cost_per_m_sq"] = model.sqlFile().get().execAndReturnFirstDouble(sql_command).get / @conditioned_floor_area_m_sq
    #        when "Total"
    #          economics_data["cost_utility_block_total_cost_per_m_sq"] = model.sqlFile().get().execAndReturnFirstDouble(sql_command).get / @conditioned_floor_area_m_sq
    #        end
    #      end
    #    else
    #      @error_warning << "costing is unavailable because the sql statement is nil RowName FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost'"
    #    end
    return economics_data
  end

  def space_type_table(model)
    table = []
    model.getSpaceTypes.sort.each do |spaceType|
      next if spaceType.floorArea == 0

      # data for space type breakdown
      display = spaceType.name.get
      floor_area_si = 0
      # loop through spaces so I can skip if not included in floor area
      spaceType.spaces.sort.each do |space|
        next if !space.partofTotalFloorArea

        floor_area_si += space.floorArea * space.multiplier
      end
      space_type_info = {}
      space_type_info['name'] = spaceType.name.get
      space_type_info['floor_m_sq'] = floor_area_si
      space_type_info['percent_area'] = (floor_area_si / @conditioned_floor_area_m_sq * 100.0).round(2)
      space_type_info['occ_per_m_sq'] = !spaceType.peoplePerFloorArea.empty? ? spaceType.peoplePerFloorArea.get : nil
      space_type_info['occ_schedule'] = !spaceType.defaultScheduleSet.empty? && !spaceType.defaultScheduleSet.get.numberofPeopleSchedule.empty? ? spaceType.defaultScheduleSet.get.numberofPeopleSchedule.get.name.get : nil
      space_type_info['lighting_w_per_m_sq'] = !spaceType.lightingPowerPerFloorArea.empty? ? spaceType.lightingPowerPerFloorArea.get : nil
      space_type_info['electric_w_per_m_sq'] = !spaceType.electricEquipmentPowerPerFloorArea.empty? ? spaceType.electricEquipmentPowerPerFloorArea.get : nil
      space_type_info['gas_w_per_m_sq'] = !spaceType.gasEquipmentPowerPerFloorArea.empty? ? spaceType.gasEquipmentPowerPerFloorArea.get : nil
      table << space_type_info
    end
    return table
  end

  def thermal_zones_table(model, cost_result)
    # Get E+ zone table.
    zones = @model.getThermalZones
    # get surface table from sql
    table = get_sql_table_to_json(@model, 'InputVerificationandResultsSummary', 'Entire Facility', 'Zone Summary')
    # Get rid of totals and averages.
    table['table'].delete_if { |row| !!(row['name'] =~ /Total|Average/) }
    raise('Could not get zone table from E+ sql') if table.empty?

    # Go through zone objects
    zones.each do |zone|
      # get E+ zone row
      row = table['table'].detect { |curr_row| zone.name.get.downcase == curr_row['name'].downcase }
      raise("Could not find zone  #{row['name']} in #{zones.map { |curr_zone| curr_zone.name.get }}") if row.nil?

      row['is_ideal_air_loads'] = zone.useIdealAirLoads
      row['heating_sizing_factor'] = zone.sizingZone.zoneHeatingSizingFactor.empty? ? -1.0 : zone.sizingZone.zoneHeatingSizingFactor.get
      row['cooling_sizing_factor'] = zone.sizingZone.zoneCoolingSizingFactor.empty? ? -1.0 : zone.sizingZone.zoneCoolingSizingFactor.get
      row['zone_heating_design_supply_air_temperature'] = zone.sizingZone.zoneHeatingDesignSupplyAirTemperature
      row['zone_cooling_design_supply_air_temperature'] = zone.sizingZone.zoneCoolingDesignSupplyAirTemperature
      # Get Air loop that it is connected to if possible
      row['air_loop_name'] = nil
      model.getAirLoopHVACs.sort.each do |air_loop|
        row['air_loop_name'] = air_loop.name.get if air_loop.thermalZones.include?(zone)
      end
      # Get Breathing zone outdoor air flow.
      sql_command = "
        SELECT Value FROM TabularDataWithStrings
        WHERE ReportName='Standard62.1Summary'
        AND ReportForString='Entire Facility'
        AND TableName='Zone Ventilation Parameters'
        AND ColumnName='Breathing Zone Outdoor Airflow - Vbz'
        AND Units='m3/s'
        AND RowName='#{row['name']}'
      "
      breathing_zone_outdoor_airflow_vbz = model.sqlFile.get.execAndReturnFirstDouble(sql_command)
      row['breathing_zone_outdoor_airflow_vbz'] = breathing_zone_outdoor_airflow_vbz.empty? ? nil : breathing_zone_outdoor_airflow_vbz.get

      if zone.useIdealAirLoads == false
        # Including ventilation tz_distribution cost data into zone_table
        zoneName = row['name'].downcase
        storyHash = cost_result['ventilation']['tz_distribution'.to_sym][0].detect { |currstoryHash| zoneName.include?(currstoryHash[:Story].to_s.downcase) }
        if storyHash
          tzHash = storyHash[:thermal_zones].detect { |currtzHash| zoneName == currtzHash[:ThermalZone].to_s.downcase && tzHash[:ducting_direction].to_s.downcase == 'supply' }
          if tzHash
            row['ducting_direction'] = tzHash[:ducting_direction]
            row['tz_mult'] = tzHash[:tz_mult]
            row['airflow_m3ps'] = tzHash[:airflow_m3ps]
            row['num_diff'] = tzHash[:num_diff]
            row['ducting_lbs'] = tzHash[:ducting_lbs]
            row['duct_insulation_ft2'] = tzHash[:duct_insulation_ft2]
            row['flex_duct_sz_in'] = tzHash[:flex_duct_sz_in]
            row['flex_duct_length_ft'] = tzHash[:flex_duct_length_ft]
            row['duct_cost'] = tzHash[:cost]
            # Check if there is a return duct hash and, if so, modify ducting direction & cost to include
            # Return duct. Note that all other return duct costing values are identical to Supply duct
            tzHash1 = storyHash[:thermal_zones].detect { |currtzHash1| zoneName == currtzHash1[:ThermalZone].to_s.downcase && currtzHash1[:ducting_direction].to_s.downcase == 'return' }
            if !tzHash1.nil?
              row['ducting_direction'] = 'Supply & Return'
              row['duct_cost'] += tzHash1[:cost]
            end
          end
        end

        # Including thermal zone HRV return ducting distribution cost information
        floorHash = cost_result['ventilation']['hrv_return_ducting'.to_sym].detect { |currfloorHash| zoneName.include?(currfloorHash[:floor].to_s.downcase) }
        if floorHash
          airSysArr = floorHash[:air_systems].select { |airSys| airSys[:air_system].to_s.downcase == row['air_loop_name'].downcase }
          if !airSysArr.empty?
            airSysArr.each do |airSysHash|
              airSys_tz_hash = airSysHash[:tz_dist].detect { |curr_airSys_tz_hash| curr_airSys_tz_hash[:tz].to_s.downcase == zoneName }
              if airSys_tz_hash
                row['hrv_ret_dist_m'] = airSys_tz_hash[:hrv_ret_dist_m]
                row['hrv_ret_size_in'] = airSys_tz_hash[:hrv_ret_size_in]
                row['hrv_ret_duct_cost'] = airSys_tz_hash[:cost]
              end
            end
          end
        end
      end
    end

    return table
  end

  def thermal_zones_equipment_table(model)
    # Store Thermal zone data
    table = []
    model.getThermalZones.sort.each do |zone|
      zone.equipmentInHeatingOrder.each do |equipment|
        item = {}
        item['air_loop_name'] = nil
        model.getAirLoopHVACs.sort.each do |air_loop|
          if air_loop.thermalZones.include?(zone)
            item['air_loop_name'] = air_loop.name.empty? ? 'None' : air_loop.name.get
          else
            item['air_loop_name'] =  'None'
          end
        end
        item['thermal_zone_name'] = zone.name.empty? ? 'None' : zone.name.get
        item['zone_equipment_name'] = equipment.name.empty? ? 'None' : equipment.name.get
        item['type'] = get_actual_child_object(equipment).class.name
        table << item
      end
    end

    table.sort_by! { |item| [item['air_loop_name'], item['thermal_zone_name'], item['zone_equipment_name']] }
    return table
  end

  def air_loops_table(model, cost_result)
    # Store Air Loop Information
    table = []
    model.getAirLoopHVACs.sort.each do |air_loop|
      air_loop_info = {}
      air_loop_info['name'] = air_loop.name.get
      sql_command = " SELECT Value FROM TabularDataWithStrings
                      WHERE ReportName='Standard62.1Summary'
                      AND ReportForString='Entire Facility'
                      AND TableName='System Ventilation Parameters'
                      AND ColumnName='Area Outdoor Air Rate - Ra'
                      AND Units='m3/s-m2'
                      AND RowName='#{air_loop.name.get.to_s.upcase}' "
      air_loop_info['area_outdoor_air_rate_m_cu_per_s_m_sq'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)

      air_loop_info['total_floor_area_served'] = 0.0
      air_loop_info['total_breathing_zone_outdoor_airflow_vbz'] = 0.0
      air_loop.thermalZones.sort.each do |zone|
        sql_command = " SELECT Value FROM TabularDataWithStrings
                        WHERE ReportName='Standard62.1Summary'
                        AND ReportForString='Entire Facility'
                        AND TableName='Zone Ventilation Parameters'
                        AND ColumnName='Breathing Zone Outdoor Airflow - Vbz'
                        AND Units='m3/s'
                        AND RowName='#{zone.name.get.to_s.upcase}' "
        vbz = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, 0)
        air_loop_info['total_breathing_zone_outdoor_airflow_vbz'] += vbz
        air_loop_info['total_floor_area_served'] += zone.floorArea
      end
      air_loop_info['outdoor_air_l_per_s'] = -1.0
      unless air_loop_info['area_outdoor_air_rate_m_cu_per_s_m_sq'] == -1.0
        air_loop_info['outdoor_air_l_per_s'] = air_loop_info['area_outdoor_air_rate_m_cu_per_s_m_sq'] * air_loop_info['total_floor_area_served'] * 1000
      end

      # SUpply Fan
      unless air_loop.supplyFan.empty?
        if air_loop.supplyFan.get.to_FanConstantVolume.is_initialized
          air_loop_info['supply_fan_type'] = 'CV'
          fan = air_loop.supplyFan.get.to_FanConstantVolume.get
        elsif air_loop.supplyFan.get.to_FanVariableVolume.is_initialized
          air_loop_info['supply_fan_type'] = 'VV'
          fan = air_loop.supplyFan.get.to_FanVariableVolume.get
        end
        air_loop_info['supply_fan_name'] = fan.name.get
        air_loop_info['supply_fan_efficiency'] = fan.fanEfficiency
        air_loop_info['supply_fan_motor_efficiency'] = fan.motorEfficiency
        air_loop_info['supply_fan_pressure_rise'] = fan.pressureRise
        air_loop_info['supply_fan_max_air_flow_rate_m_cu_per_s'] = -1.0
        sql_command = " SELECT RowName FROM TabularDataWithStrings
                        WHERE ReportName='EquipmentSummary'
                        AND ReportForString='Entire Facility'
                        AND TableName='Fans'
                        AND ColumnName='Max Air Flow Rate'
                        AND Units='m3/s' "
        max_air_flow_info = model.sqlFile.get.execAndReturnVectorOfString(sql_command)
        max_air_flow_info = validate_optional(max_air_flow_info, model, 'N/A')
        if max_air_flow_info != 'N/A'
          if max_air_flow_info.include?(air_loop_info['supply_fan_name'].to_s.upcase)
            sql_command = " SELECT Value FROM TabularDataWithStrings
                            WHERE ReportName='EquipmentSummary'
                            AND ReportForString='Entire Facility'
                            AND TableName='Fans'
                            AND ColumnName='Max Air Flow Rate'
                            AND Units='m3/s'
                            AND RowName='#{air_loop_info['supply_fan_name'].upcase}' "
            air_loop_info['supply_fan_max_air_flow_rate_m_cu_per_s'] = model.sqlFile.get.execAndReturnFirstDouble(sql_command).get
            sql_coommand = " SELECT Value FROM TabularDataWithStrings
                              WHERE ReportName='EquipmentSummary'
                              AND ReportForString='Entire Facility'
                              AND TableName='Fans'
                              AND ColumnName='Rated Electric Power'
                              AND Units='W'
                              AND RowName='#{air_loop_info['supply_fan_name'].upcase}' "
            air_loop_info['supply_fan_rated_electric_power_w'] = model.sqlFile.get.execAndReturnFirstDouble(sql_coommand).get
          else
            @error_warning << "#{air_loop_info['supply_fan_name']} does not exist in sql file WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s'"
          end
        else
          @error_warning << "max_air_flow_info is nil because the following sql statement returned nil: RowName FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s' "
        end
      end

      # Fan
      unless air_loop.returnFan.empty?
        air_loop_info['return_fan'] = {}
        if air_loop.returnFan.get.to_FanConstantVolume.is_initialized
          air_loop_info['return_fan_type'] = 'CV'
          fan = air_loop.returnFan.get.to_FanConstantVolume.get
        elsif air_loop.returnFan.get.to_FanVariableVolume.is_initialized
          air_loop_info['return_fan_type'] = 'VV'
          fan = air_loop.returnFan.get.to_FanVariableVolume.get
        end
        air_loop_info['return_fan_name'] = fan.name.get
        air_loop_info['return_fan_efficiency'] = fan.fanEfficiency
        air_loop_info['return_fan_motor_efficiency'] = fan.motorEfficiency
        air_loop_info['return_fan_pressure_rise'] = fan.pressureRise
        air_loop_info['return_fan_max_air_flow_rate_m_cu_per_s'] = -1.0
        sql_command = " SELECT RowName FROM TabularDataWithStrings
                        WHERE ReportName='EquipmentSummary'
                        AND ReportForString='Entire Facility'
                        AND TableName='Fans'
                        AND ColumnName='Max Air Flow Rate'
                        AND Units='m3/s' "
        max_air_flow_info = model.sqlFile.get.execAndReturnVectorOfString(sql_command)
        max_air_flow_info = validate_optional(max_air_flow_info, model, 'N/A')
        if max_air_flow_info != 'N/A'
          if max_air_flow_info.include?(air_loop_info['return_fan_name'].to_s.upcase.to_s)
            sql_command = " SELECT Value FROM TabularDataWithStrings
                            WHERE ReportName='EquipmentSummary'
                            AND ReportForString='Entire Facility'
                            AND TableName='Fans'
                            AND ColumnName='Max Air Flow Rate'
                            AND Units='m3/s'
                            AND RowName='#{air_loop_info['return_fan_name'].upcase}' "
            air_loop_info['return_fan_max_air_flow_rate_m_cu_per_s'] = model.sqlFile.get.execAndReturnFirstDouble(sql_command).get
            sql_coommand = " SELECT Value FROM TabularDataWithStrings
                              WHERE ReportName='EquipmentSummary'
                              AND ReportForString='Entire Facility'
                              AND TableName='Fans'
                              AND ColumnName='Rated Electric Power'
                              AND Units='W'
                              AND RowName='#{air_loop_info['return_fan_name'].upcase}' "
            air_loop_info['return_fan_rated_electric_power_w'] = model.sqlFile.get.execAndReturnFirstDouble(sql_coommand).get
          else
            @error_warning << "#{air_loop_info['return_fan_name']} does not exist in sql file WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s'"
          end
        else
          @error_warning << "max_air_flow_info is nil because the following sql statement returned nil: RowName FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s' "
        end
      end

      # economizer
      air_loop_info['economizer_name'] = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.name.get
      air_loop_info['economizer_control_type'] = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.getEconomizerControlType

      # Include air system costs from ventilation costs
      sysNum = air_loop_info['name'][4].to_i
      sysCostInfo = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym].detect { |currsysCostInfo| currsysCostInfo[:name].to_s.downcase == air_loop_info['name'].downcase }
      if sysCostInfo.nil? && sysNum == 4
        # 04-Nov-2019 JTB: CK says that system_4 is handled the same way as system_1 so may see "Sys_4" substrings in the name of a system_1 airloop!
        sysCostInfo = cost_result['ventilation']['system_1'.to_s.to_sym].detect { |currsysCostInfo| currsysCostInfo[:name].to_s.downcase == air_loop_info['name'].downcase }
        raise("System name \"#{air_loop_info['name']}\" not found in ventilation cost info for system_1") if sysCostInfo.nil?
      else
        raise("System name \"#{air_loop_info['name']}\" not found in ventilation cost info for System_#{sysNum}") if sysCostInfo.nil?
      end
      if !sysCostInfo.nil?
        air_loop_info['airloop_flow_m3_per_s'] = sysCostInfo[:airloop_flow_m3_per_s]
        air_loop_info['num_rooftop_units'] = sysCostInfo[:num_rooftop_units]
        # air_loop_info['ahu_counter'] = sysCostInfo[:ahu_counter]
        # air_loop_info['ahu_l_per_s'] = sysCostInfo[:ahu_l_per_s]
        air_loop_info['base_ahu_cost'] = sysCostInfo[:base_ahu_cost]
        air_loop_info['revised_base_ahu_cost'] = sysCostInfo[:revised_base_ahu_cost]
        # Promote hrv data from it's own hash, if it isn't empty!
        if sysCostInfo[:hrv].empty?
          air_loop_info['hrv_type'] = sysCostInfo[:hrv]
        else
          air_loop_info['hrv_type'] = sysCostInfo[:hrv][:hrv_type]
          air_loop_info['hrv_name'] = sysCostInfo[:hrv][:hrv_name]
          air_loop_info['hrv_size_m3ps'] = sysCostInfo[:hrv][:hrv_size_m3ps]
          air_loop_info['hrv_return_fan_size_m3ps'] = sysCostInfo[:hrv][:hrv_return_fan_size_m3ps]
          air_loop_info['hrv_cost'] = sysCostInfo[:hrv][:hrv_cost]
          air_loop_info['revised_hrv_cost'] = sysCostInfo[:hrv][:revised_hrv_cost]
        end
      end

      # Also include hrv_return_ducting information from ventilation costs.
      # Note that there can be multiple hrv return duct runs for the same air loop name
      # (on different floors) plus a system level trunk return duct section.
      hrv_retduct_byflr = cost_result['ventilation']['hrv_return_ducting'.to_sym].reject { |arr| arr[:floor].nil? }
      hrv_retduct_bysys = cost_result['ventilation']['hrv_return_ducting'.to_sym].reject { |arr| arr[:air_system].nil? }

      # Floor level hrv return ducts...
      hrv_retduct_byflr.each do |arr1|
        flrNum = arr1[:floor].to_s[15].to_i
        airsys_byflr = arr1[:air_systems].select { |arr2| arr2[:air_system].to_s.downcase == air_loop_info['name'].to_s.downcase }
        airsys_byflr.each do |arr3|
          air_loop_info["flr#{flrNum}_floor_mult".to_sym] = arr3[:floor_mult]
          if !arr3[:hrv_ret_trunk].empty?
            # The hrv_ret_trunk embedded hash is not empty -- promote it
            air_loop_info["flr#{flrNum}_hrv_ret_trunk_len_m".to_sym] = arr3[:hrv_ret_trunk][:duct_length_m]
            air_loop_info["flr#{flrNum}_hrv_ret_trunk_dia_in".to_sym] = arr3[:hrv_ret_trunk][:dia_in]
            air_loop_info["flr#{flrNum}_hrv_ret_trunk_cost".to_sym] = arr3[:hrv_ret_trunk][:cost]
            # If not don't include anything!
          end
          # The individual thermal zone (by floor) ret duct distribution (tz_dist) added to zone_table
        end
      end
      # System level trunk hrv return ducts...
      hrv_retduct_bysys.each do |arr1|
        if arr1[:air_system].to_s.downcase == air_loop_info['name'].to_s.downcase
          air_loop_info[:hrv_building_trunk_length_m] = arr1[:hrv_building_trunk_length_m]
          air_loop_info[:hrv_building_trunk_dia_in] = arr1[:hrv_building_trunk_dia_in]
          air_loop_info["sys#{sysNum}_hrv_ret_duct_cost".to_sym] = arr1[:cost]
        end
      end

      table << air_loop_info
    end

    return table
  end

  def coil_table
    table = get_sql_table_to_json(model, 'CoilSizingDetails', 'Entire Facility', 'Coils')['table']
    model.getAirLoopHVACs.sort.each do |air_loop|
      air_loop.supplyComponents.each do |supply_comp|
        object = get_actual_child_object(supply_comp)
        coil_types = [
          'openstudio::model::CoilCoolingCooledBeam',
          'openstudio::model::CoilCoolingDXMultiSpeed',
          'openstudio::model::CoilCoolingDXSingleSpeed',
          'openstudio::model::CoilCoolingDXTwoSpeed',
          'openstudio::model::CoilCoolingDXTwoStageWithHumidityControlMode',
          'openstudio::model::CoilCoolingDXVariableSpeed',
          'openstudio::model::CoilCoolingFourPipeBeam',
          'openstudio::model::CoilCoolingLowTempRadiantConstFlow',
          'openstudio::model::CoilCoolingLowTempRadiantVarFlow',
          'openstudio::model::CoilHeatingDesuperheater',
          'openstudio::model::CoilHeatingDXMultiSpeed',
          'openstudio::model::CoilHeatingDXSingleSpeed',
          'openstudio::model::CoilHeatingDXVariableSpeed',
          'openstudio::model::CoilHeatingElectric',
          'openstudio::model::CoilHeatingFourPipeBeam',
          'openstudio::model::CoilHeatingGas',
          'openstudio::model::CoilHeatingGasMultiStage',
          'openstudio::model::CoilHeatingLowTempRadiantConstFlow',
          'openstudio::model::CoilHeatingLowTempRadiantVarFlow',
          'openstudio::model::CoilHeatingWaterBaseboard',
          'openstudio::model::CoilHeatingWaterBaseboardRadiant',
          'openstudio::model::CoilSystemCoolingDXHeatExchangerAssisted',
          'openstudio::model::CoilSystemCoolingWaterHeatExchangerAssisted',
          'openstudio::model::CoilWaterHeatingDesuperheater'
        ]
        # Is it a heating coil?
        if coil_types.include?(object.class.name) && object.class.name.include?('Heating')

          case object.class.name
          when 'CoilHeatingGas'
            coil = {}
            coil['name'] = object.get.name
            coil['type'] = 'Gas'
            coil['efficency'] = gas.gasBurnerEfficiency
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Heating Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(@model.sqlFile.get.execAndReturnFirstDouble(sql_command), @model, -1.0)

          when 'CoilHeatingElectric'
          when 'CoilHeatingWater'
          end

          if supply_comp.to_CoilHeatingGas.is_initialized
            coil = {}
            air_loop_info['heating_coils']['coil_heating_gas'] << coil
            gas = supply_comp.to_CoilHeatingGas.get
            coil['name'] = gas.name.get
            coil['type'] = 'Gas'
            coil['efficency'] = gas.gasBurnerEfficiency
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Heating Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(@model.sqlFile.get.execAndReturnFirstDouble(sql_command), @model, -1.0)
          end
          if supply_comp.to_CoilHeatingElectric.is_initialized
            coil = {}
            air_loop_info['heating_coils']['coil_heating_electric'] << coil
            electric = supply_comp.to_CoilHeatingElectric.get
            coil['name'] = electric.name.get
            coil['type'] = 'Electric'
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Heating Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          end
          if supply_comp.to_CoilHeatingWater.is_initialized
            coil = {}
            air_loop_info['heating_coils']['coil_heating_water'] << coil
            water = supply_comp.to_CoilHeatingWater.get
            coil['name'] = water.name.get
            coil['type'] = 'Water'
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Heating Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          end
        end

        # I dont think i need to get the type of heating coil from the sql file, because the coils are differentiated by class, and I have hard coded the information
        # model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName= 'Heating Coils' AND ColumnName='Type' ").get #padmussen to complete #AND RowName='#{air_loop_info["heating_coils"]["name"].upcase}'
        #
        # Collect all the fans into the the array.
        air_loop.supplyComponents.each do |curr_supply_comp|
          if curr_supply_comp.to_CoilCoolingDXSingleSpeed.is_initialized
            coil = {}
            air_loop_info['cooling_coils']['dx_single_speed'] << coil
            single_speed = curr_supply_comp.to_CoilCoolingDXSingleSpeed.get
            coil['name'] = single_speed.name.get
            coil['cop'] = single_speed.getRatedCOP.get
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Cooling Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          end
          if curr_supply_comp.to_CoilCoolingDXTwoSpeed.is_initialized
            coil = {}
            air_loop_info['cooling_coils']['dx_two_speed'] << coil
            two_speed = curr_supply_comp.to_CoilCoolingDXTwoSpeed.get
            coil['name'] = two_speed.name.get
            coil['cop_low'] = two_speed.getRatedLowSpeedCOP.get
            coil['cop_high'] = two_speed.getRatedHighSpeedCOP.get
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Cooling Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          end
          if curr_supply_comp.to_CoilCoolingWater.is_initialized
            coil = {}
            air_loop_info['cooling_coils']['coil_cooling_water'] << coil
            coil_cooling_water = curr_supply_comp.to_CoilCoolingWater.get
            coil['name'] = coil_cooling_water.name.get
            sql_command = "SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Cooling Coils'
                          AND ColumnName='Nominal Total Capacity'
                          AND RowName='#{coil['name'].to_s.upcase}'"
            coil['nominal_total_capacity_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
            sql_command = "SELECT Value FROM TabularDataWithStrings
                         WHERE ReportName='EquipmentSummary'
                         AND ReportForString='Entire Facility'
                         AND TableName='Cooling Coils'
                         AND ColumnName='Nominal Sensible Heat Ratio'
                         AND RowName='#{coil['name'].upcase}' "
            coil['nominal_sensible_heat_ratio'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          end
        end
      end
    end
  end

  def coil_cost_table(cost_result)
    sys_coils_table = []
    (1..7).each do |sysNum|
      sys_table = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym].reject(&:empty?)
      sys_table.each do |sysHash|
        equip_info_table = sysHash[:equipment_info].reject(&:empty?)
        equip_info_table.each do |equipHash|
          sysCoilsInfo = {}
          sys_coils_table << sysCoilsInfo
          sysCoilsInfo[:sys_type] = sysNum
          sysCoilsInfo[:sys_name] = equipHash[:name]
          sysCoilsInfo[:eq_category] = equipHash[:eq_category]
          sysCoilsInfo[:heating_fuel] = equipHash[:heating_fuel]
          sysCoilsInfo[:cooling_type] = equipHash[:cooling_type]
          sysCoilsInfo[:capacity_kw] = equipHash[:capacity_kw]
          sysCoilsInfo[:coil_cost] = equipHash[:cost]
        end
      end
    end
    return sys_coils_table
  end

  def terminal_VAV_cost_table(cost_result)
    terminal_VAV_table = []
    (1..7).each do |sysNum|
      ndx = 0
      until cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx].nil?
        ndx1 = 0
        until cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1].nil?
          sysTerminalInfo = {}
          terminal_VAV_table << sysTerminalInfo
          sysTerminalInfo[:sys_type] = sysNum
          sysTerminalInfo[:sys_name] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:name]
          sysTerminalInfo[:terminal] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:terminal]
          sysTerminalInfo[:zone_mult] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:zone_mult]
          sysTerminalInfo[:box_type] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:box_type]
          sysTerminalInfo[:box_name] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:box_name]
          sysTerminalInfo[:unit_size_kw] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:unit_info][:size_kw]
          sysTerminalInfo[:unit_air_flow_m3_per_s] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:unit_info][:air_flow_m3_per_s]
          sysTerminalInfo[:unit_pipe_dist_m] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:unit_info][:pipe_dist_m]
          sysTerminalInfo[:unit_elect_dist_m] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:unit_info][:elect_dist_m]
          sysTerminalInfo[:unit_num_units] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:unit_info][:num_units]
          sysTerminalInfo[:cost] = cost_result['ventilation']["system_#{sysNum}".to_s.to_sym][ndx][:reheat_recool][ndx1][:cost]
          ndx1 += 1
        end
        ndx += 1
      end
    end
    return terminal_VAV_table
  end

  def trunk_ducts_cost_table(cost_result)
    # Create a trunk ducts cost table that combines the building trunk duct with the floor trunk ducts
    trunk_ducts_table = []
    ndx = 0
    insert_bld_trunk_duct = true
    until cost_result['ventilation']['floor_trunk_ducts'.to_sym][0][ndx].nil?
      if insert_bld_trunk_duct
        trunkDuctsInfo = {}
        trunk_ducts_table << trunkDuctsInfo
        trunkDuctsInfo[:Floor] = 'building_trunk'
        trunkDuctsInfo[:Predominant_space_type] = 'n/a'
        trunkDuctsInfo[:SupplyDuctSize_in] = cost_result['ventilation']['trunk_duct'.to_sym][ndx][:DuctSize_in]
        trunkDuctsInfo[:SupplyDuctLength_m] = cost_result['ventilation']['trunk_duct'.to_sym][ndx][:DuctLength_m]
        if cost_result['ventilation']['trunk_duct'.to_sym][ndx][:NumberRuns] == 2
          trunkDuctsInfo[:ReturnDuctSize_in] = cost_result['ventilation']['trunk_duct'.to_sym][ndx][:DuctSize_in]
          trunkDuctsInfo[:ReturnDuctLength_m] = cost_result['ventilation']['trunk_duct'.to_sym][ndx][:DuctLength_m]
        else
          trunkDuctsInfo[:ReturnDuctSize_in] = 0
          trunkDuctsInfo[:ReturnDuctLength_m] = 0
        end
        trunkDuctsInfo[:TotalDuctCost] = cost_result['ventilation']['trunk_duct'.to_sym][ndx][:DuctCost]
        trunkDuctsInfo[:Multiplier] = 1.0
        insert_bld_trunk_duct = false
      else
        trunkDuctsInfo = {}
        trunk_ducts_table << trunkDuctsInfo
        cost_result['ventilation']['floor_trunk_ducts'.to_sym][0][ndx].each do |k, v|
          trunkDuctsInfo[k] = v
        end
        ndx += 1
      end
    end
    return trunk_ducts_table
  end

  def plant_loop_table(model)
    table = []
    model.getPlantLoops.sort.each do |plant_loop|
      plant_loop_info = {}
      table << plant_loop_info
      plant_loop_info['name'] = plant_loop.name.get

      sizing = plant_loop.sizingPlant
      plant_loop_info['design_loop_exit_temperature'] = sizing.getDesignLoopExitTemperature.value
      plant_loop_info['loop_design_temperature_difference'] = sizing.getLoopDesignTemperatureDifference.value

      # Create Container for plant equipment arrays.
      plant_loop_info['pumps'] = []
      plant_loop_info['boilers'] = []
      plant_loop_info['chiller_electric_eir'] = []
      plant_loop_info['cooling_tower_single_speed'] = []
      plant_loop_info['water_heater_mixed'] = []
      plant_loop.supplyComponents.each do |supply_comp|
        # Collect Constant Speed
        if supply_comp.to_PumpConstantSpeed.is_initialized
          pump = supply_comp.to_PumpConstantSpeed.get
          pump_info = {}
          plant_loop_info['pumps'] << pump_info
          pump_info['name'] = pump.name.get
          pump_info['type'] = 'Pump:ConstantSpeed'
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Head'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['head_pa'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Water Flow'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['water_flow_m_cu_per_s'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Electric Power'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['electric_power_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          pump_info['motor_efficency'] = pump.getMotorEfficiency.value
        end

        # Collect Variable Speed
        if supply_comp.to_PumpVariableSpeed.is_initialized
          pump = supply_comp.to_PumpVariableSpeed.get
          pump_info = {}
          plant_loop_info['pumps'] << pump_info
          pump_info['name'] = pump.name.get
          pump_info['type'] = 'Pump:VariableSpeed'
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Head'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['head_pa'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Water Flow'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['water_flow_m_cu_per_s'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          sql_command = " SELECT Value FROM TabularDataWithStrings
                          WHERE ReportName='EquipmentSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Pumps'
                          AND ColumnName='Electric Power'
                          AND RowName='#{pump_info['name'].upcase}' "
          pump_info['electric_power_w'] = validate_optional(model.sqlFile.get.execAndReturnFirstDouble(sql_command), model, -1.0)
          pump_info['motor_efficency'] = pump.getMotorEfficiency.value
        end

        # Collect HotWaterBoilers
        if supply_comp.to_BoilerHotWater.is_initialized
          boiler = supply_comp.to_BoilerHotWater.get
          boiler_info = {}
          plant_loop_info['boilers'] << boiler_info
          boiler_info['name'] = boiler.name.get
          boiler_info['type'] = 'Boiler:HotWater'
          boiler_info['fueltype'] = boiler.fuelType
          boiler_info['nominal_capacity'] = validate_optional(boiler.nominalCapacity, model, -1.0)
        end

        # Collect ChillerElectricEIR
        if supply_comp.to_ChillerElectricEIR.is_initialized
          chiller = supply_comp.to_ChillerElectricEIR.get
          chiller_info = {}
          plant_loop_info['chiller_electric_eir'] << chiller_info
          chiller_info['name'] = chiller.name.get
          chiller_info['type'] = 'Chiller:Electric:EIR'
          chiller_info['reference_capacity'] = validate_optional(chiller.referenceCapacity, model, -1.0)
          chiller_info['reference_leaving_chilled_water_temperature'] = chiller.referenceLeavingChilledWaterTemperature
        end

        # Collect CoolingTowerSingleSpeed
        if supply_comp.to_CoolingTowerSingleSpeed.is_initialized
          coolingTower = supply_comp.to_CoolingTowerSingleSpeed.get
          coolingTower_info = {}
          plant_loop_info['cooling_tower_single_speed'] << coolingTower_info
          coolingTower_info['name'] = coolingTower.name.get
          coolingTower_info['type'] = 'CoolingTower:SingleSpeed'
          coolingTower_info['fan_power_at_design_air_flow_rate'] = validate_optional(coolingTower.fanPoweratDesignAirFlowRate, model, -1.0)
        end

        # Collect WaterHeaterMixed
        if supply_comp.to_WaterHeaterMixed.is_initialized
          waterHeaterMixed = supply_comp.to_WaterHeaterMixed.get
          waterHeaterMixed_info = {}
          plant_loop_info['water_heater_mixed'] << waterHeaterMixed_info
          waterHeaterMixed_info['name'] = waterHeaterMixed.name.get
          waterHeaterMixed_info['type'] = 'WaterHeater:Mixed'
          waterHeaterMixed_info['heater_thermal_efficiency'] = waterHeaterMixed.heaterThermalEfficiency.get unless waterHeaterMixed.heaterThermalEfficiency.empty?
          waterHeaterMixed_info['heater_fuel_type'] = waterHeaterMixed.heaterFuelType
        end
      end
    end
    return table
  end

  def eplusout_err_table(model)
    table = []
    warnings = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='0' ")
    warnings = validate_optional(warnings, model, 'N/A')
    unless warnings == 'N/A'
      messages = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='0' ").get
      messages.each do |message|
        table << { 'error_type' => 'warning', 'message' => message }
      end
      messages = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='1' ").get
      messages.each do |message|
        table << { 'error_type' => 'severe', 'message' => message }
      end
      messages = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='2' ").get
      messages.each do |message|
        table << { 'error_type' => 'fatal', 'message' => message }
      end
    end
    return table
  end

  def energy_peak_data
    # Primary heaing source
    data = {}
    command = "SELECT Value
                  FROM TabularDataWithStrings
                  WHERE ReportName='LEEDsummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Sec1.1A-General Information'
                  AND RowName = 'Principal Heating Source'
                  AND ColumnName='Data'"
    value = @sqlite_file.get.execAndReturnFirstString(command)
    # make sure all the data are availalbe

    data['energy_principal_heating_source'] = 'unknown'
    unless value.empty?
      data['energy_principal_heating_source'] = value.get
    end

    # Peaks
    electric_peak = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" \
                                                                        " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Electricity' AND RowName='Electricity:Facility'" \
                                                                        " AND ColumnName='Electricity Maximum Value' AND Units='W'")
    natural_gas_peak = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" \
                                                                           " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Natural Gas' AND RowName='NaturalGas:Facility'" \
                                                                           " AND ColumnName='Natural Gas Maximum Value' AND Units='W'")
    data['energy_peak_electric_w_per_m_sq'] = electric_peak.empty? ? 0.0 : electric_peak.get / @conditioned_floor_area_m_sq
    data['energy_peak_natural_gas_w_per_m_sq'] = natural_gas_peak.empty? ? 0.0 : natural_gas_peak.get / @conditioned_floor_area_m_sq

    # Peak heating load  # @todo IMPORTANT NOTE: Peak heating load must be updated if a combination of fuel types is used in a building model.
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Electricity'
               AND RowName='Heating:Electricity'
               AND ColumnName='Electricity Maximum Value'
               AND Units='W'"
    heating_peak_w_electricity = @sqlite_file.get.execAndReturnFirstDouble(command)
    command = "SELECT Value
              FROM TabularDataWithStrings
              WHERE ReportName='EnergyMeters'
              AND ReportForString='Entire Facility'
              AND TableName='Annual and Peak Values - Natural Gas'
              AND RowName='Heating:NaturalGas'
              AND ColumnName='Natural Gas Maximum Value'
              AND Units='W'"
    heating_peak_w_gas = @sqlite_file.get.execAndReturnFirstDouble(command)
    heating_peak_w = [heating_peak_w_electricity.to_f, heating_peak_w_gas.to_f].max
    data['heating_peak_w_per_m_sq'] = heating_peak_w / @conditioned_floor_area_m_sq

    # Peak cooling load    # @todo IMPORTANT NOTE: Peak cooling load must be updated if a combination of fuel types is used in a building model.
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Electricity'
               AND RowName='Cooling:Electricity'
               AND ColumnName='Electricity Maximum Value'
               AND Units='W'"
    cooling_peak_w_electricity = @sqlite_file.get.execAndReturnFirstDouble(command)
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Natural Gas'
               AND RowName='Cooling:Electricity'
               AND ColumnName='Electricity Maximum Value'
               AND Units='W'"
    cooling_peak_w_gas = @sqlite_file.get.execAndReturnFirstDouble(command)
    cooling_peak_w = [cooling_peak_w_electricity.to_f, cooling_peak_w_gas.to_f].max
    data['cooling_peak_w_per_m_sq'] = cooling_peak_w / @conditioned_floor_area_m_sq

    # Peak water system load  # @todo IMPORTANT NOTE: Peak water system load must be updated if a combination of fuel types is used in a building model.
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Electricity'
               AND RowName='WaterSystems:Electricity'
               AND ColumnName='Electricity Maximum Value'
               AND Units='W'"
    water_heating_peak_w_electricity = @sqlite_file.get.execAndReturnFirstDouble(command)
    command = "SELECT Value
              FROM TabularDataWithStrings
              WHERE ReportName='EnergyMeters'
              AND ReportForString='Entire Facility'
              AND TableName='Annual and Peak Values - Natural Gas'
              AND RowName='WaterSystems:NaturalGas'
              AND ColumnName='Natural Gas Maximum Value'
              AND Units='W'"
    water_heating_peak_w_gas = @sqlite_file.get.execAndReturnFirstDouble(command)
    water_heating_peak_w = [water_heating_peak_w_electricity.to_f, water_heating_peak_w_gas.to_f].max
    data['energy_peak_water_systems_w_per_m_sq'] = water_heating_peak_w / @conditioned_floor_area_m_sq

    #===================================================================================================================
    # Winter peak values
    ### Get number of timesteps from the model
    number_of_timesteps_per_hour = 1
    timestep_second = 3600 / number_of_timesteps_per_hour
    #===================================================================================================================
    ### Calculate number of timesteps of the whole year, and create dates/times for the whole year
    number_of_timesteps_of_year = 365 * 24 * number_of_timesteps_per_hour
    timesteps_of_year = []
    d = Time.new(2006, 1, 1, 0)
    (0...number_of_timesteps_of_year).each do |increment|
      timesteps_of_year << (d + (60 * 60 / number_of_timesteps_per_hour) * increment).strftime('%Y-%m-%d %H:%M')
    end
    # Find month of each timestep
    keys_month = timesteps_of_year.map{ |timestep| DateTime.parse(timestep).to_date.month }
    # Peak electricity in winter
    query = "
    SELECT ReportDataDictionaryIndex
    FROM ReportDataDictionary
    WHERE Name=='Electricity:Facility' AND ReportingFrequency == 'Hourly' AND Units == 'J'
    "
    index_timestep_electricity = @model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
    number_of_timesteps_per_hour = 1
    if index_timestep_electricity.nil?
      puts "No hourly or timestep data available.  Peak data not available"
      data['energy_peak_electric_w_per_m_sq_winter'] = 0
    else
      ### Get timestep output for Electricity:Facility output.
      query = "
      Select VariableValue
      FROM ReportVariableData
      WHERE
      ReportVariableDataDictionaryIndex = #{index_timestep_electricity}
      "
      timestep_values = @model.sqlFile.get.execAndReturnVectorOfDouble(query).get
          # Create a hash where its keys are months and values for eahc month are electricity energy use (J) of all timesteps for that month
      hash_months_electricity = keys_month.zip(timestep_values).group_by(&:first).map{|key, value| [key, value.map(&:last)]}.to_h
      # Find maximum of electricity energy use (J) among all timesteps for each month of the year
      monthly_peak_J = hash_months_electricity.map { |key, value| [key, value.max()] }.to_h
      ### Convert J to W of maximum electricity energy use (J)
      monthly_peak_W = monthly_peak_J.map { |key, value| [key, value / timestep_second] }.to_h
      # Get winter peak
      winter_peak_W = [monthly_peak_W[12].to_f, monthly_peak_W[1].to_f, monthly_peak_W[2].to_f].max
      ### Normalize by building floor area
      annual_peak_W_per_m_sq = winter_peak_W / @btap_data['bldg_conditioned_floor_area_m_sq'].to_f
      data['energy_peak_electric_w_per_m_sq_winter'] = annual_peak_W_per_m_sq
    end

    # Peak electricity heating in winter
    query = "
    SELECT ReportDataDictionaryIndex
    FROM ReportDataDictionary
    WHERE Name=='Heating:Electricity' AND ReportingFrequency == 'Hourly' AND Units == 'J'
    "
    index_timestep_electricity = @model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
    number_of_timesteps_per_hour = 1
    if index_timestep_electricity.nil?
      puts "No hourly or timestep data available.  Peak data not available"
      data['energy_peak_electric_heating_w_per_m_sq_winter'] = 0
    else
      ### Get timestep output for Electricity:Facility output.
      query = "
      Select VariableValue
      FROM ReportVariableData
      WHERE
      ReportVariableDataDictionaryIndex = #{index_timestep_electricity}
      "
      timestep_values = @model.sqlFile.get.execAndReturnVectorOfDouble(query).get
      # Create a hash where its keys are months and values for eahc month are electricity energy use (J) of all timesteps for that month
      hash_months_electricity = keys_month.zip(timestep_values).group_by(&:first).map{|key, value| [key, value.map(&:last)]}.to_h
      # Find maximum of electricity energy use (J) among all timesteps for each month of the year
      monthly_peak_J = hash_months_electricity.map { |key, value| [key, value.max()] }.to_h
      ### Convert J to W of maximum electricity energy use (J)
      monthly_peak_W = monthly_peak_J.map { |key, value| [key, value / timestep_second] }.to_h
      # Get winter peak
      winter_peak_W = [monthly_peak_W[12].to_f, monthly_peak_W[1].to_f, monthly_peak_W[2].to_f].max
      ### Normalize by building floor area
      annual_peak_W_per_m_sq = winter_peak_W / @btap_data['bldg_conditioned_floor_area_m_sq'].to_f
      data['energy_peak_electric_heating_w_per_m_sq_winter'] = annual_peak_W_per_m_sq
    end

    # Peak water system electricity heating in winter
    query = "
    SELECT ReportDataDictionaryIndex
    FROM ReportDataDictionary
    WHERE Name=='WaterSystems:Electricity' AND ReportingFrequency == 'Hourly' AND Units == 'J'
    "
    index_timestep_electricity = @model.sqlFile.get.execAndReturnVectorOfInt(query).get[0]
    number_of_timesteps_per_hour = 1
    if index_timestep_electricity.nil?
      puts "No hourly or timestep data available.  Peak data not available"
      data['energy_peak_electric_water_systems_w_per_m_sq_winter'] = 0
    else
      ### Get timestep output for Electricity:Facility output.
      query = "
      Select VariableValue
      FROM ReportVariableData
      WHERE
      ReportVariableDataDictionaryIndex = #{index_timestep_electricity}
      "
      timestep_values = @model.sqlFile.get.execAndReturnVectorOfDouble(query).get
          # Create a hash where its keys are months and values for eahc month are electricity energy use (J) of all timesteps for that month
      hash_months_electricity = keys_month.zip(timestep_values).group_by(&:first).map{|key, value| [key, value.map(&:last)]}.to_h
      # Find maximum of electricity energy use (J) among all timesteps for each month of the year
      monthly_peak_J = hash_months_electricity.map { |key, value| [key, value.max()] }.to_h
      ### Convert J to W of maximum electricity energy use (J)
      monthly_peak_W = monthly_peak_J.map { |key, value| [key, value / timestep_second] }.to_h
      # Get winter peak
      winter_peak_W = [monthly_peak_W[12].to_f, monthly_peak_W[1].to_f, monthly_peak_W[2].to_f].max
      ### Normalize by building floor area
      annual_peak_W_per_m_sq = winter_peak_W / @btap_data['bldg_conditioned_floor_area_m_sq'].to_f
      data['energy_peak_electric_water_systems_w_per_m_sq_winter'] = annual_peak_W_per_m_sq
    end

    return data
  end

  def energy_eui_data(model)
    data = {}
    # default to zero to start.
    ['energy_eui_fans_gj_per_m_sq',
     'energy_eui_heating_gj_per_m_sq',
     'energy_eui_cooling_gj_per_m_sq',
     'energy_eui_interior equipment_gj_per_m_sq',
     'energy_eui_natural_gas_gj_per_m_sq',
     'energy_eui_pumps_gj_per_m_sq',
     'energy_eui_total_gj_per_m_sq',
     'energy_eui_heat recovery_gj_per_m_sq',
     'energy_eui_water systems_gj_per_m_sq'].each { |end_use| data[end_use] = 0.0 }

    # Check if the HVAC of the model is GSHP
    plant_loops = model.getPlantLoops
    model_has_how_many_GSHP = 0.0
    plant_loops.each do |plantloop|
      if plantloop.name.to_s.upcase.include? "GLHX"
        model_has_how_many_GSHP += 1.0
      end
    end

    # Get E+ End use table from sql
    table = get_sql_table_to_json(@model, 'AnnualBuildingUtilityPerformanceSummary', 'Entire Facility', 'End Uses')['table']
    # Get rid of totals and averages rows.. I want just the
    table.delete_if { |row| !!(row['name'] =~ /Total|Average/) }
    table.each do |row|
      # skip name and water_m3 columns
      energy_columns = row.select { |k, v| (k != 'name') && (k != 'water_m3') }
      # Store eui by use name.
      data["energy_eui_#{row['name'].downcase}_gj_per_m_sq"] = energy_columns.inject(0) { |sum, tuple| sum += tuple[1] } / @conditioned_floor_area_m_sq
    end

    data['energy_eui_total_gj_per_m_sq'] = 0.0

    ['natural_gas_GJ', 'electricity_GJ', 'additional_fuel_GJ', 'district_cooling_GJ', 'district_heating_GJ'].each do |column|
      data["energy_eui_#{column.downcase}_per_m_sq"] = table.inject(0) { |sum, row| sum + (row[column].nil? ? 0.0 : row[column]) } / @conditioned_floor_area_m_sq
      data['energy_eui_total_gj_per_m_sq'] += data["energy_eui_#{column.downcase}_per_m_sq"] unless data["energy_eui_#{column.downcase}_per_m_sq"].nil?
    end

    # If the HVAC of the model is GSHP, district heating and cooling must be removed from EUIs for heating and cooling and total EUI
    # NOTE: it has been assumed that if a model has GSHP, that is the only HVAC type in the model. This assumption means that any district heating/cooling in the model is related to GSHP.
    if model_has_how_many_GSHP > 0.0
      data['energy_eui_heating_gj_per_m_sq'] -= data['energy_eui_district_heating_gj_per_m_sq']
      data['energy_eui_cooling_gj_per_m_sq'] -= data['energy_eui_district_cooling_gj_per_m_sq']
      data['energy_eui_total_gj_per_m_sq'] -= (data['energy_eui_district_heating_gj_per_m_sq'] + data['energy_eui_district_cooling_gj_per_m_sq'])
    end

    # Get total and net site energy use intensity
    # Note: 'Total Site Energy' is the "gross" energy used by a building.
    # Note: 'Net Site Energy' is the final energy used by the building after considering any on-site energy generation (e.g. PV).
    # Reference: https://unmethours.com/question/25416/what-is-the-difference-between-site-energy-and-source-energy/
    # Reference: https://designbuilder.co.uk/helpv6.0/Content/KPIs.htm
    data['total_site_eui_gj_per_m_sq'] = data['energy_eui_total_gj_per_m_sq'].to_f
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='AnnualBuildingUtilityPerformanceSummary'
               AND ReportForString='Entire Facility'
               AND TableName='Site and Source Energy'
               AND RowName='Net Site Energy'
               AND ColumnName='Energy Per Conditioned Building Area'
               AND Units='MJ/m2'"
    net_site_eui_mj_per_m_sq = @sqlite_file.get.execAndReturnFirstDouble(command)
    data['net_site_eui_gj_per_m_sq'] = OpenStudio.convert(net_site_eui_mj_per_m_sq.to_f, 'MJ', 'GJ').get
    return data
  end

  def unmet_hours(model)
    # Store unmet hour data
    unmet_hours = {}
    unmet_hours['unmet_hours_cooling'] = model.getFacility.hoursCoolingSetpointNotMet.get unless model.getFacility.hoursCoolingSetpointNotMet.empty?
    unmet_hours['unmet_hours_heating'] = model.getFacility.hoursHeatingSetpointNotMet.get unless model.getFacility.hoursHeatingSetpointNotMet.empty?
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='AnnualBuildingUtilityPerformanceSummary'
               AND ReportForString='Entire Facility'
               AND TableName='Comfort and Setpoint Not Met Summary'
               AND RowName='Time Setpoint Not Met During Occupied Cooling'
               AND ColumnName='Facility'
               AND Units='Hours'"
    unmet_hours['unmet_hours_cooling_during_occupied'] = @sqlite_file.get.execAndReturnFirstDouble(command).to_f
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='AnnualBuildingUtilityPerformanceSummary'
               AND ReportForString='Entire Facility'
               AND TableName='Comfort and Setpoint Not Met Summary'
               AND RowName='Time Setpoint Not Met During Occupied Heating'
               AND ColumnName='Facility'
               AND Units='Hours'"
    unmet_hours['unmet_hours_heating_during_occupied'] = @sqlite_file.get.execAndReturnFirstDouble(command).to_f
    return unmet_hours
  end

  def service_water_heating_data
    service_water_heating = {}
    service_water_heating['shw_total_nominal_occupancy'] = -1
    # service_water_heating["total_nominal_occupancy"]=@model.sqlFile().get().execAndReturnVectorOfDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='OutdoorAirSummary' AND ReportForString='Entire Facility' AND TableName='Average Outdoor Air During Occupied Hours' AND ColumnName='Nominal Number of Occupants'").get.inject(0, :+)
    service_water_heating['shw_total_nominal_occupancy'] = get_total_nominal_capacity(@model)

    service_water_heating['shw_electricity_per_year'] = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Electricity' AND RowName='Water Systems'")
    service_water_heating['shw_electricity_per_year'] = validate_optional(service_water_heating['shw_electricity_per_year'], @model, -1)

    service_water_heating['shw_electricity_per_day'] = service_water_heating['shw_electricity_per_year'] / 365.5
    service_water_heating['shw_electricity_per_day_per_occupant'] = service_water_heating['shw_electricity_per_day'] / service_water_heating['shw_total_nominal_occupancy']

    service_water_heating['shw_natural_gas_per_year'] = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Natural Gas' AND RowName='Water Systems'")
    service_water_heating['shw_natural_gas_per_year'] = validate_optional(service_water_heating['shw_natural_gas_per_year'], @model, -1)

    service_water_heating['shw_additional_fuel_per_year'] = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Additional Fuel' AND RowName='Water Systems'")
    service_water_heating['shw_additional_fuel_per_year'] = validate_optional(service_water_heating['shw_additional_fuel_per_year'], @model, -1)

    service_water_heating['shw_water_m_cu_per_year'] = @model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Water' AND RowName='Water Systems'")
    service_water_heating['shw_water_m_cu_per_year'] = validate_optional(service_water_heating['shw_water_m_cu_per_year'], @model, -1)

    service_water_heating['shw_water_m_cu_per_day'] = service_water_heating['shw_water_m_cu_per_year'] / 365.5
    service_water_heating['shw_water_m_cu_per_day_per_occupant'] = service_water_heating['shw_water_m_cu_per_day'] / service_water_heating['shw_total_nominal_occupancy']
    return service_water_heating
  end

  # The below method (outdoor_air_data extract a couple of outputs related to outdoor air from the .html output file)
  def outdoor_air_data(model)
    # Store outdoor air data
    outdoor_air_data = {}
    #===============================================================================================================
    airloops_total_outdoor_air_mechanical_ventilation_m3 = 0.0
    airloops_total_outdoor_air_natural_ventilation_m3 = 0.0
    zones_total_outdoor_air_mechanical_ventilation_m3 = 0.0
    zones_total_outdoor_air_natural_ventilation_m3 = 0.0
    zones_total_outdoor_air_infiltration_m3 = 0.0
    #===============================================================================================================
    # Total outdoor air by airLoop
    model.getAirLoopHVACs.sort.each do |air_loop|
      air_loop_name = air_loop.name.get.upcase

      # Mechanical ventilation of all airloops
      command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='OutdoorAirDetails'
               AND ReportForString='Entire Facility'
               AND TableName='Total Outdoor Air by AirLoop'
               AND RowName='#{air_loop_name}'
               AND ColumnName='Mechanical Ventilation'
               AND Units='m3'"
      airloops_total_outdoor_air_mechanical_ventilation_m3 += @sqlite_file.get.execAndReturnFirstDouble(command).to_f

      # Natural ventilation of all airloops
      command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='OutdoorAirDetails'
               AND ReportForString='Entire Facility'
               AND TableName='Total Outdoor Air by AirLoop'
               AND RowName='#{air_loop_name}'
               AND ColumnName='Natural Ventilation'
               AND Units='m3'"
      airloops_total_outdoor_air_natural_ventilation_m3 += @sqlite_file.get.execAndReturnFirstDouble(command).to_f

    end

    # Not-normalized mechanical/natural.
    outdoor_air_data['airloops_total_outdoor_air_mechanical_ventilation_m3'] = airloops_total_outdoor_air_mechanical_ventilation_m3
    outdoor_air_data['airloops_total_outdoor_air_natural_ventilation_m3'] = airloops_total_outdoor_air_natural_ventilation_m3

    # Normalized mechanical/natural: ACH (air changes per hour)
    outdoor_air_data['airloops_total_outdoor_air_mechanical_ventilation_ach_1_per_hr'] = airloops_total_outdoor_air_mechanical_ventilation_m3 / (@btap_data['bldg_volume_m_cu'] * 365 * 24)
    outdoor_air_data['airloops_total_outdoor_air_natural_ventilation_ach_1_per_hr'] = airloops_total_outdoor_air_natural_ventilation_m3 / (@btap_data['bldg_volume_m_cu'] * 365 * 24)

    # Normalized mechanical/natural: normalized by conditioned floor area
    outdoor_air_data['airloops_total_outdoor_air_mechanical_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2'] = airloops_total_outdoor_air_mechanical_ventilation_m3 / (@conditioned_floor_area_m_sq * 365 * 24 * 3600)
    outdoor_air_data['airloops_total_outdoor_air_natural_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2'] = airloops_total_outdoor_air_natural_ventilation_m3 / (@conditioned_floor_area_m_sq * 365 * 24 * 3600)

    # Normalized mechanical/natural: normalized by exterior area
    outdoor_air_data['airloops_total_outdoor_air_mechanical_ventilation_flow_per_exterior_area_m3_per_s_m2'] = airloops_total_outdoor_air_mechanical_ventilation_m3 / (@btap_data['bldg_exterior_area_m_sq'] * 365 * 24 * 3600)
    outdoor_air_data['airloops_total_outdoor_air_natural_ventilation_flow_per_exterior_area_m3_per_s_m2'] = airloops_total_outdoor_air_natural_ventilation_m3 / (@btap_data['bldg_exterior_area_m_sq'] * 365 * 24 * 3600)

    #===============================================================================================================
    # Total outdoor air by zone
    total_outdoor_air_mechanical_ventilation_zones_m3 = 0.0
    model.getThermalZones.sort.each do |zone|
      zone_name = zone.name.get.upcase

      # Mechanical ventilation of all zones
      command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='OutdoorAirDetails'
               AND ReportForString='Entire Facility'
               AND TableName='Total Outdoor Air by Zone'
               AND RowName='#{zone_name}'
               AND ColumnName='Mechanical Ventilation'
               AND Units='m3'"
      zones_total_outdoor_air_mechanical_ventilation_m3 += @sqlite_file.get.execAndReturnFirstDouble(command).to_f

      # Natural ventilation of all zones
      command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='OutdoorAirDetails'
               AND ReportForString='Entire Facility'
               AND TableName='Total Outdoor Air by Zone'
               AND RowName='#{zone_name}'
               AND ColumnName='Natural Ventilation'
               AND Units='m3'"
      zones_total_outdoor_air_natural_ventilation_m3 += @sqlite_file.get.execAndReturnFirstDouble(command).to_f

      # Infiltration of all zones
      command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='OutdoorAirDetails'
               AND ReportForString='Entire Facility'
               AND TableName='Total Outdoor Air by Zone'
               AND RowName='#{zone_name}'
               AND ColumnName='Infiltration'
               AND Units='m3'"
      zones_total_outdoor_air_infiltration_m3 += @sqlite_file.get.execAndReturnFirstDouble(command).to_f

    end

    # Not-normalized mechanical/natural/infiltration.
    outdoor_air_data['zones_total_outdoor_air_mechanical_ventilation_m3'] = zones_total_outdoor_air_mechanical_ventilation_m3
    outdoor_air_data['zones_total_outdoor_air_natural_ventilation_m3'] = zones_total_outdoor_air_natural_ventilation_m3
    outdoor_air_data['zones_total_outdoor_air_infiltration_m3'] = zones_total_outdoor_air_infiltration_m3

    # Normalized mechanical/natural/infiltration: ACH (air changes per hour)
    outdoor_air_data['zones_total_outdoor_air_mechanical_ventilation_ach_1_per_hr'] = zones_total_outdoor_air_mechanical_ventilation_m3 / (@btap_data['bldg_volume_m_cu'] * 365 * 24)
    outdoor_air_data['zones_total_outdoor_air_natural_ventilation_ach_1_per_hr'] = zones_total_outdoor_air_natural_ventilation_m3 / (@btap_data['bldg_volume_m_cu'] * 365 * 24)
    outdoor_air_data['zones_total_outdoor_air_infiltration_ach_1_per_hr'] = zones_total_outdoor_air_infiltration_m3 / (@btap_data['bldg_volume_m_cu'] * 365 * 24)

    # Normalized mechanical/natural/infiltration: normalized by conditioned floor area
    outdoor_air_data['zones_total_outdoor_air_mechanical_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2'] = zones_total_outdoor_air_mechanical_ventilation_m3 / (@conditioned_floor_area_m_sq * 365 * 24 * 3600)
    outdoor_air_data['zones_total_outdoor_air_natural_ventilation_flow_per_conditioned_floor_area_m3_per_s_m2'] = zones_total_outdoor_air_natural_ventilation_m3 / (@conditioned_floor_area_m_sq * 365 * 24 * 3600)
    outdoor_air_data['zones_total_outdoor_air_infiltration_flow_per_conditioned_floor_area_m3_per_s_m2'] = zones_total_outdoor_air_infiltration_m3 / (@conditioned_floor_area_m_sq * 365 * 24 * 3600)

    # Normalized mechanical/natural/infiltration: normalized by exterior area
    outdoor_air_data['zones_total_outdoor_air_mechanical_ventilation_flow_per_exterior_area_m3_per_s_m2'] = zones_total_outdoor_air_mechanical_ventilation_m3 / (@btap_data['bldg_exterior_area_m_sq'] * 365 * 24 * 3600)
    outdoor_air_data['zones_total_outdoor_air_natural_ventilation_flow_per_exterior_area_m3_per_s_m2'] = zones_total_outdoor_air_natural_ventilation_m3 / (@btap_data['bldg_exterior_area_m_sq'] * 365 * 24 * 3600)
    outdoor_air_data['zones_total_outdoor_air_infiltration_flow_per_exterior_area_m3_per_s_m2'] = zones_total_outdoor_air_infiltration_m3 / (@btap_data['bldg_exterior_area_m_sq'] * 365 * 24 * 3600)
    #===============================================================================================================

    return outdoor_air_data
  end

  def sql_data_tables(model)
    puts 'Getting SQL Data into json...'
    start = Time.now
    sql_data = []

    [
      ['AnnualBuildingUtilityPerformanceSummary', 'Entire Facility', 'End Uses']
      # ["AnnualBuildingUtilityPerformanceSummary", "Entire Facility", "Site and Source Energy"],
      # ["AnnualBuildingUtilityPerformanceSummary", "Entire Facility", "On-Site Thermal Sources"],
      # ["AnnualBuildingUtilityPerformanceSummary", "Entire Facility", "Comfort and Setpoint Not Met Summary"],
      # ["InputVerificationandResultsSummary", "Entire Facility", "Window-Wall Ratio"],
      # ["InputVerificationandResultsSummary", "Entire Facility", "Conditioned Window-Wall Ratio"],
      # ["InputVerificationandResultsSummary", "Entire Facility", "Skylight-Roof Ratio"],
      # ["DemandEndUseComponentsSummary", "Entire Facility", "End Uses"],
      # ["ComponentSizingSummary", "Entire Facility", "AirLoopHVAC"],
      # ["EnergyMeters", "Entire Facility", 'Annual and Peak Values - Natural Gas'],
      # ["EnergyMeters", "Entire Facility", 'Annual and Peak Values - Electricity'],
      # ["EnergyMeters", "Entire Facility", 'Annual and Peak Values - FuelOilNo2'],
      # ["EnergyMeters", "Entire Facility", 'Annual and Peak Values - Other'],
      # ["LEEDsummary", "Entire Facility", "EAp2-7. Energy Cost Summary"],
      # ["Standard62.1Summary", "Entire Facility", "Zone Ventilation Parameters"],
      # ["EquipmentSummary", "Entire Facility", "Fans"],
      # ["EquipmentSummary", "Entire Facility", "Heating Coils"],
      # ["EquipmentSummary", "Entire Facility", "Cooling Coils"],
      # ["EquipmentSummary", "Entire Facility", "Pumps"],
      # ["CoilSizingDetails", "Entire Facility", "Coils"] # Do not use! Takes very long to parse.
    ].each do |table|
      start = Time.now
      puts "Parsing #{table[0]}-#{table[1]}-#{table[2]}"
      sql_data << get_sql_table_to_json(model, table[0], table[1], table[2])
      finish = Time.now
      puts "....finish parsing in #{finish - start} seconds and stored in sql_data_tables hash."
    end
  end

  # This measure will return an array of hashes with the varialbles used in the previous measures.
  def measures_data_table(runner)
    # Array to store hash row data.
    measure_variables_table = []
    # Go through each workstep.
    runner.workflow.workflowSteps.each do |step|
      # Check if the ws is a measure.
      if step.to_MeasureStep.is_initialized
        measure_step = step.to_MeasureStep.get
        # Set measure name using either the folder name or the measureStep name if possible.
        measure_name = measure_step.name.is_initialized ? measure_step.name.get : measure_step.measureDirName
        measures_to_skip = ['openstudio_results']
        unless measures_to_skip.include?(measure_name.to_s)
          # Check if the 'result' (?) is initialized?
          if measure_step.result.is_initialized
            result = measure_step.result.get
            # Iterate through the result object stepValues to obtain the arg values. I am assuming this is for arg, var. pivot, continous...
            result.stepValues.each do |arg|
              # Store the row /hash for the table.
              units = arg.units.empty? ? nil : arg.units
              value = nil
              case arg.variantType.value
              when 0
                value = arg.valueAsBoolean
              when 1..2
                value = arg.valueAsDouble
              when 3
                value = arg.valueAsString
              end
              measure_variables_table << { 'measure_name' => measure_name, 'arg_name' => arg.name, 'value' => value, 'units' => units, 'type' => arg.variantType.value }
            end
          end
        end
      end
    end
    return measure_variables_table
  end

  # This should be done last.

  def get_sql_table_to_json(model, report_name, report_for_string, table_name)
    table = []
    query_row_names = "
     SELECT DISTINCT
        RowName
     FROM
        tabulardatawithstrings
      WHERE
        ReportName='#{report_name}'
      AND
        ReportForString='#{report_for_string}'
      AND
        TableName='#{table_name}'"
    row_names = model.sqlFile.get.execAndReturnVectorOfString(query_row_names).get

    # get Columns
    query_col_names = "
     SELECT DISTINCT
        ColumnName
     FROM tabulardatawithstrings
      WHERE ReportName='#{report_name}'
      AND ReportForString='#{report_for_string}'
      AND TableName='#{table_name}'"
    col_names = model.sqlFile.get.execAndReturnVectorOfString(query_col_names).get

    # get units
    query_unit_names = "
     SELECT DISTINCT
        Units
     FROM tabulardatawithstrings
      WHERE ReportName='#{report_name}'
      AND ReportForString='#{report_for_string}'
      AND TableName='#{table_name}'"
    unit_names = model.sqlFile.get.execAndReturnVectorOfString(query_unit_names).get

    row_names.each do |row|
      next if row.nil? || row == ''

      row_hash = {}
      row_hash['name'] = row
      col_names.each do |col|
        unit_names.each do |unit|
          query = "
        SELECT
          Value
        FROM
          tabulardatawithstrings
        WHERE
          ReportName='#{report_name}'
        AND
          ReportForString='#{report_for_string}'
        AND
          TableName='#{table_name}'
        AND
          RowName='#{row}'
        AND
          ColumnName='#{col}'
        AND
          Units='#{unit}'
"
          column_name = col.to_s.gsub(/\s+/, '_').downcase
          column_name += "_#{unit}" if unit != ''
          value = model.sqlFile.get.execAndReturnFirstString(query)
          next if value.empty? || value.get.nil?

          value = value.get.strip
          # check is value is a number. The last chunk checks if the string includes an E, if not return true since it
          # is a regular number, if not it checks if it is in the E+ exponent format and returns the bool result of that.
          if (begin
                Float(value)
              rescue StandardError
                false
              end) && value.to_f != 0 && (value.include?('E') || value.include?('e') ? value =~ /\d*\.\d*E[+|-]\d*/ : true)
            row_hash[column_name] = value.to_f
            # Check if value is a date
          elsif unit == '' && value =~ /\d\d-\D\D\D-\d\d:\d\d/
            row_hash[column_name] = DateTime.parse(value)
            # skip if value in an empty string or a zero value
          elsif value != '' && value != '0.00'
            row_hash[column_name] = value
          end
        end
      end
      if row_hash.size > 1
        table << row_hash
      end
    end
    result = { 'report_name' => report_name, 'report_for_string' => report_for_string, 'table_name' => table_name, 'table' => table }
    return result
  end

  def merge_recursively(a, b)
    a.merge(b) { |key, a_item, b_item| merge_recursively(a_item, b_item) }
  end

  def validate_optional(var, model, return_value = 'N/A')
    return return_value if var.nil? || var.empty?

    return var.get
  end

  # @todo SQL command units may have been converted wrong.

  def get_actual_child_object(object)
    # monkey patch class to have a decendants static method to return all possible subclasses of the object.
    object.class.class_eval do
      def self.descendants
        ObjectSpace.each_object(Class).select { |k| k < self } << self
      end
    end
    # Dont try and match the class that the object is already in! So get decendants that are not of the current object class
    subclass_array = object.class.descendants.map { |classtype| classtype if classtype != object.class }.reject(&:nil?)
    subclass_array.each do |class_type|
      # convert class name to not have prefix.
      matches = class_type.name.match(/OpenStudio::Model::(?<object_name>.*)/)
      new_object = nil
      # Use eval (I know this is the devil) to try to cast to a subclass.
      eval_info = "new_object = object.to_#{matches['object_name']}"
      eval(eval_info)
      # if it does then clean it up and return it.
      if new_object.is_initialized
        new_object = new_object.get
        return get_actual_child_object(new_object)
      end
    end
    # It is not cast-able to any subclass.. so returning original object.
    return object
  end

  def set_sql_file(file)
    @sqlite_file = file
  end

  def measure_metrics(qaqc)
    # Store mesure metric data that will be used in analysis tools.
    @btap_data['env_outdoor_walls_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k]
    @btap_data['env_outdoor_roofs_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k]
    @btap_data['env_outdoor_floors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k]
    @btap_data['env_ground_walls_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k]
    @btap_data['env_ground_roofs_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k]
    @btap_data['env_ground_floors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k]
    @btap_data['env_outdoor_windows_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:windows_average_conductance_w_per_m2_k]
    @btap_data['env_outdoor_doors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:doors_average_conductance_w_per_m2_k]
    @btap_data['env_outdoor_overhead_doors_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k]
    @btap_data['env_skylights_average_conductance-w_per_m_sq_k'] = qaqc[:envelope][:skylights_average_conductance_w_per_m2_k]
    @btap_data['env_fdwr'] = (BTAP::Geometry.get_fwdr(@model) * 100.0).round(1)
    @btap_data['env_srr'] = (BTAP::Geometry.get_srr(@model) * 100.0).round(1)
    unless @btap_data['measures_data_table'].nil?
      if @btap_data['measures_data_table'].detect { |item| item['measure_name'] == 'btap_standard_building_type_geometry' }.nil?
        @btap_data['env_x_scale'] = 1.0
        @btap_data['env_y_scale'] = 1.0
        @btap_data['env_z_scale'] = 1.0
        @btap_data['env_rotation'] = 0.0
      else
        @btap_data['env_x_scale'] = @btap_data['measures_data_table'].detect { |item| item['measure_name'] == 'btap_standard_building_type_geometry' && item['arg_name'] == 'x_scale' }['value']
        @btap_data['env_y_scale'] = @btap_data['measures_data_table'].detect { |item| item['measure_name'] == 'btap_standard_building_type_geometry' && item['arg_name'] == 'y_scale' }['value']
        @btap_data['env_z_scale'] = @btap_data['measures_data_table'].detect { |item| item['measure_name'] == 'btap_standard_building_type_geometry' && item['arg_name'] == 'z_scale' }['value']
        @btap_data['env_rotation'] = @btap_data['measures_data_table'].detect { |item| item['measure_name'] == 'btap_standard_building_type_geometry' && item['arg_name'] == 'relative_building_rotation' }['value']
      end
    end

    # This does not work with the new VRF or CCASHP systems. Commenting it for now.
    # Determine dominant system type by air loop

    #    systems = {}
    #    @btap_data["air_loop_table"].each do |loop|
    # Get system name part from regex
    #      system_name = loop["name"].match(/(^.{0,6}).*/)[1]
    #      systems[system_name] = 0.0 if systems[system_name] == nil
    #      systems[system_name] += loop["total_floor_area_served"]
    #    end
    #    if systems.empty?
    #      @btap_data["mm_hvac_dominant_system_type"] = "Unknown/IdealHVAC"
    #    else
    #      @btap_data["mm_hvac_dominant_system_type"] = systems.key(systems.values.max)
    #    end
    return @btap_data
  end

  def get_utility_ghg_kg_per_gj(province:, fuel_type:)
    ghg_data = [
      # Obtained from Portfolio Manager https://portfoliomanager.energystar.gov/pdf/reference/Emissions.pdf 10/10/2020
      #{ "province": 'AB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.24, "CO2eq Emissions (g/m3)": 1939.0 },
      #{ "province": 'BC', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.19, "CO2eq Emissions (g/m3)": 1937.0 },
      #{ "province": 'MB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.09, "CO2eq Emissions (g/m3)": 1897.0 },
      #{ "province": 'NB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'NL', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'NT', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'NS', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'NU', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'ON', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.14, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'PE', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },
      #{ "province": 'QC', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.12, "CO2eq Emissions (g/m3)": 1898.0 },
      #{ "province": 'SK', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 50.53, "CO2eq Emissions (g/m3)": 1840.0 },
      #{ "province": 'YT', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.50, "CO2eq Emissions (g/m3)": 1912.0 },

      #REF (Retrieved March 11, 2025) for Year 2022 of "Table A6.1–1 CO2 Emission Factors for Marketable Natural Gas" of National Inventory Report: https://data-donnees.az.ec.gc.ca/api/file?path=%2Fsubstances%2Fmonitor%2Fcanada-s-official-greenhouse-gas-inventory%2FD-Emission-Factors%2FEN_Annex6_Emission_Factors.pdf
      { "province": 'AB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.87, "CO2eq Emissions (g/m3)": 1962.0 },
      { "province": 'BC', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.98, "CO2eq Emissions (g/m3)": 1966.0 },
      { "province": 'MB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.58, "CO2eq Emissions (g/m3)": 1915.0 },
      { "province": 'NB', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.69, "CO2eq Emissions (g/m3)": 1919.0 },
      { "province": 'NL', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.69, "CO2eq Emissions (g/m3)": 1919.0 },
      { "province": 'NT', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.98, "CO2eq Emissions (g/m3)": 1966.0 },
      { "province": 'NS', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.69, "CO2eq Emissions (g/m3)": 1919.0 },
      { "province": 'NU', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 53.98, "CO2eq Emissions (g/m3)": 1966.0 },
      { "province": 'ON', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.75, "CO2eq Emissions (g/m3)": 1921.0 },
      { "province": 'PE', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.69, "CO2eq Emissions (g/m3)": 1919.0 },
      { "province": 'QC', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.88, "CO2eq Emissions (g/m3)": 1926.0 },
      { "province": 'SK', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 52.72, "CO2eq Emissions (g/m3)": 1920.0 },
      { "province": 'YT', "fuel_type": 'NaturalGas', "CO2eq Emissions (kg/MBtu)": 56.98, "CO2eq Emissions (g/m3)": 1966.0 },

      # Obtained from Portfolio Manager https://portfoliomanager.energystar.gov/pdf/reference/Emissions.pdf 10/10/2020
      { "province": 'AB', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'BC', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'MB', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'NB', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'NL', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'NT', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'NS', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'NU', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'ON', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'PE', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'QC', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'SK', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },
      { "province": 'YT', "fuel_type": 'FuelOilNo2', "CO2eq Emissions (kg/MBtu)": 75.13, "CO2eq Emissions (g/m3)": 2763.0 },

      { "province": 'AB', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'BC', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'MB', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'NB', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'NL', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'NT', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'NS', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'NU', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'ON', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'PE', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'QC', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'SK', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },
      { "province": 'YT', "fuel_type": 'Propane', "CO2eq Emissions (kg/MBtu)": 64.25, "CO2eq Emissions (g/m3)": 1548.00 },

      { "province": 'AB', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 202.23, "CO2eq Emissions (g/m3)": 690.0 },
      { "province": 'BC', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 3.84, "CO2eq Emissions (g/m3)": 13.1 },
      { "province": 'MB', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 0.41, "CO2eq Emissions (g/m3)": 1.4 },
      { "province": 'NB', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 84.99, "CO2eq Emissions (g/m3)": 290.0 },
      { "province": 'NL', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 7.91, "CO2eq Emissions (g/m3)": 27.0 },
      { "province": 'NT', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 46.89, "CO2eq Emissions (g/m3)": 160.0 },
      { "province": 'NS', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 216.88, "CO2eq Emissions (g/m3)": 740.0 },
      { "province": 'NU', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 260.84, "CO2eq Emissions (g/m3)": 890.0 },
      { "province": 'ON', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 8.79, "CO2eq Emissions (g/m3)": 30.0 },
      { "province": 'PE', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 84.99, "CO2eq Emissions (g/m3)": 290.0 },
      { "province": 'QC', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 0.47, "CO2eq Emissions (g/m3)": 1.6 },
      { "province": 'SK', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 219.81, "CO2eq Emissions (g/m3)": 750.0 },
      { "province": 'YT', "fuel_type": 'Electricity', "CO2eq Emissions (kg/MBtu)": 23.15, "CO2eq Emissions (g/m3)": 79.0 }
    ]
    mbtu_to_gj = 1.05505585
    factor = ghg_data.detect { |item| (item[:province] == province) && (item[:fuel_type] == fuel_type) }
    raise "could not find ghg factor for province name #{province} and fuel_type #{fuel_type}" if factor.nil?

    return factor[:"CO2eq Emissions (kg/MBtu)"] / mbtu_to_gj
  end

  def bc_energy_step_code_performance_indicators
    # TEDI (Thermal Energy Demand Intensity) [kWh/(m2.year)]
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Other'
               AND RowName='Baseboard:EnergyTransfer'
               AND ColumnName='Annual Value'
               AND Units='GJ'"
    baseboard_energy_transfer_gj = @sqlite_file.get.execAndReturnFirstDouble(command)
    baseboard_energy_transfer_kwh = OpenStudio.convert(baseboard_energy_transfer_gj.to_f, 'GJ', 'kWh')
    command = "SELECT Value
               FROM TabularDataWithStrings
               WHERE ReportName='EnergyMeters'
               AND ReportForString='Entire Facility'
               AND TableName='Annual and Peak Values - Other'
               AND RowName='HeatingCoils:EnergyTransfer'
               AND ColumnName='Annual Value'
               AND Units='GJ'"
    heating_coils_energy_transfer_gj = @sqlite_file.get.execAndReturnFirstDouble(command)
    heating_coils_energy_transfer_kwh = OpenStudio.convert(heating_coils_energy_transfer_gj.to_f, 'GJ', 'kWh')
    tedi_kwh_per_m_sq = (baseboard_energy_transfer_kwh.to_f + heating_coils_energy_transfer_kwh.to_f) / @btap_data['bldg_conditioned_floor_area_m_sq']
    @btap_data.merge!('bc_step_code_tedi_kwh_per_m_sq' => tedi_kwh_per_m_sq)

    # MEUI (Mechanical Energy Use Intensity) [kWh/(m2.year)]
    meui_gj_per_m_sq = @btap_data['energy_eui_heating_gj_per_m_sq'].to_f +
                       @btap_data['energy_eui_cooling_gj_per_m_sq'].to_f +
                       @btap_data['energy_eui_fans_gj_per_m_sq'].to_f +
                       @btap_data['energy_eui_pumps_gj_per_m_sq'].to_f +
                       @btap_data['energy_eui_water systems_gj_per_m_sq'].to_f
    meui_kwh_per_m_sq = OpenStudio.convert(meui_gj_per_m_sq, 'GJ', 'kWh').to_f
    @btap_data.merge!('bc_step_code_meui_kwh_per_m_sq' => meui_kwh_per_m_sq)
  end

  # The below method calculates energy demands and peak loads calculations as per PHIUS and NECB; and compares them to see if NECB meets PHIUS' performance criteria.
  ### References:
  ### (1) PHIUS 2021 Passive Building Standard Standard-Setting Documentation. Available at https://www.phius.org/phius-certification-for-buildings-products/project-certification/phius-2021-emissions-down-scale-up
  ### (2) Wright, L. (2019). Setting the Heating/Cooling Performance Criteria for the PHIUS 2018 Passive Building Standard. In ASHRAE Topical Conference Proceedings, pp. 399-409
  def phius_performance_indicators(model)
    ### Envelope to Floor Area ratio (EnvFlr)
    ### Note: 'Floor Area' has been considered as iCFA (interior conditioned floor area) as per REF: Wright (2019)
    bldg_exterior_area_m_sq = @btap_data['bldg_exterior_area_m_sq']
    bldg_conditioned_floor_area_m_sq = @btap_data['bldg_conditioned_floor_area_m_sq']
    bldg_conditioned_floor_area_ft_sq = OpenStudio.convert(bldg_conditioned_floor_area_m_sq, 'm^2', 'ft^2').get
    envelope_to_floor_area_ratio = bldg_exterior_area_m_sq / bldg_conditioned_floor_area_m_sq

    ### UnitDens: Unit density (1/ft2) (inverse of the floor area per unit) in PHIUS, 2021
    # Note: if commercial buildings, set the number of units to 1 and divide by the floor area
    # This is the list of building types considered as some sort of residential buildings when the whole building method is used
    building_type_names_necb_2011 = ['Dormitory', 'Hospital', 'Hotel', 'Motel', 'Multi-unit residential', 'Penitentiary']
    building_type_names_necb_2015 = ['Dormitory', 'Health care clinic', 'Hospital', 'Hotel/Motel', 'Long-term care - dwelling units', 'Long-term care - other', 'Multi-unit residential building', 'Penitentiary']
    building_type_names_necb_2017 = ['Dormitory', 'Health care clinic', 'Hospital', 'Hotel/Motel', 'Long-term care - dwelling units', 'Long-term care - other', 'Multi-unit residential building', 'Penitentiary']
    building_type_names_list = building_type_names_necb_2011 + building_type_names_necb_2015 + building_type_names_necb_2017
    building_type_names_list = building_type_names_list.uniq
    # This is the list of space types considered as some sort of residential spaces when the space type method is used
    space_type_names_necb_2011 = ['Dormitory - living quarters', 'Dwelling Unit(s)', 'Hotel/Motel - rooms', 'Hway lodging - rooms']
    space_type_names_necb_2015 = ['Guest room', 'Dormitory living quarters', 'Dwelling units general', 'Dwelling units long-term', 'Fire station sleeping quarters', 'Health care facility patient room', 'Health care facility recovery room']
    space_type_names_necb_2017 = ['Guest room', 'Dormitory living quarters', 'Dwelling units general', 'Dwelling units long-term', 'Fire station sleeping quarters', 'Health care facility patient room', 'Health care facility recovery room']
    space_type_names_list = space_type_names_necb_2011 + space_type_names_necb_2015 + space_type_names_necb_2017
    space_type_names_list = space_type_names_list.uniq
    sum_handle = 0.0
    number_of_dwelling_units = 0.0
    @btap_data['space_table'].each do |space_info|
      building_type_name = space_info['building_type'].sub! 'building', ''
      building_type_name = building_type_name.strip unless building_type_name.nil?
      space_type_name = space_info['space_type_name']
      if !space_type_name.include?('WholeBuilding')
        # puts "This_is_the_space_type_method"
        space_type_name = space_info['space_type_name'].sub! 'Space Function ', '' # This removes 'Space Function' from space type name
        if space_type_names_list.include?(space_type_name)
          number_of_dwelling_units += 1.0 * space_info['multiplier']
          sum_handle += OpenStudio.convert(space_info['floor_area_m2'], 'm^2', 'ft^2').get * space_info['multiplier']
        end
      elsif space_type_name.include?('WholeBuilding') && building_type_names_list.include?(building_type_name) && space_info['is_conditioned'] == 'Yes'
        # puts "This_is_the_whole_building_method"
        number_of_dwelling_units += 1.0 * space_info['multiplier']
        sum_handle += OpenStudio.convert(space_info['floor_area_m2'], 'm^2', 'ft^2').get * space_info['multiplier']
      end
    end
    # Calculate what percentage of conditioned floor area has space types of the 'space_type_names_list' list.
    # This percentage is used to determine if most of a building model is sort of dwelling type or not.
    # The threshold for this percentage has been set to 60% based on the below reference:
    # GSA (2012), Circulation: Defining and planning, U.S. General Services Administration, Available at Https://Www.Gsa.Gov/
    # The above reference says: 'As a general planning rule of thumb, Circulation Area comprises roughly 25 to 40% of the total Usable Area.'
    # Moreover, ~63% and ~41% of the SmallHotel and LargeHotel archetype, respectively, are guest rooms. So, the threshold has been chosen as 40%.
    percentage_dwelling = 100.0 * sum_handle / bldg_conditioned_floor_area_ft_sq
    # now, calculate UnitDens depending on whether a building model is sort of dwelling type or not
    if percentage_dwelling >= 40.0 && number_of_dwelling_units > 0.0
      unit_density_per_ft_sq = 1.0 / (sum_handle / number_of_dwelling_units)
    else # i.e. if commercial buildings, set the number of units to 1 and divide by the floor area
      unit_density_per_ft_sq = 1.0 / bldg_conditioned_floor_area_ft_sq
    end

    ### Get weather file
    weather_file_path = model.weatherFile.get.path.get.to_s
    epw_file = model.weatherFile.get.file.get
    stat_file_path = weather_file_path.gsub('.epw', '.stat')
    stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)

    ### Cooling Degree Days, base 50degF
    cdd10_degree_c_days = stat_file.cdd10
    cdd50_degree_f_days = cdd10_degree_c_days * 9.0 / 5.0

    ### Heating Degree Days, base 65degF (note that base temperature of 18degC has been considered)
    hdd18_degree_c_days = stat_file.hdd18
    hdd65_degree_f_days = hdd18_degree_c_days * 9.0 / 5.0

    ### Dehumidification degree days
    ### ('Dehumidification degree-days, base 0.010' in REF: Wright (2019))
    dehumidification_degree_days = OpenstudioStandards::Weather.epw_file_get_dehumidification_degree_days(epw_file)

    ### annual global horizontal irradiance (GHI)

    # Workaround for case when the weather file contains the February from a leap year but that February only has 28
    # days of data.
    has_leap_day = false

    # Find the first day in February
    feb_index = epw_file.data.find_index { |entry| entry.date.monthOfYear.value == 2 }

    # Find the year for February
    feb_year = epw_file.data[feb_index].year
    # Determine if February's year is a leap year
    leap_year = false
    if (feb_year % 100) > 0
      leap_year = true if (feb_year % 4) == 0
    else
      leap_year = true if (feb_year % 400) == 0
    end
    # If the February is from a leap year determine if it contains a leap day
    if leap_year

      day = epw_file.data[feb_index].date.dayOfMonth
      inc = 0

      while epw_file.data[feb_index].date.dayOfMonth == day
        feb_index += 1
        inc       += 1
      end

      has_leap_day = epw_file.data[feb_index + (inc * 28)].date.dayOfMonth == 29
    end

    # If the February is from a leap year and there is no leap day then do not use the faulty OpenStudio Epw
    # .getTimeSeries method.  Otherwise, use the method.
    if has_leap_day || !leap_year
      ghi_timeseries = epw_file.getTimeSeries('Global Horizontal Radiation').get.values
    else
      # Access the data directly instead of using the OpenStudio API to avoid the faulty OpenStudioEpw
      # .getTimeSeries method.

      # Open the weather file
      regex_csv = /[^,]+/
      regex_num = /[0-9]/
      f         = File.open(epw_file.path.to_s, 'r')
      i         = 0

      # Skip the header
      i += 1 until f.readline[0] =~ regex_num

      # Get all of the hourly weather data
      lines         = IO.readlines(f)[i..-1]

      # Get hourly weather data for a specific column
      ghi_timeseries = lines.map {|line| Float(line.scan(regex_csv)[13])}
    end

    annual_ghi_kwh_per_m_sq = ghi_timeseries.sum / 1000.0

    ### THD-1 Temperature at the colder of the two heating design conditions in PHIUS, 2021
    ### ('Heating design temperature' in REF: Wright (2019))
    thd_degree_c = stat_file.heating_design_info[1]
    thd_degree_f = OpenStudio.convert(thd_degree_c, 'C', 'F').get

    ### TCD  Temperature at the cooling design condition in PHIUS, 2021
    ### ('Cooling design temperature' in REF: Wright (2019))
    tcd_degree_c = stat_file.cooling_design_info[2]
    tcd_degree_f = OpenStudio.convert(tcd_degree_c.to_f, 'C', 'F').get

    ### IGHL (Irradiance, Global, at the heating design condition) (Btu/h.ft2) in PHIUS, 2021
    average_daily_global_irradiance_w_per_m2_array = []
    model.getDesignDays.each do |design_day|
      next unless design_day.dayType == 'WinterDesignDay'

      average_daily_global_irradiance_w_per_m2 = OpenstudioStandards::Weather.design_day_average_global_irradiance(design_day)
      average_daily_global_irradiance_w_per_m2_array << average_daily_global_irradiance_w_per_m2
    end
    solar_irradiance_on_heating_design_day_w_per_m_sq = average_daily_global_irradiance_w_per_m2_array.min
    solar_irradiance_on_heating_design_day_btu_per_hr_ft_sq = OpenStudio.convert(solar_irradiance_on_heating_design_day_w_per_m_sq.to_f, 'W/m^2', 'Btu/ft^2*h').get

    ### IGCL (Irradiance, Global, at the cooling design condition) (Btu/h.ft2) in PHIUS, 2021
    average_daily_global_irradiance_w_per_m2_array = []
    model.getDesignDays.each do |design_day|
      next unless design_day.dayType == 'SummerDesignDay'

      average_daily_global_irradiance_w_per_m2 = OpenstudioStandards::Weather.design_day_average_global_irradiance(design_day)
      average_daily_global_irradiance_w_per_m2_array << average_daily_global_irradiance_w_per_m2
    end
    solar_irradiance_on_cooling_design_day_w_per_m_sq = average_daily_global_irradiance_w_per_m2_array.max
    solar_irradiance_on_cooling_design_day_btu_per_hr_ft_sq = OpenStudio.convert(solar_irradiance_on_cooling_design_day_w_per_m_sq.to_f, 'W/m^2', 'Btu/ft^2*h').get

    ### occupant density (persons per ft2 of floor area)
    sum_handle = 0.0
    @btap_data['space_type_table'].each do |space_info|
      unless space_info['occ_per_m_sq'].nil?
        sum_handle += space_info['floor_m_sq'] * space_info['occ_per_m_sq']
      end
    end
    occ_density_person_per_m_sq = sum_handle / bldg_conditioned_floor_area_m_sq
    occ_density_person_per_ft_sq = OpenStudio.convert(occ_density_person_per_m_sq, 'ft^2', 'm^2').get

    ### marginal electricity price ($/kWh)
    ### ('Electricity price' in REF: Wright (2019))
    electricity_price_per_gj = @btap_data['cost_utility_neb_electricity_cost_per_m_sq'] / @btap_data['energy_eui_electricity_gj_per_m_sq']
    electricity_price_per_kwh = OpenStudio.convert(electricity_price_per_gj, 'kWh', 'GJ').get # note: this is not GJ to kWh since 1/GJ should be converted to 1/kWh.

    ### Calculate annual heating and cooling energy demands based on PHIUS
    # REF: page 27 of PHIUS 2021 Passive Building Standard Standard-Setting Documentation. Available at https://www.phius.org/phius-certification-for-buildings-products/project-certification/phius-2021-emissions-down-scale-up
    annual_heating_demand_kbtu_per_ft_sq_phius = 3.2606827206 +
                                                 1.1634499236 * envelope_to_floor_area_ratio +
                                                 904.39163818 * unit_density_per_ft_sq +
                                                 0.000604853 * hdd65_degree_f_days +
                                                 -0.001645777 * annual_ghi_kwh_per_m_sq +
                                                 -11.87299596 * electricity_price_per_kwh +
                                                 (envelope_to_floor_area_ratio - 1.766) * (envelope_to_floor_area_ratio - 1.766) * 0.8314860529 +
                                                 (envelope_to_floor_area_ratio - 1.766) * (hdd65_degree_f_days - 5860.0833333) * 0.0002310823 +
                                                 (hdd65_degree_f_days - 5860.0833333) * (hdd65_degree_f_days - 5860.0833333) * -5.736435e-8 +
                                                 (hdd65_degree_f_days - 5860.0833333) * (annual_ghi_kwh_per_m_sq - 1451.0633333) * -3.260379e-7 +
                                                 (envelope_to_floor_area_ratio - 1.766) * (electricity_price_per_kwh - -0.2029193333) * -3.851052937 +
                                                 (hdd65_degree_f_days - 5860.0833333) * (electricity_price_per_kwh - -0.2029193333) * -0.001897043
    annual_heating_demand_kwh_per_m_sq_phius = OpenStudio.convert(annual_heating_demand_kbtu_per_ft_sq_phius, 'kBtu/ft^2', 'kWh/m^2').get
    @btap_data.merge!('phius_annual_heating_demand_kwh_per_m_sq' => annual_heating_demand_kwh_per_m_sq_phius)

    # REF: page 28 of PHIUS 2021 Passive Building Standard Standard-Setting Documentation. Available at https://www.phius.org/phius-certification-for-buildings-products/project-certification/phius-2021-emissions-down-scale-up
    annual_cooling_demand_kbtu_per_ft_sq_phius = -6.510791255 +
                                                 -0.749993351 * envelope_to_floor_area_ratio +
                                                 0.0004550801 * cdd50_degree_f_days +
                                                 0.004990109 * annual_ghi_kwh_per_m_sq +
                                                 7.9460878688 * dehumidification_degree_days +
                                                 (envelope_to_floor_area_ratio - 1.766) * (envelope_to_floor_area_ratio - 1.766) * 1.6367059356 +
                                                 (cdd50_degree_f_days - 4104.8333333) * (cdd50_degree_f_days - 4104.8333333) * 8.6952014e-8 +
                                                 (envelope_to_floor_area_ratio - 1.766) * (annual_ghi_kwh_per_m_sq - 1451.0633333) * 0.001671947 +
                                                 (cdd50_degree_f_days - 4104.8333333) * (annual_ghi_kwh_per_m_sq - 1451.0633333) * 0.0000013639 +
                                                 (unit_density_per_ft_sq - 0.0008646735) * (dehumidification_degree_days - 0.3233057481) * 5547.7542211 +
                                                 (dehumidification_degree_days - 0.3233057481) * (electricity_price_per_kwh - 0.2029193333) * -15.67511944 +
                                                 1624.6144639 * unit_density_per_ft_sq
    annual_cooling_demand_kwh_per_m_sq_phius = OpenStudio.convert(annual_cooling_demand_kbtu_per_ft_sq_phius, 'kBtu/ft^2', 'kWh/m^2').get
    @btap_data.merge!('phius_annual_cooling_demand_kwh_per_m_sq' => annual_cooling_demand_kwh_per_m_sq_phius)

    ### Calculate peak heating and cooling loads based on PHIUS
    # REF: page 29 of PHIUS 2021 Passive Building Standard Standard-Setting Documentation. Available at https://www.phius.org/phius-certification-for-buildings-products/project-certification/phius-2021-emissions-down-scale-up
    peak_heating_load_btu_per_hr_ft_sq_phius = 4.6700403241 +
                                               0.6774809481 * envelope_to_floor_area_ratio +
                                               239.08369574 * occ_density_person_per_ft_sq +
                                               596.681543 * unit_density_per_ft_sq +
                                               -0.000177742 * hdd65_degree_f_days +
                                               -0.076727655 * thd_degree_f +
                                               -0.03316804 * solar_irradiance_on_heating_design_day_btu_per_hr_ft_sq +
                                               -4.140193817 * electricity_price_per_kwh +
                                               (envelope_to_floor_area_ratio - 1.766) * (envelope_to_floor_area_ratio - 1.766) * 0.8449921713 +
                                               (hdd65_degree_f_days - 5860.0833333) * (hdd65_degree_f_days - 5860.0833333) * 2.8376386e-8 +
                                               (envelope_to_floor_area_ratio - 1.766) * (thd_degree_f - 14.7102) * -0.013821021 +
                                               (unit_density_per_ft_sq - 0.0008646735) * (thd_degree_f - 14.7102) * -20.10551451 +
                                               (hdd65_degree_f_days - 5860.0833333) * (thd_degree_f - 14.7102) * 5.1870203e-6 +
                                               (thd_degree_f - 14.7102) * (electricity_price_per_kwh - 0.2029193333) * 0.1264922802
    peak_heating_load_w_per_m_sq_phius = OpenStudio.convert(peak_heating_load_btu_per_hr_ft_sq_phius, 'Btu/ft^2*h', 'W/m^2').get
    @btap_data.merge!('phius_peak_heating_load_w_per_m_sq' => peak_heating_load_w_per_m_sq_phius)

    # REF: page 30 of PHIUS 2021 Passive Building Standard Standard-Setting Documentation. Available at https://www.phius.org/phius-certification-for-buildings-products/project-certification/phius-2021-emissions-down-scale-up
    peak_cooling_load_btu_per_hr_ft_sq_phius = -7.289806442 +
                                               98.245977611 * occ_density_person_per_ft_sq +
                                               236.93351876 * unit_density_per_ft_sq +
                                               0.0967328928 * tcd_degree_f +
                                               0.010777725 * solar_irradiance_on_cooling_design_day_btu_per_hr_ft_sq +
                                               (cdd50_degree_f_days - 4104.8333333) * (cdd50_degree_f_days - 4104.8333333) * 1.7699655e-8 +
                                               (cdd50_degree_f_days - 4104.8333333) * (tcd_degree_f - 78.127) * 6.5268802e-6 +
                                               (tcd_degree_f - 78.127) * (envelope_to_floor_area_ratio - 1.766) * 0.0165401721 +
                                               (tcd_degree_f - 78.127) * (occ_density_person_per_ft_sq - 0.0027218) * 8.0465528305 +
                                               (cdd50_degree_f_days - 4104.8333333) * (envelope_to_floor_area_ratio - 1.766) * 0.0000322288 +
                                               (envelope_to_floor_area_ratio - 1.766) * (envelope_to_floor_area_ratio - 1.766) * 0.6579032913
    peak_cooling_load_w_per_m_sq_phius = OpenStudio.convert(peak_cooling_load_btu_per_hr_ft_sq_phius, 'Btu/ft^2*h', 'W/m^2').get
    @btap_data.merge!('phius_peak_cooling_load_w_per_m_sq' => peak_cooling_load_w_per_m_sq_phius)

    ### Gather annual heating and cooling energy demands based on NECB

    annual_heating_demand_kwh_per_m_sq_necb = OpenStudio.convert(@btap_data['energy_eui_heating_gj_per_m_sq'], 'GJ', 'kWh') unless @btap_data['energy_eui_heating_gj_per_m_sq'].nil?
    annual_cooling_demand_kwh_per_m_sq_necb = OpenStudio.convert(@btap_data['energy_eui_cooling_gj_per_m_sq'], 'GJ', 'kWh') unless @btap_data['energy_eui_cooling_gj_per_m_sq'].nil?

    ### Gather peak heating and cooling loads based on NECB
    peak_heating_load_w_per_m_sq_necb = @btap_data['heating_peak_w_per_m_sq']
    peak_cooling_load_w_per_m_sq_necb = @btap_data['cooling_peak_w_per_m_sq']
    @btap_data.merge!('peak_heating_load_w_per_m_sq_necb' => peak_heating_load_w_per_m_sq_necb)
    @btap_data.merge!('peak_cooling_load_w_per_m_sq_necb' => peak_cooling_load_w_per_m_sq_necb)

    ### Compare annual heating and cooling energy demands of NECB with PHIUS to see if NECB meets PHIUS
    if annual_heating_demand_kwh_per_m_sq_necb.to_f <= annual_heating_demand_kwh_per_m_sq_phius.to_f
      @btap_data.merge!('phius_necb_meet_heating_demand' => 'True')
    else
      @btap_data.merge!('phius_necb_meet_heating_demand' => 'False')
    end
    if annual_cooling_demand_kwh_per_m_sq_necb.to_f <= annual_cooling_demand_kwh_per_m_sq_phius.to_f
      @btap_data.merge!('phius_necb_meet_cooling_demand' => 'True')
    else
      @btap_data.merge!('phius_necb_meet_cooling_demand' => 'False')
    end

    ### Compare peak heating and cooling loads of NECB with PHIUS to see if NECB meets PHIUS
    if peak_heating_load_w_per_m_sq_necb.to_f <= peak_heating_load_w_per_m_sq_phius.to_f
      @btap_data.merge!('phius_necb_meet_heating_peak_load' => 'True')
    else
      @btap_data.merge!('phius_necb_meet_heating_peak_load' => 'False')
    end
    if peak_cooling_load_w_per_m_sq_necb.to_f <= peak_cooling_load_w_per_m_sq_phius.to_f
      @btap_data.merge!('phius_necb_meet_cooling_peak_load' => 'True')
    else
      @btap_data.merge!('phius_necb_meet_cooling_peak_load' => 'False')
    end
    # def phius_metrics(model)
  end

  def get_national_ghg_cost(year:)
    raise "Nil year submitted for national ghg cost" if year.nil?
    year = year.to_i
    if year < 2019
      price = 0.0
    elsif (year >= 2019) && (year <= 2030)
      ghg_price_data = @standards_data["tables"]["canada_national_carbon_pricing"]["table"]
      year_price = ghg_price_data.detect { |item| (item["year"].to_i == year) }
      price = year_price["price_per_tonne"].to_f
    elsif (year > 2030)
      price = 170.0
    end
    return price.to_f
  end
end
