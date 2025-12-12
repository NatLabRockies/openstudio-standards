class String
  def underscore
    self.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        tr("-", "_").
        downcase
  end
end

class BTAPCosting

  # @param prototype_creator [Standard]
  def cost_audit_envelope(prototype_creator)

    # Populate the `costing_report` hash to report costing details per surface
    # type.
    @attributes.surface_types.each do |surface_type|
      @costing_report["envelope"]["#{surface_type.underscore}_cost"]        = 0.0
      @costing_report["envelope"]["#{surface_type.underscore}_area_m2"]     = 0.0
      @costing_report["envelope"]["#{surface_type.underscore}_cost_per_m2"] = 0.0
    end

    # Cost all the constructions found by BTAP Attributes.
    @attributes.get_constructions.each do |construction|
      cost_construction(construction, @costing_report['province_state'], @costing_report['city'])
    end

    @costing_report["envelope"]["construction_costs"] = []

    totEnvCost = 0

    @attributes.spaces.each do |space|

      # Get SpaceType defined for space. If not defined it will skip the
      # spacetype. May have to deal with Attic spaces.
      if space.spaceType.empty? or 
         space.spaceType.get.standardsSpaceType.empty? or 
         space.spaceType.get.standardsBuildingType.empty?
        raise("standards Space type and building type is not defined for space:#{space.name.get}. Skipping this " \
              "space for costing.")
      end

      @attributes.surface_types.each do |surface_type|

        # Iterate through actual surfaces in the model of surface_type.
        num_surface_types = 0
        space.surfaces_hash[surface_type].each do |surface|
          if surface.btap_constructions.nil?
            next
          end

          num_surface_types += 1
          surface_is_glazing = surface.btap_constructions.first.type == "glazing"
          construction_name  = surface.btap_constructions.first.name

          # We don't need all the information, just the rsi and cost. Window
          # costs from the API data use U-value, which was converted to rsi for
          # cost_range_array above.
          if surface_is_glazing
            cost_range_array = surface.btap_constructions.map do |construction|
              [1 / surface.rsi, construction.cost]
            end
          else
            cost_range_array = surface.btap_constructions.map do |construction|
              [surface.rsi, construction.cost]
            end
          end

          # Sorted based on rsi.
          cost_range_array.sort! { |a, b| a[0] <=> b[0] }

          # Use the cost_range_array to interpolate the estimated cost for the
          # given rsi.
          exterpolate_percentage_range = 30.0
          cost = interpolate(
            x_y_array: cost_range_array, 
            x2: surface.rsi, 
            exterpolate_percentage_range: exterpolate_percentage_range)

          # If the cost is nil, that means the rsi is out of range. Flag in the report.
          if cost.nil?
            unless cost_range_array.empty?
              notes = "Warning! RSI out of the range (#{'%.2f' % surface.rsi}) or cost is 0!. Range for " \
                      "#{construction_name} is " \
                      "#{'%.2f' % cost_range_array.first[0]}-#{'%.2f' % cost_range_array.last[0]}."
              cost = 0.0
            else
              notes = "No cost found for this! So Cost is set to 0.0!"
              cost = 0.0
            end
          elsif cost.nan?
            raise("The values for cost and conductance for #{construction_name} cannot be interpolated. Cannot " \
                  "create an equation of a line from #{cost_range_array.sort.uniq}. Check the construction database " \
                  "and either eliminate the errant row, or set the x value to an appropriate number.")
          else

            # Tell user if we are extrapolating outside of library.
            array = cost_range_array.sort { |a, b| a[0] <=> b[0] }
            if surface.rsi < (array.first[0].to_f) || surface.rsi > (array.last[0].to_f)
              notes = "RSI out of the range (#{'%.2f' % surface.rsi}). Range for " \
                      "#{construction_name} is " \
                      "#{'%.2f' % cost_range_array.first[0]}-#{'%.2f' % cost_range_array.last[0]}. " \
                      "Using extrapolation up to +/-30% of library boundaries."
            else
              notes = "OK"
            end
          end

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

          surfArea   = surface.netArea * space.thermalZone.get.multiplier
          surfAreaft = (OpenStudio.convert(surfArea, "m^2", "ft^2").get).to_f
          surfCost   = (cost + film_cost) * surfAreaft
          totEnvCost = totEnvCost + surfCost
          name       = ""

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
              'name'          => name, 
              'conductance'   => ((1.0 / surface.rsi).round(3)), 
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

          # Not using += for @costing_report additions so that output can be
          # properly rounded.
          @costing_report["envelope"]["#{surface_type.underscore}_cost"] = (
            @costing_report["envelope"]["#{surface_type.underscore}_cost"] + surfCost).round(2)
          @costing_report["envelope"]["#{surface_type.underscore}_area_m2"] = (
            @costing_report["envelope"]["#{surface_type.underscore}_area_m2"] + surfArea).round(2)
          @costing_report["envelope"]["#{surface_type.underscore}_cost_per_m2"] = (
            @costing_report["envelope"]["#{surface_type.underscore}_cost"] / \
            @costing_report["envelope"]["#{surface_type.underscore}_area_m2"]).round(2)
        end # surfaces of surface type
      end # surface_type
    end # spaces

    # Parapets aren't explicitly modeled in an OpenStudio model. If TBD was run,
    # account for parapets by taking the calculated parapet length and multiply
    # it by 1m to factor it into the total cost. So, take the cost of the
    # exterior walls per m^2 and multiply it buy the total parapet length.
    if @attributes.use_tbd
      wall_cost_per_m2 = @costing_report["envelope"]["exterior_wall_cost_per_m2"]
      parapet_cost = prototype_creator.tbd.tally[:edges][:parapet].values.first * wall_cost_per_m2
      @costing_report["envelope"]["parapet_cost"] = parapet_cost.round(2)
      totEnvCost += parapet_cost
    end

    @costing_report["envelope"]["total_envelope_cost"] = totEnvCost.to_f.round(2)
    puts "\nEnvelope costing data successfully generated. Total envelope cost is $#{totEnvCost.to_f.round(2)}"

    return totEnvCost
  end

  # Assign the "cost" parameter of a BTAP Construction by calculating the cost
  # from each layer from either the opaque (materials_opaque.csv) or glazing
  # (materials_glazing.csv) while also accounting for regional and installation
  # factors.
  #
  # @param construction   [BTAP::Construction]
  # @param province_state [String]
  # @param city           [String]
  def cost_construction(construction, province_state, city)
    material_id = "materials_#{construction.type}_id"
    materials_database = @costing_database["raw"]["materials_#{construction.type}"]

    total_with_op = 0.0
    material_cost_pairs = []
    construction.id_layers.each do |material_index|
      material = materials_database.find { |data| data[material_id] == material_index }
      if material.nil?
        puts "Material ID #{material_index} was not found in the materials_#{construction.type} database. " \
             "Skipping. This construction will be inaccurate."
      else
        costing_data = @costing_database['costs'].detect { |data| data['id'] == material['id'] }
        if costing_data.nil?
          puts "Material ID #{material_index} was not found in the costing database. Skipping. This construction " \
               "will be inaccurate."
        else
          regional_material, regional_installation = get_regional_cost_factors(province_state, city, material)

          # Get cost information from lookup.
          # Note that "glazing" types don't have a 'quantity' hash entry!
          # Don't need "and" below but using in-case this hash field is added in 
          # the future.
          if construction.type == 'glazing' and material['quantity'].to_f == 0.0
            material['quantity'] = '1.0'
          end
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

    construction.cost = total_with_op
  end
end
