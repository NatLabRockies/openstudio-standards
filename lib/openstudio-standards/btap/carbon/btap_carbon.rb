# Calculates embodied carbon emissions currently accounting only for building
# envelopes.

class BTAPCarbon

  # @param attributes     [BTAP::Attributes]
  # @param standards_data [Hash] Required for window frame conversions.
  def initialize(attributes:, standards_data:)
    @carbon_database  = {}
    @costing_database = BTAPDatabase.instance
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
    total_emissions = 0

    @attributes.surface_types.each do |surface_type|
      @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"] = 0.0
      @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"]  = 0.0
    end

    @attributes.spaces.each do |space|
      @attributes.surface_types.each do |surface_type|
        space.surfaces_hash[surface_type].each do |surface|
          surface_area = surface.netArea * space.thermalZone.get.multiplier
          @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"] = \
            @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"] + surface_area

          # Get the carbon emissions for each material in the space.
          if surface.btap_construction_closest.nil?
            emissions = 0.0
          else

            # Note that the carbon tallying method must be called per-surface
            # to account for the perimeter values for each surface.
            emissions = get_carbon_emissions(surface.btap_construction_closest, surface.vertices, surface_area)
          end

          # Calculate the carbon emissions for the surface and append the result
          # to the total emissions.
          @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"] = \
            @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"] + emissions
          total_emissions += emissions
        end
        @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon_per_m2"] = (
          @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"] /
          @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"])

        if @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon_per_m2"].nan?
          @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon_per_m2"] = 0.0
        end
      end
    end
    # Get the total emissions from all the surface types.
    @attributes.surface_types.each do |surface_type|
      total_emissions += @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"]
    end

    # Add the embodied carbon tallied from TBD which tallies carbon emissions
    # of items that aren't explicitly modeled 
    structure_carbon = @attributes.model.getBuilding.additionalProperties.getFeatureAsDouble("co2_structure").get
    @carbon_report["structure_carbon"] = structure_carbon.round(2)
    total_emissions += structure_carbon

    # Factor in parapets likewise for costing in `envelope_costing.rb`.
    if @attributes.use_tbd
      wall_carbon_per_m2 = @costing_report["exterior_wall_carbon_per_m2"]
      parapet_carbon = @attributes.tbd_edge_tallies["parapet"].values.first * wall_carbon_per_m2
      @carbon_report["parapet_carbon"] = parapet_carbon.round(2)
      total_emissions += parapet_carbon
    end

    # Round everything at the end.
    @attributes.surface_types.each do |surface_type|
      @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"] = \
        @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon"].round(2)
      @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"] = \
        @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_area_m2"].round(2)
      @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon_per_m2"] = \
        @carbon_report["#{@attributes.surface_type_to_snake[surface_type]}_carbon_per_m2"].round(2)
    end

    puts "\nEmbodied carbon data successfully generated. Total embodied carbon emissions is " \
         "#{total_emissions.to_f.round(2)} kg/m^2"
    @carbon_report["total"] = total_emissions
    return @carbon_report
  end

  # Retrieve the carbon emissions given a surface, its construction, and its
  # area. Surface vertices are required to calculate the perimeter of window
  # frames.
  #
  # @param construction [Hash]
  # @param vertices     [Array[OpenStudio::Point3d]]
  # @param surface_area [Float]
  def get_carbon_emissions(construction, vertices, surface_area)
    total_emissions  = 0.0
    materials_file   = "materials_#{construction["type"]}"
    id_column        = materials_file + "_id"

    construction["id_layers"].each do |material_id|

      # Locate the material entry in the carbon database
      material_entry = @carbon_database[construction["type"]].find { |row|
        row[id_column] == material_id }

      if material_entry.nil?
        puts "Error: Could not find #{construction["type"]} material with ID #{material_id} in the carbon database. " \
             "Skipping."
        next
      end

      material_carbon = material_entry["Embodied Carbon (A-C)"]

      # If the material is glazing, the frame must be calculated by retrieving
      # the perimeter of the window and converting according to the correct
      # attributes of the window.
      if construction["type"] == "glazing"
        fenestration_type = construction["fenestration_type"]

        # Skip skylights and doors since we don't have the data for them.
        # Only consider fixed and operable windows.
        if fenestration_type != "FixedWindow" and fenestration_type != "OperableWindow"
          puts "Fenestration type #{fenestration_type} is not defined for carbon calculation, skipping this component."
          next
        end

        fenestration_number_of_panes = construction["fenestration_number_of_panes"]
        frame_material               = construction["frame_material"]

        material_frame = @carbon_database["frame"].find { |row|
          row[id_column] == material_id }["Embodied Carbon (A-C)"]

        # Get the materials_glazing entry from the costing database to access the number of panes the window has.
        material_costing = @costing_database["raw"][materials_file].find { |row| row[id_column] == material_id }

        if material_costing.nil?
          raise("Error: Could not find material with ID #{material_id} in the costing database.")
        end

        # Get the conversion factor for the window frame and add it to the total emissions.
        conversion_factor = @frame_m_to_kg[frame_material][fenestration_type][fenestration_number_of_panes]
        perimeter = BTAP::Geometry::Surfaces.getSurfacePerimeterFromVertices(vertices: vertices)
        total_emissions += material_frame * perimeter * conversion_factor
      end

      total_emissions += material_carbon * surface_area
    end

    return total_emissions
  end
end
