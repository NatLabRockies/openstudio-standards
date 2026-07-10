module OpenstudioStandards
  # The HVAC module provides methods to create, modify, and get information about HVAC systems
  module HVAC
    # @!group System and Efficiency
    # Methods to add any supported HVAC system (CBECS/generic, NECB reference sys1-6, or NECB ECM)
    # plus its efficiency to a set of thermal zones, using descriptive, fuel-encoding system names.

    # Add a complete HVAC system to a set of zones and apply the template's efficiency standard.
    # Dispatches by descriptive system name to the right family builder, then sizes and applies
    # efficiency (and ECM efficiencies for ECM systems).
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a built standard object, e.g. Standard.build('NECB2011')
    # @param system [String] a descriptive system name. One of:
    #   a CBECS type ('Baseboard gas boiler'), a bare model_add_hvac_system type ('PSZ-AC'),
    #   an NECB systems.json description ('PSZ RTU Gas and DX Coils and Hot Water Baseboard'),
    #   or an NECB ECM id ('hs08_ccashp_vrf').
    # @param zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
    # @param sizing_run_dir [String] directory for sizing runs
    # @param climate_zone [String, nil] required for non-NECB templates; NECB uses 'NECB HDD Method'
    # @param family [Symbol, nil] optional explicit :cbecs/:generic/:necb_ref/:ecm override
    # @param primary_heating_fuel [String] base NECB fuel set name (NECB standards only)
    # @param remove_existing [Boolean] if true, remove any HVAC serving these zones first, so the
    #   new system replaces (rather than stacks on top of) whatever was there. Zone-scoped: other
    #   zones' systems are untouched. Default false.
    # @param opts [Hash] family-specific options (generic fuels, control_zone, etc.)
    # @return [Boolean] true on success
    def self.add_hvac_system_and_efficiency(model, standard, system:, zones:, sizing_run_dir:,
                                            climate_zone: nil, family: nil,
                                            primary_heating_fuel: 'NaturalGas',
                                            remove_existing: false, **opts)
      require_thermostats!(zones)
      remove_hvac_from_zones(model, zones) if remove_existing
      fam = family || classify_system(standard, system)
      ensure_fuel_type_set!(standard, primary_heating_fuel: primary_heating_fuel) if %i[necb_ref ecm].include?(fam)

      case fam
      when :cbecs
        # Try the CBECS descriptive-name mapping; fall back to the generic builder if unrecognized.
        add_cbecs_hvac_system(model, standard, system, zones) ||
          standard.model_add_hvac_system(model, system, *generic_fuels(opts), zones)
      when :generic
        standard.model_add_hvac_system(model, system, *generic_fuels(opts), zones)
      when :necb_ref
        add_necb_reference_hvac_system(model, standard, system, zones, **opts)
      when :ecm
        add_necb_ecm_hvac_system(model, standard, system, zones, **opts)
      end

      size_and_apply_efficiency_standard(model, standard, sizing_run_dir: sizing_run_dir, climate_zone: climate_zone)
      if fam == :ecm
        Standard.build('ECMS').apply_system_efficiencies_ecm(model: model, ecm_system_name: system, template_standard: standard)
      end
      true
    end

    # Add an NECB reference system (sys1-6) by descriptive, fuel-encoding name to a set of zones.
    # Delegates to the existing create_hvac_by_name (which maps the name to the right add_sysN_*
    # builder with the row's coils/chiller/baseboard, so fuel comes from the name), supplying an
    # explicit control_zone so sys3/sys4 need no sizing run or NECB-tagged geometry.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] an NECB (or ECMS/BTAP) standard object
    # @param system_name [String] an NECB systems.json 'description', e.g.
    #   'PSZ RTU Gas and DX Coils and Hot Water Baseboard'
    # @param zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
    # @option opts [OpenStudio::Model::ThermalZone] :control_zone control zone (default zones.first)
    # @option opts [Boolean] :remove_existing remove existing HVAC on these zones first (default false)
    # @return [Boolean] true on success
    def self.add_necb_reference_hvac_system(model, standard, system_name, zones, **opts)
      ensure_fuel_type_set!(standard)
      require_thermostats!(zones)
      remove_hvac_from_zones(model, zones) if opts[:remove_existing]
      hw_loop = necb_hw_loop_for_named_system(model, standard, system_name)
      standard.create_hvac_by_name(model: model, hvac_system_name: system_name, zones: zones,
                                   hw_loop: hw_loop, control_zone: opts.fetch(:control_zone, zones.first))
      true
    end

    # Add an NECB ECM system (hs08-hs16) by id to a set of zones, building directly on the zones
    # (bypassing apply_system_ecm's air-loop teardown by supplying a hand-built system_zones_map).
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] an NECB standard object (used for fuels)
    # @param ecm [String] the ECM id, e.g. 'hs08_ccashp_vrf'
    # @param zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
    # @return [Boolean] true on success
    def self.add_necb_ecm_hvac_system(model, standard, ecm, zones, **opts)
      ensure_fuel_type_set!(standard)
      require_thermostats!(zones)
      remove_hvac_from_zones(model, zones) if opts[:remove_existing]
      ecm_std = Standard.build('ECMS')
      add_method = "add_ecm_#{ecm.downcase}"
      raise("Unknown NECB ECM system '#{ecm}' (no #{add_method})") unless ecm_std.respond_to?(add_method)
      ecm_std.public_send(add_method,
                          model: model,
                          system_zones_map: { 'sys_1' => zones },
                          system_doas_flags: { 'sys_1' => opts.fetch(:doas, true) },
                          ecm_system_zones_map_option: 'NECB_Default',
                          standard: standard)
      true
    end

    # Size the model and apply the template's HVAC efficiency standard, dispatching to the correct
    # per-standard sequence (NECB delegates to apply_standard_efficiencies; 90.1/others mirror the
    # create_typical sizing+efficiency sequence).
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a built standard object
    # @param sizing_run_dir [String] directory for the sizing run
    # @param climate_zone [String, nil] required for non-NECB templates
    # @return [Boolean] true on success, false if a non-NECB sizing run failed
    def self.size_and_apply_efficiency_standard(model, standard, sizing_run_dir:, climate_zone: nil)
      if standard.respond_to?(:apply_standard_efficiencies)
        # NECB/ECMS/BTAP. Mirror apply_standard_efficiencies (necb_2011.rb:1235) but size with the
        # base model_run_sizing_run, which — unlike try_sizing_run — does NOT gate on
        # validate_initial_model, so this works on arbitrary (non-NECB-prototype) geometry.
        # (Trade-off: try_sizing_run's DX-heating-coil resize-and-retry is not replicated; a
        # heat-pump system whose DX heating coil autosizes below 1 kW may need that — future work.)
        necb_climate_zone = 'NECB HDD Method'
        return false if standard.model_run_sizing_run(model, "#{sizing_run_dir}/SR1") == false

        model.getAirTerminalSingleDuctVAVReheats.each { |t| standard.air_terminal_single_duct_vav_reheat_set_heating_cap(t) }
        standard.model_apply_prototype_hvac_assumptions(model, nil, necb_climate_zone)
        standard.model_apply_hvac_efficiency_standard(model, necb_climate_zone, sql_db_vars_map: {})
        standard.model_enable_demand_controlled_ventilation(model, 'NECB_Default')
      else
        raise('climate_zone is required for non-NECB templates') if climate_zone.nil?

        standard.model_apply_prm_sizing_parameters(model)
        return false if standard.model_run_sizing_run(model, "#{sizing_run_dir}/SR1") == false

        standard.model_apply_multizone_vav_outdoor_air_sizing(model)
        standard.model_apply_prototype_hvac_assumptions(model, nil, climate_zone)
        standard.model_apply_hvac_efficiency_standard(model, climate_zone)
      end
      true
    end

    # Ensure the standard has an NECB fuel_type_set, and that its force flags are off so a
    # descriptive system name (not a forced fuel policy) determines the fuel/coils.
    #
    # @param standard [Standard] a built standard object (no-op for standards without fuel_type_set)
    # @param primary_heating_fuel [String] base NECB fuel set name from fuel_type_sets.json
    # @return [void]
    def self.ensure_fuel_type_set!(standard, primary_heating_fuel: 'NaturalGas')
      return unless standard.respond_to?(:fuel_type_set)

      if standard.fuel_type_set.nil?
        standard.fuel_type_set = SystemFuels.new
        standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: primary_heating_fuel)
      end
      # "Fuel comes from the name" requires the force flags OFF, else create_hvac_by_name overrides
      # the row's baseboard/coil/supp-fuel from fuel_type_set. A standard from prior BTAP use may
      # have them set; clear so the descriptive name wins.
      standard.fuel_type_set.force_boiler = false
      standard.fuel_type_set.force_airloop_hot_water = false
    end

    # Build (or reuse) a hot-water loop when the named NECB system's row needs a boiler, using the
    # row's authoritative +needs_boiler+ field. Returns nil when no boiler is needed. Reusing an
    # existing HW loop avoids a new boiler per call.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] an NECB standard object (must have a fuel_type_set)
    # @param system_name [String] an NECB systems.json 'description'
    # @return [OpenStudio::Model::PlantLoop, nil] the hot-water loop, or nil if no boiler needed
    def self.necb_hw_loop_for_named_system(model, standard, system_name)
      row = standard.standards_data['hvac_types'].find { |r| r['description'] == system_name }
      raise("unknown NECB system name: #{system_name}") if row.nil?
      return nil unless row['needs_boiler'].to_s == 'true'

      existing = model.getPlantLoops.find do |pl|
        pl.supplyComponents(OpenStudio::Model::BoilerHotWater.iddObjectType).any?
      end
      return existing unless existing.nil?

      fts = standard.fuel_type_set
      loop = OpenStudio::Model::PlantLoop.new(model)
      standard.setup_hw_loop_with_components(model, loop, fts.boiler_fueltype, fts.backup_boiler_fueltype, model.alwaysOnDiscreteSchedule)
      loop
    end

    # Raise a clear error if any zone lacks a dual-setpoint thermostat. Without one, NECB sizing
    # runs yield zero design loads and the CBECS path silently builds nothing.
    #
    # @param zones [Array<OpenStudio::Model::ThermalZone>] zones to validate
    # @return [void]
    def self.require_thermostats!(zones)
      bad = zones.reject { |z| z.thermostatSetpointDualSetpoint.is_initialized }
      return if bad.empty?

      raise("zones need a dual-setpoint thermostat before adding an HVAC system: #{bad.map(&:nameString).join(', ')}")
    end

    # Classify a descriptive system name into a family for dispatch.
    #
    # @param standard [Standard] a built standard object (for the NECB hvac_types catalog)
    # @param system [String] the descriptive system name
    # @return [Symbol] :ecm, :necb_ref, or :cbecs (the default; the :cbecs branch falls back to generic)
    def self.classify_system(standard, system)
      return :ecm if system.to_s =~ /\Ahs\d/i

      if standard.respond_to?(:standards_data)
        rows = standard.standards_data['hvac_types']
        return :necb_ref if rows.is_a?(Array) && rows.any? { |r| r['description'] == system }
      end
      :cbecs
    end

    # Resolve the 3 generic model_add_hvac_system fuels from opts (with sensible defaults).
    #
    # @param opts [Hash] may contain :main_heat_fuel, :zone_heat_fuel, :cool_fuel
    # @return [Array<String>] [main_heat_fuel, zone_heat_fuel, cool_fuel]
    def self.generic_fuels(opts)
      [opts.fetch(:main_heat_fuel, 'NaturalGas'),
       opts.fetch(:zone_heat_fuel, 'Electricity'),
       opts.fetch(:cool_fuel, 'Electricity')]
    end
  end
end
