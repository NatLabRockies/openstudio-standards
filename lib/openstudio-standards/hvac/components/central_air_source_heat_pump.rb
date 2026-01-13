module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:CentralAirSourceHeatPump
    # Methods to create central air source heat pumps

    # Create CentralAirSourceHeatPump object using PlantComponentUserDefined
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param hot_water_loop [<OpenStudio::Model::PlantLoop>] a hot water loop served by the central air source heat pump
    # @param name [String] the name of the central air source heat pump, or nil in which case it will be defaulted
    # @param cop [Double] air source heat pump rated cop
    # @return [OpenStudio::Model::PlantComponentUserDefined] a plant component representing the air source heat pump
    # @todo update curve to better calculate based on the rated cop
    # @todo refactor to use the new EnergyPlus central air source heat pump object when it becomes available
    #   set hot_water_loop to an optional keyword argument, and add input keyword arguments for other characteristics
    def self.create_central_air_source_heat_pump(model,
                                                 hot_water_loop,
                                                 name: nil,
                                                 cop: 3.65)

      # create the PlantComponentUserDefined object as a proxy for the Central Air Source Heat Pump
      plant_comp = OpenStudio::Model::PlantComponentUserDefined.new(model)
      if name.nil?
        if hot_water_loop.nil?
          name = 'Central Air Source Heat Pump'
        else
          name = "#{hot_water_loop.name} Central Air Source Heat Pump"
        end
      end

      # change equipment name for EMS validity
      plant_comp.setName(OpenstudioStandards::HVAC.ems_friendly_name(name))

      # set plant component properties
      plant_comp.setPlantLoadingMode('MeetsLoadWithNominalCapacityHiOutLimit')
      plant_comp.setPlantLoopFlowRequestMode('NeedsFlowIfLoopOn')

      # plant design volume flow rate internal variable
      vdot_des_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Plant Design Volume Flow Rate')
      vdot_des_int_var.setName("#{plant_comp.name}_Vdot_Des_Int_Var")
      vdot_des_int_var.setInternalDataIndexKeyName(hot_water_loop.handle.to_s)

      # inlet temperature internal variable
      tin_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Inlet Temperature for Plant Connection 1')
      tin_int_var.setName("#{plant_comp.name}_Tin_Int_Var")
      tin_int_var.setInternalDataIndexKeyName(plant_comp.handle.to_s)

      # inlet mass flow rate internal variable
      mdot_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Inlet Mass Flow Rate for Plant Connection 1')
      mdot_int_var.setName("#{plant_comp.name}_Mdot_Int_Var")
      mdot_int_var.setInternalDataIndexKeyName(plant_comp.handle.to_s)

      # inlet specific heat internal variable
      cp_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Inlet Specific Heat for Plant Connection 1')
      cp_int_var.setName("#{plant_comp.name}_Cp_Int_Var")
      cp_int_var.setInternalDataIndexKeyName(plant_comp.handle.to_s)

      # inlet density internal variable
      rho_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Inlet Density for Plant Connection 1')
      rho_int_var.setName("#{plant_comp.name}_rho_Int_Var")
      rho_int_var.setInternalDataIndexKeyName(plant_comp.handle.to_s)

      # load request internal variable
      load_int_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Load Request for Plant Connection 1')
      load_int_var.setName("#{plant_comp.name}_Load_Int_Var")
      load_int_var.setInternalDataIndexKeyName(plant_comp.handle.to_s)

      # supply outlet node setpoint temperature sensor
      setpt_mgr_sch_sen = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
      setpt_mgr_sch_sen.setName("#{plant_comp.name}_Setpt_Mgr_Temp_Sen")
      hot_water_loop.supplyOutletNode.setpointManagers.each do |m|
        if m.to_SetpointManagerScheduled.is_initialized
          setpt_mgr_sch_sen.setKeyName(m.to_SetpointManagerScheduled.get.schedule.name.to_s)
        end
      end

      # outdoor air drybulb temperature sensor
      oa_dbt_sen = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Site Outdoor Air Drybulb Temperature')
      oa_dbt_sen.setName("#{plant_comp.name}_OA_DBT_Sen")
      oa_dbt_sen.setKeyName('Environment')

      # minimum mass flow rate actuator
      mdot_min_act = plant_comp.minimumMassFlowRateActuator.get
      mdot_min_act.setName("#{plant_comp.name}_Mdot_Min_Act")

      # maximum mass flow rate actuator
      mdot_max_act = plant_comp.maximumMassFlowRateActuator.get
      mdot_max_act.setName("#{plant_comp.name}_Mdot_Max_Act")

      # design flow rate actuator
      vdot_des_act = plant_comp.designVolumeFlowRateActuator.get
      vdot_des_act.setName("#{plant_comp.name}_Vdot_Des_Act")

      # minimum loading capacity actuator
      cap_min_act = plant_comp.minimumLoadingCapacityActuator.get
      cap_min_act.setName("#{plant_comp.name}_Cap_Min_Act")

      # maximum loading capacity actuator
      cap_max_act = plant_comp.maximumLoadingCapacityActuator.get
      cap_max_act.setName("#{plant_comp.name}_Cap_Max_Act")

      # optimal loading capacity actuator
      cap_opt_act = plant_comp.optimalLoadingCapacityActuator.get
      cap_opt_act.setName("#{plant_comp.name}_Cap_Opt_Act")

      # outlet temperature actuator
      tout_act = plant_comp.outletTemperatureActuator.get
      tout_act.setName("#{plant_comp.name}_Tout_Act")

      # mass flow rate actuator
      mdot_req_act = plant_comp.massFlowRateActuator.get
      mdot_req_act.setName("#{plant_comp.name}_Mdot_Req_Act")

      # heat pump COP curve
      constant_coeff = 1.932 + (cop - 3.65)
      hp_cop_curve = OpenStudio::Model::CurveQuadratic.new(model)
      hp_cop_curve.setCoefficient1Constant(constant_coeff)
      hp_cop_curve.setCoefficient2x(0.227674286)
      hp_cop_curve.setCoefficient3xPOW2(-0.007313143)
      hp_cop_curve.setMinimumValueofx(1.67)
      hp_cop_curve.setMaximumValueofx(12.78)
      hp_cop_curve.setInputUnitTypeforX('Temperature')
      hp_cop_curve.setOutputUnitType('Dimensionless')

      # heat pump COP curve index variable
      hp_cop_curve_idx_var = OpenStudio::Model::EnergyManagementSystemCurveOrTableIndexVariable.new(model, hp_cop_curve)

      # high outlet temperature limit actuator
      tout_max_act = OpenStudio::Model::EnergyManagementSystemActuator.new(plant_comp, 'Plant Connection 1', 'High Outlet Temperature Limit')
      tout_max_act.setName("#{plant_comp.name}_Tout_Max_Act")

      # init program
      init_pgrm = plant_comp.plantInitializationProgram.get
      init_pgrm.setName("#{plant_comp.name}_Init_Pgrm")
      init_pgrm_body = <<-EMS
      SET Loop_Exit_Temp = #{hot_water_loop.sizingPlant.designLoopExitTemperature}
      SET Loop_Delta_Temp = #{hot_water_loop.sizingPlant.loopDesignTemperatureDifference}
      SET Cp = @CPHW Loop_Exit_Temp
      SET rho = @RhoH2O Loop_Exit_Temp
      SET #{vdot_des_act.handle} = #{vdot_des_int_var.handle}
      SET #{mdot_min_act.handle} = 0
      SET Mdot_Max = #{vdot_des_int_var.handle} * rho
      SET #{mdot_max_act.handle} = Mdot_Max
      SET Cap = Mdot_Max * Cp * Loop_Delta_Temp
      SET #{cap_min_act.handle} = 0
      SET #{cap_max_act.handle} = Cap
      SET #{cap_opt_act.handle} = 1 * Cap
      EMS
      init_pgrm.setBody(init_pgrm_body)

      # sim program
      sim_pgrm = plant_comp.plantSimulationProgram.get
      sim_pgrm.setName("#{plant_comp.name}_Sim_Pgrm")
      sim_pgrm_body = <<-EMS
      SET tmp = #{load_int_var.handle}
      SET tmp = #{tin_int_var.handle}
      SET tmp = #{mdot_int_var.handle}
      SET #{tout_max_act.handle} = 75.0
      IF #{load_int_var.handle} == 0
      SET #{tout_act.handle} = #{tin_int_var.handle}
      SET #{mdot_req_act.handle} = 0
      SET Elec = 0
      RETURN
      ENDIF
      IF #{load_int_var.handle} >= #{cap_max_act.handle}
      SET Qdot = #{cap_max_act.handle}
      SET Mdot = #{mdot_max_act.handle}
      SET #{mdot_req_act.handle} = Mdot
      SET #{tout_act.handle} = (Qdot / (Mdot * #{cp_int_var.handle})) + #{tin_int_var.handle}
      IF #{tout_act.handle} > #{tout_max_act.handle}
      SET #{tout_act.handle} = #{tout_max_act.handle}
      SET Qdot = Mdot * #{cp_int_var.handle} * (#{tout_act.handle} - #{tin_int_var.handle})
      ENDIF
      ELSE
      SET Qdot = #{load_int_var.handle}
      SET #{tout_act.handle} = #{setpt_mgr_sch_sen.handle}
      SET Mdot = Qdot / (#{cp_int_var.handle} * (#{tout_act.handle} - #{tin_int_var.handle}))
      SET #{mdot_req_act.handle} = Mdot
      ENDIF
      SET Tdb = #{oa_dbt_sen.handle}
      SET COP = @CurveValue #{hp_cop_curve_idx_var.handle} Tdb
      SET EIR = 1 / COP
      SET Pwr = Qdot * EIR
      SET Elec = Pwr * SystemTimestep * 3600
      EMS
      sim_pgrm.setBody(sim_pgrm_body)

      # init program calling manager
      init_mgr = plant_comp.plantInitializationProgramCallingManager.get
      init_mgr.setName("#{plant_comp.name}_Init_Pgrm_Mgr")

      # sim program calling manager
      sim_mgr = plant_comp.plantSimulationProgramCallingManager.get
      sim_mgr.setName("#{plant_comp.name}_Sim_Pgrm_Mgr")

      # metered output variable
      elec_mtr_out_var = OpenStudio::Model::EnergyManagementSystemMeteredOutputVariable.new(model, "#{plant_comp.name} Electricity Consumption")
      elec_mtr_out_var.setName("#{plant_comp.name} Electricity Consumption")
      elec_mtr_out_var.setEMSVariableName('Elec')
      elec_mtr_out_var.setUpdateFrequency('SystemTimestep')
      elec_mtr_out_var.setString(4, sim_pgrm.handle.to_s)
      elec_mtr_out_var.setResourceType('Electricity')
      elec_mtr_out_var.setGroupType('HVAC')
      elec_mtr_out_var.setEndUseCategory('Heating')
      elec_mtr_out_var.setEndUseSubcategory('')
      elec_mtr_out_var.setUnits('J')

      # add to supply side of hot water loop if specified
      hot_water_loop&.addSupplyBranchForComponent(plant_comp)

      # add operation scheme
      htg_op_scheme = OpenStudio::Model::PlantEquipmentOperationHeatingLoad.new(model)
      htg_op_scheme.addEquipment(1000000000.0, plant_comp)
      hot_water_loop.setPlantEquipmentOperationHeatingLoad(htg_op_scheme)

      return plant_comp
    end
  end
end
