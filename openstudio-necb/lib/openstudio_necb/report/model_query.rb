module OpenStudioNECB
  module Report
    # SDK -> plain hashes. With report.rb (which drives the openstudio-hvac
    # diagram engine), this is one of the only TWO renderer files that touch
    # the OpenStudio SDK; every other module (charts, sections, checklist) is
    # SDK-free and unit-testable. Never raises on odd models — missing data
    # maps to nil and any extraction error collapses to an {error:} hash.
    module ModelQuery
      module_function

      # @return [Hash, nil] plain-data snapshot of one model, nil if model nil
      def extract(model)
        return nil if model.nil?

        {
          envelope: envelope(model),
          space_types: space_types(model)
        }
      rescue StandardError => e
        { error: "model extraction failed: #{e.message}" }
      end

      # Surfaces grouped by type with area-weighted average conductance, plus
      # FDWR/SRR. SimpleGlazing constructions return an empty thermalConductance
      # so subsurfaces fall back to uFactor.
      def envelope(model)
        groups = Hash.new { |h, k| h[k] = { area_m2: 0.0, ua_w_per_k: 0.0 } }
        model.getSurfaces.each do |surface|
          next unless surface.outsideBoundaryCondition == 'Outdoors'

          key = surface.surfaceType # Wall / RoofCeiling / Floor
          area = surface.grossArea
          u = construction_conductance(surface.construction)
          groups[key][:area_m2] += area
          groups[key][:ua_w_per_k] += (u || 0.0) * area
        end
        model.getSubSurfaces.each do |sub|
          next unless sub.outsideBoundaryCondition == 'Outdoors'

          key = sub.subSurfaceType =~ /Window|GlassDoor/ ? 'Window' : sub.subSurfaceType
          area = sub.grossArea
          u = construction_conductance(sub.construction)
          groups[key][:area_m2] += area
          groups[key][:ua_w_per_k] += (u || 0.0) * area
        end

        surfaces = groups.map do |type, g|
          avg_u = g[:area_m2].positive? && g[:ua_w_per_k].positive? ? g[:ua_w_per_k] / g[:area_m2] : nil
          { type: type, area_m2: g[:area_m2].round(1), avg_u_w_per_m2k: avg_u&.round(3) }
        end

        wall_area = groups['Wall'][:area_m2]
        window_area = groups['Window'][:area_m2]
        roof_area = groups['RoofCeiling'][:area_m2]
        skylight_area = groups['Skylight'][:area_m2]
        {
          surfaces: surfaces,
          fdwr: wall_area.positive? ? (window_area / (wall_area + window_area)).round(3) : nil,
          srr: roof_area.positive? ? (skylight_area / (roof_area + skylight_area)).round(3) : nil
        }
      end

      def construction_conductance(optional_construction)
        return nil if optional_construction.empty?

        construction = optional_construction.get.to_LayeredConstruction
        return nil if construction.empty?

        tc = construction.get.thermalConductance
        return tc.get if tc.is_initialized

        u = construction.get.uFactor # SimpleGlazing path
        u.is_initialized ? u.get : nil
      rescue StandardError
        nil
      end

      def space_types(model)
        model.getSpaceTypes.sort_by(&:nameString).filter_map do |st|
          area = st.spaces.sum(&:floorArea)
          next if area.zero?

          {
            name: st.nameString,
            area_m2: area.round(1),
            lpd_w_per_m2: unwrap(st.lightingPowerPerFloorArea)&.round(2),
            people_per_m2: unwrap(st.peoplePerFloorArea)&.round(4),
            equipment_w_per_m2: unwrap(st.electricEquipmentPowerPerFloorArea)&.round(2)
          }
        end
      end

      # Density getters return a plain double or an OptionalDouble depending on
      # SDK version — normalize to Float or nil.
      def unwrap(value)
        return value if value.is_a?(Numeric)
        return value.get if value.respond_to?(:is_initialized) && value.is_initialized

        nil
      end

    end
  end
end
