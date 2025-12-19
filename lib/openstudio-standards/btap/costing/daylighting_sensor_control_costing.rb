class BTAPCosting

  def cost_audit_daylighting_sensor_control(model:, prototype_creator:)
    @costing_report["lighting"]["daylighting_sensor_control"] = []
    # NOTE: Number of daylighting sensors is based on how many a daylighted space needs sensors as per Mike Lubun's costing spec, rather than daylighting sensor control measure.
    standards_template = model.building.get.standardsTemplate.to_s
    if standards_template.include?('NECB')
      # insert a space between NECB and 2011/2015/2017
      standards_template = standards_template.gsub(/NECB(\d)/, 'NECB \1')
    end

    #-------------------------------------------------------------------------------------------------------------------
    dsc_cost_total = 0.0
    all_tz_primary_sidelighted_quatity = 0.0
    all_tz_skylight_quatity = 0.0
    #-------------------------------------------------------------------------------------------------------------------
    model.getThermalZonesSorted.each do |tz|
      if tz.primaryDaylightingControl.is_initialized
        tz_cost_primary_sidelighted = 0.0
        tz_cost_skylight = 0.0
        tz_multiplier = tz.multiplier()
        daylight_spaces = []
        primary_sidelighted_area_hash = {}
        daylighted_area_under_skylights_hash = {}
        primary_sidelighted_area = 0.0
        daylighted_under_skylight_area = 0.0
        tz_area = 0.0
        tz_number_fixtures = 0.0
        tz_primary_sidelighted_ratio_daylight_area = 0.0
        tz_primary_sidelighted_number_fixtures = 0.0
        tz_primary_sidelighted_number_sensors = 0.0
        tz_skylights_ratio_daylight_area = 0.0
        tz_skylights_number_fixtures = 0.0
        tz_skylights_number_sensors = 0.0
        if !tz.primaryDaylightingControl.get.name().empty? && tz.fractionofZoneControlledbyPrimaryDaylightingControl() > 0.00
          tz.spaces().sort.each do |space|
            daylight_spaces << space
          end
        end

        #-------------------------------------------------------------------------------------------------------------------
        ##### Calculate tz_primary_sidelighted_area AND tz_daylighted_area_under_skylights.
        ##### The above two area values are required for the calculation of tz_primary_sidelighted_number_fixtures AND tz_skylights_number_fixtures
        daylight_spaces.sort.each do |daylight_space|
          # Go to the next space if the current space's space type is undefined.
          next if daylight_space.spaceType.get.name.to_s.downcase.include? "undefined"

          area_weighted_vt_handle = 0.0
          window_area_sum = 0.0
          skylight_area_weighted_vt_handle = 0.0
          skylight_area_sum = 0.0

          ##### Find lights_type in each daylight_space
          led_lights = 0
          daylight_space_type = daylight_space.spaceType()
          daylight_space_type.get.lights.sort.each do |inst|
            daylight_space_lights_definition = inst.lightsDefinition
            daylight_space_lights_definition_name = daylight_space_lights_definition.name
            if daylight_space_lights_definition_name.to_s.include?('LED lighting')
              led_lights += 1
            end
          end
          if (led_lights > 0) or (standards_template == 'NECB 2020')
            lights_type = 'LED'
          else
            lights_type = 'CFL'
          end

          ##### Find height of daylight_space
          max_space_height_m = 0.0
          daylight_space.surfaces.sort.select { |surface| surface.surfaceType == 'Wall' }.each do |wall_surface|
            # Find the vertex with the max z value.
            vertex_with_max_height = wall_surface.vertices.max_by(&:z)
            # Replace max if this surface has something bigger.
            max_space_height_m = vertex_with_max_height.z if vertex_with_max_height.z > max_space_height_m
          end
          max_space_height_ft = (OpenStudio.convert(max_space_height_m, 'm', 'ft').get) #Convert height to ft

          ##### Find area, floor_surface, and floor_vertices of daylight_space
          floor_surface = nil
          floor_area = 0.0
          floor_vertices = []
          daylight_space.surfaces.sort.each do |surface|
            if surface.surfaceType == 'Floor'
              floor_surface = surface
              floor_area += surface.netArea
              floor_vertices << surface.vertices
            end
          end

          ##### COSTING-related step: Find fixture type that should be used in the daylight_space based on space_type, template, and lights_type
          search_fixture_type = {
              row_id_1: daylight_space.spaceType.get.standardsSpaceType.to_s, #space_type
              row_id_2: standards_template,
              row_id_3: lights_type
          }
          sheet_name = 'lighting_sets'
          if max_space_height_ft < 7.88
            column_search = 'Fixture_type_less_than_7.88ft_ht'
          elsif max_space_height_ft >= 7.88 && max_space_height_ft < 15.75
            column_search = 'Fixture_type_7.88_to_15.75ft_ht'
          else #i.e. max_space_height_ft >= 15.75ft_ht
            column_search = 'Fixture_type_greater_than_>15.75ft_ht'
          end
          row_search_1 = 'space_type'
          row_search_2 = 'template'
          row_search_3 = 'Type'
          fixture_type = get_fixture_type_id(fixture_info: search_fixture_type, sheet_name: sheet_name, row_name_1: row_search_1, row_name_2: row_search_2, row_name_3: row_search_3, column_search: column_search)

          ##### COSTING-related step: Find number_fixtures_per_1000_ft2 that should be considered in the daylight_space based on fixture_type
          search_fixtures_per_1000_ft2 = @costing_database['raw']['lighting'].select { |data|
            data['lighting_type_id'].to_f.round(1) == fixture_type.to_f.round(1)
          }.first
          if search_fixtures_per_1000_ft2.nil?
            puts("No data found for #{search_fixtures_per_1000_ft2}!")
            raise
          end
          number_fixtures_per_1000_ft2 = search_fixtures_per_1000_ft2['Fix_1000ft'].to_i

          ##### COSTING-related step: Calculate number_fixtures_space that should be considered in the daylight_space based on number_fixtures_per_1000_ft2 and area of daylight_space
          floor_area_ft2 = (OpenStudio.convert(floor_area, 'm^2', 'ft^2').get) #convert floor_area to ft2
          number_fixtures_space = (floor_area_ft2 / 1000) * number_fixtures_per_1000_ft2
          number_fixtures_space = number_fixtures_space.ceil
          tz_number_fixtures += number_fixtures_space

          #-----------------------------------------------------------------------------------------------------------------
          ############################## Calculate 'primary_sidelighted_area' of the thermal zone ##########################
          primary_sidelighted_area, area_weighted_vt_handle, window_area_sum =
              prototype_creator.get_parameters_sidelighting(daylight_space: daylight_space,
                                                   floor_surface: floor_surface,
                                                   floor_vertices: floor_vertices,
                                                   floor_area: floor_area,
                                                   primary_sidelighted_area: primary_sidelighted_area,
                                                   area_weighted_vt_handle: area_weighted_vt_handle,
                                                   window_area_sum: window_area_sum)

          primary_sidelighted_area_hash[daylight_space.name.to_s] = primary_sidelighted_area
          #-----------------------------------------------------------------------------------------------------------------
          ########################### Calculate 'daylighted_under_skylight_area' of the thermal zone #########################
          ##### Loop through the surfaces of each daylight_space to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
          daylighted_under_skylight_area, skylight_area_weighted_vt_handle, skylight_area_sum =
              prototype_creator.get_parameters_skylight(daylight_space: daylight_space,
                                               skylight_area_weighted_vt_handle: skylight_area_weighted_vt_handle,
                                               skylight_area_sum: skylight_area_sum,
                                               daylighted_under_skylight_area: daylighted_under_skylight_area)

          daylighted_area_under_skylights_hash[daylight_space.name.to_s] = daylighted_under_skylight_area
          #-----------------------------------------------------------------------------------------------------------------

          tz_area += floor_area

        end #daylight_spaces.sort.each do |daylight_space|

        #-------------------------------------------------------------------------------------------------------------------
        # If no fixtures or daylighting is defined then go to the next thermal zone
        next if tz_number_fixtures.to_f == 0.0 || tz_primary_sidelighted_ratio_daylight_area.to_f.nan?
        ##### COSTING-related step: Calculate number of fixtures in thermal zones with window(s)-------------------------------------------------
        tz_primary_sidelighted_ratio_daylight_area = primary_sidelighted_area / tz_area
        tz_primary_sidelighted_number_fixtures = (tz_number_fixtures * tz_primary_sidelighted_ratio_daylight_area).ceil
        tz_primary_sidelighted_number_sensors = (tz_primary_sidelighted_number_fixtures / 4.0).ceil
        all_tz_primary_sidelighted_quatity += tz_primary_sidelighted_number_sensors * tz_multiplier

        if tz_primary_sidelighted_number_sensors > 0.0
          tags = ['lighting', 'daylighting_sensor_control']
          # cost of daylighting sensor
          quantity_tz_primary_sidelighted_daylighting_sensor = 1.0 * tz_primary_sidelighted_number_sensors * tz_multiplier
          search_tz_primary_sidelighted_daylighting_sensor = {
              row_id_1: 'Ea',
              row_id_2: 407
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_primary_sidelighted_daylighting_sensor = assembly_cost(cost_info:search_tz_primary_sidelighted_daylighting_sensor,
                                                                         sheet_name:sheet_name,
                                                                         column_1:column_1,
                                                                         column_2:column_2,
                                                                         quantity:quantity_tz_primary_sidelighted_daylighting_sensor,
                                                                         tags: tags)
          # cost of wiring
          quantity_tz_primary_sidelighted_wiring = (30.0 / 100.0) * tz_primary_sidelighted_number_sensors * tz_multiplier
          search_tz_primary_sidelighted_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_primary_sidelighted_wiring = assembly_cost(cost_info:search_tz_primary_sidelighted_wiring,
                                                             sheet_name:sheet_name,
                                                             column_1:column_1,
                                                             column_2:column_2,
                                                             quantity:quantity_tz_primary_sidelighted_wiring,
                                                             tags: tags)
          # cost of pvc conduit
          quantity_tz_primary_sidelighted_pvc_conduit = 30.0 * tz_primary_sidelighted_number_sensors * tz_multiplier
          search_tz_primary_sidelighted_pvc_conduit = {
              row_id_1: 'LF',
              row_id_2: 17
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_primary_sidelighted_pvc_conduit = assembly_cost(cost_info:search_tz_primary_sidelighted_pvc_conduit,
                                                                  sheet_name:sheet_name,
                                                                  column_1:column_1,
                                                                  column_2:column_2,
                                                                  quantity:quantity_tz_primary_sidelighted_pvc_conduit,
                                                                  tags: tags)
          # cost of box
          quantity_tz_primary_sidelighted_box = 1.0 * tz_primary_sidelighted_number_sensors * tz_multiplier
          search_tz_primary_sidelighted_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_primary_sidelighted_box = assembly_cost(cost_info:search_tz_primary_sidelighted_box,
                                                          sheet_name:sheet_name,
                                                          column_1:column_1,
                                                          column_2:column_2,
                                                          quantity:quantity_tz_primary_sidelighted_box,
                                                          tags: tags)
          # total cost for this zone
          tz_cost_primary_sidelighted = cost_tz_primary_sidelighted_daylighting_sensor +
                                        cost_tz_primary_sidelighted_wiring +
                                        cost_tz_primary_sidelighted_pvc_conduit +
                                        cost_tz_primary_sidelighted_box
          dsc_cost_total += tz_cost_primary_sidelighted
        end

        ##### COSTING-related step: Calculate number of fixtures in thermal zones with skylight(s)-------------------------------------------------
        tz_skylights_ratio_daylight_area = daylighted_under_skylight_area / tz_area
        tz_skylights_number_fixtures = (tz_number_fixtures * tz_skylights_ratio_daylight_area).ceil
        tz_skylights_number_sensors = (tz_skylights_number_fixtures / 4.0).ceil
        all_tz_skylight_quatity += tz_skylights_number_sensors * tz_multiplier

        if tz_skylights_number_sensors > 0.0
          tags = ['lighting', 'daylighting_sensor_control']
          # cost of daylighting sensor
          quantity_tz_skylights_daylighting_sensor = 1.0 * tz_skylights_number_sensors * tz_multiplier
          search_tz_skylights_daylighting_sensor = {
              row_id_1: 'Ea',
              row_id_2: 407
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_skylights_daylighting_sensor = assembly_cost(cost_info:search_tz_skylights_daylighting_sensor,
                                                               sheet_name:sheet_name,
                                                               column_1:column_1,
                                                               column_2:column_2,
                                                               quantity:quantity_tz_skylights_daylighting_sensor,
                                                               tags: tags)

          # cost of wiring
          quantity_tz_skylights_wiring = (30.0 / 100.0) * tz_skylights_number_sensors * tz_multiplier
          search_tz_skylights_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_skylights_wiring = assembly_cost(cost_info:search_tz_skylights_wiring,
                                                   sheet_name:sheet_name,
                                                   column_1:column_1,
                                                   column_2:column_2,
                                                   quantity:quantity_tz_skylights_wiring,
                                                   tags: tags)

          # cost of pvc conduit
          quantity_tz_skylights_pvc_conduit = 30.0 * tz_skylights_number_sensors * tz_multiplier
          search_tz_skylights_pvc_conduit = {
              row_id_1: 'LF',
              row_id_2: 17
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_skylights_pvc_conduit = assembly_cost(cost_info:search_tz_skylights_pvc_conduit,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity:quantity_tz_skylights_pvc_conduit,
                                                        tags: tags)

          # cost of box
          quantity_tz_skylights_box = 1.0 * tz_skylights_number_sensors * tz_multiplier
          search_tz_skylights_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          cost_tz_skylights_box = assembly_cost(cost_info:search_tz_skylights_box,
                                                sheet_name:sheet_name,
                                                column_1:column_1,
                                                column_2:column_2,
                                                quantity:quantity_tz_skylights_box,
                                                tags: tags)

          # total cost for this zone
          tz_cost_skylight = cost_tz_skylights_daylighting_sensor +
                             cost_tz_skylights_wiring +
                             cost_tz_skylights_pvc_conduit +
                             cost_tz_skylights_box

          dsc_cost_total += tz_cost_skylight
        end

        ##### Gather information for reporting
        @costing_report["lighting"]["daylighting_sensor_control"] << {
            'zone' => tz.name.to_s,
            'zone_area' => tz_area,
            'zone_multiplier' => tz_multiplier,
            'number_of_fixtures_required_without_considering_daylighted_area_under_sidelighting_and_skylights' => tz_number_fixtures,
            'primary_sidelighted_area' => primary_sidelighted_area,
            'primary_sidelighted_number_fixtures' => tz_primary_sidelighted_number_fixtures,
            'primary_sidelighted_number_sensors' => tz_primary_sidelighted_number_sensors,
            'skylights_daylighted_area' => daylighted_under_skylight_area,
            'skylights_number_fixtures' => tz_skylights_number_fixtures,
            'skylights_number_sensors' => tz_skylights_number_sensors,
            'daylighting_sensor_control_cost_for_this_zone' => tz_cost_primary_sidelighted + tz_cost_skylight
        }

      end #tz.primaryDaylightingControl.is_initialized
    end #model.getThermalZonesSorted.each do |tz|
    #-------------------------------------------------------------------------------------------------------------------

    puts "\nDaylighting sensor controls costing data successfully generated. Total DSC costs: $#{dsc_cost_total.round(2)}"

    return dsc_cost_total

  end #cost_audit_daylighting_sensor_control(model, prototype_creator)


  def get_fixture_type_id(fixture_info:, sheet_name:, row_name_1:, row_name_2:, row_name_3:, column_search:)
    fixture_type = nil
    fixture_type = @costing_database['raw'][sheet_name].select { |data|
      data[row_name_1].to_s.upcase == fixture_info[:row_id_1].to_s.upcase and
          data[row_name_2].to_s.upcase == fixture_info[:row_id_2].to_s.upcase and
          data[row_name_3].to_s.upcase == fixture_info[:row_id_3].to_s.upcase
    }.first
    if fixture_type.nil?
      puts("No data found for #{fixture_type}!")
      raise
    end
    return fixture_type[column_search]
  end

end
