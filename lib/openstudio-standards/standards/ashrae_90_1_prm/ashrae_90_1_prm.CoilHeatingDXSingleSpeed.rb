class ASHRAE901PRM < Standard
  # @!group CoilHeatingDXSingleSpeed

  include ASHRAEPRMCoilDX

  # Finds capacity in W. This is the cooling capacity of the paired DX cooling coil.
  #
  # @param coil_heating_dx_single_speed [OpenStudio::Model::CoilHeatingDXSingleSpeed] coil heating dx single speed object
  # @param sys_type [String] HVAC system type
  # @return [Double] capacity in W to be used for find object
  def coil_heating_dx_single_speed_find_capacity(coil_heating_dx_single_speed, sys_type)
    capacity_w = nil

    # Get the paired cooling coil
    clg_coil = nil

    # Unitary and zone equipment
    if coil_heating_dx_single_speed.airLoopHVAC.empty?
      if coil_heating_dx_single_speed.containingHVACComponent.is_initialized
        containing_comp = coil_heating_dx_single_speed.containingHVACComponent.get
        if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
          clg_coil = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.get.coolingCoil
        elsif containing_comp.to_AirLoopHVACUnitarySystem.is_initialized
          unitary = containing_comp.to_AirLoopHVACUnitarySystem.get
          if unitary.coolingCoil.is_initialized
            clg_coil = unitary.coolingCoil.get
          end
        end
      elsif coil_heating_dx_single_speed.containingZoneHVACComponent.is_initialized
        containing_comp = coil_heating_dx_single_speed.containingZoneHVACComponent.get
        # PTHP
        if containing_comp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
          pthp = containing_comp.to_ZoneHVACPackagedTerminalHeatPump.get
          clg_coil = containing_comp.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil
        end
      end
    end

    # On AirLoop directly
    if coil_heating_dx_single_speed.airLoopHVAC.is_initialized
      air_loop = coil_heating_dx_single_speed.airLoopHVAC.get
      # Check for the presence of any other type of cooling coil
      clg_types = ['OS:Coil:Cooling:DX:SingleSpeed',
                   'OS:Coil:Cooling:DX:TwoSpeed']
      clg_types.each do |ct|
        coils = air_loop.supplyComponents(ct.to_IddObjectType)
        next if coils.empty?

        clg_coil = coils[0]
        break # Stop on first DX cooling coil found
      end
    end

    # If no paired cooling coil was found, throw an error and fall back to the heating capacity of the DX heating coil
    if clg_coil.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, the paired DX cooling coil could not be found to determine capacity. Efficiency will incorrectly be based on DX coil's heating capacity.")
      if coil_heating_dx_single_speed.ratedTotalHeatingCapacity.is_initialized
        capacity_w = coil_heating_dx_single_speed.ratedTotalHeatingCapacity.get
      elsif coil_heating_dx_single_speed.autosizedRatedTotalHeatingCapacity.is_initialized
        capacity_w = coil_heating_dx_single_speed.autosizedRatedTotalHeatingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name} capacity is not available, cannot apply efficiency standard to paired DX heating coil.")
        return 0.0
      end
      return capacity_w
    end

    # find properties
    multiplier = coil_dx_number_of_systems(clg_coil, sys_type)

    # If a coil was found, cast to the correct type
    if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      clg_coil = clg_coil.to_CoilCoolingDXSingleSpeed.get
      capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(clg_coil, multiplier: multiplier)
    elsif clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      clg_coil = clg_coil.to_CoilCoolingDXTwoSpeed.get
      capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_two_speed_get_capacity(clg_coil, multiplier: multiplier)
    end

    # Check for user data that indicates multiple systems per thermal zone
    # This could be true for a data center where this is common practice
    # Or it could be for a thermal zone that represents multiple real building zones
    mult = 1
    thermal_zone = nil
    comp = coil_heating_dx_single_speed.containingHVACComponent
    if comp.is_initialized && comp.get.to_AirLoopHVACUnitarySystem.is_initialized
      unitary = comp.get.to_AirLoopHVACUnitarySystem.get
      thermal_zone = unitary.controllingZoneorThermostatLocation.get
    end
    # meth = comp.methods
    comp = coil_heating_dx_single_speed.containingZoneHVACComponent
    if comp.is_initialized && comp.get.thermalZone.is_initialized
      thermal_zone = comp.get.thermalZone.get
    end

    if !thermal_zone.nil? && standards_data.key?('userdata_thermal_zone')
      standards_data['userdata_thermal_zone'].each do |row|
        next unless row['name'].to_s.downcase.strip == thermal_zone.name.to_s.downcase.strip

        if row['number_of_systems'].to_s.upcase.strip != ''
          mult = row['number_of_systems'].to_s
          if mult.to_i.to_s == mult
            mult = mult.to_i
            capacity_w /= mult
          else
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', 'In userdata_thermalzone, number_of_systems requires integer input.')
          end
          break
        end
      end
    end

    # If it's a PTAC or PTHP System, we need to divide the capacity by the potential zone multiplier
    # because the COP is dependent on capacity, and the capacity should be the capacity of a single zone, not all the zones
    if sys_type == 'PTHP'
      mult = 1
      comp = coil_heating_dx_single_speed.containingZoneHVACComponent
      if comp.is_initialized && comp.get.thermalZone.is_initialized
        mult = comp.get.thermalZone.get.multiplier
        if mult > 1
          total_cap = capacity_w
          capacity_w /= mult
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{mult} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
        end
      end
    end

    return capacity_w
  end

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_heating_dx_single_speed [OpenStudio::Model::CoilHeatingDXSingleSpeed] coil heating dx single speed object
  # @param sys_type [String] HVAC system type
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @return [Double] full load efficiency (COP)
  def coil_heating_dx_single_speed_standard_minimum_cop(coil_heating_dx_single_speed, sys_type, rename = false)
    # find ac properties
    capacity_w = coil_heating_dx_single_speed_find_capacity(coil_heating_dx_single_speed, sys_type)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    search_criteria = coil_dx_find_search_criteria(coil_heating_dx_single_speed, capacity_btu_per_hr, sys_type)
    if sys_type == 'PSZ-HP' && capacity_btu_per_hr > 65000
      search_criteria['rating_condition'] = '47F db/43F wb outdoor air'
    end

    # Get the minimum efficiency standards
    hp_props = nil
    cop = nil
    hp_props = model_find_object(standards_data['heat_pumps_heating'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if hp_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return false
    end

    cop = hp_props['minimum_coefficient_of_performance_no_fan_heating']
    new_comp_name = "#{coil_heating_dx_single_speed.name} #{capacity_btu_per_hr.round}Btu/hr #{cop}COP"

    # Rename
    if rename
      coil_heating_dx_single_speed.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_heating_dx_single_speed [OpenStudio::Model::CoilHeatingDXSingleSpeed] coil heating dx single speed object
  # @param sql_db_vars_map [Hash] hash map
  # @param sys_type [String] HVAC system type
  # @return [Hash] hash of coil objects
  def coil_heating_dx_single_speed_apply_efficiency_and_curves(coil_heating_dx_single_speed, sql_db_vars_map, sys_type)
    # Preserve the original name
    orig_name = coil_heating_dx_single_speed.name.to_s

    # Find the minimum COP and rename with efficiency rating
    cop = coil_heating_dx_single_speed_standard_minimum_cop(coil_heating_dx_single_speed, sys_type, false)

    # Map the original name to the new name
    sql_db_vars_map[coil_heating_dx_single_speed.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_heating_dx_single_speed.setRatedCOP(cop)
    end

    return sql_db_vars_map
  end
end
