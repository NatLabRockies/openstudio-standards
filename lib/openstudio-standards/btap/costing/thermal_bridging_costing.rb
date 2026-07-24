module BTAP
  class Costing

    # @param prototype_creator [Standard]
    def cost_audit_thermal_bridging(prototype_creator)
      total_tbd_cost      = 0.0
      material_quantities = BTAP::BridgingData::get_material_quantities_for_edges(@attributes.tbd_edge_tallies)

      # Calculate the cost associated from each of the ID-quantity pairs.
      # Note that no localization facors are used. This is because thermal
      # bridging edge tallies should be costed nationwide.
      material_quantities.each do |id, tbd_quantity|
        material = @costing_database["raw"]["materials_opaque"].find do |data|
          data["materials_opaque_id"].to_s == id.to_s
        end

        if material.nil?
          puts "Thermal bridging material id #{id} not found in the materials_opaque sheet. Skipping."
          next
        end

        costing_data      = @costing_database["costs"].find { |data| data["id"] == material["id"] }
        if costing_data.nil?
          puts "Thermal bridging material id #{material['id']} not found in the costing database. Skipping."
          next
        end
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
        total_tbd_cost += ((material_cost + labour_cost + equipment_cost) * \
                          (tbd_quantity / material_quantity)).round(2)
      end

      puts "\nThermal bridging costing data successfully generated. Total TBD costs: $#{total_tbd_cost.to_f.round(2)}"
      return total_tbd_cost
    end
  end
end
