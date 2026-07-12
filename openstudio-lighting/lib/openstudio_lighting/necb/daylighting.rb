module OpenStudioLighting
  module NECB
    # Daylighting controls — port of the legacy model_add_daylighting_controls
    # 'add_daylighting_controls' option: every space with exterior fenestration
    # (fixed/operable window or skylight) gets ONE DaylightingControl at the
    # centre of its lowest floor's bounding box, 0.8 m above the floor, Stepped
    # control with 2 steps (NECB minimum), illuminance setpoint from the
    # space-type target_illuminance_setpoint, wired as the zone's primary
    # control at fraction 1.0.
    #
    # HONEST SCOPE: the NECB-threshold option (sensors ONLY where 4.2.2 requires
    # them, driven by the primary-sidelighted-area / effective-aperture geometry)
    # is NOT ported — the daylighted-area machinery remains a documented future.
    # This is the legacy Option #2 semantics ("sensors in all daylighted spaces
    # regardless of NECB requirements").
    module Daylighting
      module_function

      STEPPED_STEPS = 2 # NECB minimum

      # @return [Integer] number of controls created
      def add_controls(model, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        created = 0

        model.getSpaces.sort_by(&:nameString).each do |space|
          next unless daylighted?(space)
          next if space.thermalZone.empty?

          zone = space.thermalZone.get
          next if zone.primaryDaylightingControl.is_initialized

          setpoint = illuminance_setpoint(space, data_vintage)
          if setpoint.nil?
            audit.warn(:daylighting, 'no target_illuminance_setpoint for this space type — no sensor placed',
                       target: space.nameString)
            next
          end

          bounds = lowest_floor_bounds(space)
          next if bounds.nil?

          sensor = OpenStudio::Model::DaylightingControl.new(model)
          sensor.setName("#{space.nameString} daylighting control")
          sensor.setSpace(space)
          sensor.setIlluminanceSetpoint(setpoint)
          sensor.setLightingControlType('Stepped')
          sensor.setNumberofSteppedControlSteps(STEPPED_STEPS)
          sensor.setPosition(OpenStudio::Point3d.new((bounds[:xmin] + bounds[:xmax]) / 2.0,
                                                     (bounds[:ymin] + bounds[:ymax]) / 2.0,
                                                     bounds[:zmin] + 0.8))
          zone.setPrimaryDaylightingControl(sensor)
          zone.setFractionofZoneControlledbyPrimaryDaylightingControl(1.0)
          created += 1
          audit.info(:daylighting, 'daylighting control placed (all-daylighted-spaces option)',
                     target: space.nameString,
                     inputs: { illuminance_lux: setpoint, control: 'Stepped x2', fraction: 1.0 },
                     article: '4.2.2. (sensor hardware; threshold geometry not evaluated)')
        end

        audit.decision(:daylighting, 'daylighting controls added to every daylighted space ' \
                                     '(legacy add_daylighting_controls option; the 4.2.2 threshold-based ' \
                                     'placement is a documented future)',
                       inputs: { controls: created }, article: '4.2.2.')
        created
      end

      def daylighted?(space)
        space.surfaces.any? do |surface|
          surface.subSurfaces.any? do |sub|
            sub.outsideBoundaryCondition == 'Outdoors' &&
              %w[FixedWindow OperableWindow Skylight].include?(sub.subSurfaceType)
          end
        end
      end

      def illuminance_setpoint(space, data_vintage)
        return nil if space.spaceType.empty?

        space_type = space.spaceType.get
        return nil unless space_type.standardsBuildingType.is_initialized && space_type.standardsSpaceType.is_initialized

        record = OpenStudioLoads::NECB::SpaceTypes.find(
          building_type: space_type.standardsBuildingType.get,
          space_type: space_type.standardsSpaceType.get, vintage: data_vintage)
        return nil if record.nil?

        value = record['target_illuminance_setpoint'].to_f
        value.zero? ? nil : value
      end

      def lowest_floor_bounds(space)
        floors = space.surfaces.select { |s| s.surfaceType == 'Floor' }
        return nil if floors.empty?

        lowest_z = floors.map { |f| f.vertices.map(&:z).min }.min
        lowest = floors.select { |f| f.vertices.map(&:z).min == lowest_z }
        points = lowest.flat_map(&:vertices)
        { xmin: points.map(&:x).min, xmax: points.map(&:x).max,
          ymin: points.map(&:y).min, ymax: points.map(&:y).max, zmin: lowest_z }
      end
    end

    def self.add_daylighting_controls(model, **kwargs)
      Daylighting.add_controls(model, **kwargs)
    end
  end

  # Facade: add NECB daylighting controls (all-daylighted-spaces option).
  def self.add_daylighting_controls(model, **kwargs)
    NECB.add_daylighting_controls(model, **kwargs)
  end
end
