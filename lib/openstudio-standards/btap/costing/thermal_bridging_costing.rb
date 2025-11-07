class BTAPCosting
  def cost_audit_thermal_bridging(model, prototype_creator)
    total_tbd_cost      = 0.0
    material_quantities = prototype_creator.tbd.get_material_quantities # Opaque IDs to quantities

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

    puts "\nThermal bridging costing data successfully generated. Total TBD costs: $#{total_tbd_cost.to_f.round(2)}"
    return total_tbd_cost
  end
end
