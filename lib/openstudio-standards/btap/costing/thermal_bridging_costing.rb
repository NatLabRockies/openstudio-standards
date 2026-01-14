class BTAPCosting

  # @param prototype_creator [Standard]
  def cost_audit_thermal_bridging(prototype_creator)
    total_tbd_cost      = 0.0
    material_quantities = get_material_quantities_for_edges # Opaque IDs to quantities

    # Calculate the cost associated from each of the ID-quantity pairs
    material_quantities.each do |id, tbd_quantity|
      @costing_database["raw"]["materials_opaque"].find do |material|
        regional_material, regional_installation = \
          get_regional_cost_factors(@cost_items["Province"], @cost_items["City"], material)

        costing_data      = @costing_database["costs"].find { |data| data["id"] == material["id"] }
        material_cost     = costing_data["baseCosts"]["materialOpCost"] * material["material_mult"].to_f
        labour_cost       = costing_data["baseCosts"]["laborOpCost"] * material["labour_mult"].to_f
        equipment_cost    = costing_data["baseCosts"]["equipmentOpCost"]
        tbd_quantity      = OpenStudio.convert(tbd_quantity, "m", "ft").get # Convert from m to ft
        material_quantity = Math.sqrt(material["quantity"].to_f) # Convert from ft^2 to ft

        # Calculate the total cost. Notable units and conversion factors: 
        # tbd_quantity:      Converted from meters to feet in bridging.rb
        # material_quantity: Square feet converted to feet. Some material
        #                    entries have varying units but those are just for
        #                    reference to RSMeans.
        total_tbd_cost += (((material_cost * regional_material / 100.0) + \
                          (labour_cost * regional_installation / 100.0) + \
                          equipment_cost) * (tbd_quantity / material_quantity)).round(2)
      end
    end

    puts "\nThermal bridging costing data successfully generated. Total TBD costs: $#{total_tbd_cost.to_f.round(2)}"
    return total_tbd_cost
  end

  # Retrieve the material quantities for the values in the tbd.edges
  # parameter.
  # @return [Hash] IDs mapped to their quantities in feet.
  def get_material_quantities_for_edges
    cp                  = CommonPaths.instance
    csv                 = CSV.read(cp.thermal_bridging_path, headers: true)
    material_quantities = {}

    # The "convex/concave" suffix on tally edges can be safely ignored since
    # they currently aren't relevant to any NECB standard, but they are to
    # ASHRAE 90.1.
    tally_edges = @attributes.tbd_edge_tallies.transform_keys { |key| key.gsub(/concave|convex/, '') }
    tally_edges.each do |edge_type, value|
      value.each do |wall_reference_and_quality, quantity|

        # "transition" edges aren't considered.
        if edge_type == "transition"
          next

        # "jamb", "sill", and "head" may all be grouped under fenestration
        # when referencing the thermal bridging CSV. Same for "skylightjamb",
        # "skylightsill", and "skylighthead".
        elsif edge_type.match?(/^(skylight)?(jamb|sill|head)$/)
          edge_type = "fenestration"
        end

        result = csv.find do |row|
          row["edge_type"]      == edge_type &&
          row["wall_reference"] == wall_reference_and_quality
        end

        if result.nil?
          puts("Wall with type #{edge_type} and reference #{wall_reference_and_quality}" \
               " could not be found in the thermal bridging database")
          next
        end

        material_opaque_id_layers = result['material_opaque_id_layers'].split(",")
        id_layers_quantity_multipliers = result['id_layers_quantity_multipliers'].split(",")
        material_opaque_id_layers.zip(id_layers_quantity_multipliers).each do |id, scale|
          if material_quantities[id].nil?
            material_quantities[id] = 0.0
          end

          material_quantities[id] = material_quantities[id] + scale.to_f * quantity
        end
      end
    end

    return material_quantities
  end
end
