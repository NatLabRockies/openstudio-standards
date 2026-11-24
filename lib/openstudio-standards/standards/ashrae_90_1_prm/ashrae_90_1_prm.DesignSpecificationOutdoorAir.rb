class ASHRAE901PRM < Standard
  # @!group DesignSpecification:OutdoorAir
  # Sets the rules on outdoor air specifications on spaces / spaceType

  # Function applies user specified OA to the model
  # @param model [OpenStudio::Model::Model] model object
  # @return [Boolean] returns true if successful, false if not
  def model_apply_userdata_outdoor_air(model)
    # Step 1: Create a hash that maps design_spec_oa to a list of spaces
    # Also create a map that maps each design_spec_oa name to design_spec_oa.
    oa_spec_to_spaces = {}
    oa_spec_hash = {}
    model.getSpaces.each do |space|
      oa_spec = space.designSpecificationOutdoorAir
      if oa_spec.is_initialized
        oa_spec = oa_spec.get
        oa_spec_name = oa_spec.name.get
        unless oa_spec_to_spaces.key?(oa_spec_name)
          # init oa_spec_name associate zone name list.
          oa_spec_to_spaces[oa_spec_name] = []
        end
        unless oa_spec_hash.key?(oa_spec_name)
          # init the map of oa_spec_name to oa_spec object
          oa_spec_hash[oa_spec_name] = oa_spec
        end
        oa_spec_to_spaces[oa_spec_name].push(space)
      end
    end

    # Step 2: Loop the hash (oa_spec_name -> space_lists)
    oa_spec_to_spaces.each do |oa_spec_name, space_list|
      design_spec_oa = oa_spec_hash[oa_spec_name]
      if design_spec_oa.additionalProperties.hasFeature('has_user_data')
        outdoor_air_method = design_spec_oa.outdoorAirMethod

        outdoor_airflow_per_person = get_additional_property_as_double(design_spec_oa, 'outdoor_airflow_per_person')
        outdoor_airflow_per_floor_area = get_additional_property_as_double(design_spec_oa, 'outdoor_airflow_per_floor_area')
        outdoor_air_flowrate = get_additional_property_as_double(design_spec_oa, 'outdoor_air_flowrate')
        outdoor_air_flow_air_changes_per_hour = get_additional_property_as_double(design_spec_oa, 'outdoor_air_flow_air_changes_per_hour')

        # Area SQL - TabularDataWithStrings -> InputVerificationResultsSummary -> Entire Facility -> Zone Summary -> Zone Name -> Area
        total_modeled_area_oa = 0.0 # m2
        total_user_area_oa = 0.0 # m2
        total_modeled_people_oa = 0.0 # m3/s-person
        total_user_people_oa = 0.0 # m3/s-person
        total_modeled_airflow_oa = 0.0 # m3/s
        total_user_airflow_oa = 0.0 # m3/s
        total_modeled_ach_oa = 0.0 # ach
        total_user_ach_oa = 0.0 # ach
        space_list.each do |space|
          floor_area = space.floorArea
          volume = space.volume
          number_people = space.numberOfPeople
          total_modeled_area_oa += floor_area * design_spec_oa.outdoorAirFlowperFloorArea
          total_user_area_oa += floor_area * outdoor_airflow_per_floor_area

          total_modeled_people_oa += number_people * design_spec_oa.outdoorAirFlowperPerson
          total_user_people_oa += number_people * outdoor_airflow_per_person

          total_modeled_airflow_oa += design_spec_oa.outdoorAirFlowRate
          total_user_airflow_oa += outdoor_air_flowrate
          # convert to m3/s -> ach * volume / 3600
          total_modeled_ach_oa += design_spec_oa.outdoorAirFlowAirChangesperHour * volume / 3600
          total_user_ach_oa += outdoor_air_flow_air_changes_per_hour * volume / 3600
        end

        # calculate the amount of total outdoor air
        if outdoor_air_method.casecmp('sum') == 0
          total_modeled_airflow = total_modeled_area_oa + total_modeled_people_oa + total_modeled_airflow_oa + total_modeled_ach_oa
          total_user_airflow = total_user_area_oa + total_user_people_oa + total_user_airflow_oa + total_user_ach_oa
        elsif outdoor_air_method.casecmp('maximum') == 0
          total_modeled_airflow = [total_modeled_area_oa, total_modeled_people_oa, total_modeled_airflow_oa, total_modeled_ach_oa].max
          total_user_airflow = [total_user_area_oa, total_user_people_oa, total_user_airflow_oa, total_user_ach_oa].max
        else
          # No outdoor air method specified or match to the options available in OpenStudio
          # Raise exception to flag the modeling error
          error_msg = "DesignSpecification:OutdoorAir: #{design_spec_oa.name.get} is missing a method or the method is not one of the options {'Maximum', 'Sum'}."
          OpenStudio.logFree(OpenStudio::Warn, 'prm.log', error_msg)
          prm_raise(false,
                    @sizing_run_dir,
                    error_msg)
        end

        if total_modeled_airflow < total_user_airflow
          # Do not modify the model outdoor air if the total user airflow is lower than total modeled airflow
          OpenStudio.logFree(OpenStudio::Warn, 'prm.log', "The calculated total airflow for DesignSpecification:OutdoorAir is #{total_modeled_airflow} m3/s, which is smaller than the calculated user total airflow #{total_user_airflow} m3/s. Skip modifying the Outdoor Air.")
        else
          # set values.
          design_spec_oa.setOutdoorAirFlowperFloorArea(outdoor_airflow_per_floor_area)
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Update DesignSpecification:OutdoorAir #{oa_spec_name} Outdoor Air Flow Per Floor Area to #{outdoor_airflow_per_floor_area} m3/s-m2.")
          design_spec_oa.setOutdoorAirFlowperPerson(outdoor_airflow_per_person)
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Update DesignSpecification:OutdoorAir #{oa_spec_name} Outdoor Air Flow Per Person to #{outdoor_airflow_per_person} m3/s-person.")
          design_spec_oa.setOutdoorAirFlowRate(outdoor_air_flowrate)
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Update DesignSpecification:OutdoorAir #{oa_spec_name} Outdoor Air Flow Rate to #{outdoor_air_flowrate} m3/s.")
          design_spec_oa.setOutdoorAirFlowAirChangesperHour(outdoor_air_flow_air_changes_per_hour)
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Update DesignSpecification:OutdoorAir #{oa_spec_name} Outdoor Air ACH to #{outdoor_air_flow_air_changes_per_hour}.")
        end
      end
    end
  end
end
