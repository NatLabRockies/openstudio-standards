module OpenStudioGeometry
  # The three small BTAP geometry helpers the wizards depend on, ported
  # standalone (BTAP::Geometry.match_surfaces / rotate_model and
  # BTAP::Geometry::Surfaces.set_surfaces_boundary_condition).
  module Helpers
    module_function

    # Match interior surfaces between every pair of spaces (legacy semantics:
    # sorted pairwise matchSurfaces).
    def match_surfaces(model)
      model.getSpaces.sort_by(&:nameString).each do |space1|
        model.getSpaces.sort_by(&:nameString).each do |space2|
          space1.matchSurfaces(space2)
        end
      end
      model
    end

    # Set an outside boundary condition on surfaces; Adiabatic removes
    # subsurfaces first (an adiabatic surface cannot carry them).
    def set_boundary_condition(surfaces, boundary_condition)
      unless OpenStudio::Model::Surface.validOutsideBoundaryConditionValues.include?(boundary_condition)
        raise(ArgumentError, "invalid outside boundary condition '#{boundary_condition}'")
      end

      surfaces.each do |surface|
        surface.subSurfaces.each(&:remove) if boundary_condition == 'Adiabatic'
        surface.setOutsideBoundaryCondition(boundary_condition)
      end
      surfaces
    end

    # Rotate every planar surface group about the z axis.
    def rotate_model(model, degrees)
      transformation = OpenStudio::Transformation.rotation(OpenStudio::Vector3d.new(0, 0, 1),
                                                           degrees * Math::PI / 180)
      model.getPlanarSurfaceGroups.each { |group| group.changeTransformation(transformation) }
      model
    end
  end
end
