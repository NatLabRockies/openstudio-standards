class Standard
  # Create a construction from the openstudio standards dataset.
  # If construction_props are specified, modifies the insulation layer accordingly.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param construction_name [String] name of the construction
  # @param construction_props [Hash] hash of construction properties
  # @return [OpenStudio::Model::Construction] construction object
  # @todo make return an OptionalConstruction
  def model_add_construction(model, construction_name, construction_props = nil, surface = nil)
    intended_surface_type = construction_props&.[]('intended_surface_type') || ''

    # First check model and return construction if it already exists
    model.getConstructions.sort.each do |construction|
      if construction.name.get.to_s == construction_name
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added construction: #{construction_name}")
        valid = true
        if !surface.nil?
          if intended_surface_type == 'GroundContactFloor' && construction.iddObjectType.valueName != 'OS_Construction_FfactorGroundFloor'
            valid = false
          elsif intended_surface_type == 'GroundContactWall' && construction.iddObjectType.valueName != 'OS_Construction_CfactorUndergroundWall'
            valid = false
          end
        end
        if valid
          return construction
        end
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Already added construction: '#{construction_name}' but its type '#{construction.iddObjectType.valueName}' is not valid for the intended surface type '#{intended_surface_type}'. A new construction will be created.")
      end
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Adding construction: #{construction_name}")

    # Get the object data
    if standards_data.keys.include?('prm_constructions')
      data = model_find_object(standards_data['prm_constructions'], 'name' => construction_name)
    else
      data = model_find_object(standards_data['constructions'], 'name' => construction_name)
    end

    unless data
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find data for construction: #{construction_name}, will not be created.")
      return OpenStudio::Model::OptionalConstruction.new
    end

    intended_surface_type = data["intended_surface_type"]
    intended_surface_type ||= ''

    # Make a new construction and set the standards details
    is_layered_construction = true

    if intended_surface_type == 'GroundContactFloor' && !surface.nil?
      if construction_props
        construction = OpenStudio::Model::FFactorGroundFloorConstruction.new(model)
        is_layered_construction = false
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Construction properties not specified for '#{construction_name}', cannot create F-Factor Ground Floor Construction.  A regular construction will be created instead, and Surface '#{surface.name}' will be set to use the 'Ground' outside boundary condition (previously '#{surface.outsideBoundaryCondition}').")
        surface.setOutsideBoundaryCondition('Ground')
      end
    elsif intended_surface_type == 'GroundContactWall' && !surface.nil?
      if construction_props
        construction = OpenStudio::Model::CFactorUndergroundWallConstruction.new(model)
        is_layered_construction = false
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Construction properties not specified for '#{construction_name}', cannot create C-Factor Underground Wall Construction.  A regular construction will be created instead, and Surface '#{surface.name}' will be set to use the 'Ground' outside boundary condition (previously '#{surface.outsideBoundaryCondition}').")
        surface.setOutsideBoundaryCondition('Ground')
      end
    end

    if is_layered_construction
      construction = OpenStudio::Model::Construction.new(model)
      # Add the material layers to the construction
      layers = OpenStudio::Model::MaterialVector.new
      data['materials'].each do |material_name|
        material = model_add_material(model, material_name)
        if material
          layers << material
        end
      end
      construction.setLayers(layers)
    end
    construction.setName(construction_name)
    standards_info = construction.standardsInformation

    standards_info.setIntendedSurfaceType(intended_surface_type)

    standards_construction_type = data['standards_construction_type']
    standards_construction_type ||= ''
    standards_info.setStandardsConstructionType(standards_construction_type)

    # @todo could put construction rendering color in the spreadsheet

    # Modify the R value of the insulation to hit the specified U-value, C-Factor, or F-Factor.
    # Doesn't currently operate on glazing constructions
    if construction_props
      # Determine the target U-value, C-factor, and F-factor
      target_u_value_ip = construction_props['assembly_maximum_u_value']
      target_f_factor_ip = construction_props['assembly_maximum_f_factor']
      target_c_factor_ip = construction_props['assembly_maximum_c_factor']
      target_shgc = construction_props['assembly_maximum_solar_heat_gain_coefficient']
      u_includes_int_film = construction_props['u_value_includes_interior_film_coefficient']
      u_includes_ext_film = construction_props['u_value_includes_exterior_film_coefficient']

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "#{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")

      if target_u_value_ip

        # Handle Opaque and Fenestration Constructions differently
        # if construction.isFenestration && OpenstudioStandards::Constructions.construction_simple_glazing?(construction)
        if construction.isFenestration
          if OpenstudioStandards::Constructions.construction_simple_glazing?(construction)
            # Set the U-Value and SHGC
            OpenstudioStandards::Constructions.construction_set_glazing_u_value(construction, target_u_value_ip.to_f,
                                                                                target_includes_interior_film_coefficients: u_includes_int_film,
                                                                                target_includes_exterior_film_coefficients: u_includes_ext_film)
            simple_glazing = construction.layers.first.to_SimpleGlazing
            unless simple_glazing.is_initialized && !target_shgc.nil?
              simple_glazing.get.setSolarHeatGainCoefficient(target_shgc.to_f)
            end
          else # if !data['intended_surface_type'] == 'ExteriorWindow' && !data['intended_surface_type'] == 'Skylight'
            # Set the U-Value
            OpenstudioStandards::Constructions.construction_set_u_value(construction, target_u_value_ip.to_f,
                                                                        insulation_layer_name: data['insulation_layer'],
                                                                        intended_surface_type: data['intended_surface_type'],
                                                                        target_includes_interior_film_coefficients: u_includes_int_film,
                                                                        target_includes_exterior_film_coefficients: u_includes_ext_film)
            # else
            # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Not modifying U-value for #{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")
          end
        else
          # Set the U-Value
          OpenstudioStandards::Constructions.construction_set_u_value(construction, target_u_value_ip.to_f,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
          # else
          # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Not modifying U-value for #{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")
        end

      elsif target_f_factor_ip && data['intended_surface_type'] == 'GroundContactFloor'
        # F-factor objects are unique to each surface, so a surface needs to be passed
        # If not surface is passed, use the older approach to model ground contact floors
        if surface.nil?
          # Set the F-Factor (only applies to slabs on grade)
          # @todo figure out what the prototype buildings did about ground heat transfer
          # OpenstudioStandards::Constructions.construction_set_slab_f_factor(construction, target_f_factor_ip.to_f, insulation_layer_name: data['insulation_layer'])
          OpenstudioStandards::Constructions.construction_set_u_value(construction, 0.0,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
        else
          # create a new construction for the specific surface
          construction = OpenstudioStandards::Constructions.construction_deep_copy(construction)
          OpenstudioStandards::Constructions.construction_set_surface_slab_f_factor(construction, target_f_factor_ip, surface)
        end
      elsif target_c_factor_ip && (data['intended_surface_type'] == 'GroundContactWall' || data['intended_surface_type'] == 'GroundContactRoof')
        # C-factor objects are unique to each surface, so a surface needs to be passed
        # If not surface is passed, use the older approach to model ground contact walls
        if surface.nil?
          # Set the C-Factor (only applies to underground walls)
          # @todo figure out what the prototype buildings did about ground heat transfer
          # OpenstudioStandards::Constructions.construction_set_underground_wall_c_factor(construction, target_c_factor_ip.to_f, insulation_layer_name: data['insulation_layer'])
          OpenstudioStandards::Constructions.construction_set_u_value(construction, 0.0,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
        else
          # create a new construction for the specific surface
          construction = OpenstudioStandards::Constructions.construction_deep_copy(construction)
          OpenstudioStandards::Constructions.construction_set_surface_underground_wall_c_factor(construction, target_c_factor_ip, surface)
        end
      end

      # If the construction is fenestration,
      # also set the frame type for use in future lookups
      if construction.isFenestration
        case standards_construction_type
        when 'Metal framing (all other)'
          standards_info.setFenestrationFrameType('Metal Framing')
        when 'Nonmetal framing (all)'
          standards_info.setFenestrationFrameType('Non-Metal Framing')
        end
      end

      # If the construction has a skylight framing material specified,
      # get the skylight frame material properties and add frame to
      # all skylights in the model.
      if data['skylight_framing']
        # Get the skylight framing material
        framing_name = data['skylight_framing']
        frame_data = model_find_object(standards_data['materials'], 'name' => framing_name)
        if frame_data
          frame_width_in = frame_data['frame_width'].to_f
          frame_with_m = OpenStudio.convert(frame_width_in, 'in', 'm').get
          frame_resistance_ip = frame_data['resistance'].to_f
          frame_resistance_si = OpenStudio.convert(frame_resistance_ip, 'hr*ft^2*R/Btu', 'm^2*K/W').get
          frame_conductance_si = 1.0 / frame_resistance_si
          frame = OpenStudio::Model::WindowPropertyFrameAndDivider.new(model)
          frame.setName("Skylight frame R-#{frame_resistance_ip.round(2)} #{frame_width_in.round(1)} in. wide")
          frame.setFrameWidth(frame_with_m)
          frame.setFrameConductance(frame_conductance_si)
          skylights_frame_added = 0
          model.getSubSurfaces.each do |sub_surface|
            next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && sub_surface.subSurfaceType == 'Skylight'

            if model.version < OpenStudio::VersionString.new('3.1.0')
              # window frame setting before https://github.com/NREL/OpenStudio/issues/2895 was fixed
              sub_surface.setString(8, frame.name.get.to_s)
              skylights_frame_added += 1
            else
              if sub_surface.allowWindowPropertyFrameAndDivider
                sub_surface.setWindowPropertyFrameAndDivider(frame)
                skylights_frame_added += 1
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "For #{sub_surface.name}: cannot add a frame to this skylight.")
              end
            end
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding #{frame.name} to #{skylights_frame_added} skylights.") if skylights_frame_added > 0
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find skylight framing data for: #{framing_name}, will not be created.")
          return false
          # @todo change to return empty optional material
        end
      end

    end
    #     # Check if the construction with the modified name was already in the model.
    #     # If it was, delete this new construction and return the copy already in the model.
    #     m = construction.name.get.to_s.match(/\s(\d+)/)
    #     if m
    #       revised_cons_name = construction.name.get.to_s.gsub(/\s\d+/,'')
    #       model.getConstructions.sort.each do |exist_construction|
    #         if exist_construction.name.get.to_s == revised_cons_name
    #           OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added construction: #{construction_name}")
    #           # Remove the recently added construction
    #           lyrs = construction.layers
    #           # Erase the layers in the construction
    #           construction.setLayers([])
    #           # Delete unused materials
    #           lyrs.uniq.each do |lyr|
    #             if lyr.directUseCount.zero?
    #               OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Removing Material: #{lyr.name}")
    #               lyr.remove
    #             end
    #           end
    #           construction.remove # Remove the construction
    #           return exist_construction
    #         end
    #       end
    #     end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding construction #{construction.name}.")

    return construction
  end
end
