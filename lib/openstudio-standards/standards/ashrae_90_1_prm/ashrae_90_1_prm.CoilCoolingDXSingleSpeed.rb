class ASHRAE901PRM < Standard
  # @!group CoilCoolingDXSingleSpeed

  include ASHRAEPRMCoilDX

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param sys_type [String] HVAC system type
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @return [Double] full load efficiency (COP)
  def coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, sys_type, rename = false)
    # find properties
    multiplier = coil_dx_number_of_systems(coil_cooling_dx_single_speed, sys_type)
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_single_speed, capacity_btu_per_hr, sys_type)

    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    eff_key = 'minimum_coefficient_of_performance_no_fan_cooling'
    if sys_type == 'PSZ_HP' || sys_type == 'PTHP'
      ac_props = model_find_object(standards_data['heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)
    else
      ac_props = model_find_object(standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)
    end

    # Get the minimum efficiency standards
    cop = nil

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return cop # value of nil
    end

    cop = ac_props[eff_key]
    new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_btu_per_hr.round}Btu/hr #{cop}COP"

    # Rename
    if rename
      coil_cooling_dx_single_speed.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings to this object.
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param sql_db_vars_map [Hash] hash map
  # @param sys_type [String] HVAC system type
  # @return [Hash] hash of coil objects
  def coil_cooling_dx_single_speed_apply_efficiency_and_curves(coil_cooling_dx_single_speed, sql_db_vars_map, sys_type)
    # Preserve the original name
    orig_name = coil_cooling_dx_single_speed.name.to_s

    # Find the minimum COP and rename with efficiency rating
    # Set last argument to false to avoid renaming coil, since that complicates lookup of HP heating coil efficiency later
    cop = coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, sys_type, false)

    # Map the original name to the new name
    sql_db_vars_map[coil_cooling_dx_single_speed.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_cooling_dx_single_speed.setRatedCOP(OpenStudio::OptionalDouble.new(cop))
    end

    return sql_db_vars_map
  end
end
