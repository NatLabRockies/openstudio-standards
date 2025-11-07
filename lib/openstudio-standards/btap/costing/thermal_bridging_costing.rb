class BTAPCosting
  def cost_audit_thermal_bridging(model, prototype_creator)
    cp                  = CommonPaths.instance
    csv                 = CSV.read(cp.thermal_bridging_path, headers: true)
    tbd                 = prototype_creator.tbd
    total_tbd_cost      = 0.0
    tally_edges         = tbd.tally[:edges].transform_keys(&:to_s)
    material_quantities = {} # Opaque IDs to quantities

    # Retrive the material quantities associated with each edge
    tally_edges.each do |edge_type, value|
      value.each do |wall_reference_and_quality, quantity|

        result = csv.find do |row| 
          row['construction_type'] == edge_type &&
          row['wall_reference']    == wall_reference_and_quality
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

          material_quantities[id] = material_quantities[id] + scale.to_f * quantity.to_f
        end
      end
    end

    # Calculate the cost associated from each of the ID-quantity pairs
    material_quantities.each do |id, tbd_quantity|
      @costing_database["raw"]["materials_opaque"].find do |material|
        regional_material, regional_installation = \
          get_regional_cost_factors(@cost_items["Province"], @cost_items["City"], material)

        costing_data    = @costing_database["costs"].find { |data| data["id"] == material["id"] }
        material_cost   = costing_data["baseCosts"]["materialOpCost"] * material["material_mult"].to_f
        labour_cost     = costing_data["baseCosts"]["laborOpCost"] * material["labour_mult"].to_f
        equipment_cost  = costing_data["baseCosts"]["equipmentOpCost"]
        total_tbd_cost += (((material_cost * regional_material / 100.0) + \
                          (labour_cost * regional_installation / 100.0) + \
                          equipment_cost) * (tbd_quantity / material["quantity"].to_f)).round(2)
      end
    end
   
    return total_tbd_cost
  end
end
