class DOERef1980to2004 < ASHRAE901
  # @!group AirConditionerVariableRefrigerantFlow

  # Finds lookup object in standards and return minimum thermal efficiency
  #
  # @param air_conditioner_variable_refrigerant_flow [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] vrf unit
  # @return [Boolean] returns true if successful, false if not
  def air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves(air_conditioner_variable_refrigerant_flow)
    OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{air_conditioner_variable_refrigerant_flow.name}, unable to set equipment efficiency, because VRF equipment and corresponding efficiency standards were not available in the time period 'DOE Ref 1980-2004'. Use a more recent 90.1 template to set efficiency standards for VRF equipment.")

    return false
  end
end
