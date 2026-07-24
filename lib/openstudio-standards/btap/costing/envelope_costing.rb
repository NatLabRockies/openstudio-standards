module BTAP
  class Costing
    # @param prototype_creator [Standard]
    def cost_audit_envelope(prototype_creator)

      # Populate the `costing_report` hash to report costing details per surface
      # type.
      @attributes.surface_types.each do |surface_type|
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost"]        = 0.0
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"]     = 0.0
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"] = 0.0
      end

      # Cost all the constructions found by BTAP Attributes.
      @attributes.get_constructions.each do |construction|
        cost_construction(construction, @costing_report['province_state'], @costing_report['city'])
      end

      @costing_report["envelope"]["construction_costs"] = []

      totEnvCost = 0

      @attributes.spaces.each do |space|
        @attributes.surface_types.each do |surface_type|
          num_surface_types = 0
          space.surfaces_hash[surface_type].each do |surface|
            if surface.btap_constructions.nil?
              next
            end

            num_surface_types += 1
            surface_is_glazing = surface.btap_constructions.first["type"] == "glazing"
            construction_name  = surface.btap_constructions.first["name"]
            cost_range_array   = surface.btap_constructions.map { |construction|
              [construction["rsi"], construction["cost"]] }

            # Use the cost_range_array to interpolate the estimated cost for the
            # RSI of the current surface.
            cost, notes = BTAP::LinearRegression.interpolate(x_y_array: cost_range_array, x2: surface.rsi)

            # Calculate SHGC/film cost.
            film_cost = 0.0
            if surface_is_glazing

              # Get SHGC from surface.
              shgc = OpenstudioStandards::Constructions.construction_get_solar_transmittance(
                surface.construction.get.to_Construction.get)

              # Get the closest value in materials_glazing sheet of SolarFilms.
              material_row = @costing_database["raw"]["materials_glazing"].select { |row|
                row['material_type'] == 'Solarfilms' }.min_by {|row|
                  (shgc.to_f - row['solar_heat_gain_coefficient'].to_f).abs}

              standard_film_cost = getCost(material_row['description'], material_row, 1.0)
              regional_factors   = get_regional_cost_factors(
                @costing_report['province_state'],
                @costing_report['city'],
                material_row)

              # Multiply regional cost and sum costs. Zip adds the arrays
              # together, map multiplies each row and divides by 100.0 since the
              # regional factor is a percentage.
              film_cost = standard_film_cost.zip(regional_factors).map { |cost,region_factor|
                cost * region_factor / 100.0 }.inject(0, :+)
            end

            surfArea    = surface.netArea * space.thermalZone.get.multiplier
            surfAreaft  = (OpenStudio.convert(surfArea, "m^2", "ft^2").get).to_f
            surfCost    = (cost + film_cost) * surfAreaft
            totEnvCost += surfCost
            name        = ""

            # Bin the costing by construction standard type and rsi.
            if surface.btap_constructions.nil?
              name = "undefined surface construction_#{(1.0 / surface.rsi).round(3)}"
            else
              name = "#{construction_name}"
            end
            row = @costing_report["envelope"]["construction_costs"].detect { |row|
              (row['name'] == name) && (row['conductance'].round(3) == ((1.0 / surface.rsi).round(3))) }

            if row.nil?
              @costing_report["envelope"]["construction_costs"] << {
                'assembly_name' => name,
                'surface_type'  => surface_type,
                'surface_name'  => surface.nameString,
                'conductance'   => (surface.rsi.round(3)),
                'area'          => (surfArea.round(2)),
                'cost'          => (surfCost.round(2)),
                'cost_per_area' => (surfCost / surfArea).round(2),
                'note'          => "Surf ##{num_surface_types}: #{notes}"
              }
            else
              row['area']          = (row['area'] + surfArea).round(2)
              row['cost']          = (row['cost'] + surfCost).round(2)
              row['cost_per_area'] = ((row['cost'] / row['area']).to_f.round(2))
              row['note']         += " / #{num_surface_types}: #{notes}"
            end

            @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost"]    += surfCost
            @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] += surfArea
          end # surfaces of surface type
          @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"] = (
            @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost"] /
            @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"])

          if @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"].nan?
            @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"] = 0.0
          end
        end # surface_type
      end # spaces

      # Parapets aren't explicitly modeled in an OpenStudio model. If TBD was run,
      # account for parapets by taking the calculated parapet length and multiply
      # it by 1m to factor it into the total cost. So, take the cost of the
      # exterior walls per m^2 and multiply it buy the total parapet length.
      if @attributes.use_tbd
        wall_cost_per_m2 = @costing_report["envelope"]["exterior_wall_cost_per_m2"]
        parapet_cost = @attributes.tbd_edge_tallies["parapet"].values.first * wall_cost_per_m2
        @costing_report["envelope"]["parapet_cost"] = parapet_cost.round(2)
        totEnvCost += parapet_cost
      end

      # When using thermal bridging it may create too demanding of a model, or
      # when data is insufficient, some R-factors will be outside of the data
      # and BTAP::LinearRegression will refuse to extrapolate beyond its default
      # range. If that occured, don't raise an error but add a really high number
      # to the envelope cost to make the user aware of what happened.
      if BTAP::LinearRegression.extrapolation_boundaries_exceeded?
        revolutionary_engineering_technology_fudge_factor = 1000000000000
        totEnvCost += revolutionary_engineering_technology_fudge_factor
        @costing_report["envelope"]["unrealistic_assembly_cost"] = revolutionary_engineering_technology_fudge_factor
        @costing_report["unrealistic_assembly_note"] = \
          "Could not extrapolate beyond the given range. The given model might be unrealistic to build because no " \
          "assemblies exist in the database with the given heat transfer requirements. This could be that the thermal " \
          "bridging module created too demanding of a model given the performance constraints. Try changing the " \
          "`tbd_option` parameter in your run options."
      end

      # Round everything at the end.
      @attributes.surface_types.each do |surface_type|
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost"] = \
          @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost"].round(2)
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] = \
          @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"].round(2)
        @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"] = \
          @costing_report["envelope"]["#{@attributes.surface_types_to_snake[surface_type]}_cost_per_m2"].round(2)
      end

      @costing_report["envelope"]["total_envelope_cost"] = totEnvCost.to_f.round(2)
      puts "\nEnvelope costing data successfully generated. Total envelope cost is $#{totEnvCost.to_f.round(2)}"

      return totEnvCost
    end

    # Append the "cost" key-value pair to a construction hash by calculating
    # the cost from each layer from either the opaque (materials_opaque.csv)
    # or glazing (materials_glazing.csv) while also accounting for regional and
    # installation factors.
    #
    # @param construction   [Hash]
    # @param province_state [String]
    # @param city           [String]
    def cost_construction(construction, province_state, city)
      material_id = "materials_#{construction["type"]}_id"
      materials_database = @costing_database["raw"]["materials_#{construction["type"]}"]

      total_with_op = 0.0
      material_cost_pairs = []
      construction["id_layers"].each do |material_index|
        material = materials_database.find { |data| data[material_id] == material_index }
        if material.nil?
          raise("Material ID #{material_index} was not found in the materials_#{construction["type"]} database.")
        else
          costing_data = @costing_database['costs'].detect { |data| data['id'] == material['id'] }
          if costing_data.nil?
            raise("Material ID #{material_index} was not found in the costing database")
          else
            regional_material, regional_installation = get_regional_cost_factors(province_state, city, material)

            # Get cost information from lookup.
            material_cost  = costing_data['baseCosts']['materialOpCost'] * material['material_mult'].to_f
            labour_cost    = costing_data['baseCosts']['laborOpCost']    * material['labour_mult'].to_f
            equipment_cost = costing_data['baseCosts']['equipmentOpCost']
            layer_cost     = (((material_cost * regional_material / 100.0) + \
                             (labour_cost * regional_installation / 100.0) + equipment_cost) * \
                             material['quantity'].to_f).round(2)
            material_cost_pairs << {material_id => material_index, 'cost' => layer_cost}
            total_with_op += layer_cost
          end
        end
      end

      construction["cost"] = total_with_op
    end
  end
end