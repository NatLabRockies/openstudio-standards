class CBES < Standard
  # @!group elevators

  # Add an elevator the the specified space
  #
  # @param space [OpenStudio::Model::Space] the space to assign the elevators to.
  # @param number_of_elevators [Integer] the number of elevators
  # @param elevator_type [String] valid choices are Traction, Hydraulic
  # @param elevator_schedule [String] the name of the elevator schedule
  # @param elevator_fan_schedule [String] the name of the elevator fan schedule
  # @param elevator_lights_schedule [String] the name of the elevator lights schedule
  # @param building_type [String] the building type
  # @return [OpenStudio::Model::ElectricEquipment] the resulting elevator
  # @todo Inconsistency.  Older vintages don't have lights or fans in elevators, which is not realistic.
  def model_add_elevator(model,
                         space,
                         number_of_elevators,
                         elevator_type,
                         elevator_schedule,
                         elevator_fan_schedule,
                         elevator_lights_schedule,
                         building_type = nil)
    # Lift motor assumptions
    lift_pwr_w = model_elevator_lift_power(model, elevator_type, building_type)

    # Size assumptions
    length_ft = 6.66
    width_ft = 4.25
    height_ft = 8.0
    area_ft2 = length_ft * width_ft
    volume_ft3 = area_ft2 * height_ft

    # Ventilation assumptions
    vent_rate_acm = 1 # air changes per minute
    vent_rate_cfm = volume_ft3 / vent_rate_acm
    vent_pwr_w = model_elevator_fan_pwr(model, vent_rate_cfm)

    # Heating fraction radiant assumptions
    elec_equip_frac_radiant = 0.5

    # Lighting assumptions
    design_ltg_lm_per_ft2 = 30
    light_loss_factor = 0.75
    pct_incandescent = model_elevator_lighting_pct_incandescent(model)
    pct_led = 1.0 - pct_incandescent

    incandescent_efficacy_lm_per_w = 10.0
    led_efficacy_lm_per_w = 35.0
    target_ltg_lm_per_ft2 = design_ltg_lm_per_ft2 / light_loss_factor # 40
    target_ltg_lm = target_ltg_lm_per_ft2 * area_ft2 # 1132.2
    lm_incandescent = target_ltg_lm * pct_incandescent # 792.54
    lm_led = target_ltg_lm * pct_led # 339.66
    w_incandescent = lm_incandescent / incandescent_efficacy_lm_per_w # 79.254
    w_led = lm_led / led_efficacy_lm_per_w # 9.7
    lighting_pwr_w = w_incandescent + w_led

    # Elevator lift motor
    elevator_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_definition.setName('Elevator Lift Motor')
    elevator_definition.setDesignLevel(lift_pwr_w)
    elevator_definition.setFractionRadiant(elec_equip_frac_radiant)

    elevator_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_definition)
    elevator_equipment.setName("#{number_of_elevators.round} Elevator Lift Motors")
    elevator_equipment.setEndUseSubcategory('Elevators')
    elevator_sch = model_add_schedule(model, elevator_schedule)
    elevator_equipment.setSchedule(elevator_sch)
    elevator_equipment.setSpace(space)
    elevator_equipment.setMultiplier(number_of_elevators)

    return elevator_equipment
  end

  # Determines the power required by an individual elevator
  # of a given type.  Values used by the older vintages
  # are slightly higher than those used by the DOE prototypes.
  # @param elevator_type [String] valid choices are
  # Traction, Hydraulic
  def model_elevator_lift_power(model, elevator_type, building_type)
    lift_pwr_w = 0
    if elevator_type == 'Traction'
      lift_pwr_w = 18_537.0
    elsif elevator_type == 'Hydraulic'
      lift_pwr_w = if building_type == 'MidriseApartment'
                     16_055.0
                   else
                     14_610.0
                   end
    else
      lift_pwr_w = 14_610.0
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Elevator type '#{elevator_type}', not recognized, will assume Hydraulic elevator, #{lift_pwr_w} W.")
    end

    return lift_pwr_w
  end
end
