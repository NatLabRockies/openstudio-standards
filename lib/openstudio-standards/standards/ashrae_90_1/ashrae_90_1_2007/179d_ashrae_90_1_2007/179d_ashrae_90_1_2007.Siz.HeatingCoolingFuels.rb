class OpenStudio::Model::Model
  # NOTE: 179D SQUASHES it because we want to correctly determine the fuel type
  # used by the central air source heat pump that is modeled as a PlantComponentUserDefined
  # via openstudio-standards/lib/openstudio-standards/prototypes/common/objects/Prototype.CentralAirSourceHeatPump.rb
  # Overriding is **NOT** possible in this case because this is a method that
  # is patched onto OpenStudio::Model::Model and not in the Standard class
  # But this is **SAFE** because we're just adding a `when` case
  # (I can't patch it at openstudio-standards/lib/openstudio-standards/hvac_sizing/Siz.HeatingCoolingFuels.rb
  # because we do NOT want to have to pull the openstudio-standards gem from
  # github as it is way too large)

  # Get the heating fuel type of a plant loop
  # @todo If no heating equipment is found, check if there's a heat exchanger,
  # or a WaterHeater:Mixed or stratified that is connected to a heating source on the demand side
  def plant_loop_heating_fuels(plant_loop)
    fuels = []
    # Get the heating fuels for all supply components
    # on this plant loop.
    plant_loop.supplyComponents.each do |component|
       # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_Boiler_HotWater'
        component = component.to_BoilerHotWater.get
        fuels << component.fuelType
      when 'OS_Boiler_Steam'
        component = component.to_BoilerHotWater.get
        fuels << component.fuelType
      when 'OS_DistrictHeating'
        fuels << 'DistrictHeating'
      when 'OS_HeatPump_WaterToWater_EquationFit_Heating'
        fuels << 'Electricity'
      when 'OS_SolarCollector_FlatPlate_PhotovoltaicThermal'
        fuels << 'SolarEnergy'
      when 'OS_SolarCollector_FlatPlate_Water'
        fuels << 'SolarEnergy'
      when 'OS_SolarCollector_IntegralCollectorStorage'
        fuels << 'SolarEnergy'
      when 'OS_WaterHeater_HeatPump'
        fuels << 'Electricity'
      when 'OS_WaterHeater_Mixed'
        component = component.to_WaterHeaterMixed.get

        # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
        if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
          # If it does, we add the heater Fuel Type
          fuels << component.heaterFuelType
        end
        # @todo not sure about whether it should be an elsif or not
        # Check the plant loop connection on the source side
        if component.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(component.secondaryPlantLoop.get)
        end
      when 'OS_WaterHeater_Stratified'
        component = component.to_WaterHeaterStratified.get

        # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
        if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
          # If it does, we add the heater Fuel Type
          fuels << component.heaterFuelType
        end
        # @todo not sure about whether it should be an elsif or not
        # Check the plant loop connection on the source side
        if component.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(component.secondaryPlantLoop.get)
        end
      when 'OS_HeatExchanger_FluidToFluid'
        hx = component.to_HeatExchangerFluidToFluid.get
        cooling_hx_control_types = ['CoolingSetpointModulated', 'CoolingSetpointOnOff', 'CoolingDifferentialOnOff', 'CoolingSetpointOnOffWithComponentOverride']
        cooling_hx_control_types.each {|x| x.downcase!}
        if !cooling_hx_control_types.include?(hx.controlType.downcase) && hx.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(hx.secondaryPlantLoop.get)
        end
      # NOTE: begin 179D addition
      when 'OS_PlantComponent_UserDefined'
        # I could just assume 'Electricity' here too
        plant_comp = component.to_PlantComponentUserDefined.get
        if plant_comp.plantSimulationProgram.is_initialized
          heating_cats = [
            'heating', 'heatingcoils', 'boilers', 'baseboard',
            'heatrecoveryforheating', 'onsitegeneration'
          ]
          sim_pgrm = plant_comp.plantSimulationProgram.get
          sources = sim_pgrm.getSources('OS_EnergyManagementSystem_MeteredOutputVariable'.to_IddObjectType)
          sources.each do |s|
            ems_metered_var = s.to_EnergyManagementSystemMeteredOutputVariable.get
            if heating_cats.include?(ems_metered_var.endUseCategory.downcase)
              fuel_string = ems_metered_var.resourceType
              begin
                fuels << OpenStudio::FuelType.new(fuel_string).valueDescription
              rescue
                OpenStudio::logFree(OpenStudio::Warn, 'openstudio.sizing.Model', "Could not determine what fuel type '#{fuel_string}' is in EMS:MeteredOutputVariable '#{ems_metered_var.nameString}' for PlantComponentUserDefined '#{plant_comp.nameString}'")
              end
            end
          end
        end
        # NOTE: end 179D addition
      when 'OS_Node', 'OS_Pump_ConstantSpeed', 'OS_Pump_VariableSpeed', 'OS_Connector_Splitter', 'OS_Connector_Mixer', 'OS_Pipe_Adiabatic'
        # To avoid extraneous debug messages
      else
        #OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort

  end
end
