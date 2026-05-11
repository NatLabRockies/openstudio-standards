class SystemFuels
  attr_accessor :name
  attr_accessor :boiler_fueltype
  attr_accessor :backup_boiler_fueltype
  attr_accessor :primary_boiler_cap_frac
  attr_accessor :secondary_boiler_cap_frac
  attr_accessor :baseboard_type
  attr_accessor :mau_type
  attr_accessor :mau_heating_coil_type
  attr_accessor :mau_cooling_type
  attr_accessor :chiller_type
  attr_accessor :heating_coil_type_sys2
  attr_accessor :heating_coil_type_sys3
  attr_accessor :heating_coil_type_sys4
  attr_accessor :heating_coil_type_sys6
  attr_accessor :necb_reference_hp
  attr_accessor :necb_reference_hp_supp_fuel
  attr_accessor :fan_type
  attr_accessor :ecm_fueltype
  attr_accessor :swh_fueltype
  attr_accessor :force_boiler
  attr_accessor :force_airloop_hot_water

  def set_defaults(standards_data:, primary_heating_fuel:)
    # Get fuelset.
    system_fuel_defaults = standards_data['fuel_type_sets'].detect { |fuel_type_set| fuel_type_set['name'] == primary_heating_fuel }
    raise("fuel_type_sets named #{primary_heating_fuel} not found in fuel_type_sets table.") if system_fuel_defaults.nil?
    # Assign fuel sources.
    @name = system_fuel_defaults['name']
    @boiler_fueltype = system_fuel_defaults['boiler_fueltype']
    @backup_boiler_fueltype = system_fuel_defaults['boiler_fueltype']
    @primary_boiler_cap_frac = nil
    @secondary_boiler_cap_frac = nil
    @baseboard_type = system_fuel_defaults['baseboard_type']
    @mau_type = system_fuel_defaults['mau_type']
    @mau_cooling_type = system_fuel_defaults['mau_cooling_type']
    @chiller_type = system_fuel_defaults['chiller_type']
    @mau_heating_coil_type = system_fuel_defaults['mau_heating_coil_type']
    @heating_coil_type_sys2 = system_fuel_defaults['heating_coil_type_sys2']
    @heating_coil_type_sys3 = system_fuel_defaults['heating_coil_type_sys3']
    @heating_coil_type_sys4 = system_fuel_defaults['heating_coil_type_sys4']
    @heating_coil_type_sys6 = system_fuel_defaults['heating_coil_type_sys6']
    @necb_reference_hp = system_fuel_defaults['necb_reference_hp']
    @necb_reference_hp_supp_fuel = system_fuel_defaults['necb_reference_hp_supp_fuel']
    @fan_type = system_fuel_defaults['fan_type']
    @swh_fueltype = system_fuel_defaults['swh_fueltype']
    @ecm_fueltype = system_fuel_defaults['ecm_fueltype']
    @force_boiler = false
    @force_airloop_hot_water = false
  end

  # Forces a boiler to be generated.  It searches boiler_fuel_type_sets.json for the boiler_fuel string and sets the
  # primary and backup boiler fuels to be whatever is boiler fuel type set.
  def set_boiler_fuel(standards_data:, boiler_fuel:, boiler_cap_ratios:)
    boiler_fuel_defaults = standards_data['boiler_fuel_type_sets'].detect { |fuel_type_set| fuel_type_set['name'] == boiler_fuel }
    @boiler_fueltype = boiler_fuel_defaults['boiler_fueltype']
    @primary_boiler_cap_frac = boiler_cap_ratios[:primary_ratio]
    @backup_boiler_fueltype = boiler_fuel_defaults['backup_boiler_fueltype']
    @secondary_boiler_cap_frac = boiler_cap_ratios[:secondary_ratio]
    @baseboard_type = boiler_fuel_defaults['baseboard_type']
    @heating_coil_type_sys6 = boiler_fuel_defaults['heating_coil_type_sys6']
    @force_boiler = true
  end

  # Reset the Service Hot Water fuel.
  def set_swh_fuel(swh_fuel:)
    @swh_fueltype = swh_fuel
  end

  #Forces heating_coils to be 'Hot Water' except when using HPs
  def set_airloop_fancoils_heating()
    @force_airloop_hot_water = true
    @mau_heating_coil_type = "Hot Water" unless @mau_heating_coil_type == 'DX'
    @heating_coil_type_sys2 = "Hot Water" unless @heating_coil_type_sys2 == 'DX'
    @heating_coil_type_sys3 = "Hot Water" unless @heating_coil_type_sys3 == 'DX'
    @heating_coil_type_sys4 = "Hot Water" unless @heating_coil_type_sys4 == 'DX'
    @heating_coil_type_sys6 = "Hot Water" unless @heating_coil_type_sys6 == 'DX'
    if @mau_heating_coil_type == 'DX' || @heating_coil_type_sys3 == 'DX' || @heating_coil_type_sys4 == 'DX' || @heating_coil_type_sys6 == 'DX' || @heating_coil_type_sys2 == 'DX'
      @necb_reference_hp_supp_fuel = 'Hot Water'
    end
  end

  # Reset system fuels to match parameters defined by hvac_system_primary
  def set_fuel_to_hvac_system_primary(hvac_system_primary:, standards_data:)
    hvac_system_data = standards_data['hvac_types'].find { |system| system['description'].to_s.downcase == hvac_system_primary.to_s.downcase }
    return if hvac_system_data.nil? || hvac_system_data.empty?
    @baseboard_type = hvac_system_data["baseboard_type"].to_s unless hvac_system_data["baseboard_type"].nil? || @force_boiler == true
    @mau_heating_coil_type = hvac_system_data["mau_heating_type"].to_s unless hvac_system_data["mau_heating_type"].nil? || @force_airloop_hot_water == true
    @mau_type = hvac_system_data["mau_type"].to_bool unless hvac_system_data["mau_type"].nil?
    @necb_reference_hp = hvac_system_data["necb_reference_hp"].to_bool unless hvac_system_data["necb_reference_hp"].nil?
    @necb_reference_hp_supp_fuel = hvac_system_data["necb_reference_hp_supp_fuel"] unless hvac_system_data["necb_reference_hp_supp_fuel"].nil? || @force_airloop_hot_water == true
    # If applying a hvac_system_primary with an NECB reference HP, make sure that the system 4 systems (if left at
    # NECB_Default) work with the NECB reference HP.
    if hvac_system_data["necb_reference_hp"].to_bool
      @heating_coil_type_sys4 = "DX"
    end
  end

  # Reset to default fuel info
  def reset_default_fuel_info(init_fuel_type:)
    @name = init_fuel_type[:name]
    @boiler_fueltype = init_fuel_type[:boiler_fueltype]
    @backup_boiler_fueltype = init_fuel_type[:backup_boiler_fueltype]
    @primary_boiler_cap_frac = init_fuel_type[:primary_boiler_cap_frac]
    @secondary_boiler_cap_frac = init_fuel_type[:secondary_boiler_cap_frac]
    @baseboard_type = init_fuel_type[:baseboard_type]
    @mau_type = init_fuel_type[:mau_type]
    @mau_heating_coil_type = init_fuel_type[:mau_heating_coil_type]
    @mau_cooling_type = init_fuel_type[:mau_cooling_type]
    @chiller_type = init_fuel_type[:chiller_type]
    @heating_coil_type_sys2 = init_fuel_type[:heating_coil_type_sys2]
    @heating_coil_type_sys3 = init_fuel_type[:heating_coil_type_sys3]
    @heating_coil_type_sys4 = init_fuel_type[:heating_coil_type_sys4]
    @heating_coil_type_sys6 = init_fuel_type[:heating_coil_type_sys6]
    @necb_reference_hp = init_fuel_type[:necb_reference_hp]
    @necb_reference_hp_supp_fuel = init_fuel_type[:necb_reference_hp_supp_fuel]
    @fan_type = init_fuel_type[:fan_type]
    @ecm_fueltype = init_fuel_type[:ecm_fueltype]
    @swh_fueltype = init_fuel_type[:swh_fueltype]
    @force_boiler = init_fuel_type[:force_boiler]
    @force_airloop_hot_water = init_fuel_type[:force_airloop_hot_water]
  end
end
