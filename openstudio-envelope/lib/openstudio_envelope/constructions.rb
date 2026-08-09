module OpenStudioEnvelope
  # SDK-only construction machinery — SI-native ports of the clean pieces of
  # OpenstudioStandards::Constructions plus the legacy BTAP conventions the parity
  # gate (and future costing) depend on:
  #
  # - Opaque targets are applied as CONSTRUCTION-ONLY conductance (films excluded),
  #   exactly like legacy BTAP customize_opaque_construction (btap/envelope.rb:145 —
  #   OS Construction#setConductance on the insulation layer). Pass include_films:
  #   true to the NECB appliers for the code-literal interpretation (table values are
  #   overall transmittance): the construction target becomes 1/(1/U - R_films).
  # - Naming/reuse conventions preserved: opaque "Base:U-<cond>", fenestration
  #   "Base:U=<cond*0.1> SHGC=<shgc>" with a shared SimpleGlazing — BTAP envelope
  #   costing keys on these names.
  module Constructions
    module_function

    IP_TO_SI_R = 0.17611018368230098 # ft2·h·R/Btu -> m2·K/W

    FILM_R_SI = {
      ext: 0.17 * IP_TO_SI_R,
      semi_ext: 0.46 * IP_TO_SI_R,
      int_up: 0.61 * IP_TO_SI_R,
      int_down: 0.92 * IP_TO_SI_R,
      int_vertical: 0.68 * IP_TO_SI_R
    }.freeze

    # Interior+exterior film resistance for the envelope surface classes this gem
    # touches (subset of OpenstudioStandards film_coefficients_r_value).
    def film_r(surface, boundary)
      case [boundary.to_s, surface.to_s]
      when %w[outdoors wall], %w[outdoors window], %w[outdoors door]
        FILM_R_SI[:ext] + FILM_R_SI[:int_vertical]
      when %w[outdoors roofceiling], %w[outdoors skylight]
        FILM_R_SI[:ext] + FILM_R_SI[:int_up]
      when %w[outdoors floor]
        FILM_R_SI[:ext] + FILM_R_SI[:int_down]
      when %w[ground wall]
        FILM_R_SI[:int_vertical]
      when %w[ground floor]
        FILM_R_SI[:int_down]
      when %w[ground roofceiling]
        FILM_R_SI[:int_up]
      else
        0.0
      end
    end

    # Both faces of an assembly separating conditioned from enclosed
    # unconditioned space see INTERIOR films (attic ceilings, walls to
    # unheated storage, floors over crawlspaces).
    def film_r_interzone(surface)
      case surface.to_s
      when 'wall' then 2 * FILM_R_SI[:int_vertical]
      when 'roofceiling' then 2 * FILM_R_SI[:int_up]
      when 'floor' then 2 * FILM_R_SI[:int_down]
      else 0.0
      end
    end

    # Clone the construction AND every layer material (a bare Construction#clone
    # shares material objects, so solving one construction's insulation would mutate
    # every other construction using the same material — port of the legacy
    # construction_deep_copy).
    def deep_copy(model, construction)
      copy = construction.clone(model).to_Construction.get
      copy.setName(construction.nameString)
      copy.setLayers(construction.layers.map { |layer| layer.clone(model).to_Material.get })
      copy.resetInsulation if copy.insulation.is_initialized
      copy
    end

    # Lowest-conductance opaque layer, memoized on the construction (port of
    # construction_find_and_set_insulation_layer).
    def find_and_set_insulation_layer(construction)
      return construction.insulation.get if construction.insulation.is_initialized

      best = nil
      best_conductance = Float::INFINITY
      construction.layers.each do |layer|
        material = layer.to_OpaqueMaterial
        next unless material.is_initialized

        c = material_conductance(material.get)
        if c < best_conductance
          best_conductance = c
          best = material.get
        end
      end
      construction.setInsulation(best) if best
      construction.insulation.is_initialized ? construction.insulation.get : nil
    end

    def material_conductance(material)
      if material.to_StandardOpaqueMaterial.is_initialized
        m = material.to_StandardOpaqueMaterial.get
        m.conductivity / m.thickness
      elsif material.to_MasslessOpaqueMaterial.is_initialized
        1.0 / material.to_MasslessOpaqueMaterial.get.thermalResistance
      elsif material.to_AirGap.is_initialized
        1.0 / material.to_AirGap.get.thermalResistance
      else
        Float::INFINITY
      end
    end

    # Opaque construction at a target CONSTRUCTION conductance, W/(m2.K) —
    # legacy-exact port of BTAP customize_opaque_construction: reuse by name,
    # deep-copy, insulation-layer solve via SDK setConductance, layer-trimming
    # fallback when the non-insulation layers alone exceed the target resistance.
    def opaque_at_conductance(model, construction, conductance)
      base = construction.nameString.sub(/:.*\z/, '')
      # Names are keys for humans and legacy costing matchers; the full-precision
      # value lives in the material (setConductance below uses the unrounded
      # `conductance` arg). Rounding only the display string is safe here because
      # every caller feeds discrete NECB table U-values (see necb/prescriptive.rb),
      # which are separated by far more than 1e-4 W/(m2.K) even after the
      # include_films transform — two distinct table entries colliding at 4dp is
      # not plausible with the current call sites.
      name = "#{base}:U-#{conductance.round(4)}"
      existing = model.getConstructionByName(name)
      return existing.get unless existing.empty?

      copy = deep_copy(model, construction)
      copy.setName(name)
      insulation = find_and_set_insulation_layer(copy)
      raise("no insulation layer identifiable in #{construction.nameString}") if insulation.nil?

      minimum_resistance = (1.0 / copy.thermalConductance.to_f) -
                           (1.0 / material_conductance(insulation.to_OpaqueMaterial.get))
      if minimum_resistance > (1.0 / conductance)
        trim_layers_to_conductance(copy, conductance)
      else
        copy.setConductance(conductance) || raise("could not set conductance of #{name}")
      end
      copy
    end

    # Fallback when the insulation layer alone cannot reach the target: remove the
    # least-conductive non-insulation layers until the SDK solve succeeds, ending
    # with a single massless layer at the exact resistance if all else fails
    # (behavior-compatible simplification of legacy adjust_opaque_construction).
    def trim_layers_to_conductance(construction, conductance)
      insulation = construction.insulation
      loop do
        removable = construction.layers.each_with_index.reject do |layer, _|
          insulation.is_initialized && layer.handle == insulation.get.handle
        end
        break if removable.empty?

        # remove the most resistive removable layer first
        layer, index = removable.min_by { |l, _| material_conductance(l.to_OpaqueMaterial&.get || l) rescue Float::INFINITY }
        construction.eraseLayer(index)
        return construction if construction.setConductance(conductance)
        break if construction.layers.size <= 1
      end
      material = OpenStudio::Model::MasslessOpaqueMaterial.new(construction.model, 'MediumSmooth', 1.0 / conductance)
      material.setName("#{construction.nameString} R-#{(1.0 / conductance).round(3)}")
      construction.setLayers([material])
      construction.setInsulation(material)
      construction
    end

    # Fenestration construction at a target U — legacy-exact port of BTAP
    # customize_fenestration_construction: replace with a shared SimpleGlazing that
    # preserves SHGC and visible transmittance; reuse by name.
    def fenestration_at_conductance(model, construction, conductance)
      shgc = fenestration_solar_transmittance(construction)
      vt = fenestration_visible_transmittance(construction)
      base = construction.nameString.sub(/:.*\z/, '')
      suffix = "U=#{format('%.3f', conductance * 0.10)} SHGC=#{format('%.3f', shgc)}"
      name = "#{base}:#{suffix}"
      existing = model.getConstructionByName(name)
      return existing.get unless existing.empty?

      glazing_name = "SimpleGlazing:#{suffix}"
      glazing = model.getSimpleGlazingByName(glazing_name)
      glazing = if glazing.empty?
                  g = OpenStudio::Model::SimpleGlazing.new(model)
                  g.setSolarHeatGainCoefficient(shgc)
                  g.setUFactor(conductance)
                  g.setThickness(0.21)
                  g.setVisibleTransmittance(vt)
                  g.setName(glazing_name)
                  g
                else
                  glazing.get
                end

      new_construction = OpenStudio::Model::Construction.new(model)
      new_construction.setName(name)
      new_construction.setLayers([glazing])
      new_construction
    end

    def fenestration_solar_transmittance(construction)
      construction.layers.each do |layer|
        return layer.to_SimpleGlazing.get.solarHeatGainCoefficient if layer.to_SimpleGlazing.is_initialized
        return layer.to_StandardGlazing.get.solarTransmittanceatNormalIncidence.to_f if layer.to_StandardGlazing.is_initialized
      end
      0.60
    end

    def fenestration_visible_transmittance(construction)
      construction.layers.each do |layer|
        if layer.to_SimpleGlazing.is_initialized
          vt = layer.to_SimpleGlazing.get.visibleTransmittance
          return vt.is_initialized ? vt.get : 0.60 if vt.respond_to?(:is_initialized)
          return vt
        end
        if layer.to_StandardGlazing.is_initialized
          return layer.to_StandardGlazing.get.visibleTransmittanceatNormalIncidence.to_f
        end
      end
      0.60
    end
  end
end
