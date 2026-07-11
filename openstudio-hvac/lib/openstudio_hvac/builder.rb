module OpenStudioHVAC
  # The public facade.
  module Builder
    FAMILIES = {
      'psz' => Systems::PSZ,
      'vav_reheat' => Systems::VAVReheat
    }.freeze

    Result = Struct.new(:system_name, :family, :air_loops, :control_zone, keyword_init: true)

    # Build a complete HVAC system topology on a set of thermal zones by descriptive name.
    #
    # Topology only: run your sizing and code-efficiency passes afterwards (e.g. with
    # openstudio-standards, whose efficiency application is data-driven and applies to any
    # topology, including systems built by this gem).
    #
    # @param model [OpenStudio::Model::Model]
    # @param system_name [String] a catalog name (see OpenStudioHVAC.systems)
    # @param zones [Array<OpenStudio::Model::ThermalZone>] zones to serve
    # @param control_zone [OpenStudio::Model::ThermalZone] control zone for single-zone
    #   systems (default: zones.first)
    # @param remove_existing [Boolean] tear down HVAC serving these zones first, so the new
    #   system replaces rather than stacks (zone-scoped; other zones untouched)
    # @param namer [Symbol] :default or :necb_pipe_name
    # @param config [Hash, nil] per-call overrides merged over the catalog row
    # @return [Result] system_name, family, air_loops, control_zone
    def self.build_system(model, system_name, zones,
                          control_zone: nil, remove_existing: false,
                          namer: :default, config: nil)
      Validation.require_zones!(zones)
      Validation.require_thermostats!(zones)
      control_zone ||= zones.first
      Validation.require_control_zone!(zones, control_zone)

      resolved = Catalog.resolve(system_name)
      resolved = resolved.merge(config.transform_keys(&:to_s)) if config

      system_class = FAMILIES[resolved['family']]
      raise(ArgumentError, "no builder registered for family '#{resolved['family']}'") if system_class.nil?

      Teardown.remove_hvac_from_zones(model, zones) if remove_existing

      hw_loop = nil
      hw_loop = Systems::PlantLoops.hot_water(model, fuel: resolved.fetch('boiler_fuel', 'NaturalGas')) if resolved['needs_boiler']
      chw_loop = nil
      chw_loop = Systems::PlantLoops.chilled_water(model, chiller_type: resolved.fetch('chiller_type', 'Scroll')) if resolved['needs_chiller']

      air_loops = system_class.new(resolved).build(model, zones,
                                                   control_zone: control_zone,
                                                   namer: namer,
                                                   hw_loop: hw_loop,
                                                   chw_loop: chw_loop)

      Result.new(system_name: system_name, family: resolved['family'],
                 air_loops: air_loops, control_zone: control_zone)
    end
  end
end
