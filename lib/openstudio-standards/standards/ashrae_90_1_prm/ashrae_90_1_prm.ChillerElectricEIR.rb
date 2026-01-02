class ASHRAE901PRM < Standard
  # @!group ChillerElectricEIR

  # Applies the standard efficiency ratings to this object.
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @return [Boolean] returns true if successful, false if not
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir)
    # Get the chiller capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get

    # Set the efficiency value
    cop = chiller_electric_eir_standard_minimum_full_load_efficiency(chiller_electric_eir)
    unless cop
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      return false
    end
    chiller_electric_eir.setReferenceCOP(cop)

    # Append the name with size and kw/ton
    kw_per_ton = OpenstudioStandards::HVAC.cop_to_kw_per_ton(cop)
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(1)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(1)}kW/ton)")

    return true
  end
end
