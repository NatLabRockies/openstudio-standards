class NECB2011
  attr_accessor :qaqc_data

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
      row_hash[:name] = row
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
          # If the column name is "additional_fuel" and the file contains a boiler with a FuelOilNo2 fuel type assume
          # the column name should be "fueloilno2".
          if column_name.include? 'additional_fuel'
            model.getPlantLoops.sort.each do |iplantloop|
              boilers = iplantloop.components.select { |icomponent| icomponent.to_BoilerHotWater.is_initialized }
              column_name = 'fueloilno2' unless boilers.select { |boiler| boiler.to_BoilerHotWater.get.fuelType.to_s == 'FuelOilNo2' }.empty?
            end
          end
          column_name += "_#{unit}" if unit != ''
          value = model.sqlFile.get.execAndReturnFirstString(query)
          next if value.empty? || value.get.nil?

          value = value.get.strip
          # check is value is a number
          if (begin
                Float(value)
              rescue StandardError
                false
              end) && value.to_f != 0
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
    result = { report_name: report_name, report_for_string: report_for_string, table_name: table_name, table: table }
    return result
  end

  def merge_recursively(a, b)
    a.merge(b) { |key, a_item, b_item| merge_recursively(a_item, b_item) }
  end

  def get_sql_tables_to_json(model)
    sql_data = []
    sql_data << get_sql_table_to_json(model, 'AnnualBuildingUtilityPerformanceSummary', 'Entire Facility', 'End Uses')
    sql_data << get_sql_table_to_json(model, 'AnnualBuildingUtilityPerformanceSummary', 'Entire Facility', 'Site and Source Energy')
    # sql_data << get_sql_table_to_json(model, "AnnualBuildingUtilityPerformanceSummary", "Entire Facility", "On-Site Thermal Sources")
    # sql_data << get_sql_table_to_json(model, "AnnualBuildingUtilityPerformanceSummary", "Entire Facility", "Comfort and Setpoint Not Met Summary")
    # sql_data << get_sql_table_to_json(model, "InputVerificationandResultsSummary", "Entire Facility", "Window-Wall Ratio")
    # sql_data << get_sql_table_to_json(model, "InputVerificationandResultsSummary", "Entire Facility", "Conditioned Window-Wall Ratio")
    # sql_data << get_sql_table_to_json(model, "InputVerificationandResultsSummary", "Entire Facility", "Skylight-Roof Ratio")
    # sql_data << get_sql_table_to_json(model, "DemandEndUseComponentsSummary", "Entire Facility", "End Uses")
    # sql_data << get_sql_table_to_json(model, "ComponentSizingSummary", "Entire Facility", "AirLoopHVAC")
    return sql_data
  end

  def load_qaqc_database_new
    # Combine the data from the JSON files into a single hash
    files = Dir.glob("#{File.dirname(__FILE__)}/qaqc_data/*.json").select { |e| File.file? e }
    @qaqc_data = {}
    @qaqc_data['tables'] = {}
    files.each do |file|
      # puts "loading qaqc data from #{file}"
      data = JSON.parse(File.read(file))
      if !data['tables'].nil?
        @qaqc_data['tables'] = [*@qaqc_data['tables'], *data['tables']].to_h
      else
        @qaqc_data[data.keys.first] = data[data.keys.first]
      end
    end
    # Write test report file.
    test_result_file = File.join(File.dirname(__FILE__), '..', 'NECB2011_QAQC.json')
    File.open(test_result_file, 'w') { |f| f.write(JSON.pretty_generate(@qaqc_data)) }
    return @qaqc_data
  end

  def get_qaqc_table(table_name:, search_criteria: nil)
    return_objects = nil
    table = @qaqc_data['tables'][table_name]
    raise("could not find #{table_name} in qaqc table database. ") if table.nil?

    return table if search_criteria.nil? # removed table beause need to use the object['refs']

    rows = table['table']
    search_criteria.each do |key, value|
      rows = rows.select { |row| row[key] == value }
    end
    return rows
  end

  # generates full qaqc.json
  def init_qaqc(model)
    # load the qaqc.json files
    # This is currently disabled as most tests are now done using regression and unit tests.. but we may bring this back.
    # @qaqc_data = self.load_qaqc_database_new()

    # generate base qaqc hash
    qaqc = create_base_data(model)
    # performs the qaqc on the given base qaqc hash
    # necb_qaqc(qaqc, model)
    return qaqc
  end

  # generates only qaqc component
  def qaqc_only(model)
    # load the qaqc.json files
    @qaqc_data = load_qaqc_database_new

    # generate base qaqc hash
    qaqc = create_base_data(model)
    # performs the qaqc on the given base qaqc hash.
    # using `qaqc.clone` as an argument to pass in a shallow copy, so that the argument passed can stay unmodified.
    necb_qaqc_with_base = necb_qaqc(qaqc.clone, model)

    # subract base data from qaqc
    return (necb_qaqc_with_base.to_a - qaqc.to_a).to_h
  end

  # Generates the base data hash mainly used to perform qaqc.
  def create_base_data(model)
    # construct command with local libs
    os_version = OpenStudio.openStudioLongVersion
    eplus_version = OpenStudio.energyPlusVersion
    puts "\n\n\nOS_version is [#{os_version.strip}]"
    puts "\n\n\nEP_version is [#{eplus_version.strip}]"

    # Ensure all surfaces are unique.
    surfaces = model.getSurfaces.sort

    # Sort surfaces by type

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

    # Peaks
    electric_peak = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" \
                                                                       " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Electricity' AND RowName='Electricity:Facility'" \
                                                                       " AND ColumnName='Electricity Maximum Value' AND Units='W'")
    natural_gas_peak = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" \
                                                                          " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Natural Gas' AND RowName='NaturalGas:Facility'" \
                                                                          " AND ColumnName='Natural Gas Maximum Value' AND Units='W'")

    get_sql_tables_to_json(model)

    # Create hash to store all the collected data.
    qaqc = {}
    qaqc[:sql_data] = get_sql_tables_to_json(model)
    error_warning = []
    qaqc[:os_standards_revision] = OpenstudioStandards.git_revision
    qaqc[:os_standards_version] = OpenstudioStandards::VERSION
    qaqc[:openstudio_version] = os_version.strip
    qaqc[:energyplus_version] = eplus_version.strip
    # Store Building data.
    qaqc[:building] = {}
    qaqc[:building][:name] = model.building.get.name.get
    qaqc[:building][:conditioned_floor_area_m2] = nil
    if model.building.get.conditionedFloorArea.empty?
      error_warning << "model.building.get.conditionedFloorArea() is empty for #{model.building.get.name.get}"
    else
      qaqc[:building][:conditioned_floor_area_m2] = model.building.get.conditionedFloorArea.get
    end
    qaqc[:building][:exterior_area_m2] = model.building.get.exteriorSurfaceArea # m2
    qaqc[:building][:volume] = model.building.get.airVolume # m3
    qaqc[:building][:number_of_stories] = model.getBuildingStorys.size
    qaqc[:building][:standards_number_of_stories] = nil
    qaqc[:building][:standards_number_of_stories] = model.building.get.standardsNumberOfStories.get unless model.building.get.standardsNumberOfStories.empty?
    qaqc[:building][:standards_number_of_above_ground_stories] = nil
    qaqc[:building][:standards_number_of_above_ground_stories] = model.building.get.standardsNumberOfAboveGroundStories.get unless model.building.get.standardsNumberOfAboveGroundStories.empty?
    qaqc[:building][:standards_number_of_living_units] = nil
    qaqc[:building][:standards_number_of_living_units] = model.building.get.standardsNumberOfLivingUnits.get unless model.building.get.standardsNumberOfLivingUnits.empty?
    qaqc[:building][:nominal_floor_to_ceiling_height] = nil
    qaqc[:building][:nominal_floor_to_ceiling_height] = model.building.get.nominalFloortoCeilingHeight.get unless model.building.get.nominalFloortoCeilingHeight.empty?
    qaqc[:building][:nominal_floor_to_floor_height] = nil
    qaqc[:building][:nominal_floor_to_floor_height] = model.building.get.nominalFloortoFloorHeight.get unless model.building.get.nominalFloortoFloorHeight.empty?

    # Store Geography Data
    qaqc[:geography] = {}
    qaqc[:geography][:hdd_necb] = get_necb_hdd18(model: model, necb_hdd: true)
    qaqc[:geography][:hdd] = get_necb_hdd18(model: model, necb_hdd: false)
    weather_file_path = model.weatherFile.get.path.get.to_s
    stat_file_path = weather_file_path.gsub('.epw', '.stat')
    stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
    qaqc[:geography][:cdd] = stat_file.cdd18
    qaqc[:geography][:climate_zone] = NECB2011.new.get_climate_zone_name(qaqc[:geography][:hdd])
    qaqc[:geography][:city] = model.getWeatherFile.city
    qaqc[:geography][:state_province_region] = model.getWeatherFile.stateProvinceRegion
    qaqc[:geography][:country] = model.getWeatherFile.country
    qaqc[:geography][:latitude] = model.getWeatherFile.latitude
    qaqc[:geography][:longitude] = model.getWeatherFile.longitude

    # Spacetype Breakdown
    qaqc[:spacetype_area_breakdown] = {}
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
      qaqc[:spacetype_area_breakdown][spaceType.name.get.gsub(/\s+/, '_').downcase.to_sym] = floor_area_si
    end

    # Economics Section
    qaqc[:economics] = {}
    provinces_names_map = { 'QC' => 'Quebec', 'NL' => 'Newfoundland and Labrador', 'NS' => 'Nova Scotia', 'PE' => 'Prince Edward Island', 'ON' => 'Ontario', 'MB' => 'Manitoba', 'SK' => 'Saskatchewan', 'AB' => 'Alberta', 'BC' => 'British Columbia', 'YT' => 'Yukon', 'NT' => 'Northwest Territories', 'NB' => 'New Brunswick', 'NU' => 'Nunavut' }
    neb_prices_csv_file_name = "#{File.dirname(__FILE__)}/qaqc_resources/neb_end_use_prices.csv"
    puts neb_prices_csv_file_name
    building_type = 'Commercial'
    province = provinces_names_map[qaqc[:geography][:state_province_region]]
    neb_fuel_list = ['Electricity', 'Natural Gas', 'Oil']
    neb_eplus_fuel_map = { 'Electricity' => 'Electricity', 'Natural Gas' => 'Gas', 'Oil' => 'FuelOilNo2' }
    qaqc[:economics][:total_neb_cost] = 0.0
    qaqc[:economics][:total_neb_cost_per_m2] = 0.0
    neb_eplus_fuel_map.each do |neb_fuel, ep_fuel|
      search_info = {
        0 => building_type,
        1 => province,
        2 => neb_fuel
      }
      row = look_up_csv_data(neb_prices_csv_file_name, search_info)
      neb_fuel_cost = row['2020']
      fuel_consumption_gj = 0.0
      if neb_fuel == 'Electricity' || neb_fuel == 'Natural Gas'
        if model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters' AND ReportForString='Entire Facility' AND
        TableName='Annual and Peak Values - #{ep_fuel}' AND RowName='#{ep_fuel}:Facility' AND ColumnName='#{ep_fuel} Annual Value' AND Units='GJ'").is_initialized
          fuel_consumption_gj = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters' AND ReportForString='Entire Facility' AND
        TableName='Annual and Peak Values - #{ep_fuel}' AND RowName='#{ep_fuel}:Facility' AND ColumnName='#{ep_fuel} Annual Value' AND Units='GJ'").get
        end
      else
        if model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters' AND ReportForString='Entire Facility' AND
        TableName='Annual and Peak Values - Other' AND RowName='#{ep_fuel}:Facility' AND ColumnName='Annual Value' AND Units='GJ'").is_initialized
          fuel_consumption_gj = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters' AND ReportForString='Entire Facility' AND
        TableName='Annual and Peak Values - Other' AND RowName='#{ep_fuel}:Facility' AND ColumnName='Annual Value' AND Units='GJ'").get
        end
      end
      qaqc[:economics][:"#{neb_fuel}_neb_cost"] = fuel_consumption_gj * neb_fuel_cost.to_f
      qaqc[:economics][:"#{neb_fuel}_neb_cost_per_m2"] = qaqc[:economics][:"#{neb_fuel}_neb_cost"] / qaqc[:building][:conditioned_floor_area_m2] unless model.building.get.conditionedFloorArea.empty?
      qaqc[:economics][:total_neb_cost] += qaqc[:economics][:"#{neb_fuel}_neb_cost"]
      qaqc[:economics][:total_neb_cost_per_m2] += qaqc[:economics][:"#{neb_fuel}_neb_cost_per_m2"] || 0.0
    end

    # Fuel cost based local utility rates
    costing_rownames = model.sqlFile.get.execAndReturnVectorOfString("SELECT RowName FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost'")
    #==> ["Electricity", "Natural Gas", "Additional", "Total"]
    costing_rownames = validate_optional(costing_rownames, model, 'N/A')
    if costing_rownames != 'N/A'
      costing_rownames.each do |rowname|
        case rowname
          when 'Electricity'
            qaqc[:economics][:electricity_cost] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost' AND RowName='#{rowname}'").get
            qaqc[:economics][:electricity_cost_per_m2] = qaqc[:economics][:electricity_cost] / qaqc[:building][:conditioned_floor_area_m2] unless model.building.get.conditionedFloorArea.empty?
          when 'Natural Gas'
            qaqc[:economics][:natural_gas_cost] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost' AND RowName='#{rowname}'").get
            qaqc[:economics][:natural_gas_cost_per_m2] = qaqc[:economics][:natural_gas_cost] / qaqc[:building][:conditioned_floor_area_m2] unless model.building.get.conditionedFloorArea.empty?

          when 'Additional'
            qaqc[:economics][:additional_cost] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost' AND RowName='#{rowname}'").get
            qaqc[:economics][:additional_cost_per_m2] = qaqc[:economics][:additional_cost] / qaqc[:building][:conditioned_floor_area_m2] unless model.building.get.conditionedFloorArea.empty?

          when 'Total'
            qaqc[:economics][:total_cost] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost' AND RowName='#{rowname}'").get
            qaqc[:economics][:total_cost_per_m2] = qaqc[:economics][:total_cost] / qaqc[:building][:conditioned_floor_area_m2] unless model.building.get.conditionedFloorArea.empty?
        end
      end
    else
      error_warning << "costing is unavailable because the sql statement is nil RowName FROM TabularDataWithStrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-7. Energy Cost Summary' AND ColumnName='Total Energy Cost'"
    end

    # Store end_use data
    end_uses = [
      'Heating',
      'Cooling',
      'Interior Lighting',
      'Exterior Lighting',
      'Interior Equipment',
      'Exterior Equipment',
      'Fans',
      'Pumps',
      'Heat Rejection',
      'Humidification',
      'Heat Recovery',
      'Water Systems',
      'Refrigeration',
      'Generators',
      'Total End Uses'
    ]

    fuels = [
      ['Electricity', 'GJ'],
      ['Natural Gas', 'GJ'],
      ['Additional Fuel', 'GJ'],
      ['District Cooling', 'GJ'],
      ['District Heating', 'GJ']
    ]

    qaqc[:end_uses] = {}
    qaqc[:end_uses_eui] = {}
    end_uses.each do |use_type|
      qaqc[:end_uses]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_gj"] = 0
      qaqc[:end_uses_eui]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_gj_per_m2"] = 0
      fuels.each do |fuel_type|
        value = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND RowName='#{use_type}' AND ColumnName='#{fuel_type[0]}' AND Units='#{fuel_type[1]}'")
        if value.empty? || (value.get == 0)
        else
          qaqc[:end_uses]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_gj"] += value.get
          unless qaqc[:building][:conditioned_floor_area_m2].nil?
            qaqc[:end_uses_eui]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_gj_per_m2"] += value.get / qaqc[:building][:conditioned_floor_area_m2]
          end
        end
      end
      value = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND RowName='#{use_type}' AND ColumnName='Water' AND Units='m3'")
      if value.empty? || (value.get == 0)
      else
        qaqc[:end_uses]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_water_m3"] = value.get
        unless qaqc[:building][:conditioned_floor_area_m2].nil?
          qaqc[:end_uses_eui]["#{use_type.gsub(/\s+/, '_').downcase.to_sym}_water_m3_per_m2"] = value.get / qaqc[:building][:conditioned_floor_area_m2]
        end
      end
    end

    # Store Peak Data
    qaqc[:meter_peaks] = {}
    qaqc[:meter_peaks][:electric_w] = electric_peak.empty? ? 'NA' : electric_peak.get
    qaqc[:meter_peaks][:natural_gas_w] = natural_gas_peak.empty? ? 'NA' : natural_gas_peak.get

    # Store unmet hour data
    qaqc[:unmet_hours] = {}
    qaqc[:unmet_hours][:cooling] = model.getFacility.hoursCoolingSetpointNotMet.get unless model.getFacility.hoursCoolingSetpointNotMet.empty?
    qaqc[:unmet_hours][:heating] = model.getFacility.hoursHeatingSetpointNotMet.get unless model.getFacility.hoursHeatingSetpointNotMet.empty?

    # puts "\n\n\n#{costing_rownames}\n\n\n"
    # Padmassun's Code -- Tarrif end

    # Padmassun's Code -- Service Hotwater Heating *start*
    qaqc[:service_water_heating] = {}
    qaqc[:service_water_heating][:total_nominal_occupancy] = -1
    # qaqc[:service_water_heating][:total_nominal_occupancy]=model.sqlFile().get().execAndReturnVectorOfDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='OutdoorAirSummary' AND ReportForString='Entire Facility' AND TableName='Average Outdoor Air During Occupied Hours' AND ColumnName='Nominal Number of Occupants'").get.inject(0, :+)
    qaqc[:service_water_heating][:total_nominal_occupancy] = get_total_nominal_capacity(model)

    qaqc[:service_water_heating][:electricity_per_year] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Electricity' AND RowName='Water Systems'")
    qaqc[:service_water_heating][:electricity_per_year] = validate_optional(qaqc[:service_water_heating][:electricity_per_year], model, -1)

    qaqc[:service_water_heating][:electricity_per_day] = qaqc[:service_water_heating][:electricity_per_year] / 365.5
    qaqc[:service_water_heating][:electricity_per_day_per_occupant] = qaqc[:service_water_heating][:electricity_per_day] / qaqc[:service_water_heating][:total_nominal_occupancy]

    qaqc[:service_water_heating][:natural_gas_per_year] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Natural Gas' AND RowName='Water Systems'")
    qaqc[:service_water_heating][:natural_gas_per_year] = validate_optional(qaqc[:service_water_heating][:natural_gas_per_year], model, -1)

    qaqc[:service_water_heating][:additional_fuel_per_year] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Additional Fuel' AND RowName='Water Systems'")
    qaqc[:service_water_heating][:additional_fuel_per_year] = validate_optional(qaqc[:service_water_heating][:additional_fuel_per_year], model, -1)

    qaqc[:service_water_heating][:water_m3_per_year] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND ColumnName='Water' AND RowName='Water Systems'")
    qaqc[:service_water_heating][:water_m3_per_year] = validate_optional(qaqc[:service_water_heating][:water_m3_per_year], model, -1)

    qaqc[:service_water_heating][:water_m3_per_day] = qaqc[:service_water_heating][:water_m3_per_year] / 365.5
    qaqc[:service_water_heating][:water_m3_per_day_per_occupant] = qaqc[:service_water_heating][:water_m3_per_day] / qaqc[:service_water_heating][:total_nominal_occupancy]
    # puts qaqc[:service_water_heating][:total_nominal_occupancy]
    # Padmassun's Code -- Service Hotwater Heating *end*

    # Store Envelope data.
    qaqc[:envelope] = {}
    # Get Areas
    qaqc[:envelope][:outdoor_walls_area_m2] = outdoor_walls.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:outdoor_roofs_area_m2] = outdoor_roofs.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:outdoor_floors_area_m2] = outdoor_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:ground_walls_area_m2] = ground_walls.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:ground_roofs_area_m2] = ground_roofs.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:ground_floors_area_m2] = ground_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }
    qaqc[:envelope][:interior_floors_area_m2] = interior_floors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier }

    # Subsurface areas
    qaqc[:envelope][:windows_area_m2] = windows.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    qaqc[:envelope][:skylights_area_m2] = skylights.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    qaqc[:envelope][:doors_area_m2] = doors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }
    qaqc[:envelope][:overhead_doors_area_m2] = overhead_doors.inject(0) { |sum, e| sum + e.netArea * e.space.get.multiplier * e.multiplier }

    # Total Building Surface Area.
    qaqc[:envelope][:total_exterior_area_m2] = qaqc[:envelope][:outdoor_walls_area_m2] +
                                               qaqc[:envelope][:outdoor_roofs_area_m2] +
                                               qaqc[:envelope][:outdoor_floors_area_m2] +
                                               qaqc[:envelope][:ground_walls_area_m2] +
                                               qaqc[:envelope][:ground_roofs_area_m2] +
                                               qaqc[:envelope][:ground_floors_area_m2] +
                                               qaqc[:envelope][:windows_area_m2] +
                                               qaqc[:envelope][:skylights_area_m2] +
                                               qaqc[:envelope][:doors_area_m2] +
                                               qaqc[:envelope][:overhead_doors_area_m2]
    # Total Building Ground Surface Area.
    qaqc[:envelope][:total_ground_area_m2] = qaqc[:envelope][:ground_walls_area_m2] +
                                             qaqc[:envelope][:ground_roofs_area_m2] +
                                             qaqc[:envelope][:ground_floors_area_m2]
    # Total Building Outdoor Surface Area.
    qaqc[:envelope][:total_outdoor_area_m2] = qaqc[:envelope][:outdoor_walls_area_m2] +
                                              qaqc[:envelope][:outdoor_roofs_area_m2] +
                                              qaqc[:envelope][:outdoor_floors_area_m2] +
                                              qaqc[:envelope][:windows_area_m2] +
                                              qaqc[:envelope][:skylights_area_m2] +
                                              qaqc[:envelope][:doors_area_m2] +
                                              qaqc[:envelope][:overhead_doors_area_m2]

    # Average Conductances by surface Type
    qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_walls).round(4) if !outdoor_walls.empty?
    qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_roofs).round(4) if !outdoor_roofs.empty?
    qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_floors).round(4) if !outdoor_floors.empty?
    qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_walls).round(4) if !ground_walls.empty?
    qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_roofs).round(4) if !ground_roofs.empty?
    qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_floors).round(4) if !ground_floors.empty?
    qaqc[:envelope][:windows_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(windows).round(4) if !windows.empty?
    qaqc[:envelope][:skylights_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(skylights).round(4) if !skylights.empty?
    qaqc[:envelope][:doors_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(doors).round(4) if !doors.empty?
    qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k] = OpenstudioStandards::Constructions.surfaces_get_conductance(overhead_doors).round(4) if !overhead_doors.empty?

    # #Average Conductances for building whole weight factors
    !outdoor_walls.empty? ? o_wall_cond_weight = qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k] * qaqc[:envelope][:outdoor_walls_area_m2] : o_wall_cond_weight = 0
    !outdoor_roofs.empty? ? o_roof_cond_weight = qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k] * qaqc[:envelope][:outdoor_roofs_area_m2] : o_roof_cond_weight = 0
    !outdoor_floors.empty? ? o_floor_cond_weight = qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k] * qaqc[:envelope][:outdoor_floors_area_m2] : o_floor_cond_weight = 0
    !ground_walls.empty?   ? g_wall_cond_weight = qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k] * qaqc[:envelope][:ground_walls_area_m2] : g_wall_cond_weight = 0
    !ground_roofs.empty?   ? g_roof_cond_weight = qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k] * qaqc[:envelope][:ground_roofs_area_m2] : g_roof_cond_weight = 0
    !ground_floors.empty?  ? g_floor_cond_weight = qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k] * qaqc[:envelope][:ground_floors_area_m2] : g_floor_cond_weight = 0
    !windows.empty?        ? win_cond_weight = qaqc[:envelope][:windows_average_conductance_w_per_m2_k] * qaqc[:envelope][:windows_area_m2] : win_cond_weight = 0
    # doors.size > 0 ? sky_cond_weight = qaqc[:envelope][:skylights_average_conductance_w_per_m2_k] * qaqc[:envelope][:skylights_area_m2] : sky_cond_weight = 0
    if !doors.empty? && !qaqc[:envelope][:skylights_average_conductance_w_per_m2_k].nil? && !qaqc[:envelope][:skylights_area_m2].nil?
      sky_cond_weight = qaqc[:envelope][:skylights_average_conductance_w_per_m2_k] * qaqc[:envelope][:skylights_area_m2]
    else
      sky_cond_weight = 0
    end
    !overhead_doors.empty? ? door_cond_weight = qaqc[:envelope][:doors_average_conductance_w_per_m2_k] * qaqc[:envelope][:doors_area_m2] : door_cond_weight = 0
    !overhead_doors.empty? ? overhead_door_cond_weight = qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k] * qaqc[:envelope][:overhead_doors_area_m2] : overhead_door_cond_weight = 0

    # Building Average Conductance
    qaqc[:envelope][:building_outdoor_average_conductance_w_per_m2_k] = (
    o_floor_cond_weight +
        o_roof_cond_weight +
        o_wall_cond_weight +
        win_cond_weight +
        sky_cond_weight +
        door_cond_weight +
        overhead_door_cond_weight) / qaqc[:envelope][:total_outdoor_area_m2]

    # Building Average Ground Conductance
    qaqc[:envelope][:building_ground_average_conductance_w_per_m2_k] = (
    g_floor_cond_weight +
        g_roof_cond_weight +
        g_wall_cond_weight) / qaqc[:envelope][:total_ground_area_m2]

    # Building Average Conductance
    qaqc[:envelope][:building_average_conductance_w_per_m2_k] = (
    (qaqc[:envelope][:building_ground_average_conductance_w_per_m2_k] * qaqc[:envelope][:total_ground_area_m2]) +
        (qaqc[:envelope][:building_outdoor_average_conductance_w_per_m2_k] * qaqc[:envelope][:total_outdoor_area_m2])
  ) /
                                                                (qaqc[:envelope][:total_ground_area_m2] + qaqc[:envelope][:total_outdoor_area_m2])

    qaqc[:envelope][:fdwr] = (BTAP::Geometry.get_fwdr(model) * 100.0).round(1)
    qaqc[:envelope][:srr] = (BTAP::Geometry.get_srr(model) * 100.0).round(1)

    qaqc[:envelope][:constructions] = {}
    qaqc[:envelope][:constructions][:exterior_fenestration] = []
    constructions = []
    outdoor_subsurfaces.each { |surface| constructions << surface.construction.get }
    ext_const_base = Hash.new(0)
    constructions.each { |name| ext_const_base[name.to_Construction.get] += 1 }
    # iterate thought each construction and get store data
    ext_const_base.sort.each do |construction, count|
      construction_info = {}
      qaqc[:envelope][:constructions][:exterior_fenestration] << construction_info
      construction_info[:name] = construction.name.get
      construction_info[:net_area_m2] = construction.getNetArea.round(2)
      construction_info[:thermal_conductance_m2_w_per_k] = OpenstudioStandards::Constructions.construction_get_conductance(construction).round(3)
      construction_info[:solar_transmittance] = OpenstudioStandards::Constructions.construction_get_solar_transmittance(construction).round(3)
      construction_info[:visible_tranmittance] = OpenstudioStandards::Constructions.construction_get_visible_transmittance(construction).round(3)
    end

    # Exterior
    qaqc[:envelope][:constructions][:exterior_opaque] = []
    constructions = []
    outdoor_surfaces.each { |surface| constructions << surface.construction.get }
    ext_const_base = Hash.new(0)
    constructions.each { |name| ext_const_base[name.to_Construction.get] += 1 }
    # iterate thought each construction and get store data
    ext_const_base.sort.each do |construction, count|
      construction_info = {}
      qaqc[:envelope][:constructions][:exterior_opaque] << construction_info
      construction_info[:name] = construction.name.get
      construction_info[:net_area_m2] = construction.getNetArea.round(2)
      construction_info[:thermal_conductance_m2_w_per_k] = construction.thermalConductance.get.round(3) if construction.thermalConductance.is_initialized
      construction_info[:net_area_m2] = construction.to_Construction.get.getNetArea.round(2)
      construction_info[:solar_absorptance] = construction.to_Construction.get.layers[0].exteriorVisibleAbsorptance.get
    end

    # Ground
    qaqc[:envelope][:constructions][:ground] = []
    constructions = []
    ground_surfaces.each { |surface| constructions << surface.construction.get }
    ext_const_base = Hash.new(0)
    constructions.each { |name| ext_const_base[name.to_Construction.get] += 1 }
    # iterate thought each construction and get store data
    ext_const_base.sort.each do |construction, count|
      construction_info = {}
      qaqc[:envelope][:constructions][:ground] << construction_info
      construction_info[:name] = construction.name.get
      construction_info[:net_area_m2] = construction.getNetArea.round(2)
      construction_info[:thermal_conductance_m2_w_per_k] = construction.thermalConductance.get.round(3) if construction.thermalConductance.is_initialized
      construction_info[:net_area_m2] = construction.to_Construction.get.getNetArea.round(2)
      construction_info[:solar_absorptance] = construction.to_Construction.get.layers[0].exteriorVisibleAbsorptance.get
    end

    qaqc[:envelope][:average_thermal_conductance_m2_w_per_k] =
      # Store Space data.
      qaqc[:spaces] = []
    model.getSpaces.sort.each do |space|
      spaceinfo = {}
      qaqc[:spaces] << spaceinfo
      spaceinfo[:name] = space.name.get # name should be defined test
      spaceinfo[:multiplier] = space.multiplier
      spaceinfo[:volume] = space.volume # should be greater than zero
      spaceinfo[:exterior_wall_area] = space.exteriorWallArea # just for information.
      spaceinfo[:space_type_name] = space.spaceType.get.name.get unless space.spaceType.empty? # should have a space types name defined.
      spaceinfo[:thermal_zone] = space.thermalZone.get.name.get unless space.thermalZone.empty? # should be assigned a thermalzone name.
      # puts space.name.get
      # puts space.thermalZone.empty?
      spaceinfo[:breathing_zone_outdoor_airflow_vbz] = -1
      breathing_zone_outdoor_airflow_vbz = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName='Zone Ventilation Parameters' AND ColumnName='Breathing Zone Outdoor Airflow - Vbz' AND Units='m3/s' AND RowName='#{spaceinfo[:thermal_zone].to_s.upcase}' ")
      spaceinfo[:breathing_zone_outdoor_airflow_vbz] = breathing_zone_outdoor_airflow_vbz.get unless breathing_zone_outdoor_airflow_vbz.empty?
      spaceinfo[:infiltration_method] = 'N/A'
      spaceinfo[:infiltration_flow_per_m2] = -1.0
      if space.spaceInfiltrationDesignFlowRates[0].nil?
        error_warning << "space.spaceInfiltrationDesignFlowRates[0] is empty for #{spaceinfo[:name]}"
        error_warning << "space.spaceInfiltrationDesignFlowRates[0].designFlowRateCalculationMethod is empty for #{spaceinfo[:name]}"
        error_warning << "space.spaceInfiltrationDesignFlowRates[0].flowperExteriorSurfaceArea is empty for #{spaceinfo[:name]}"
      else
        spaceinfo[:infiltration_method] = space.spaceInfiltrationDesignFlowRates[0].designFlowRateCalculationMethod
        spaceinfo[:infiltration_flow_per_m2] = 'N/A'
        spaceinfo[:infiltration_flow_per_m2] = space.spaceInfiltrationDesignFlowRates[0].flowperExteriorSurfaceArea.get.round(5) unless space.spaceInfiltrationDesignFlowRates[0].flowperExteriorSurfaceArea.empty?
      end

      # the following should have values unless the spacetype is "undefined" other they should be set to the correct NECB values.
      if space.spaceType.empty?
        error_warning << "space.spaceType is empty for #{space.name.get}"
      else
        spaceinfo[:occupancy_schedule] = nil
        if space.spaceType.get.defaultScheduleSet.empty?
          error_warning << "space.spaceType.get.defaultScheduleSet is empty for #{space.name.get}"
        else
          if space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule.empty?
            error_warning << "space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule is empty for #{space.name.get}"
          else
            spaceinfo[:occupancy_schedule] = space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule.get.name.get # should not empty.
          end
        end

        spaceinfo[:occ_per_m2] = space.spaceType.get.people[0].peopleDefinition.peopleperSpaceFloorArea.get.round(3) unless space.spaceType.get.people[0].nil? || space.spaceType.get.people[0].peopleDefinition.peopleperSpaceFloorArea.empty?
        if space.spaceType.get.lights[0].nil?
          error_warning << "space.spaceType.get.lights[0] is nil for Space:[#{space.name.get}] Space Type:[#{spaceinfo[:space_type_name]}]"
        else
          spaceinfo[:lighting_w_per_m2] = space.spaceType.get.lights[0].lightsDefinition.wattsperSpaceFloorArea # .get.round(3) unless space.spaceType.get.lights[0].nil?
          spaceinfo[:lighting_w_per_m2] = validate_optional(spaceinfo[:lighting_w_per_m2], model, -1.0)
          unless spaceinfo[:lighting_w_per_m2].nil?
            spaceinfo[:lighting_w_per_m2] = spaceinfo[:lighting_w_per_m2].round(3)
          end
        end
        # spaceinfo[:electric_w_per_m2] = space.spaceType.get.electricEquipment[0].electricEquipmentDefinition.wattsperSpaceFloorArea.get.round(3) unless space.spaceType.get.electricEquipment[0].nil?

        unless space.spaceType.get.electricEquipment[0].nil?
          unless space.spaceType.get.electricEquipment[0].electricEquipmentDefinition.wattsperSpaceFloorArea.empty?
            spaceinfo[:electric_w_per_m2] = space.spaceType.get.electricEquipment[0].electricEquipmentDefinition.wattsperSpaceFloorArea.get.round(3)
          end
        end
        spaceinfo[:shw_m3_per_s] = space.waterUseEquipment[0].waterUseEquipmentDefinition.peakFlowRate.round(3) unless space.waterUseEquipment[0].nil?
        spaceinfo[:waterUseEquipment] = []
        if !space.waterUseEquipment.empty?
          waterUseEquipment_info = {}
          spaceinfo[:waterUseEquipment] << waterUseEquipment_info
          waterUseEquipment_info[:peak_flow_rate] = space.waterUseEquipment[0].waterUseEquipmentDefinition.peakFlowRate
          waterUseEquipment_info[:peak_flow_rate_per_area] = waterUseEquipment_info[:peak_flow_rate] / space.floorArea
          area_per_occ = space.spaceType.get.people[0].nil? ? 0.0 : validate_optional(space.spaceType.get.people[0].spaceFloorAreaPerPerson, model, -1.0)
          #                             Watt per person =             m3/s/m3                * 1000W/kW * (specific heat * dT) * m2/person
          waterUseEquipment_info[:shw_watts_per_person] = waterUseEquipment_info[:peak_flow_rate_per_area] * 1000 * (4.19 * 44.4) * 1000 * area_per_occ
          # puts waterUseEquipment_info[:shw_watts_per_ponce the erson]
          # puts "\n\n\n"
        end
      end
    end

    # Store Thermal zone data
    qaqc[:thermal_zones] = []
    model.getThermalZones.sort.each do |zone|
      zoneinfo = {}
      qaqc[:thermal_zones] << zoneinfo
      zoneinfo[:name] = zone.name.get
      zoneinfo[:floor_area] = zone.floorArea
      zoneinfo[:multiplier] = zone.multiplier
      zoneinfo[:is_conditioned] = 'N/A'
      if zone.isConditioned.empty?
        error_warning << "zone.isConditioned is empty for #{zone.name.get}"
      else
        zoneinfo[:is_conditioned] = zone.isConditioned.get
      end

      zoneinfo[:is_ideal_air_loads] = zone.useIdealAirLoads
      zoneinfo[:heating_sizing_factor] = -1.0
      if zone.sizingZone.zoneHeatingSizingFactor.empty?
        error_warning << "zone.sizingZone.zoneHeatingSizingFactor is empty for #{zone.name.get}"
      else
        zoneinfo[:heating_sizing_factor] = zone.sizingZone.zoneHeatingSizingFactor.get
      end

      zoneinfo[:cooling_sizing_factor] = -1.0 # zone.sizingZone.zoneCoolingSizingFactor.get
      if zone.sizingZone.zoneCoolingSizingFactor.empty?
        error_warning << "zone.sizingZone.zoneCoolingSizingFactor is empty for #{zone.name.get}"
      else
        zoneinfo[:cooling_sizing_factor] = zone.sizingZone.zoneCoolingSizingFactor.get
      end

      zoneinfo[:zone_heating_design_supply_air_temperature] = zone.sizingZone.zoneHeatingDesignSupplyAirTemperature
      zoneinfo[:zone_cooling_design_supply_air_temperature] = zone.sizingZone.zoneCoolingDesignSupplyAirTemperature
      zoneinfo[:spaces] = []
      zone.spaces.sort.each do |space|
        spaceinfo = {}
        zoneinfo[:spaces] << spaceinfo
        spaceinfo[:name] = space.name.get
        spaceinfo[:type] = space.spaceType.get.name.get unless space.spaceType.empty?
      end
      zoneinfo[:equipment] = []
      zone.equipmentInHeatingOrder.each do |equipment|
        item = {}
        zoneinfo[:equipment] << item
        item[:name] = equipment.name.get
        if equipment.to_ZoneHVACComponent.is_initialized
          item[:type] = 'ZoneHVACComponent'
        elsif equipment.to_StraightComponent.is_initialized
          item[:type] = 'StraightComponent'
        end
      end
      # zone
    end
    # Store Air Loop Information
    qaqc[:air_loops] = []
    model.getAirLoopHVACs.sort.each do |air_loop|
      air_loop_info = {}
      air_loop_info[:name] = air_loop.name.get
      air_loop_info[:thermal_zones] = []
      air_loop_info[:total_floor_area_served] = 0.0
      air_loop_info[:total_breathing_zone_outdoor_airflow_vbz] = 0.0
      air_loop.thermalZones.sort.each do |zone|
        air_loop_info[:thermal_zones] << zone.name.get
        vbz = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName='Zone Ventilation Parameters' AND ColumnName='Breathing Zone Outdoor Airflow - Vbz' AND Units='m3/s' AND RowName='#{zone.name.get.to_s.upcase}' ")
        vbz = validate_optional(vbz, model, 0)
        air_loop_info[:total_breathing_zone_outdoor_airflow_vbz] += vbz
        air_loop_info[:total_floor_area_served] += zone.floorArea * zone.multiplier.to_f
      end
      air_loop_info[:area_outdoor_air_rate_m3_per_s_m2] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName='System Ventilation Parameters' AND ColumnName='Area Outdoor Air Rate - Ra' AND Units='m3/s-m2' AND RowName='#{air_loop_info[:name].to_s.upcase}' ")
      air_loop_info[:area_outdoor_air_rate_m3_per_s_m2] = validate_optional(air_loop_info[:area_outdoor_air_rate_m3_per_s_m2], model, -1.0)

      air_loop_info[:outdoor_air_L_per_s] = -1.0
      unless air_loop_info[:area_outdoor_air_rate_m3_per_s_m2] == -1.0
        air_loop_info[:outdoor_air_L_per_s] = air_loop_info[:area_outdoor_air_rate_m3_per_s_m2] * air_loop_info[:total_floor_area_served] * 1000
      end
      # Fan

      unless air_loop.supplyFan.empty?
        air_loop_info[:supply_fan] = {}
        if air_loop.supplyFan.get.to_FanConstantVolume.is_initialized
          air_loop_info[:supply_fan][:type] = 'CV'
          fan = air_loop.supplyFan.get.to_FanConstantVolume.get
        elsif air_loop.supplyFan.get.to_FanVariableVolume.is_initialized
          air_loop_info[:supply_fan][:type] = 'VV'
          fan = air_loop.supplyFan.get.to_FanVariableVolume.get
        end
        air_loop_info[:supply_fan][:name] = fan.name.get
        # puts "\n\n\n\n#{fan.name.get}\n\n\n\n"
        air_loop_info[:supply_fan][:fan_efficiency] = fan.fanEfficiency
        air_loop_info[:supply_fan][:motor_efficiency] = fan.motorEfficiency
        air_loop_info[:supply_fan][:pressure_rise] = fan.pressureRise
        air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] = -1.0

        max_air_flow_info = model.sqlFile.get.execAndReturnVectorOfString("SELECT RowName FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s' ")
        max_air_flow_info = validate_optional(max_air_flow_info, model, 'N/A')
        if max_air_flow_info == 'N/A'
          error_warning << "max_air_flow_info is nil because the following sql statement returned nil: RowName FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s' "
        else
          if max_air_flow_info.include? air_loop_info[:supply_fan][:name].to_s.upcase.to_s
            air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s' AND RowName='#{air_loop_info[:supply_fan][:name].upcase}' ").get
            air_loop_info[:supply_fan][:rated_electric_power_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Rated Electric Power' AND Units='W' AND RowName='#{air_loop_info[:supply_fan][:name].upcase}' ")
            # Version 3.2.0 has renamed  rated electric_power  to rated electricity rate
            if air_loop_info[:supply_fan][:rated_electric_power_w].empty?
              air_loop_info[:supply_fan][:rated_electric_power_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Rated Electricity Rate' AND Units='W' AND RowName='#{air_loop_info[:supply_fan][:name].upcase}' ")
            end
            air_loop_info[:supply_fan][:rated_electric_power_w] = air_loop_info[:supply_fan][:rated_electric_power_w].get
            else
            error_warning << "#{air_loop_info[:supply_fan][:name]} does not exist in sql file WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Fans' AND ColumnName='Max Air Flow Rate' AND Units='m3/s'"
          end
        end
      end

      # economizer
      air_loop_info[:economizer] = {}
      air_loop_info[:economizer][:name] = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.name.get unless air_loop.airLoopHVACOutdoorAirSystem.empty? or air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.name.empty?
      air_loop_info[:economizer][:control_type] = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.getEconomizerControlType unless air_loop.airLoopHVACOutdoorAirSystem.empty?
      # DX cooling coils
      air_loop_info[:cooling_coils] = {}
      air_loop_info[:cooling_coils][:dx_single_speed] = []
      air_loop_info[:cooling_coils][:dx_two_speed] = []
      air_loop_info[:cooling_coils][:coil_cooling_water] = []

      # Heating Coil
      air_loop_info[:heating_coils] = {}
      air_loop_info[:heating_coils][:coil_heating_gas] = []
      air_loop_info[:heating_coils][:coil_heating_electric] = []
      air_loop_info[:heating_coils][:coil_heating_water] = []

      # Heat Excahnger
      air_loop_info[:heat_exchanger] = {}

      air_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_CoilHeatingGas.is_initialized
          coil = {}
          air_loop_info[:heating_coils][:coil_heating_gas] << coil
          gas = supply_comp.to_CoilHeatingGas.get
          coil[:name] = gas.name.get
          coil[:type] = 'Gas'
          coil[:efficency] = gas.gasBurnerEfficiency
          # coil[:nominal_capacity]= gas.nominalCapacity()
          coil[:nominal_capacity] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Heating Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].to_s.upcase}'")
          coil[:nominal_capacity] = validate_optional(coil[:nominal_capacity], model, -1.0)
        end
        if supply_comp.to_CoilHeatingElectric.is_initialized
          coil = {}
          air_loop_info[:heating_coils][:coil_heating_electric] << coil
          electric = supply_comp.to_CoilHeatingElectric.get
          coil[:name] = electric.name.get
          coil[:type] = 'Electric'
          coil[:nominal_capacity] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Heating Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].to_s.upcase}'")
          coil[:nominal_capacity] = validate_optional(coil[:nominal_capacity], model, -1.0)
        end
        if supply_comp.to_CoilHeatingWater.is_initialized
          coil = {}
          air_loop_info[:heating_coils][:coil_heating_water] << coil
          water = supply_comp.to_CoilHeatingWater.get
          coil[:name] = water.name.get
          coil[:type] = 'Water'
          coil[:nominal_capacity] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Heating Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].to_s.upcase}'")
          coil[:nominal_capacity] = validate_optional(coil[:nominal_capacity], model, -1.0)
        end
        if supply_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized
          heatExchanger = supply_comp.to_HeatExchangerAirToAirSensibleAndLatent.get
          air_loop_info[:heat_exchanger][:name] = heatExchanger.name.get
        end
      end
      # I dont think i need to get the type of heating coil from the sql file, because the coils are differentiated by class, and I have hard coded the information
      # model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName= 'Heating Coils' AND ColumnName='Type' ").get #padmussen to complete #AND RowName='#{air_loop_info[:heating_coils][:name].upcase}'

      # Collect all the fans into the the array.
      air_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_CoilCoolingDXSingleSpeed.is_initialized
          coil = {}
          air_loop_info[:cooling_coils][:dx_single_speed] << coil
          single_speed = supply_comp.to_CoilCoolingDXSingleSpeed.get
          coil[:name] = single_speed.name.get
          coil[:cop] = single_speed.ratedCOP.to_f
          coil[:nominal_total_capacity_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Cooling Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].upcase}' ")
          coil[:nominal_total_capacity_w] = validate_optional(coil[:nominal_total_capacity_w], model, -1.0)
        end
        if supply_comp.to_CoilCoolingDXTwoSpeed.is_initialized
          coil = {}
          air_loop_info[:cooling_coils][:dx_two_speed] << coil
          two_speed = supply_comp.to_CoilCoolingDXTwoSpeed.get
          coil[:name] = two_speed.name.get
          coil[:cop_low] = two_speed.ratedLowSpeedCOP.to_f
          coil[:cop_high] = two_speed.ratedHighSpeedCOP.to_f
          coil[:nominal_total_capacity_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Cooling Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].upcase}' ")
          coil[:nominal_total_capacity_w] = validate_optional(coil[:nominal_total_capacity_w], model, -1.0)
        end
        if supply_comp.to_CoilCoolingWater.is_initialized
          coil = {}
          air_loop_info[:cooling_coils][:coil_cooling_water] << coil
          coil_cooling_water = supply_comp.to_CoilCoolingWater.get
          coil[:name] = coil_cooling_water.name.get
          coil[:nominal_total_capacity_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Cooling Coils' AND ColumnName='Nominal Total Capacity' AND RowName='#{coil[:name].upcase}' ")
          coil[:nominal_total_capacity_w] = validate_optional(coil[:nominal_total_capacity_w], model, -1.0)
          coil[:nominal_sensible_heat_ratio] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Cooling Coils' AND ColumnName='Nominal Sensible Heat Ratio' AND RowName='#{coil[:name].upcase}' ")
          coil[:nominal_sensible_heat_ratio] = validate_optional(coil[:nominal_sensible_heat_ratio], model, -1.0)
        end
      end
      qaqc[:air_loops] << air_loop_info
    end

    qaqc[:plant_loops] = []
    model.getPlantLoops.sort.each do |plant_loop|
      plant_loop_info = {}
      qaqc[:plant_loops] << plant_loop_info
      plant_loop_info[:name] = plant_loop.name.get

      sizing = plant_loop.sizingPlant
      plant_loop_info[:design_loop_exit_temperature] = sizing.designLoopExitTemperature
      plant_loop_info[:loop_design_temperature_difference] = sizing.loopDesignTemperatureDifference

      # Create Container for plant equipment arrays.
      plant_loop_info[:pumps] = []
      plant_loop_info[:boilers] = []
      plant_loop_info[:chiller_electric_eir] = []
      plant_loop_info[:cooling_tower_single_speed] = []
      plant_loop_info[:water_heater_mixed] = []
      plant_loop.supplyComponents.each do |supply_comp|
        # Collect Constant Speed
        if supply_comp.to_PumpConstantSpeed.is_initialized
          pump = supply_comp.to_PumpConstantSpeed.get
          pump_info = {}
          plant_loop_info[:pumps] << pump_info
          pump_info[:name] = pump.name.get
          pump_info[:type] = 'Pump:ConstantSpeed'
          pump_info[:head_pa] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Head' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:head_pa] = validate_optional(pump_info[:head_pa], model, -1.0)
          pump_info[:water_flow_m3_per_s] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Water Flow' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:water_flow_m3_per_s] = validate_optional(pump_info[:water_flow_m3_per_s], model, -1.0)
          pump_info[:electric_power_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Electric Power' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:electric_power_w] = validate_optional(pump_info[:electric_power_w], model, -1.0)
          pump_info[:motor_efficency] = pump.motorEfficiency
        end

        # Collect Variable Speed
        if supply_comp.to_PumpVariableSpeed.is_initialized
          pump = supply_comp.to_PumpVariableSpeed.get
          pump_info = {}
          plant_loop_info[:pumps] << pump_info
          pump_info[:name] = pump.name.get
          pump_info[:type] = 'Pump:VariableSpeed'
          pump_info[:head_pa] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Head' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:head_pa] = validate_optional(pump_info[:head_pa], model, -1.0)
          pump_info[:water_flow_m3_per_s] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Water Flow' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:water_flow_m3_per_s] = validate_optional(pump_info[:water_flow_m3_per_s], model, -1.0)
          pump_info[:electric_power_w] = model.sqlFile.get.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='EquipmentSummary' AND ReportForString='Entire Facility' AND TableName='Pumps' AND ColumnName='Electric Power' AND RowName='#{pump_info[:name].upcase}' ")
          pump_info[:electric_power_w] = validate_optional(pump_info[:electric_power_w], model, -1.0)
          pump_info[:motor_efficency] = pump.motorEfficiency
        end

        # Collect HotWaterBoilers
        if supply_comp.to_BoilerHotWater.is_initialized
          boiler = supply_comp.to_BoilerHotWater.get
          boiler_info = {}
          plant_loop_info[:boilers] << boiler_info
          boiler_info[:name] = boiler.name.get
          boiler_info[:type] = 'Boiler:HotWater'
          boiler_info[:fueltype] = boiler.fuelType
          boiler_info[:nominal_capacity] = boiler.nominalCapacity
          boiler_info[:nominal_capacity] = validate_optional(boiler_info[:nominal_capacity], model, -1.0)
        end

        # Collect ChillerElectricEIR
        if supply_comp.to_ChillerElectricEIR.is_initialized
          chiller = supply_comp.to_ChillerElectricEIR.get
          chiller_info = {}
          plant_loop_info[:chiller_electric_eir] << chiller_info
          chiller_info[:name] = chiller.name.get
          chiller_info[:type] = 'Chiller:Electric:EIR'
          chiller_info[:reference_capacity] = validate_optional(chiller.referenceCapacity, model, -1.0)
          chiller_info[:reference_leaving_chilled_water_temperature] = chiller.referenceLeavingChilledWaterTemperature
        end

        # Collect CoolingTowerSingleSpeed
        if supply_comp.to_CoolingTowerSingleSpeed.is_initialized
          coolingTower = supply_comp.to_CoolingTowerSingleSpeed.get
          coolingTower_info = {}
          plant_loop_info[:cooling_tower_single_speed] << coolingTower_info
          coolingTower_info[:name] = coolingTower.name.get
          coolingTower_info[:type] = 'CoolingTower:SingleSpeed'
          coolingTower_info[:fan_power_at_design_air_flow_rate] = validate_optional(coolingTower.fanPoweratDesignAirFlowRate, model, -1.0)

        end

        # Collect WaterHeaterMixed
        if supply_comp.to_WaterHeaterMixed.is_initialized
          waterHeaterMixed = supply_comp.to_WaterHeaterMixed.get
          waterHeaterMixed_info = {}
          plant_loop_info[:water_heater_mixed] << waterHeaterMixed_info
          waterHeaterMixed_info[:name] = waterHeaterMixed.name.get
          waterHeaterMixed_info[:type] = 'WaterHeater:Mixed'
          waterHeaterMixed_info[:heater_thermal_efficiency] = waterHeaterMixed.heaterThermalEfficiency.get unless waterHeaterMixed.heaterThermalEfficiency.empty?
          waterHeaterMixed_info[:heater_fuel_type] = waterHeaterMixed.heaterFuelType
        end
      end

      qaqc[:eplusout_err] = {}
      warnings = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='0' ")
      warnings = validate_optional(warnings, model, 'N/A')
      unless warnings == 'N/A'
        qaqc[:eplusout_err][:warnings] = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='0' ").get
        qaqc[:eplusout_err][:fatal] = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='2' ").get
        qaqc[:eplusout_err][:severe] = model.sqlFile.get.execAndReturnVectorOfString("SELECT ErrorMessage FROM Errors WHERE ErrorType='1' ").get
      end

      qaqc[:ruby_warnings] = error_warning
    end

    qaqc[:code_metrics] = {}
    qaqc[:code_metrics]['heating_gj']  = qaqc[:end_uses]['heating_gj']
    qaqc[:code_metrics]['cooling_gj']  = qaqc[:end_uses]['cooling_gj']
    qaqc[:code_metrics][:ep_conditioned_floor_area_m2] = qaqc[:building][:conditioned_floor_area_m2]
    qaqc[:code_metrics][:os_conditioned_floor_area_m2] = qaqc[:envelope][:interior_floors_area_m2] +
                                                         qaqc[:envelope][:outdoor_floors_area_m2] +
                                                         qaqc[:envelope][:ground_floors_area_m2]
    # TEDI
    unless qaqc[:building][:conditioned_floor_area_m2].nil?
      qaqc[:code_metrics][:building_tedi_gj_per_m2] = (qaqc[:end_uses]['heating_gj'] + qaqc[:end_uses]['cooling_gj']
                                                      ) / qaqc[:building][:conditioned_floor_area_m2]
      # Mech TEDI?
      qaqc[:code_metrics][:building_medi_gj_per_m2] = (qaqc[:end_uses]['fans_gj'] +
          qaqc[:end_uses]['pumps_gj'] +
          qaqc[:end_uses]['heat_rejection_gj'] +
          qaqc[:end_uses]['humidification_gj'] +
          qaqc[:end_uses]['heat_recovery_gj']
      ) / qaqc[:building][:conditioned_floor_area_m2]
    end


    return qaqc
  end

  # Checks if a space with a proper schedule is conditioned or not
  def sanity_check(qaqc)
    qaqc[:sanity_check] = {}
    qaqc[:sanity_check][:fail] = []
    qaqc[:sanity_check][:pass] = []
    # Padmassun's code for isConditioned start
    qaqc[:thermal_zones].each do |zoneinfo|
      zoneinfo[:spaces].each do |space|
        # skip plenums and undefined spaces/zones
        if zoneinfo[:name].to_s.include? '- undefined -'
          next
        end

        if zoneinfo[:space_type_name].to_s.include? 'Space Function - undefined -'
          if zoneinfo[:is_conditioned].to_s == 'No'
            qaqc[:sanity_check][:pass] << "[TEST-PASS][SANITY_CHECK-PASS] for [SPACE][#{space[:name]}] and [THERMAL ZONE] [#{zoneinfo[:name]}] where isConditioned is supposed to be [" 'No' "] and found as #{zoneinfo[:is_conditioned]}"
          else
            qaqc[:sanity_check][:fail] << "[ERROR][SANITY_CHECK-FAIL] for [SPACE][#{space[:name]}] and [THERMAL ZONE] [#{zoneinfo[:name]}] where isConditioned is supposed to be [" 'No' "] but found as #{zoneinfo[:is_conditioned]}"
          end
        else
          if zoneinfo[:is_conditioned].to_s == 'Yes'
            qaqc[:sanity_check][:pass] << "[TEST-PASS][SANITY_CHECK-PASS] for [SPACE][#{space[:name]}] and [THERMAL ZONE] [#{zoneinfo[:name]}] where isConditioned is supposed to be [" 'Yes' "] and found as #{zoneinfo[:is_conditioned]}"
          elsif zoneinfo[:name]
            qaqc[:sanity_check][:fail] << "[ERROR][SANITY_CHECK-FAIL] for [SPACE][#{space[:name]}] and [THERMAL ZONE] [#{zoneinfo[:name]}] where isConditioned is supposed to be [" 'Yes' "] but found as #{zoneinfo[:is_conditioned]}"
          end
        end
      end
    end
    qaqc[:sanity_check][:fail] = qaqc[:sanity_check][:fail].sort
    qaqc[:sanity_check][:pass] = qaqc[:sanity_check][:pass].sort
    # Padmassun's code for isConditioned end
  end

  # checks the pump power using pressure, and flowrate
  def necb_plantloop_sanity(qaqc)
    necb_section_name = 'SANITY-??'
    qaqc[:plant_loops].each do |plant_loop_info|
      pump_head = plant_loop_info[:pumps][0][:head_pa]
      flow_rate = plant_loop_info[:pumps][0][:water_flow_m3_per_s] * 1000
      hp_check = ((flow_rate * 60 * 60) / 1000 * 1000 * 9.81 * pump_head * 0.000101997) / 3600000
      puts "\npump_head #{pump_head}"
      puts "name: #{qaqc[:building][:name]}"
      puts "name: #{plant_loop_info[:name]}"
      puts "flow_rate #{flow_rate}"
      puts "hp_check #{hp_check}\n"
      pump_power_hp = plant_loop_info[:pumps][0][:electric_power_w] / 1000 * 0.746
      percent_diff = (hp_check - pump_power_hp).to_f.abs / hp_check * 100

      if percent_diff.nan?
        qaqc[:ruby_warnings] << "(hp_check - pump_power_hp).to_f.abs/hp_check * 100 for #{plant_loop_info[:name]} is NaN"
        next
      end

      if pump_power_hp < 1.0
        qaqc[:warnings] << "necb_plantloop_sanity [SKIP] [PLANT LOOP][#{plant_loop_info[:name]}][:pumps][0][:electric_power_hp] because  pump_power_hp: [#{pump_power_hp}] < 1 hp"
        next
      end

      necb_section_test(
        qaqc,
        percent_diff,
        '<=',
        20, # diff of 20%
        necb_section_name,
        "[PLANT LOOP][#{plant_loop_info[:name]}][:pumps][0][:electric_power_hp] [#{pump_power_hp}]; NECB value [#{hp_check}]; Percent Diff"
      )
    end
  end

  # checks space compliance
  # Re: lighting_per_area, occupancy_per_area, occupancy_schedule, electric_equipment_per_area

  def necb_space_compliance(qaqc)
    #    #Padmassun's Code Start
    # csv_file_name ="#{File.dirname(__FILE__)}/necb_2011_spacetype_info.csv"
    qaqc[:spaces].each do |space|
      building_type = ''
      space_type = ''
      if space[:space_type_name].include? 'Space Function '
        space_type = space[:space_type_name].to_s.rpartition('Space Function ')[2].strip
        building_type = 'Space Function'
      elsif space[:space_type_name].include? ' WholeBuilding'
        space_type = space[:space_type_name].to_s.rpartition(' WholeBuilding')[0].strip
        building_type = 'WholeBuilding'
      end

      ['lighting_per_area_w_per_m2', 'occupancy_per_area_people_per_m2', 'occupancy_schedule', 'electric_equipment_per_area_w_per_m2'].each do |compliance_var|
        qaqc_table = get_qaqc_table(table_name: 'space_compliance', search_criteria: { 'building_type' => building_type, 'space_type' => space_type }).first
        puts "\n#{qaqc_table}\n"
        necb_section_name = get_qaqc_table(table_name: 'space_compliance')['refs'][compliance_var]
        tolerance = get_qaqc_table(table_name: 'space_compliance')['tolerance'][compliance_var]
        # puts "\ncompliance_var:#{compliance_var}\n\tnecb_section_name:#{necb_section_name}\n\texp Value:#{qaqc_table[compliance_var]}\n"
        if compliance_var == 'lighting_per_area_w_per_m2'
          if space[:lighting_w_per_m2].nil?
            result_value = 0
          else
            result_value = space[:lighting_w_per_m2] * qaqc_table['lpd_ratio']
          end
        elsif compliance_var == 'occupancy_per_area_people_per_m2'
          result_value = space[:occ_per_m2]
        elsif compliance_var == 'occupancy_schedule'
          result_value = space[:occupancy_schedule]
        elsif compliance_var == 'electric_equipment_per_area_w_per_m2'
          result_value = space[:electric_w_per_m2]
        end

        test_text = "[SPACE][#{space[:name]}]-[TYPE:][#{space_type}]-#{compliance_var}"
        next if result_value.nil?

        necb_section_test(
          qaqc,
          result_value,
          '==',
          qaqc_table[compliance_var],
          necb_section_name,
          test_text,
          tolerance
        )
      end

      # row = look_up_csv_data(csv_file_name,{2 => space_type, 1 => building_type})
      # if row.nil?
      #   #raise ("space type of [#{space_type}] and/or building type of [#{building_type}] was not found in the excel sheet for space: [#{space[:name]}]")
      #   qaqc[:ruby_warnings] << "space type of [#{space_type}] and/or building type of [#{building_type}] was not found in the excel sheet for space: [#{space[:name]}]"
      #   puts "space type of [#{space_type}] and/or building type of [#{building_type}] was not found in the excel sheet for space: [#{space[:name]}]"
      # else
      #   #correct the data from the csv file to include a multiplier of 0.9 for specific space types.

      #   reduceLPDSpaces = ["Classroom/lecture/training", "Conf./meet./multi-purpose", "Lounge/recreation",
      #     "Washroom-sch-A", "Washroom-sch-B", "Washroom-sch-C", "Washroom-sch-D", "Washroom-sch-E",
      #     "Washroom-sch-F", "Washroom-sch-G", "Washroom-sch-H", "Washroom-sch-I", "Dress./fitt. - performance arts",
      #     "Locker room", "Retail - dressing/fitting","Locker room-sch-A","Locker room-sch-B","Locker room-sch-C",
      #     "Locker room-sch-D","Locker room-sch-E","Locker room-sch-F","Locker room-sch-G","Locker room-sch-H",
      #     "Locker room-sch-I", "Office - open plan - occsens", "Office - enclosed - occsens", "Storage area - occsens",
      #     "Hospital - medical supply - occsens", "Storage area - refrigerated - occsens"]

      #   if reduceLPDSpaces.include?(space_type)
      #     row[3] = row[3]*0.9
      #     puts "\n============================\nspace_type: #{space_type}\n============================\n"
      #   end

      #   # Start of Space Compliance
      #   necb_section_name = "NECB2011-Section 8.4.3.6"
      #   data = {}
      #   data[:lighting_per_area]            = [ row[3],'==',space[:lighting_w_per_m2] , "Table 4.2.1.6"     ,1 ] unless space[:lighting_w_per_m2].nil?
      #   data[:occupancy_per_area]           = [ row[4],'==',space[:occ_per_m2]        , "Table A-8.4.3.3.1" ,3 ] unless space[:occ_per_m2].nil?
      #   data[:occupancy_schedule]           = [ row[5],'==',space[:occupancy_schedule], "Table A-8.4.3.3.1" ,nil ] unless space[:occupancy_schedule].nil?
      #   data[:electric_equipment_per_area]  = [ row[6],'==',space[:electric_w_per_m2] , "Table A-8.4.3.3.1" ,1 ] unless space[:electric_w_per_m2].nil?
      #   data.each do |key,value|
      #     #puts key
      #     necb_section_test(
      #       qaqc,
      #       value[0],
      #       value[1],
      #       value[2],
      #       value[3],
      #       "[SPACE][#{space[:name]}]-[TYPE:][#{space_type}]#{key}",
      #       value[4]
      #     )
      #   end
      # end#space Compliance
    end
    # Padmassun's Code End
  end

  # checks envelope compliance
  # fenestration_to_door_and_window_percentage, skylight_to_roof_percentage
  def necb_envelope_compliance(qaqc)
    # Envelope
    necb_section_name = 'NECB2011-Section 3.2.1.4'
    # store hdd in short form
    hdd = qaqc[:geography][:hdd]
    # calculate fdwr based on hdd.
    fdwr = 0
    if hdd < 4000
      fdwr = 0.40
    elsif (hdd >= 4000) && (hdd <= 7000)
      fdwr = (2000 - 0.2 * hdd) / 3000
    elsif hdd > 7000
      fdwr = 0.20
    end
    # hardset srr to 0.05
    srr = 0.05
    # create table of expected values and results.
    data = {}
    data[:fenestration_to_door_and_window_percentage] = [fdwr * 100, qaqc[:envelope][:fdwr].round(3)]
    data[:skylight_to_roof_percentage] = [srr * 100, qaqc[:envelope][:srr].round(3)]
    # perform test. result must be less than or equal to.
    data.each do |key, value|
      necb_section_test(
        qaqc,
        value[0],
        '>=',
        value[1],
        necb_section_name,
        "[ENVELOPE]#{key}",
        1 # padmassun added tollerance
      )
    end
  end

  def necb_infiltration_compliance(qaqc, model)
    # Infiltration
    # puts "\n"
    # puts get_qaqc_table("infiltration_compliance")
    # puts "\n"
    # puts "\n"
    # puts get_qaqc_table("infiltration_compliance", {"var" => ":infiltration_method"} )
    # puts "\n"
    # puts "\n"
    infiltration_compliance = get_qaqc_table(table_name: 'infiltration_compliance')['table']
    necb_section_name = get_qaqc_table(table_name: 'infiltration_compliance')['refs'].join(',')
    qaqc[:spaces].each do |spaceinfo|
      model.getSpaces.sort.each do |space|
        next unless space.name.get == spaceinfo[:name]

        found = false
        space.surfaces.each do |surface|
          next unless surface.outsideBoundaryCondition == 'Outdoors'

          found = true
          # peform this infiltration qaqc if and only if the space's surface is in contact with outdoors
          infiltration_compliance.each do |compliance|
            # puts "\nspaceinfo[#{compliance['var']}]"
            eval_string = "spaceinfo[:#{compliance['var']}]"
            result_value = eval(eval_string)
            # puts "#{compliance['test_text']}"
            test_text = "[SPACE][#{spaceinfo[:name]}]-#{compliance['var']}"
            # puts "result_value: #{result_value}"
            # puts "test_text: #{test_text}\n"
            # data[:infiltration_method]    = [ "Flow/ExteriorArea", spaceinfo[:infiltration_method] , nil ]
            # data[:infiltration_flow_per_m2] = [ 0.00025,       spaceinfo[:infiltration_flow_per_m2], 5 ]
            # data.each do |key,value|
            # puts key
            necb_section_test(
              qaqc,
              result_value,
              compliance['bool_operator'],
              compliance['expected_value'],
              necb_section_name,
              test_text,
              compliance['tolerance']
            )
          end
          # peform qaqc only once per space
          break
        end
        if !found
          qaqc[:warnings] << "necb_infiltration_compliance for SPACE:[#{spaceinfo[:name]}] was skipped because it does not contain surfaces with 'Outside' boundary condition."
        end
      end
    end
  end

  def necb_exterior_opaque_compliance(qaqc)
    # puts JSON.pretty_generate @qaqc_data
    # Exterior Opaque
    necb_section_name = get_qaqc_table(table_name: 'exterior_opaque_compliance')['refs'].join(',')
    climate_index = NECB2011.new.get_climate_zone_index(qaqc[:geography][:hdd])
    puts "HDD #{qaqc[:geography][:hdd]}"
    tolerance = 3
    # puts "\n\n"
    # puts "climate_index: #{climate_index}"
    # puts get_qaqc_table("exterior_opaque_compliance", {"var" => "ext_wall_conductances", "climate_index" => 2})
    ['ext_wall_conductances', 'ext_roof_conductances', 'ext_floor_conductances'].each do |compliance_var|
      qaqc_table = get_qaqc_table(table_name: 'exterior_opaque_compliance', search_criteria: { 'var' => compliance_var, 'climate_index' => climate_index }).first
      # puts "\n#{qaqc_table}\n"
      if compliance_var == 'ext_wall_conductances'
        result_value = qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ext_roof_conductances'
        result_value = qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ext_floor_conductances'
        result_value = qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k]
      end

      test_text = "[ENVELOPE] #{compliance_var}"
      next if result_value.nil?

      necb_section_test(
        qaqc,
        result_value,
        qaqc_table['bool_operator'],
        qaqc_table['expected_value'],
        necb_section_name,
        test_text,
        tolerance
      )
    end
    # result_value_index = 6
    # round_precision = 3
    # data = {}
    # data[:ext_wall_conductances]        =  [0.315,0.278,0.247,0.210,0.210,0.183,qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k].nil?
    # data[:ext_roof_conductances]        =  [0.227,0.183,0.183,0.162,0.162,0.142,qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k].nil?
    # data[:ext_floor_conductances]       =  [0.227,0.183,0.183,0.162,0.162,0.142,qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:outdoor_floors_average_conductance_w_per_m2_k].nil?

    # data.each {|key,value| necb_section_test(
    #     qaqc,
    #     value[result_value_index],
    #     '==',
    #     value[climate_index],
    #     necb_section_name,
    #     "[ENVELOPE]#{key}",
    #     round_precision
    #   )
    # }
  end

  def necb_exterior_fenestration_compliance(qaqc)
    # Exterior Fenestration
    necb_section_name = get_qaqc_table(table_name: 'exterior_fenestration_compliance')['refs'].join(',')
    climate_index = NECB2011.new.get_climate_zone_index(qaqc[:geography][:hdd])
    tolerance = 3
    # puts "\n\n"
    # puts "climate_index: #{climate_index}"
    # puts get_qaqc_table("exterior_fenestration_compliance", {"var" => "ext_window_conductances", "climate_index" => 2})

    ['ext_window_conductances', 'ext_door_conductances', 'ext_overhead_door_conductances', 'ext_skylight_conductances'].each do |compliance_var|
      qaqc_table = get_qaqc_table(table_name: 'exterior_fenestration_compliance', search_criteria: { 'var' => compliance_var, 'climate_index' => climate_index }).first
      # puts "\n#{qaqc_table}\n"
      if compliance_var == 'ext_window_conductances'
        result_value = qaqc[:envelope][:windows_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ext_door_conductances'
        result_value = qaqc[:envelope][:doors_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ext_overhead_door_conductances'
        result_value = qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ext_skylight_conductances'
        result_value = qaqc[:envelope][:skylights_average_conductance_w_per_m2_k]
      end
      test_text = "[ENVELOPE] #{compliance_var}"
      next if result_value.nil?

      necb_section_test(
        qaqc,
        result_value,
        qaqc_table['bool_operator'],
        qaqc_table['expected_value'],
        necb_section_name,
        test_text,
        tolerance
      )
    end
    # necb_section_name = "NECB2011-Section 3.2.2.3"
    # climate_index = BTAP::Compliance::NECB2011::get_climate_zone_index(qaqc[:geography][:hdd])
    # result_value_index = 6
    # round_precision = 3
    # data = {}
    # data[:ext_window_conductances]      =     [2.400,2.200,2.200,2.200,2.200,1.600,qaqc[:envelope][:windows_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:windows_average_conductance_w_per_m2_k].nil?
    # data[:ext_door_conductances]        =     [2.400,2.200,2.200,2.200,2.200,1.600,qaqc[:envelope][:doors_average_conductance_w_per_m2_k]]   unless qaqc[:envelope][:doors_average_conductance_w_per_m2_k].nil?
    # data[:ext_overhead_door_conductances] =   [2.400,2.200,2.200,2.200,2.200,1.600,qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:overhead_doors_average_conductance_w_per_m2_k].nil?
    # data[:ext_skylight_conductances]  =       [2.400,2.200,2.200,2.200,2.200,1.600,qaqc[:envelope][:skylights_average_conductance_w_per_m2_k]] unless qaqc[:envelope][:skylights_average_conductance_w_per_m2_k].nil?

    # data.each do |key,value|
    #   #puts key
    #   necb_section_test(
    #     qaqc,
    #     value[result_value_index].round(round_precision),
    #     '==',
    #     value[climate_index].round(round_precision),
    #     necb_section_name,
    #     "[ENVELOPE]#{key}",
    #     round_precision
    #   )
    # end
  end

  def necb_exterior_ground_surfaces_compliance(qaqc)
    # Exterior Ground surfaces
    necb_section_name = get_qaqc_table(table_name: 'exterior_ground_surfaces_compliance')['refs'].join(',')
    climate_index = NECB2011.new.get_climate_zone_index(qaqc[:geography][:hdd])
    tolerance = 3
    # puts "\n\n"
    # puts "climate_index: #{climate_index}"
    # puts get_qaqc_table("exterior_ground_surfaces_compliance", {"var" => "ground_wall_conductances", "climate_index" => 2})

    ['ground_wall_conductances', 'ground_roof_conductances', 'ground_floor_conductances'].each do |compliance_var|
      qaqc_table = get_qaqc_table(table_name: 'exterior_ground_surfaces_compliance', search_criteria: { 'var' => compliance_var, 'climate_index' => climate_index }).first
      # puts "\n#{qaqc_table}\n"
      if compliance_var == 'ground_wall_conductances'
        result_value = qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ground_roof_conductances'
        result_value = qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k]
      elsif compliance_var == 'ground_floor_conductances'
        result_value = qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k]
      end
      test_text = "[ENVELOPE] #{compliance_var}"
      next if result_value.nil?

      necb_section_test(
        qaqc,
        result_value,
        qaqc_table['bool_operator'],
        qaqc_table['expected_value'],
        necb_section_name,
        test_text,
        tolerance
      )
    end
    # necb_section_name = "NECB2011-Section 3.2.3.1"
    # climate_index = BTAP::Compliance::NECB2011::get_climate_zone_index(qaqc[:geography][:hdd])
    # result_value_index = 6
    # round_precision = 3
    # data = {}
    # data[:ground_wall_conductances]  = [ 0.568,0.379,0.284,0.284,0.284,0.210, qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k] ]  unless qaqc[:envelope][:ground_walls_average_conductance_w_per_m2_k].nil?
    # data[:ground_roof_conductances]  = [ 0.568,0.379,0.284,0.284,0.284,0.210, qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k] ]  unless qaqc[:envelope][:ground_roofs_average_conductance_w_per_m2_k].nil?
    # data[:ground_floor_conductances] = [ 0.757,0.757,0.757,0.757,0.757,0.379, qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k] ] unless qaqc[:envelope][:ground_floors_average_conductance_w_per_m2_k].nil?
    # data.each {|key,value| necb_section_test(
    #     qaqc,
    #     value[result_value_index],
    #     '==',
    #     value[climate_index],
    #     necb_section_name,
    #     "[ENVELOPE]#{key}",
    #     round_precision
    #   )
    # }
  end

  def necb_zone_sizing_compliance(qaqc)
    # Zone Sizing test
    necb_section_name = get_qaqc_table(table_name: 'zone_sizing_compliance')['refs'].join(',')
    qaqc_table = get_qaqc_table(table_name: 'zone_sizing_compliance')
    tolerance = 3
    # necb_section_name = "NECB2011-?"
    # round_precision = 3
    qaqc[:thermal_zones].each do |zoneinfo|
      #    skipping undefined schedules
      if (qaqc_table['exclude']['exclude_string'].any? { |ex_string| zoneinfo[:name].to_s.include? ex_string }) && !qaqc_table['exclude']['exclude_string'].empty?
        # if zoneinfo[:name].to_s.include?"- undefined -"
        puts "#{zoneinfo[:name]} was skipped in necb_zone_sizing_compliance because it contains #{qaqc_table['exclude']['exclude_string'].join(',')}"
        next
      end
      zone_sizing_compliance = qaqc_table['table']
      zone_sizing_compliance.each do |compliance|
        eval_string = "zoneinfo[:#{compliance['var']}]"
        result_value = eval(eval_string)
        next if result_value.nil?

        test_text = "[ZONE][#{zoneinfo[:name]}] #{compliance['var']}"
        # puts key
        necb_section_test(
          qaqc,
          result_value,
          compliance['bool_operator'],
          compliance['expected_value'],
          necb_section_name,
          test_text,
          tolerance
        )
      end
      # data = {}
      # data[:heating_sizing_factor] = [1.3 , zoneinfo[:heating_sizing_factor]]
      # data[:cooling_sizing_factor] = [1.1 ,zoneinfo[:cooling_sizing_factor]]
      # #data[:heating_design_supply_air_temp] =   [43.0, zoneinfo[:zone_heating_design_supply_air_temperature] ] #unless zoneinfo[:zone_heating_design_supply_air_temperature].nil?
      # #data[:cooling_design_supply_temp]   =   [13.0, zoneinfo[:zone_cooling_design_supply_air_temperature] ]
      # data.each do |key,value|
      #   #puts key
      #   necb_section_test(
      #     qaqc,
      #     value[0],
      #     '==',
      #     value[1],
      #     necb_section_name,
      #     "[ZONE][#{zoneinfo[:name]}] #{key}",
      #     round_precision
      #   )
      # end
    end
  end

  def necb_design_supply_temp_compliance(qaqc)
    necb_section_name = get_qaqc_table(table_name: 'design_supply_temp_compliance')['refs'].join(',')
    qaqc_table = get_qaqc_table(table_name: 'design_supply_temp_compliance')
    tolerance = 3
    qaqc[:thermal_zones].each do |zoneinfo|
      #    skipping undefined schedules
      if (qaqc_table['exclude']['exclude_string'].any? { |ex_string| zoneinfo[:name].to_s.include? ex_string }) && !qaqc_table['exclude']['exclude_string'].empty?
        puts "#{zoneinfo[:name]} was skipped in necb_zone_sizing_compliance because it contains #{qaqc_table['exclude']['exclude_string'].join(',')}"
        next
      end
      design_supply_temp_compliance = qaqc_table['table']

      design_supply_temp_compliance.each do |compliance|
        if compliance['var'] == 'heating_design_supply_air_temp'
          result_value = zoneinfo[:zone_heating_design_supply_air_temperature]
        elsif compliance['var'] == 'cooling_design_supply_temp'
          result_value = zoneinfo[:zone_cooling_design_supply_air_temperature]
        end

        next if result_value.nil?

        test_text = "[ZONE][#{zoneinfo[:name]}] #{compliance['var']}"
        # puts key
        necb_section_test(
          qaqc,
          result_value,
          compliance['bool_operator'],
          compliance['expected_value'],
          necb_section_name,
          test_text,
          tolerance
        )
      end
    end
    # Design supply temp test
    # necb_section_name = "NECB2011-?"
    # round_precision = 3
    # qaqc[:thermal_zones].each do |zoneinfo|
    #   #    skipping undefined schedules
    #   if zoneinfo[:name].to_s.include?"- undefined -"
    #     next
    #   end
    #   data = {}
    #   #data[:heating_sizing_factor] = [1.3 , zoneinfo[:heating_sizing_factor]]
    #   #data[:cooling_sizing_factor] = [1.1 ,zoneinfo[:cooling_sizing_factor]]
    #   data[:heating_design_supply_air_temp] =   [43.0, zoneinfo[:zone_heating_design_supply_air_temperature] ] #unless zoneinfo[:zone_heating_design_supply_air_temperature].nil?
    #   data[:cooling_design_supply_temp]   =   [13.0, zoneinfo[:zone_cooling_design_supply_air_temperature] ]
    #   data.each do |key,value|
    #     #puts key
    #     necb_section_test(
    #       qaqc,
    #       value[0],
    #       '==',
    #       value[1],
    #       necb_section_name,
    #       "[ZONE][#{zoneinfo[:name]}] #{key}",
    #       round_precision
    #     )
    #   end
    # end
  end

  def necb_economizer_compliance(qaqc)
    # determine correct economizer usage according to section 5.2.2.7 of NECB2011
    necb_section_name = get_qaqc_table(table_name: 'economizer_compliance')['refs'].join(',')
    qaqc_table = get_qaqc_table(table_name: 'economizer_compliance') # stores the full hash of qaqc for economizer_compliance
    # necb_section_name = "NECB2011-5.2.2.7"

    qaqc[:air_loops].each do |air_loop_info|
      capacity = -1.0
      if !air_loop_info[:cooling_coils][:dx_single_speed][0].nil?
        puts 'capacity = air_loop_info[:cooling_coils][:dx_single_speed][0][:nominal_total_capacity_w]'
        capacity = air_loop_info[:cooling_coils][:dx_single_speed][0][:nominal_total_capacity_w]
      elsif !air_loop_info[:cooling_coils][:dx_two_speed][0].nil?
        puts 'capacity = air_loop_info[:cooling_coils][:dx_two_speed][0][:cop_high]'
        capacity = air_loop_info[:cooling_coils][:dx_two_speed][0][:cop_high]
      elsif !air_loop_info[:cooling_coils][:coil_cooling_water][0].nil?
        puts 'capacity = air_loop_info[:cooling_coils][:coil_cooling_water][0][:nominal_total_capacity_w]'
        capacity = air_loop_info[:cooling_coils][:coil_cooling_water][0][:nominal_total_capacity_w]
      end
      puts capacity
      if capacity == -1.0
        # This should not happen
        qaqc[:errors] << "[necb_economizer_compliance] air_loop_info[:cooling_coils] for #{air_loop_info[:name]} does not have a capacity "
      else
        # check for correct economizer usage
        # puts "air_loop_info[:supply_fan][:max_air_flow_rate]: #{air_loop_info[:supply_fan][:max_air_flow_rate]}"
        unless air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] == -1.0
          # capacity should be in kW
          max_air_flow_rate_m3_per_s = air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s]
          necb_section_test(
            qaqc,
            eval(qaqc_table['table'][0]['expected_value']),
            '==',
            air_loop_info[:economizer][:control_type],
            necb_section_name,
            "[AIR LOOP][#{air_loop_info[:name]}][:economizer][:control_type]"
          )
        end
      end
    end
  end

  def necb_hrv_compliance(qaqc, model)
    # HRV check
    hrv_compliance = get_qaqc_table(table_name: 'hrv_compliance')['table']
    necb_section_name = get_qaqc_table(table_name: 'hrv_compliance')['refs'].join(',')
    qaqc[:air_loops].each do |air_loop_info|
      hrv_compliance.each do |compliance|
        data = {}

        # puts "\nspaceinfo[#{compliance['var']}]"
        result_value = !air_loop_info[:heat_exchanger].empty?
        # puts "#{compliance['test_text']}"
        test_text = "[AIR LOOP][:heat_exchanger] for [#{air_loop_info[:name]}] is present?"
        # puts "result_value: #{result_value}"
        # puts "test_text: #{test_text}\n"
        # data[:infiltration_method]    = [ "Flow/ExteriorArea", spaceinfo[:infiltration_method] , nil ]
        # data[:infiltration_flow_per_m2] = [ 0.00025,       spaceinfo[:infiltration_flow_per_m2], 5 ]
        # data.each do |key,value|
        # puts key
        outdoor_air_L_per_s = air_loop_info[:outdoor_air_L_per_s]
        weather_file_path = model.weatherFile.get.path.get.to_s
        stat_file_path = weather_file_path.gsub('.epw', '.stat')
        stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
        db990 = stat_file.heating_design_info[2]
        necb_section_test(
          qaqc,
          result_value,
          '==',
          eval(compliance['expected_value']),
          necb_section_name,
          test_text,
          compliance['tolerance']
        )
      end
    end
    # necb_section_name = "NECB2011-5.2.10.1"
    # qaqc[:air_loops].each do |air_loop_info|
    #   unless air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] == -1.0
    #     weather_file_path = model.weatherFile.get.path.get.to_s
    #     stat_file_path = weather_file_path.gsub('.epw', '.stat')
    #     stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
    #     db990 = stat_file.heating_design_info[2]
    #     hrv_calc = 0.00123 * air_loop_info[:outdoor_air_L_per_s] * (21 - db990) #=AP46*(21-O$1)
    #     hrv_reqd = hrv_calc > 150 ? true : false
    #     #qaqc[:information] << "[Info][TEST-PASS][#{necb_section_name}]:#{test_text} result value:#{result_value} #{bool_operator} expected value:#{expected_value}"
    #     hrv_present = false
    #     unless air_loop_info[:heat_exchanger].empty?
    #       hrv_present = true
    #     end
    #     necb_section_test(
    #       qaqc,
    #       hrv_reqd,
    #       '==',
    #       hrv_present,
    #       necb_section_name,
    #       "[AIR LOOP][:heat_exchanger] for [#{air_loop_info[:name]}] is present?"
    #     )
    #   else
    #     qaqc['warnings'] << "[hrv_compliance] air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] == -1.0 for [#{air_loop_info[:name]}]"
    #   end
    # end
  end

  # This methos is not used as part of the QAQC process,
  # because support for MURBS has not been implemented for HRV
  # in NECB 2011 and 2015
  def necb_hrv_compliance_inc_murb(qaqc, model)
    murb_hrv_compliance = get_qaqc_table('murb_hrv_compliance')
    hrv_spacetpye_ignore_regex = murb_hrv_compliance['ignored_spacetypes_regex']
    hrv_dwelling_unit_spacetpye_regex = murb_hrv_compliance['dwelling_unit_spacetype_regex']
    necb_section_name = murb_hrv_compliance['refs'].join(',')

    model.getAirLoopHVACs.sort.each do |air_loop|
      air_loop_info = {}

      qaqc[:air_loops].each do |air_loop_i|
        next unless air_loop_i[:name] == air_loop.name.get

        air_loop_info = air_loop_i
      end

      zones = air_loop.thermalZones
      if zones.length == 1
        # here the Airloop is serving only one zone

        # So, next we need to determine if the zone has only
        # one dwelling unit and no other space types other than stairs, corridor, and lobby

        zone = zones.first
        # get the spaces and keep track of the number of spaces and dewlling units
        num_of_served_spaces = zone.spaces.length
        contains_dwelling_unit = false
        if num_of_served_spaces == 0
          qaqc[:warnings] << "[necb_murb_hrv_compliance] Thermal Zone [#{zone.name}] does not serve any Spaces"
        else
          spaces = zone.spaces()
          spaces.each do |z_space|
            spacetype = z_space.spaceType
            spacetype = validate_optional(spacetype, model, nil)
            if spacetype.nil?
              qaqc[:warnings] << "[necb_murb_hrv_compliance] Space [#{z_space.name}] does not have a SpaceType"
            else
              # reduce the number of spaces if the space served by the thermal zone is a
              # stairwell/staircase/lobby/corridor
              spacetype_name = spacetype.name.to_s
              ignored_spacetypes_regex = Regexp.new(hrv_spacetpye_ignore_regex, Regexp::IGNORECASE)
              if ignored_spacetypes_regex =~ spacetype_name
                num_of_served_spaces -= 1
              end
              # detect is the thermal zone serves a Dwelling Unit
              dwelling_unit_regex = Regexp.new(hrv_dwelling_unit_spacetpye_regex, Regexp::IGNORECASE)
              if dwelling_unit_regex =~ spacetype_name
                contains_dwelling_unit = true
              end
            end
          end
          if (num_of_served_spaces == 1) && contains_dwelling_unit
            # here the Thermal zone serves one space that is a dwelling unit
            # and other space types such as lobby, stairs, or corridors are ignored
            # So in this case, an HRV is required
            test_text = "[AIR LOOP][:heat_exchanger] (murb) for [#{air_loop_info[:name]}] is present?"
            result_value = murb_hrv_compliance['table']['expected_value']
            necb_section_test(
              qaqc,
              result_value,
              '==',
              true,
              necb_section_name,
              test_text,
              nil
            )
          else
            # Here either the number of served spaces exceed 1 or
            # does not contain a dwelling unit, So a regular HRV check has to be done for this air loop
            qaqc[:warnings] << "[necb_murb_hrv_compliance] Regular HRV compliance check for airloop: [#{air_loop.name}], because (it does not serve a single dwelling unit) OR (serves multiple spacetypes)"
            necb_hrv_compliance_for_single_airloop(qaqc, model, air_loop_info)
          end
        end
      else
        # here the Airloop does not serve any zones, or it serves more than one zone
        # So, a regular hrv compliance must be done for this air loop
        qaqc[:warnings] << "[necb_murb_hrv_compliance] Regular HRV compliance check for airloop: [#{air_loop.name}], because it serves multiple Thermal zones"
        necb_hrv_compliance_for_single_airloop(qaqc, model, air_loop_info)
      end
    end
  end

  # This methos is not used as part of the QAQC process,
  # because support for MURBS has not been implemented for HRV
  # in NECB 2011 and 2015
  #
  # This method will run the HRV compliance for a single air loop
  #
  # @param qaqc [:hash] Hash that contains the base data with qaqc keys
  # @param model [:OS:Model] OpenStudio Model
  # @param  air_loop_info [:hash]  single air_loop object from the qaqc hash
  def necb_hrv_compliance_for_single_airloop(qaqc, model, air_loop_info)
    # HRV check
    hrv_compliance = get_qaqc_table('hrv_compliance')['table']
    necb_section_name = get_qaqc_table('hrv_compliance')['refs'].join(',')
    hrv_compliance.each do |compliance|
      data = {}

      # puts "\nspaceinfo[#{compliance['var']}]"
      result_value = !air_loop_info[:heat_exchanger].empty?
      # puts "#{compliance['test_text']}"
      test_text = "[AIR LOOP][:heat_exchanger] for [#{air_loop_info[:name]}] is present?"
      # puts "result_value: #{result_value}"
      # puts "test_text: #{test_text}\n"
      # data[:infiltration_method]    = [ "Flow/ExteriorArea", spaceinfo[:infiltration_method] , nil ]
      # data[:infiltration_flow_per_m2] = [ 0.00025,       spaceinfo[:infiltration_flow_per_m2], 5 ]
      # data.each do |key,value|
      # puts key
      outdoor_air_L_per_s = air_loop_info[:outdoor_air_L_per_s]
      weather_file_path = model.weatherFile.get.path.get.to_s
      stat_file_path = weather_file_path.gsub('.epw', '.stat')
      stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
      db990 = stat_file.heating_design_info[2]
      necb_section_test(
        qaqc,
        result_value,
        '==',
        eval(compliance['expected_value']),
        necb_section_name,
        test_text,
        compliance['tolerance']
      )
    end
    # necb_section_name = "NECB2011-5.2.10.1"
    # qaqc[:air_loops].each do |air_loop_info|
    #   unless air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] == -1.0
    #     weather_file_path = model.weatherFile.get.path.get.to_s
    #     stat_file_path = weather_file_path.gsub('.epw', '.stat')
    #     stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
    #     db990 = stat_file.heating_design_info[2]
    #     hrv_calc = 0.00123 * air_loop_info[:outdoor_air_L_per_s] * (21 - db990) #=AP46*(21-O$1)
    #     hrv_reqd = hrv_calc > 150 ? true : false
    #     #qaqc[:information] << "[Info][TEST-PASS][#{necb_section_name}]:#{test_text} result value:#{result_value} #{bool_operator} expected value:#{expected_value}"
    #     hrv_present = false
    #     unless air_loop_info[:heat_exchanger].empty?
    #       hrv_present = true
    #     end
    #     necb_section_test(
    #       qaqc,
    #       hrv_reqd,
    #       '==',
    #       hrv_present,
    #       necb_section_name,
    #       "[AIR LOOP][:heat_exchanger] for [#{air_loop_info[:name]}] is present?"
    #     )
    #   else
    #     qaqc['warnings'] << "[hrv_compliance] air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] == -1.0 for [#{air_loop_info[:name]}]"
    #   end
    # end
  end

  def necb_vav_fan_power_compliance(qaqc)
    necb_section_name = get_qaqc_table(table_name: 'vav_fan_power_compliance')['refs'].join(',')
    qaqc_table = get_qaqc_table(table_name: 'vav_fan_power_compliance')
    # necb_section_name = "NECB2011-5.2.3.3"
    qaqc[:air_loops].each do |air_loop_info|
      # necb_clg_cop = air_loop_info[:cooling_coils][:dx_single_speed][:cop] #*assuming that the cop is defined correctly*
      if air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s].nil?
        qaqc[:warnings] << '[vav_fan_power_compliance] air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s] is nil'
        next
      end

      max_air_flow_rate_m3_per_s = air_loop_info[:supply_fan][:max_air_flow_rate_m3_per_s]
      necb_supply_fan_w = -1

      if air_loop_info[:name].include? 'PSZ'
        necb_supply_fan_w = eval(qaqc_table['formulas']['NECB PSZ fan power (W)']).round(2)
      elsif air_loop_info[:name].include? 'VAV'
        necb_supply_fan_w = eval(qaqc_table['formulas']['NECB VAV fan power (W)']).round(2)
      end

      if air_loop_info[:supply_fan][:rated_electric_power_w].nil?
        qaqc[:warnings] << '[vav_fan_power_compliance] air_loop_info[:supply_fan][:rated_electric_power_w] is nil'
        next
      end

      supply_fan_w = (air_loop_info[:supply_fan][:rated_electric_power_w]).round(3)
      absolute_diff = (necb_supply_fan_w - supply_fan_w).to_f.abs
      if absolute_diff < 10
        # This case should ALWAYS PASS
        necb_section_test(
          qaqc,
          10,
          '>=',
          absolute_diff,
          necb_section_name,
          "[AIR LOOP][#{air_loop_info[:name]}][:supply_fan][:rated_electric_power_w] [#{supply_fan_w}] Absolute Difference from NECB value [#{necb_supply_fan_w}]"
        )
        next
      else
        # The test should pass if and only if the percent difference is less than 10%
        percent_diff = ((necb_supply_fan_w - supply_fan_w).to_f.abs / necb_supply_fan_w * 100).round(3)
        necb_section_test(
          qaqc,
          10,
          '>=',
          percent_diff,
          necb_section_name,
          "[AIR LOOP][#{air_loop_info[:name]}][:supply_fan][:rated_electric_power_w] [#{supply_fan_w}] Percent Diff from NECB value [#{necb_supply_fan_w}]"
        )
      end
    end
  end

  def necb_qaqc(qaqc, model)
    puts "\n\nin necb_qaqc 2011 now\n\n"
    # Now perform basic QA/QC on items for NECB2011
    qaqc[:information] = []
    qaqc[:warnings] = []
    qaqc[:errors] = []
    qaqc[:unique_errors] = []

    necb_space_compliance(qaqc)

    necb_envelope_compliance(qaqc)

    necb_infiltration_compliance(qaqc, model)

    necb_exterior_opaque_compliance(qaqc)

    necb_exterior_fenestration_compliance(qaqc)

    necb_exterior_ground_surfaces_compliance(qaqc)

    necb_zone_sizing_compliance(qaqc)

    necb_design_supply_temp_compliance(qaqc)

    necb_economizer_compliance(qaqc)

    necb_hrv_compliance(qaqc, model)

    necb_vav_fan_power_compliance(qaqc)

    sanity_check(qaqc)

    necb_plantloop_sanity(qaqc)

    qaqc[:information] = qaqc[:information].sort
    qaqc[:warnings] = qaqc[:warnings].sort
    qaqc[:errors] = qaqc[:errors].sort
    qaqc[:unique_errors] = qaqc[:unique_errors].sort
    return qaqc
  end

  def necb_section_test(qaqc, result_value, bool_operator, expected_value, necb_section_name, test_text, tolerance = nil)
    test = 'eval_failed'
    command = ''
    if tolerance.is_a?(Integer)
      command = "#{result_value}.round(#{tolerance}) #{bool_operator} #{expected_value}.round(#{tolerance})"
    elsif expected_value.is_a?(String) && result_value.is_a?(String)
      command = "'#{result_value}' #{bool_operator} '#{expected_value}'"
    else
      command = "#{result_value} #{bool_operator} #{expected_value}"
    end
    test = eval(command)
    test_res = nil
    test_res = true if test.to_s.downcase == 'true'
    test_res = false if test.to_s.downcase == 'false'
    raise "Eval command failed #{test}" if test_res.nil?

    if test_res
      qaqc[:information] << "[Info][TEST-PASS][#{necb_section_name}]:#{test_text} result value:#{result_value} #{bool_operator} expected value:#{expected_value}"
    else
      qaqc[:errors] << "[ERROR][TEST-FAIL][#{necb_section_name}]:#{test_text} expected value:#{expected_value} #{bool_operator} result value:#{result_value}"
      unless (expected_value == -1.0) || (expected_value == 'N/A')
        qaqc[:unique_errors] << "[ERROR][TEST-FAIL][#{necb_section_name}]:#{test_text} expected value:#{expected_value} #{bool_operator} result value:#{result_value}"
      end
    end
  end

  def check_boolean_value(value, varname)
    return true if value =~ /^(true|t|yes|y|1)$/i
    return false if value.empty? || value =~ /^(false|f|no|n|0)$/i

    raise ArgumentError, "invalid value for #{varname}: #{value}"
  end

  def look_up_csv_data(csv_fname, search_criteria)
    options = { headers: :first_row,
                converters: [:numeric] }
    unless File.exist?(csv_fname)
      raise "File: [#{csv_fname}] Does not exist"
    end

    # we'll save the matches here
    matches = nil
    # save a copy of the headers
    headers = nil
    CSV.open(csv_fname, 'r', **options) do |csv|
      # Since CSV includes Enumerable we can use 'find_all'
      # which will return all the elements of the Enumerble for
      # which the block returns true

      matches = csv.find_all do |row|
        match = true
        search_criteria.keys.each do |key|
          match &&= (row[key].strip == search_criteria[key].strip)
        end
        match
      end
      headers = csv.headers
    end
    # puts matches
    raise('More than one match') if matches.size > 1

    puts "Zero matches found for [#{search_criteria}]" if matches.empty?
    # return matches[0]
    return matches[0]
  end
end
