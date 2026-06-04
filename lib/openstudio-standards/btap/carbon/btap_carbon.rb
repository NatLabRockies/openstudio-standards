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
  end

  def audit_embodied_carbon
    total_emissions = 0

    @attributes.surface_types.each do |surface_type|
      @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] = 0.0
      @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"]  = 0.0
    end

    # Calculate emissions for all constructions found by BTAP Attributes.
    @attributes.get_constructions.each do |construction|
      construction["carbon"] = emissions_from_construction(construction)
    end

    @attributes.spaces.each do |space|
      @attributes.surface_types.each do |surface_type|
        space.surfaces_hash[surface_type].each do |surface|
          if surface.btap_constructions.nil?
            next
          end

          surface_area = surface.netArea * space.thermalZone.get.multiplier
          @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] = \
            @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] + surface_area

          surface_is_glazing = surface.btap_constructions.first["type"] == "glazing"

          # Factor in window frame emissions if this is a glazing construction.
          if surface_is_glazing
            perimeter          = BTAP::Geometry::Surfaces.getSurfacePerimeterFromVertices(vertices: surface.vertices)
            carbon_range_array = surface.btap_constructions.map { |construction|
              [construction["rsi"], construction["carbon"] + emissions_from_window_frame(construction, perimeter)] }
          else
            carbon_range_array = surface.btap_constructions.map { |construction|
              [construction["rsi"], construction["carbon"]] }
          end

          emissions, _ = BTAP::LinearRegression.interpolate(x_y_array: carbon_range_array, x2: surface.rsi)

          # Calculate the carbon emissions for the surface and append the result
          # to the total emissions.
          @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"] = \
            @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"] + emissions
          total_emissions += emissions * surface_area
        end
        @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon_per_m2"] = (
          @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"] /
          @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"])

        if @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon_per_m2"].nan?
          @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon_per_m2"] = 0.0
        end
      end
    end

    # Get the total emissions from all the surface types.
    @attributes.surface_types.each do |surface_type|
      total_emissions += @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"]
    end

    # Add the embodied carbon tallied from TBD which tallies carbon emissions
    # of items that aren't explicitly modeled
    structure_carbon = @attributes.model.getBuilding.additionalProperties.getFeatureAsDouble("co2_structure").get
    @carbon_report["structure_carbon"] = structure_carbon.round(2)
    total_emissions += structure_carbon

    # Factor in parapets likewise for costing in `envelope_costing.rb`.
    if @attributes.use_tbd
      wall_carbon_per_m2 = @carbon_report["exterior_wall_carbon_per_m2"]
      parapet_carbon = @attributes.tbd_edge_tallies["parapet"].values.first * wall_carbon_per_m2
      @carbon_report["parapet_carbon"] = parapet_carbon.round(2)
      total_emissions += parapet_carbon
    end

    puts "Warning: Interpolation limits exceeded." if BTAP::LinearRegression.extrapolation_boundaries_exceeded?

    # Round everything at the end.
    @attributes.surface_types.each do |surface_type|
      @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"] = \
        @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon"].round(2)
      @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"] = \
        @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_area_m2"].round(2)
      @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon_per_m2"] = \
        @carbon_report["#{@attributes.surface_types_to_snake[surface_type]}_carbon_per_m2"].round(2)
    end

    puts "\nEmbodied carbon data successfully generated. Total embodied carbon emissions is " \
         "#{total_emissions.to_f.round(2)} kg/m^2"
    @carbon_report["total"] = total_emissions
    return @carbon_report
  end

  # Retrieve the carbon emissions given a construction.
  #
  # @param construction [Hash]
  # @param vertices     [Array[OpenStudio::Point3d]]
  # @param surface_area [Float]
  # @return [Float]
  def emissions_from_construction(construction)
    total_emissions  = 0.0
    materials_file   = "materials_#{construction["type"]}"
    id_column        = materials_file + "_id"

    construction["id_layers"].each do |material_id|
      material_entry = get_material_entry(material_id, id_column, construction["type"])
      next if material_entry.nil?
      material_emissions  = material_entry["Embodied Carbon (A-C)"]
      total_emissions += material_emissions
    end

    return total_emissions
  end

  # Retrieve the carbon emissions for window frames. This requires its surface,
  # its construction, and its perimeter.
  #
  # @param construction [Hash]
  # @param Perimeter    [Float]
  # @return [Float]
  def emissions_from_window_frame(construction, perimeter)
    materials_file    = "frame"
    fenestration_type = construction["fenestration_type"]

    # Skip skylights and doors since we don't have the data for them.
    # Only consider fixed and operable windows.
    if fenestration_type != "FixedWindow" and fenestration_type != "OperableWindow"
      puts "Warning: #{construction["name"]} is not available for carbon calculation, returning zero."
      return 0.0
    end

    frame_emissions              = 0.0
    frame_material               = construction["frame_material"]
    fenestration_number_of_panes = construction["fenestration_number_of_panes"]

    construction["id_layers"].each do |material_id|
      material_entry = get_material_entry(material_id, "materials_glazing_id", construction["type"])
      next if material_entry.nil?
      frame_emissions += material_entry["Embodied Carbon (A-C)"]
    end

    # Get the conversion factor for the window frame and add it to the total emissions.
    conversion_factor = @frame_m_to_kg[frame_material][fenestration_type][fenestration_number_of_panes]
    return frame_emissions * perimeter * conversion_factor
  end

  # Get a material entry from the carbon database.
  #
  # @param type [String] Name of the hash key.
  def get_material_entry(id, id_column, materials_file)
    material_entry = @carbon_database[materials_file].find { |row|
      row[id_column] == id }

    if material_entry.nil?
      # TODO: This will happen a lot because of the new thermal bridging entries
      # as of nrcan_476. The carbon database needs to be updated. BTAP Carbon
      # will not be very useful until then.
      puts "Error: Could not find #{materials_file} material with ID #{id} in the carbon database. " \
           "Skipping."
    end

    return material_entry
  end
end
