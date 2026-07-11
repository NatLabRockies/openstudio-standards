module OpenStudioHVAC
  # Precondition checks with clear errors (silent no-ops and deep SDK crashes are the
  # failure modes these guard against).
  module Validation
    # Every zone must carry a dual-setpoint thermostat: without setpoint schedules, sizing
    # runs yield zero design loads and zone equipment silently conditions nothing.
    #
    # @param zones [Array<OpenStudio::Model::ThermalZone>]
    # @return [void]
    def self.require_thermostats!(zones)
      bad = zones.reject { |z| z.thermostatSetpointDualSetpoint.is_initialized }
      return if bad.empty?

      raise(ArgumentError,
            'zones need a dual-setpoint thermostat before adding an HVAC system: ' \
            "#{bad.map(&:nameString).join(', ')}")
    end

    # The control zone (for single-zone systems) must be one of the served zones.
    #
    # @return [OpenStudio::Model::ThermalZone] the validated control zone
    def self.require_control_zone!(zones, control_zone)
      raise(ArgumentError, 'control_zone must be one of the passed zones') unless zones.include?(control_zone)

      control_zone
    end

    # Zones must be a non-empty array of ThermalZones.
    def self.require_zones!(zones)
      raise(ArgumentError, 'zones must be a non-empty Array of ThermalZones') if !zones.is_a?(Array) || zones.empty?
    end
  end
end
