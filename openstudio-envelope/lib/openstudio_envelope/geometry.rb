module OpenStudioEnvelope
  # SDK-only geometry: exposed conditioned surface census, the FDWR window rebuild
  # (port of legacy apply_max_fdwr_nrcan) and the SRR centroid-scaled skylight
  # creator (port of OPTION A apply_max_srr_nrcan / scaled-subsurface creator).
  #
  # "Conditioned, non-plenum" is proxied by Space#partofTotalFloorArea + a zone
  # thermostat (the legacy check reads NECB space-type setpoint schedules; on
  # standards-untagged models the proxy is equivalent) — same convention as the
  # openstudio-hvac gem's classifier.
  module Geometry
    module_function

    def conditioned?(space)
      return false unless space.partofTotalFloorArea

      zone = space.thermalZone
      zone.is_initialized && zone.get.thermostatSetpointDualSetpoint.is_initialized
    end

    # Census of exterior conditioned walls (near-vertical) with area totals and the
    # current FDWR (port of find_exposed_conditioned_vertical_surfaces).
    def exposed_walls(model, min_angle: 89, max_angle: 91)
      walls = []
      wall_area = 0.0
      sub_area = 0.0
      model.getSpaces.sort_by(&:nameString).each do |space|
        next unless conditioned?(space)

        space.surfaces.sort_by(&:nameString).each do |surface|
          next unless surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'

          tilt = surface.tilt * 180.0 / Math::PI
          next unless tilt >= min_angle && tilt <= max_angle

          walls << surface
          wall_area += surface.grossArea * space.multiplier
          surface.subSurfaces.each { |ss| sub_area += ss.grossArea * space.multiplier }
        end
      end
      { walls: walls, wall_area_m2: wall_area, subsurface_area_m2: sub_area,
        fdwr: wall_area < 0.1 ? nil : sub_area / wall_area }
    end

    # Census of exterior conditioned roofs with the current SRR.
    def exposed_roofs(model)
      roofs = []
      roof_area = 0.0
      sub_area = 0.0
      model.getSpaces.sort_by(&:nameString).each do |space|
        next unless conditioned?(space)

        space.surfaces.sort_by(&:nameString).each do |surface|
          next unless surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'

          roofs << surface
          roof_area += surface.grossArea * space.multiplier
          surface.subSurfaces.each { |ss| sub_area += ss.grossArea * space.multiplier }
        end
      end
      { roofs: roofs, roof_area_m2: roof_area, subsurface_area_m2: sub_area,
        srr: roof_area < 0.1 ? nil : sub_area / roof_area }
    end

    # Rebuild windows to hit an FDWR limit (port of apply_max_fdwr_nrcan): remove
    # existing subsurfaces, setWindowToWallRatio per exposed wall, retype to
    # FixedWindow and assign the given construction.
    def apply_fdwr(model, fdwr_lim, window_construction, audit: nil)
      census = exposed_walls(model)
      return false if census[:wall_area_m2] < 0.1 || fdwr_lim > 1

      census[:walls].each do |surface|
        surface.subSurfaces.sort_by(&:nameString).each(&:remove)
        next if fdwr_lim < 0.001

        surface.setWindowToWallRatio(fdwr_lim)
        surface.subSurfaces.sort_by(&:nameString).each do |sub|
          sub.setSubSurfaceType('FixedWindow')
          sub.setConstruction(window_construction)
          sub.setName("#{surface.nameString}_#{sub.subSurfaceType}")
        end
      end
      audit&.decision(:geometry, 'windows rebuilt to FDWR limit',
                      inputs: { fdwr_limit: fdwr_lim.round(4), walls: census[:walls].size },
                      value: "resulting FDWR #{exposed_walls(model)[:fdwr]&.round(4)}",
                      article: '3.2.1.4.(1)')
      true
    end

    # Add centroid-scaled skylights at an SRR limit (port of OPTION A): one skylight
    # per exposed conditioned roof, the roof polygon scaled about its centroid by
    # sqrt(fraction) — exact for convex roofs (a scaled convex polygon has exactly
    # fraction x the area).
    def apply_srr(model, srr_lim, skylight_construction, audit: nil)
      census = exposed_roofs(model)
      return false if census[:roof_area_m2] < 0.1 || srr_lim > 1

      scale = Math.sqrt(srr_lim)
      census[:roofs].each do |surface|
        surface.subSurfaces.sort_by(&:nameString).each(&:remove)
        next if srr_lim < 0.001

        centroid = vertex_centroid(surface.vertices)
        new_vertices = surface.vertices.map do |v|
          OpenStudio::Point3d.new(centroid.x + (v.x - centroid.x) * scale,
                                  centroid.y + (v.y - centroid.y) * scale,
                                  centroid.z + (v.z - centroid.z) * scale)
        end
        skylight = OpenStudio::Model::SubSurface.new(new_vertices, model)
        skylight.setSurface(surface)
        skylight.setSubSurfaceType('Skylight')
        skylight.setConstruction(skylight_construction)
        skylight.setName("#{surface.nameString}_Skylight")
      end
      audit&.decision(:geometry, 'skylights added at SRR limit',
                      inputs: { srr_limit: srr_lim.round(4), roofs: census[:roofs].size },
                      value: "resulting SRR #{exposed_roofs(model)[:srr]&.round(4)}",
                      article: '3.2.1.4.(2)')
      true
    end

    # Scale every subsurface of a surface about its own centroid so its area changes
    # by `area_ratio` (used by the reference-envelope per-orientation FDWR reduction:
    # 8.4.4.3.(3) scales EXISTING fenestration proportionally, never rebuilds).
    def scale_subsurfaces(surface, area_ratio)
      scale = Math.sqrt(area_ratio)
      surface.subSurfaces.sort_by(&:nameString).each do |sub|
        centroid = vertex_centroid(sub.vertices)
        sub.setVertices(sub.vertices.map do |v|
          OpenStudio::Point3d.new(centroid.x + (v.x - centroid.x) * scale,
                                  centroid.y + (v.y - centroid.y) * scale,
                                  centroid.z + (v.z - centroid.z) * scale)
        end)
      end
    end

    def vertex_centroid(vertices)
      n = vertices.size.to_f
      OpenStudio::Point3d.new(vertices.sum(&:x) / n, vertices.sum(&:y) / n, vertices.sum(&:z) / n)
    end
  end
end
