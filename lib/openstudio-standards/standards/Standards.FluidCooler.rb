class Standard
  # @!group FluidCooler

  # Set the fluid cooler fan power such that the tower
  # hits the minimum performance (gpm/hp) specified by the standard.
  # Note that in this case hp is motor nameplate hp, per 90.1.
  # This method assumes that the fan brake horsepower is 90%
  # of the motor nameplate hp.
  # This method determines the minimum motor efficiency
  # for the nameplate motor hp and sets the actual
  # fan power by multiplying the brake horsepower
  # by the efficiency.  Thus the fan power used as
  # an input to the simulation divided by the design flow
  # rate will not (and should not)
  # exactly equal the minimum tower performance.
  #
  # @param fluid_cooler [OpenStudio::Model::FluidCoolerSingleSpeed,
  #   OpenStudio::Model::FluidCoolerTwoSpeed,
  #   OpenStudio::Model::EvaporativeFluidCoolerSingleSpeed,
  #   OpenStudio::Model::EvaporativeFluidCoolerTwoSpeed] the fluid cooler
  # @param equipment_type [String] heat rejection equipment type enumeration used for lookup query,
  #   options are 'Closed Cooling Tower', modeled as an EvaporativeFluidCooler,
  #   or 'Dry Cooler', modeled as a FluidCooler
  # @return [Boolean] returns true if successful, false if not
  def fluid_cooler_apply_minimum_power_per_flow(fluid_cooler, equipment_type: 'Closed Cooling Tower')
    # Get the design water flow rate
    if fluid_cooler.designWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = fluid_cooler.designWaterFlowRate.get
    elsif fluid_cooler.autosizedDesignWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = fluid_cooler.autosizedDesignWaterFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FluidCooler', "For #{fluid_cooler.name} design water flow rate is not available, cannot apply efficiency standard.")
      return false
    end
    design_water_flow_gpm = OpenStudio.convert(design_water_flow_m3_per_s, 'm^3/s', 'gal/min').get

    # Get the table of fluid cooler efficiencies
    heat_rejection = standards_data['heat_rejection']

    # Define the criteria to find the fluid cooler properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template

    # Closed cooling towers are fluidcooler objects.
    search_criteria['equipment_type'] = equipment_type

    # @todo Standards replace this with a mechanism to store this
    # data in the fluid cooler object itself.
    # For now, retrieve the fan type from the name
    name = fluid_cooler.name.get
    if name.include?('Centrifugal')
      fan_type = 'Centrifugal'
    elsif name.include?('Propeller or Axial')
      fan_type = 'Propeller or Axial'
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FluidCooler', "Cannot find fan type for #{fluid_cooler.name}. Assuming propeller or axial.")
      fan_type = 'Propeller or Axial'
    end
    unless fan_type.nil?
      search_criteria['fan_type'] = fan_type
    end

    # Get the fluid cooler properties
    ct_props = model_find_object(heat_rejection, search_criteria)
    unless ct_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FluidCooler', "For #{fluid_cooler.name}, cannot find heat rejection properties, cannot apply standard efficiencies or curves.")
      return false
    end

    # Get fluid cooler efficiency
    min_gpm_per_hp = ct_props['minimum_performance_gpm_per_hp']
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FluidCooler', "For #{fluid_cooler.name}, design water flow = #{design_water_flow_gpm.round} gpm, minimum performance = #{min_gpm_per_hp} gpm/hp (nameplate).")

    # Calculate the allowed fan brake horsepower
    # per method used in PNNL prototype buildings.
    # Assumes that the fan brake horsepower is 90%
    # of the fan nameplate rated motor power.
    # Source: Thornton et al. (2011), Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010, Section 4.5.4
    nominal_hp = design_water_flow_gpm / min_gpm_per_hp
    fan_bhp = 0.9 * nominal_hp
    fan_motor_eff = 0.85

    if nominal_hp <= 0.75
      motor_type = motor_type(nominal_hp)
      motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type = motor_type)
    else
      # Lookup the minimum motor efficiency
      motors = standards_data['motors']

      # Assuming all fan motors are 4-pole Enclosed
      search_criteria = {
        'template' => template,
        'number_of_poles' => 4.0,
        'type' => 'Enclosed'
      }

      # Use the efficiency largest motor efficiency when BHP is greater than the largest size for which a requirement is provided
      data = model_find_objects(motors, search_criteria)
      if data.empty?
        search_criteria = {
          'template' => template,
          'type' => nil
        }
        data = model_find_objects(motors, search_criteria)
      end
      maximum_capacity = model_find_maximum_value(data, 'maximum_capacity')
      if fan_bhp > maximum_capacity
        fan_bhp = maximum_capacity
      end

      motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = Date.today, area = nil, num_floors = nil, fan_motor_bhp = fan_bhp)
      if motor_properties.nil?
        # Retry without the date
        motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = fan_bhp)
      end
    end

    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.FluidCooler', "For #{fluid_cooler.name}, could not find motor properties using search criteria: #{search_criteria}, motor_hp = #{norminal_hp} hp. Using a default value of #{fan_motor_eff}.")
    end

    unless motor_properties.nil?
      fan_motor_eff = motor_properties['nominal_full_load_efficiency']
      nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    end
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    # Calculate the fan motor power
    fan_motor_actual_power_hp = fan_bhp / fan_motor_eff
    # Convert to W
    fan_motor_actual_power_w = fan_motor_actual_power_hp * 745.7 # 745.7 W/HP

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FluidCooler', "For #{fluid_cooler.name}, allowed fan motor nameplate hp = #{nominal_hp.round(1)} hp, fan brake horsepower = #{fan_bhp.round(1)}, and fan motor actual power = #{fan_motor_actual_power_hp.round(1)} hp (#{fan_motor_actual_power_w.round} W) at #{fan_motor_eff} motor efficiency.")

    # Append the efficiency to the name
    fluid_cooler.setName("#{fluid_cooler.name} #{min_gpm_per_hp.to_f.round(1)} gpm/hp")

    # Hard size the design fan power.
    # Leave the water flow and air flow autosized.
    if fluid_cooler.to_FluidCoolerSingleSpeed.is_initialized
      fluid_cooler.setDesignAirFlowRateFanPower(fan_motor_actual_power_w)
    elsif fluid_cooler.to_FluidCoolerTwoSpeed.is_initialized || fluid_cooler.to_EvaporativeFluidCoolerTwoSpeed.is_initialized
      fluid_cooler.setHighFanSpeedFanPower(fan_motor_actual_power_w)
      fluid_cooler.setLowFanSpeedFanPower(0.3 * fan_motor_actual_power_w)
    elsif fluid_cooler.to_EvaporativeFluidCoolerSingleSpeed.is_initialized
      fluid_cooler.setFanPoweratDesignAirFlowRate(fan_motor_actual_power_w)
    end

    return true
  end
end
