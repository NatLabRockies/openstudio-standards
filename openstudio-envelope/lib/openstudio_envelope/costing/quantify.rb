module OpenStudioEnvelope
  module Costing
    # Surface census for envelope costing — port of BTAP::Attributes#compile_model.
    # Buckets every costed surface/subsurface into the 16 legacy surface types and
    # computes each one's RSI the way legacy does:
    #   - exterior/ground opaque surfaces: construction resistance + air films
    #     (legacy TBD.rsi(construction, filmResistance))
    #   - subsurfaces: construction resistance only (no films)
    #   - surfaces carrying a TBD 'uprated_Uo' additional property: 1/uprated_Uo
    #     (the thermally-derated effective value, films included by TBD)
    #
    # Space conditioning: the legacy 'space_conditioning_category' additional
    # property is honoured when present (standards-built models); otherwise the
    # gem's proxy (partofTotalFloorArea + dual-setpoint thermostat) decides.
    # Unconditioned spaces contribute no exterior roofs/floors — instead their
    # floor/wall surfaces' ADJACENT (conditioned-side) mirrors are censused as
    # InterzonalRoof / InterzonalSkylightWalls (attic pattern).
    module Quantify
      module_function

      SURFACE_TYPES = %w[
        ExteriorWall ExteriorRoof ExteriorFloor
        InterzonalRoof InterzonalSkylightWalls
        ExteriorFixedWindow ExteriorOperableWindow ExteriorSkylight
        ExteriorTubularDaylightDiffuser ExteriorTubularDaylightDome
        ExteriorDoor ExteriorGlassDoor ExteriorOverheadDoor
        GroundContactWall GroundContactRoof GroundContactFloor
      ].freeze

      SUBSURFACE_TYPES = {
        'FixedWindow' => 'ExteriorFixedWindow',
        'OperableWindow' => 'ExteriorOperableWindow',
        'Skylight' => 'ExteriorSkylight',
        'TubularDaylightDiffuser' => 'ExteriorTubularDaylightDiffuser',
        'TubularDaylightDome' => 'ExteriorTubularDaylightDome',
        'Door' => 'ExteriorDoor',
        'GlassDoor' => 'ExteriorGlassDoor',
        'OverheadDoor' => 'ExteriorOverheadDoor'
      }.freeze

      GROUND_BOUNDARIES = %w[Ground Foundation GroundFCfactorMethod GroundSlabPreprocessorAverage].freeze

      Item = Struct.new(:surface, :surface_type, :rsi, :area_m2, :multiplier, :space_name, keyword_init: true)

      # @return [Hash{String => Array<Item>}] surface type -> censused items
      def census(model, audit: nil)
        items = Hash.new { |h, k| h[k] = [] }
        model.getSpaces.sort_by(&:nameString).each do |space|
          multiplier = space.thermalZone.is_initialized ? space.thermalZone.get.multiplier : 1
          unconditioned = unconditioned?(space)

          space.surfaces.sort_by(&:nameString).each do |surface|
            if surface.outsideBoundaryCondition == 'Outdoors'
              census_exterior(items, space, surface, multiplier, unconditioned)
            elsif GROUND_BOUNDARIES.include?(surface.outsideBoundaryCondition)
              type = { 'Wall' => 'GroundContactWall', 'RoofCeiling' => 'GroundContactRoof',
                       'Floor' => 'GroundContactFloor' }[surface.surfaceType]
              add(items, type, space, surface, multiplier, film: true) if type
            elsif unconditioned && surface.adjacentSurface.is_initialized
              census_interzonal(items, surface, multiplier)
            end
          end
        end

        audit&.info(:costing_envelope, 'envelope surface census',
                    inputs: items.transform_values { |list| { count: list.size, area_m2: list.sum(&:area_m2).round(1) } }
                                 .select { |_, v| v[:count].positive? })
        items
      end

      def census_exterior(items, space, surface, multiplier, unconditioned)
        case surface.surfaceType
        when 'Wall'
          add(items, 'ExteriorWall', space, surface, multiplier, film: true)
        when 'RoofCeiling'
          add(items, 'ExteriorRoof', space, surface, multiplier, film: true) unless unconditioned
        when 'Floor'
          add(items, 'ExteriorFloor', space, surface, multiplier, film: true) unless unconditioned
        end
        return if unconditioned

        surface.subSurfaces.sort_by(&:nameString).each do |sub|
          type = SUBSURFACE_TYPES[sub.subSurfaceType]
          add(items, type, space, sub, multiplier, film: false) if type
        end
      end

      # Attic pattern: this surface belongs to an UNCONDITIONED space and touches a
      # conditioned one — census the conditioned-side mirror (legacy walks attic
      # floors -> InterzonalRoof, attic walls -> InterzonalSkylightWalls).
      def census_interzonal(items, surface, _multiplier)
        mirror = surface.adjacentSurface.get
        mirror_space = mirror.space
        return if mirror_space.empty? || unconditioned?(mirror_space.get)

        zone = mirror_space.get.thermalZone
        mirror_multiplier = zone.is_initialized ? zone.get.multiplier : 1
        case surface.surfaceType
        when 'Floor'
          add(items, 'InterzonalRoof', mirror_space.get, mirror, mirror_multiplier, film: true)
        when 'Wall'
          add(items, 'InterzonalSkylightWalls', mirror_space.get, mirror, mirror_multiplier, film: true)
        end
      end

      def add(items, type, space, surface, multiplier, film:)
        rsi = rsi_of(surface, film: film)
        return if rsi.nil?

        items[type] << Item.new(surface: surface, surface_type: type, rsi: rsi,
                                area_m2: surface.netArea, multiplier: multiplier,
                                space_name: space.nameString)
      end

      # @param film [Boolean] include air films (legacy: surfaces yes, subsurfaces no)
      def rsi_of(surface, film:)
        uprated = surface.additionalProperties.getFeatureAsDouble('uprated_Uo')
        return 1.0 / uprated.get if uprated.is_initialized && uprated.get.positive?

        return nil if surface.construction.empty?

        construction = surface.construction.get.to_LayeredConstruction
        return nil if construction.empty?

        conductance = construction.get.thermalConductance
        # fenestration (SimpleGlazing) has no layer conductance — use the U-factor
        # (films included by definition; legacy TBD.rsi treats it as 1/usi likewise)
        conductance = construction.get.uFactor if conductance.empty?
        return nil if conductance.empty? || conductance.get <= 0

        rsi = 1.0 / conductance.get
        rsi += surface.filmResistance if film
        rsi
      end

      def unconditioned?(space)
        category = space.additionalProperties.getFeatureAsString('space_conditioning_category')
        return category.get.downcase == 'unconditioned' if category.is_initialized

        !Geometry.conditioned?(space)
      end
    end
  end
end
