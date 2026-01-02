class BTAPCarbon
  def initialize(attributes:, standards_data:)
    @carbon_database  = {}
    @costing_database = CostingDatabase.instance
    @cp               = CommonPaths.instance
    @attributes       = attributes
    @carbon_report    = {}
    @frame_m_to_kg    = standards_data["constants"]["glazing_frame_m_to_kg"]

    # Build the carbon database.
    carbon_opaque = CSV.read(@cp.carbon_opaque_path)
    @carbon_database["opaque"] = Array.new

    1.upto carbon_opaque.length - 1 do |i|
      row   = carbon_opaque[i]
      index = row.each
      item  = Hash.new

      item["materials_opaque_id"]                     = index.next
      item["description"]                             = index.next
      item["type"]                                    = index.next
      item["quantity"]                                = index.next.to_f
      item["per m2"]                                  = index.next.to_f
      item["Product Category"]                        = index.next
      item["Embodied Carbon (A1-A5)"]                 = index.next.to_f
      item["Embodied Carbon (A-C)"]                   = index.next.to_f
      item["Environmental Product Declaration (EPD)"] = index.next

      @carbon_database["opaque"] << item
    end

    carbon_glazing = CSV.read(@cp.carbon_glazing_path)
    @carbon_database["glazing"] = Array.new

    1.upto carbon_glazing.length - 1 do |i|
      row   = carbon_glazing[i]
      index = row.each
      item  = Hash.new

      item["materials_glazing_id"]    = index.next
      item["description"]             = index.next
      item["per m2"]                  = index.next.to_f
      item["Embodied Carbon (A1-A5)"] = index.next.to_f
      item["Embodied Carbon (A-C)"]   = index.next.to_f
      item["Environmental Product Declaration (EPD)"] = index.next

      @carbon_database["glazing"] << item
    end

    carbon_frame = CSV.read(@cp.carbon_frame_path)
    @carbon_database["frame"] = Array.new

    1.upto carbon_frame.length - 1 do |i|
      row   = carbon_frame[i]
      index = row.each
      item  = Hash.new

      item["materials_glazing_id"]    = index.next
      item["description"]             = index.next
      item["per m2"]                  = index.next.to_f
      item["Embodied Carbon (A1-A5)"] = index.next.to_f
      item["Embodied Carbon (A-C)"]   = index.next.to_f
      item["Environmental Product Declaration (EPD)"] = index.next

      @carbon_database["frame"] << item
    end
  end

  def audit_embodied_carbon
    @attributes.surface_types.each do |surface_type|
      @carbon_report["#{surface_type.underscore}_area_m2"] = 0.0
      @carbon_report["#{surface_type.underscore}_carbon"]  = 0.0
    end

    @attributes.spaces.each do |space|
      @attributes.surface_types.each do |surface_type|
        space.surfaces_hash[surface_type].each do |surface|
          surface_area = surface.netArea * space.thermalZone.get.multiplier
          @carbon_report["#{surface_type.underscore}_area_m2"] = \
            (@carbon_report["#{surface_type.underscore}_area_m2"] + surface_area).round(2)

          # Get the carbon emissions for each material in the space.
          if surface.construction_hash.nil?
            emissions = 0.0
          else
            emissions = get_carbon_emissions(surface.construction_hash, surface, surface_area) 
            construction = surface.construction_hash
          end

          # Calculate the carbon emissions
          @carbon_report["#{surface_type.underscore}_carbon"] = \
            (@carbon_report["#{surface_type.underscore}_carbon"] + emissions).round(2)
        end
      end
    end

    # Get the total emissions from all the surface types.
    total_emissions = 0
    @attributes.surface_types.each do |surface_type|
      total_emissions += @carbon_report["#{surface_type.underscore}_carbon"]
    end

    @carbon_report["total"] = total_emissions
    return @carbon_report
  end

  # Retrieve the carbon emissions given a surface, its construction, and its area.
  def get_carbon_emissions(construction, surface, surface_area)
    total_emissions  = 0.0
    materials_file   = "materials_#{construction["type"]}"
    id_column        = materials_file + "_id"
    id_layers_column = "material_#{construction["type"]}_id_layers"

    construction[id_layers_column].split(',').each do |material_id|

      # Locate the material entry in the carbon database
      material_carbon = @carbon_database[construction["type"]].find { |row| 
        row[id_column] == material_id }["Embodied Carbon (A-C)"]

      if material_carbon.nil?
        raise("Error: Could not find material with ID #{material_id} in the carbon database.")
      end

      # If the material is glazing, the frame must be calculated by retrieving the perimeter of the window
      # and converting according to the correct attributes of the window.
      if construction["type"] == "glazing"
        fenestration_type = construction["fenestration_type"]

        # Skip skylights and doors since we don't have the data for them.
        # Only consider fixed and operable windows.
        if fenestration_type != "FixedWindow" and fenestration_type != "OperableWindow"
          puts "Fenestration type #{fenestration_type} is not defined for carbon calculation, skipping this component."
          next
        end

        material_frame = @carbon_database["frame"].find { |row|
          row[id_column] == material_id }["Embodied Carbon (A-C)"]

        # Get the materials_glazing entry from the costing database to access the number of panes the window has.
        material_costing = @costing_database["raw"][materials_file].find { |row| row[id_column] == material_id }

        if material_costing.nil?
          raise("Error: Could not find material with ID #{material_id} in the costing database.")
        end

        fenestration_number_of_panes = material_costing["fenestration_number_of_panes"]

        # Try to get the correct frame material. 
        frame_material = nil
        construction_component   = construction["component"].downcase
        construction_description = construction["description"].downcase
        ["vinyl-wood", "plastic", "aluminum"].each do |material|
          if material in construction_component
            frame_material = material
            break
          elsif material in construction_description
            frame_material = material
            break
          end
        end

        if frame_material.nil?
          raise("Error: Could not find frame material for glazing ID #{material_id} in constructions_glazing.csv.")
        end

        # Get the conversion factor for the window frame and add it to the total emissions.
        conversion_factor = @frame_m_to_kg[frame_material][fenestration_type][fenestration_number_of_panes] 
        perimeter = BTAP::Geometry::Surfaces.getSurfacePerimeterFromVertices(vertices: surface.vertices)
        total_emissions += material_frame * perimeter * conversion_factor
      end

      total_emissions += material_carbon * surface_area
    end

    return total_emissions
  end
end
