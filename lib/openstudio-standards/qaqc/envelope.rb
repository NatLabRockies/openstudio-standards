# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Envelope

    # Check the envelope conductance against a standard
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param min_pass_pct [Double] threshold for throwing an error for percent difference
    # @param max_pass_pct [Double] threshold for throwing an error for percent difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    # @todo unique tolerance ranges for conductance, reflectance, and shgc
    def self.check_envelope_conductance(category, target_standard, min_pass_pct: 0.2, max_pass_pct: 0.2, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Envelope R-Value')
      check_elems << OpenStudio::Attribute.new('category', category)
      if target_standard == 'ICC IECC 2015'
        dislay_standard = target_standard
        check_elems << OpenStudio::Attribute.new('description', "Check envelope against Table R402.1.2 and R402.1.4 in #{dislay_standard} Residential Provisions.")
      elsif target_standard.include?('90.1-2013')
        display_standard = "ASHRAE #{target_standard}"
        check_elems << OpenStudio::Attribute.new('description', "Check envelope against #{display_standard} Table 5.5.2, Table G2.1.5 b,c,d,e, Section 5.5.3.1.1a. Roof reflectance of 55%, wall reflectance of 30%.")
      else
        # @todo could add more elsifs if want to dsiplay tables and sections for additional 90.1 standards
        if target_standard.include?('90.1')
          display_standard = "ASHRAE #{target_standard}"
        else
          display_standard = target_standard
        end
        check_elems << OpenStudio::Attribute.new('description', "Check envelope against #{display_standard}. Roof reflectance of 55%, wall reflectance of 30%.")
      end

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = check_elems.map(&:valueAsString)
        return results
      end

      std = Standard.build(target_standard)

      # list of surface types to identify for each space type for surfaces and sub-surfaces
      construction_type_array = []
      construction_type_array << ['ExteriorWall', 'SteelFramed']
      construction_type_array << ['ExteriorRoof', 'IEAD']
      construction_type_array << ['ExteriorFloor', 'Mass']
      construction_type_array << ['ExteriorDoor', 'Swinging']
      construction_type_array << ['ExteriorWindow', 'Metal framing (all other)']
      construction_type_array << ['Skylight', 'Glass with Curb']
      # overhead door doesn't show in list, or glass door

      begin
        # loop through all space types used in the model
        @model.getSpaceTypes.sort.each do |space_type|
          next if space_type.floorArea <= 0

          space_type_const_properties = {}
          construction_type_array.each do |const_type|
            # gather data for exterior wall
            intended_surface_type = const_type[0]
            standards_construction_type = const_type[1]
            space_type_const_properties[intended_surface_type] = {}
            data = std.space_type_get_construction_properties(space_type, intended_surface_type, standards_construction_type)
            if data.nil?
              puts "lookup for #{target_standard},#{intended_surface_type},#{standards_construction_type}"
              check_elems << OpenStudio::Attribute.new('flag', "Didn't find construction for #{standards_construction_type} #{intended_surface_type} for #{space_type.name}.")
            elsif ['ExteriorWall', 'ExteriorFloor', 'ExteriorDoor'].include? intended_surface_type
              space_type_const_properties[intended_surface_type]['u_value'] = data['assembly_maximum_u_value']
              space_type_const_properties[intended_surface_type]['reflectance'] = 0.30 # hard coded value
            elsif intended_surface_type == 'ExteriorRoof'
              space_type_const_properties[intended_surface_type]['u_value'] = data['assembly_maximum_u_value']
              space_type_const_properties[intended_surface_type]['reflectance'] = 0.55 # hard coded value
            else
              space_type_const_properties[intended_surface_type]['u_value'] = data['assembly_maximum_u_value']
              space_type_const_properties[intended_surface_type]['shgc'] = data['assembly_maximum_solar_heat_gain_coefficient']
            end
          end

          # make array of construction details for surfaces
          surface_details = []
          missing_surface_constructions = []
          sub_surface_details = []
          missing_sub_surface_constructions = []

          # loop through spaces
          space_type.spaces.each do |space|
            space.surfaces.each do |surface|
              next if surface.outsideBoundaryCondition != 'Outdoors'

              if surface.construction.is_initialized
                surface_details << { boundary_condition: surface.outsideBoundaryCondition, surface_type: surface.surfaceType, construction: surface.construction.get }
              else
                missing_surface_constructions << surface.name.get
              end

              # make array of construction details for sub_surfaces
              surface.subSurfaces.each do |sub_surface|
                if sub_surface.construction.is_initialized
                  sub_surface_details << { boundary_condition: sub_surface.outsideBoundaryCondition, surface_type: sub_surface.subSurfaceType, construction: sub_surface.construction.get }
                else
                  missing_sub_surface_constructions << sub_surface.name.get
                end
              end
            end
          end

          if !missing_surface_constructions.empty?
            check_elems << OpenStudio::Attribute.new('flag', "#{missing_surface_constructions.size} surfaces are missing constructions in #{space_type.name}. Spaces and can't be checked.")
          end

          if !missing_sub_surface_constructions.empty?
            check_elems << OpenStudio::Attribute.new('flag', "#{missing_sub_surface_constructions.size} sub surfaces are missing constructions in #{space_type.name}. Spaces and can't be checked.")
          end

          # gather target values for this space type
          # @todo address support for other surface types e.g. overhead door glass door
          target_r_value_ip = {}
          target_reflectance = {}
          target_u_value_ip = {}
          target_shgc = {}
          target_r_value_ip['Wall'] = 1.0 / space_type_const_properties['ExteriorWall']['u_value'].to_f
          target_reflectance['Wall'] = space_type_const_properties['ExteriorWall']['reflectance'].to_f
          target_r_value_ip['RoofCeiling'] = 1.0 / space_type_const_properties['ExteriorRoof']['u_value'].to_f
          target_reflectance['RoofCeiling'] = space_type_const_properties['ExteriorRoof']['reflectance'].to_f
          target_r_value_ip['Floor'] = 1.0 / space_type_const_properties['ExteriorFloor']['u_value'].to_f
          target_reflectance['Floor'] = space_type_const_properties['ExteriorFloor']['reflectance'].to_f
          target_r_value_ip['Door'] = 1.0 / space_type_const_properties['ExteriorDoor']['u_value'].to_f
          target_reflectance['Door'] = space_type_const_properties['ExteriorDoor']['reflectance'].to_f
          target_u_value_ip['FixedWindow'] = space_type_const_properties['ExteriorWindow']['u_value'].to_f
          target_shgc['FixedWindow'] = space_type_const_properties['ExteriorWindow']['shgc'].to_f
          target_u_value_ip['OperableWindow'] = space_type_const_properties['ExteriorWindow']['u_value'].to_f
          target_shgc['OperableWindow'] = space_type_const_properties['ExteriorWindow']['shgc'].to_f
          target_u_value_ip['Skylight'] = space_type_const_properties['Skylight']['u_value'].to_f
          target_shgc['Skylight'] = space_type_const_properties['Skylight']['shgc'].to_f

          # loop through unique construction array combinations
          surface_details.uniq.each do |surface_detail|
            if surface_detail[:construction].thermalConductance.is_initialized

              # don't use intended surface type of construction, look map based on surface type and boundary condition
              boundary_condition = surface_detail[:boundary_condition]
              surface_type = surface_detail[:surface_type]
              intended_surface_type = ''
              if boundary_condition.to_s == 'Outdoors'
                case surface_type.to_s
                when 'Wall'
                  intended_surface_type = 'ExteriorWall'
                when 'RoofCeiling'
                  intended_surface_type = 'ExteriorRoof'
                when 'Floor'
                  intended_surface_type = 'ExteriorFloor'
                end
              end
              film_coefficients_r_value = OpenstudioStandards::Constructions.film_coefficients_r_value(intended_surface_type, includes_int_film = true, includes_ext_film = true)
              thermal_conductance = surface_detail[:construction].thermalConductance.get
              r_value_with_film = (1 / thermal_conductance) + film_coefficients_r_value
              source_units = 'm^2*K/W'
              target_units = 'ft^2*h*R/Btu'
              r_value_ip = OpenStudio.convert(r_value_with_film, source_units, target_units).get
              solar_reflectance = surface_detail[:construction].to_LayeredConstruction.get.layers[0].to_OpaqueMaterial.get.solarReflectance.get
              # @todo check with exterior air wall

              # stop if didn't find values (0 or infinity)
              next if target_r_value_ip[surface_detail[:surface_type]] < 0.01
              next if target_r_value_ip[surface_detail[:surface_type]] == Float::INFINITY

              # check r avlues
              if r_value_ip < target_r_value_ip[surface_detail[:surface_type]] * (1.0 - min_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_r_value_ip[surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
              elsif r_value_ip > target_r_value_ip[surface_detail[:surface_type]] * (1.0 + max_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_r_value_ip[surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
              end

              # check solar reflectance
              if (solar_reflectance < target_reflectance[surface_detail[:surface_type]] * (1.0 - min_pass_pct)) && (target_standard != 'ICC IECC 2015')
                check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{(target_reflectance[surface_detail[:surface_type]] * 100).round} %.")
              elsif (solar_reflectance > target_reflectance[surface_detail[:surface_type]] * (1.0 + max_pass_pct)) && (target_standard != 'ICC IECC 2015')
                check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{(target_reflectance[surface_detail[:surface_type]] * 100).round} %.")
              end

            else
              check_elems << OpenStudio::Attribute.new('flag', "Can't calculate R value for #{surface_detail[:construction].name}.")
            end
          end

          # loop through unique construction array combinations
          sub_surface_details.uniq.each do |sub_surface_detail|
            if sub_surface_detail[:surface_type] == 'FixedWindow' || sub_surface_detail[:surface_type] == 'OperableWindow' || sub_surface_detail[:surface_type] == 'Skylight'
              # check for non opaque sub surfaces
              source_units = 'W/m^2*K'
              target_units = 'Btu/ft^2*h*R'
              surface_construction = sub_surface_detail[:construction].to_LayeredConstruction.get
              u_factor_si = OpenstudioStandards::Constructions.construction_get_conductance(surface_construction)
              u_factor_ip = OpenStudio.convert(u_factor_si, source_units, target_units).get
              shgc = OpenstudioStandards::Constructions.construction_get_solar_transmittance(surface_construction)

              # stop if didn't find values (0 or infinity)
              next if target_u_value_ip[sub_surface_detail[:surface_type]] < 0.01
              next if target_u_value_ip[sub_surface_detail[:surface_type]] == Float::INFINITY

              # check u avlues
              if u_factor_ip < target_u_value_ip[sub_surface_detail[:surface_type]] * (1.0 - min_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "U value of #{u_factor_ip.round(2)} (#{target_units}) for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_u_value_ip[sub_surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
              elsif u_factor_ip > target_u_value_ip[sub_surface_detail[:surface_type]] * (1.0 + max_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "U value of #{u_factor_ip.round(2)} (#{target_units}) for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_u_value_ip[sub_surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
              end

              # check shgc
              if shgc < target_shgc[sub_surface_detail[:surface_type]] * (1.0 - min_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "SHGC of #{shgc.round(2)} % for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_shgc[sub_surface_detail[:surface_type]].round(2)} %.")
              elsif shgc > target_shgc[sub_surface_detail[:surface_type]] * (1.0 + max_pass_pct)
                check_elems << OpenStudio::Attribute.new('flag', "SHGC of #{shgc.round(2)} % for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_shgc[sub_surface_detail[:surface_type]].round(2)} %.")
              end

            else
              # check for opaque sub surfaces
              if sub_surface_detail[:construction].thermalConductance.is_initialized

                # don't use intended surface type of construction, look map based on surface type and boundary condition
                boundary_condition = sub_surface_detail[:boundary_condition]
                surface_type = sub_surface_detail[:surface_type]
                intended_surface_type = ''
                if boundary_condition.to_s == 'Outdoors' && surface_type.to_s == 'Door'
                  # @todo add additional intended surface types
                  intended_surface_type = 'ExteriorDoor'
                end
                film_coefficients_r_value = OpenstudioStandards::Constructions.film_coefficients_r_value(intended_surface_type, includes_int_film = true, includes_ext_film = true)

                thermal_conductance = sub_surface_detail[:construction].thermalConductance.get
                r_value_with_film = (1 / thermal_conductance) + film_coefficients_r_value
                source_units = 'm^2*K/W'
                target_units = 'ft^2*h*R/Btu'
                r_value_ip = OpenStudio.convert(r_value_with_film, source_units, target_units).get
                solar_reflectance = sub_surface_detail[:construction].to_LayeredConstruction.get.layers[0].to_OpaqueMaterial.get.solarReflectance.get
                # @todo check what happens with exterior air wall

                # stop if didn't find values (0 or infinity)
                next if target_r_value_ip[sub_surface_detail[:surface_type]] < 0.01
                next if target_r_value_ip[sub_surface_detail[:surface_type]] == Float::INFINITY

                # check r avlues
                if r_value_ip < target_r_value_ip[sub_surface_detail[:surface_type]] * (1.0 - min_pass_pct)
                  check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{target_r_value_ip[sub_surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
                elsif r_value_ip > target_r_value_ip[sub_surface_detail[:surface_type]] * (1.0 + max_pass_pct)
                  check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{target_r_value_ip[sub_surface_detail[:surface_type]].round(2)} (#{target_units}) for #{display_standard}.")
                end

                # check solar reflectance
                if (solar_reflectance < target_reflectance[sub_surface_detail[:surface_type]] * (1.0 - min_pass_pct)) && (target_standard != 'ICC IECC 2015')
                  check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{min_pass_pct * 100} % below the expected value of #{(target_reflectance[sub_surface_detail[:surface_type]] * 100).round} %.")
                elsif (solar_reflectance > target_reflectance[sub_surface_detail[:surface_type]] * (1.0 + max_pass_pct)) && (target_standard != 'ICC IECC 2015')
                  check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{sub_surface_detail[:construction].name} in #{space_type.name} is more than #{max_pass_pct * 100} % above the expected value of #{(target_reflectance[sub_surface_detail[:surface_type]] * 100).round} %.")
                end

              else
                check_elems << OpenStudio::Attribute.new('flag', "Can't calculate R value for #{sub_surface_detail[:construction].name}.")
              end

            end
          end
        end

        # check spaces without space types against Nonresidential for this climate zone
        @model.getSpaces.sort.each do |space|
          unless space.spaceType.is_initialized

            # make array of construction details for surfaces
            surface_details = []
            missing_surface_constructions = []
            sub_surface_details = []
            missing_sub_surface_constructions = []

            space.surfaces.each do |surface|
              next if surface.outsideBoundaryCondition != 'Outdoors'

              if surface.construction.is_initialized
                surface_details << { boundary_condition: surface.outsideBoundaryCondition, surface_type: surface.surfaceType, construction: surface.construction.get }
              else
                missing_surface_constructions << surface.name.get
              end

              # make array of construction details for sub_surfaces
              surface.subSurfaces.each do |sub_surface|
                if sub_surface.construction.is_initialized
                  sub_surface_details << { boundary_condition: sub_surface.outsideBoundaryCondition, surface_type: sub_surface.subSurfaceType, construction: sub_surface.construction.get }
                else
                  missing_sub_surface_constructions << sub_surface.name.get
                end
              end
            end

            unless missing_surface_constructions.empty?
              check_elems << OpenStudio::Attribute.new('flag', "#{missing_surface_constructions.size} surfaces are missing constructions in #{space_type.name}. Spaces and can't be checked.")
            end

            unless missing_sub_surface_constructions.empty?
              check_elems << OpenStudio::Attribute.new('flag', "#{missing_sub_surface_constructions.size} sub surfaces are missing constructions in #{space_type.name}. Spaces and can't be checked.")
            end

            surface_details.uniq.each do |surface_detail|
              if surface_detail[:construction].thermalConductance.is_initialized
                # don't use intended surface type of construction, look map based on surface type and boundary condition
                boundary_condition = surface_detail[:boundary_condition]
                surface_type = surface_detail[:surface_type]
                intended_surface_type = ''
                if boundary_condition.to_s == 'Outdoors'
                  case surface_type.to_s
                  when 'Wall'
                    intended_surface_type = 'ExteriorWall'
                    standards_construction_type = 'SteelFramed'
                  when 'RoofCeiling'
                    intended_surface_type = 'ExteriorRoof'
                    standards_construction_type = 'IEAD'
                  when 'Floor'
                    intended_surface_type = 'ExteriorFloor'
                    standards_construction_type = 'Mass'
                  end
                end
                film_coefficients_r_value = OpenstudioStandards::Constructions.film_coefficients_r_value(intended_surface_type, includes_int_film = true, includes_ext_film = true)
                thermal_conductance = surface_detail[:construction].thermalConductance.get
                r_value_with_film = (1 / thermal_conductance) + film_coefficients_r_value
                source_units = 'm^2*K/W'
                target_units = 'ft^2*h*R/Btu'
                r_value_ip = OpenStudio.convert(r_value_with_film, source_units, target_units).get
                solar_reflectance = surface_detail[:construction].to_LayeredConstruction.get.layers[0].to_OpaqueMaterial.get.solarReflectance.get
                # @todo check what happens with exterior air wall

                # calculate target_r_value_ip
                target_reflectance = nil
                data = std.model_get_construction_properties(@model, intended_surface_type, standards_construction_type)

                if data.nil?
                  check_elems << OpenStudio::Attribute.new('flag', "Didn't find construction for #{standards_construction_type} #{intended_surface_type} for #{space.name}.")
                  next
                elsif ['ExteriorWall', 'ExteriorFloor', 'ExteriorDoor'].include? intended_surface_type
                  assembly_maximum_u_value = data['assembly_maximum_u_value']
                  target_reflectance = 0.30
                elsif intended_surface_type == 'ExteriorRoof'
                  assembly_maximum_u_value = data['assembly_maximum_u_value']
                  target_reflectance = 0.55
                else
                  assembly_maximum_u_value = data['assembly_maximum_u_value']
                  assembly_maximum_solar_heat_gain_coefficient = data['assembly_maximum_solar_heat_gain_coefficient']
                end
                assembly_maximum_r_value_ip = 1 / assembly_maximum_u_value

                # stop if didn't find values (0 or infinity)
                next if assembly_maximum_r_value_ip < 0.01
                next if assembly_maximum_r_value_ip == Float::INFINITY

                # check r avlues
                if r_value_ip < assembly_maximum_r_value_ip * (1.0 - min_pass_pct)
                  check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{surface_detail[:construction].name} in #{space.name} is more than #{min_pass_pct * 100} % below the expected value of #{assembly_maximum_r_value_ip.round(2)} (#{target_units}) for #{display_standard}.")
                elsif r_value_ip > assembly_maximum_r_value_ip * (1.0 + max_pass_pct)
                  check_elems << OpenStudio::Attribute.new('flag', "R value of #{r_value_ip.round(2)} (#{target_units}) for #{surface_detail[:construction].name} in #{space.name} is more than #{max_pass_pct * 100} % above the expected value of #{assembly_maximum_r_value_ip.round(2)} (#{target_units}) for #{display_standard}.")
                end

                # check solar reflectance
                if (solar_reflectance < target_reflectance * (1.0 - min_pass_pct)) && (target_standard != 'ICC IECC 2015')
                  check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{surface_detail[:construction].name} in #{space.name} is more than #{min_pass_pct * 100} % below the expected value of #{(target_reflectance * 100).round} %.")
                elsif (solar_reflectance > target_reflectance * (1.0 + max_pass_pct)) && (target_standard != 'ICC IECC 2015')
                  check_elems << OpenStudio::Attribute.new('flag', "Solar Reflectance of #{(solar_reflectance * 100).round} % for #{surface_detail[:construction].name} in #{space.name} is more than #{max_pass_pct * 100} % above the expected value of #{(target_reflectance * 100).round} %.")
                end
              else
                check_elems << OpenStudio::Attribute.new('flag', "Can't calculate R value for #{surface_detail[:construction].name}.")
              end
            end

            sub_surface_details.uniq.each do |sub_surface_detail|
              # @todo update this so it works for doors and windows
              check_elems << OpenStudio::Attribute.new('flag', "Not setup to check sub-surfaces of spaces without space types. Can't check properties for #{sub_surface_detail[:construction].name}.")
            end

          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end
  end
end
