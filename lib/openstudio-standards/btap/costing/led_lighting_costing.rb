class BTAPCosting

  def cost_audit_led_lighting(model:, prototype_creator:)
    a = 0 # This is for reporting purposes.
    standards_template = model.building.get.standardsTemplate.to_s
    if standards_template.include?('NECB')
      # insert a space between NECB and 2011/2015/2017
      standards_template = standards_template.gsub(/NECB(\d)/, 'NECB \1')
    end
    # puts standards_template

    #-------------------------------------------------------------------------------------------------------------------
    led_cost_total = 0.0
    #-------------------------------------------------------------------------------------------------------------------
    model.getSpaces.sort.each do |space|

      ##### Find height of the space
      max_space_height_m = 0.0
      space.surfaces.sort.select { |surface| surface.surfaceType == 'Wall' }.each do |wall_surface|
        # Find the vertex with the max z value.
        vertex_with_max_height = wall_surface.vertices.max_by(&:z)
        # Replace max if this surface has something bigger.
        max_space_height_m = vertex_with_max_height.z if vertex_with_max_height.z > max_space_height_m
      end
      # puts "max_space_height_m - #{max_space_height_m}"
      max_space_height_ft = (OpenStudio.convert(max_space_height_m, 'm', 'ft').get) #Convert height to ft
      # puts "max_space_height_ft - #{max_space_height_ft}"

      ##### Find space's floor area
      floor_surface = nil
      floor_area_m2 = 0.0
      floor_vertices = []
      space.surfaces.sort.each do |surface|
        # puts floor_area_m2
        if surface.surfaceType == 'Floor'
          floor_surface = surface
          floor_area_m2 += surface.netArea
          # puts floor_area_m2
        end
      end
      floor_area_ft2 = (OpenStudio.convert(floor_area_m2, 'm^2', 'ft^2').get) #convert floor_area_m2 to ft2
      # puts "floor_area_m2 - #{floor_area_m2}"
      # puts "floor_area_ft2 - #{floor_area_ft2}"

      ##### Find type of the space
      space_type = space.spaceType()
      # puts space_type.get
      space_type_name = space_type.get.standardsSpaceType
      # puts "space_type_name - #{space_type_name}"

      ##### Figure out if the space has LED lighting; and calculate its associated cost
      space_type.get.lights.sort.each do |light|
        space_lights_definition = light.lightsDefinition
        space_lights_definition_name = space_lights_definition.name
        # puts space_lights_definition_name

        if space_lights_definition_name.to_s.include?('LED lighting')
          led_cost_space = 0.0
          ##### COSTING-related step: Find fixture type that should be used in the space based on space_type, template, and lights_type
          search_fixture_type = {
              row_id_1: space_type_name,
              row_id_2: standards_template,
              row_id_3: 'LED'
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
          # puts "fixture_type - #{fixture_type}"

          ##### COSTING-related step: Find 'id_layers' and 'Id_layers_quantity_multipliers' based on fixture_type; and calculate LED cost
          search_id_layers = @costing_database['raw']['lighting'].select { |data|
            data['lighting_type_id'].to_f.round(1) == fixture_type.to_f.round(1)
          }.first
          if search_id_layers.nil?
            puts("No data found for #{search_id_layers}!")
            raise
          end
          ids = search_id_layers['id_layers'].to_s.split(',')
          # puts "id_layers - #{ids}"

          search_id_layers_quantity_multipliers = @costing_database['raw']['lighting'].select { |data|
            data['lighting_type_id'].to_f.round(1) == fixture_type.to_f.round(1)
          }.first
          if search_id_layers_quantity_multipliers.nil?
            puts("No data found for #{search_id_layers_quantity_multipliers}!")
            raise
          end
          id_quants = search_id_layers_quantity_multipliers['Id_layers_quantity_multipliers'].to_s.split(',')
          # puts "id_layers_quantity_multipliers - #{id_quants}"

          overall_mult = 1.0

          index_id_quant = 0.0
          ids.each do |id|
            quantity_led = id_quants[index_id_quant].to_f * overall_mult * floor_area_ft2
            # id_description_search = @costing_database['raw']['materials_lighting'].select { |data|
            #   data['lighting_type_id'].to_f.round(1) == id.to_f.round(1)
            # }.first
            # id_description = id_description_search['description']

            search_led = {
                row_id_1: nil,
                row_id_2: id
            }
            sheet_name = 'materials_lighting'
            column_1 = nil
            column_2 = 'lighting_type_id'
            tags = ['lighting', 'led_lighting']
            led_costing = assembly_cost(cost_info:search_led,
                                        sheet_name:sheet_name,
                                        column_1:column_1,
                                        column_2:column_2,
                                        quantity:quantity_led,
                                        tags: tags)
            led_cost_space += led_costing
            index_id_quant += 1.0
          end

          led_cost_total += led_cost_space

          @costing_report["lighting"]["led_lighting"] << {
              'space' => space.name.to_s,
              'led_costing' => led_cost_space,
          }

          a += 1

        end #if space_lights_definition_name.to_s.include?('LED lighting')
      end #space_type.get.lights.sort.each do |light|
      #-------------------------------------------------------------------------------------------------------------------

    end #model.getSpaces.sort.each do |space|
    #-------------------------------------------------------------------------------------------------------------------

    if a > 0
      @costing_report["lighting"]["led_lighting"] << {
          'total_cost' => led_cost_total
      }
    end

    puts "\nLED lighting costing data successfully generated. Total LED lighting costs: $#{led_cost_total.round(2)}"

    return led_cost_total

  end #cost_audit_led_lighting(model, prototype_creator)

end