class BTAPCosting

  def cost_audit_dcv(model:, prototype_creator:)
    @costing_report['ventilation'][:demand_controlled_ventilation] = []
    a = 0.0 # This is for reporting purposes.

    ##### Initialize cost of various parts of DCV
    dcv_cost_zone_occupancy = 0.0
    dcv_cost_zone_co2 = 0.0
    dcv_cost_box = 0.0
    dcv_cost_vertical_conduit = 0.0
    dcv_cost_roof = 0.0
    dcv_cost_control = 0.0
    dcv_cost_total = 0.0

    ##### Get number of stories and nominal floor to floor height.
    ##### These inputs are required for the calculation of the length of conduit for each AirLoopHVAC.
    util_dist, ht_roof, nominal_flr2flr_height_ft, horizontal_dist, standards_number_of_stories, mechRmInBsmt = getGeometryData(model, prototype_creator)
    nominal_flr2flr_height_m = (OpenStudio.convert(nominal_flr2flr_height_ft, 'ft', 'm').get)

    number_of_dcv_controller_for_all_air_loops = 0

    model.getAirLoopHVACs.sort.each do |air_loop|
      number_of_thermal_zones_served_by_air_loop = 0
      number_floors_served_by_air_loop = 0
      number_of_junction_boxes_for_air_loop = 0

      ##### Step A: Calculate number of thermal zones and floors served by each AirLoopHVAC (air_loop)
      building_story_list = []
      air_loop.thermalZones.sort.each do |thermal_zone|
        thermal_zone.spaces().sort.each do |space|
          building_story_list << space.buildingStory.get.name()
        end
        number_of_thermal_zones_served_by_air_loop += thermal_zone.multiplier()
      end
      building_story_list = building_story_list.uniq()
      number_floors_served_by_air_loop = building_story_list.length

      ##### Loop through AirLoopHVAC's supply nodes to:
      ##### (1) Find its AirLoopHVAC:OutdoorAirSystem using the supply node;
      ##### (2) Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem;
      ##### (3) Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
      air_loop.supplyComponents.sort.each do |supply_component|
        ##### Find AirLoopHVAC:OutdoorAirSystem of AirLoopHVAC using the supply node.
        hvac_component = supply_component.to_AirLoopHVACOutdoorAirSystem

        if !hvac_component.empty?

          tags = ['ventilation', 'demand_controlled_ventilation']

          ##### Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem.
          hvac_component = hvac_component.get
          hvac_component_name = hvac_component.name()
          controller_outdoorair = hvac_component.getControllerOutdoorAir
          controller_outdoorair_name = controller_outdoorair.name()

          ##### Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
          controller_mechanical_ventilation = controller_outdoorair.controllerMechanicalVentilation
          controller_mechanical_ventilation_name = controller_mechanical_ventilation.name()

          ##### Check if "Demand Controlled Ventilation" is "Yes" in Controller:MechanicalVentilation depending on dcv_type.
          controller_mechanical_ventilation_demand_controlled_ventilation_status = controller_mechanical_ventilation.demandControlledVentilation

          controller_mechanical_ventilation_system_outdoor_air_method = controller_mechanical_ventilation.systemOutdoorAirMethod()
          if controller_mechanical_ventilation_demand_controlled_ventilation_status == true && (controller_mechanical_ventilation_system_outdoor_air_method == 'ZoneSum' || controller_mechanical_ventilation_system_outdoor_air_method == 'IndoorAirQualityProcedure')

            ##### Step B: Calculate costs of the installation of a single junction box for each floor within that AirLoopHVAC (air_loop) to accumulate the wiring
            quantity_ahu_floors_junction_box = 1.0 * number_floors_served_by_air_loop
            search_ahu_floors_junction_box = {
                row_id_1: 'Ea',
                row_id_2: 14
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            dcv_cost_box = assembly_cost(cost_info:search_ahu_floors_junction_box,
                                         sheet_name:sheet_name,
                                         column_1:column_1,
                                         column_2:column_2,
                                         quantity:quantity_ahu_floors_junction_box,
                                         tags: tags)

            ##### Step C: Calculate costs of the installation of a single conduit that runs the entire height of the building for each AirLoopHVAC to accumulate the wiring
            quantity_ahu_vertical_wiring = 1.0/100.0 * standards_number_of_stories * nominal_flr2flr_height_ft
            search_ahu_vertical_wiring = {
                row_id_1: 'CLF',
                row_id_2: 10
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            cost_ahu_vertical_wiring = assembly_cost(cost_info:search_ahu_vertical_wiring,
                                                     sheet_name:sheet_name,
                                                     column_1:column_1,
                                                     column_2:column_2,
                                                     quantity:quantity_ahu_vertical_wiring,
                                                     tags: tags)
            quantity_ahu_vertical_conduit = 1.0 * standards_number_of_stories * nominal_flr2flr_height_ft
            search_ahu_vertical_conduit = {
                row_id_1: 'LF',
                row_id_2: 13
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            cost_ahu_vertical_conduit = assembly_cost(cost_info:search_ahu_vertical_conduit,
                                                      sheet_name:sheet_name,
                                                      column_1:column_1,
                                                      column_2:column_2,
                                                      quantity:quantity_ahu_vertical_conduit,
                                                      tags: tags)
            dcv_cost_vertical_conduit = cost_ahu_vertical_wiring + cost_ahu_vertical_conduit

            ##### Step D: Calculate the roof conduit and wiring for each AirLoopHVAC.
            quantity_ahu_roof_wiring = 20.0/100.0
            search_ahu_roof_wiring = {
                row_id_1: 'CLF',
                row_id_2: 10
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            cost_ahu_roof_wiring = assembly_cost(cost_info:search_ahu_roof_wiring,
                                                 sheet_name:sheet_name,
                                                 column_1:column_1,
                                                 column_2:column_2,
                                                 quantity:quantity_ahu_roof_wiring,
                                                 tags: tags)
            quantity_ahu_roof_conduit = 20.0
            search_ahu_roof_conduit = {
                row_id_1: 'LF',
                row_id_2: 13
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            cost_ahu_roof_conduit = assembly_cost(cost_info:search_ahu_roof_conduit,
                                                  sheet_name:sheet_name,
                                                  column_1:column_1,
                                                  column_2:column_2,
                                                  quantity:quantity_ahu_roof_conduit,
                                                  tags: tags)
            quantity_ahu_roof_junction_box = 1.0
            search_ahu_roof_junction_box = {
                row_id_1: 'Ea',
                row_id_2: 14
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            cost_ahu_roof_junction_box = assembly_cost(cost_info:search_ahu_roof_junction_box,
                                                       sheet_name:sheet_name,
                                                       column_1:column_1,
                                                       column_2:column_2,
                                                       quantity:quantity_ahu_roof_junction_box,
                                                       tags: tags)
            dcv_cost_roof = cost_ahu_roof_wiring + cost_ahu_roof_conduit + cost_ahu_roof_junction_box

            ##### Step E: Calculate DCV controller for each AirLoopHVAC.
            number_of_dcv_controller_for_all_air_loops += 1
            quantity_ahu_contorller = 1.0
            search_ahu_contorller = {
                row_id_1: 'Ea',
                row_id_2: 400
            }
            sheet_name = 'materials_lighting'
            column_1 = 'unit'
            column_2 = 'lighting_type_id'
            dcv_cost_control = assembly_cost(cost_info:search_ahu_contorller,
                                             sheet_name:sheet_name,
                                             column_1:column_1,
                                             column_2:column_2,
                                             quantity:quantity_ahu_contorller,
                                             tags: tags)

            if controller_mechanical_ventilation_system_outdoor_air_method == 'ZoneSum'
              ##### Step F: Calculate total Cost for each AirLoopHVAC
              # Calculate occupancy sensor-related costs of each thermal zone served by each AirLoopHVAC (air_loop)
              quantity_tz_occupancy_sensor = 1.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_occupancy_sensor = {
                  row_id_1: 'Ea',
                  row_id_2: 404
              }
              sheet_name = 'materials_lighting'
              column_1 = 'unit'
              column_2 = 'lighting_type_id'
              cost_tz_occupancy_sensor = assembly_cost(cost_info:search_tz_occupancy_sensor,
                                                       sheet_name:sheet_name,
                                                       column_1:column_1,
                                                       column_2:column_2,
                                                       quantity:quantity_tz_occupancy_sensor,
                                                       tags: tags)
              quantity_tz_occupancy_sensor_wiring = 30.0/100.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_occupancy_sensor_wiring = {
                  row_id_1: 'CLF',
                  row_id_2: 10
              }
              sheet_name = 'materials_lighting'
              column_1 = 'unit'
              column_2 = 'lighting_type_id'
              cost_tz_occupancy_sensor_wiring = assembly_cost(cost_info:search_tz_occupancy_sensor_wiring,
                                                              sheet_name:sheet_name,
                                                              column_1:column_1,
                                                              column_2:column_2,
                                                              quantity:quantity_tz_occupancy_sensor_wiring,
                                                              tags: tags)
              quantity_tz_occupancy_sensor_pvc_conduit = 30.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_occupancy_sensor_pvc_conduit = {
                  row_id_1: 'LF',
                  row_id_2: 17
              }
              sheet_name = 'materials_lighting'
              column_1 = 'unit'
              column_2 = 'lighting_type_id'
              cost_tz_occupancy_sensor_pvc_conduit = assembly_cost(cost_info:search_tz_occupancy_sensor_pvc_conduit,
                                                                   sheet_name:sheet_name,
                                                                   column_1:column_1,
                                                                   column_2:column_2,
                                                                   quantity:quantity_tz_occupancy_sensor_pvc_conduit,
                                                                   tags: tags)
              dcv_cost_zone_occupancy = cost_tz_occupancy_sensor + cost_tz_occupancy_sensor_wiring + cost_tz_occupancy_sensor_pvc_conduit
              dcv_cost_total += dcv_cost_zone_occupancy + dcv_cost_box + dcv_cost_vertical_conduit + dcv_cost_roof + dcv_cost_control
              total_cost_for_air_loop = dcv_cost_zone_occupancy + dcv_cost_box + dcv_cost_vertical_conduit + dcv_cost_roof + dcv_cost_control
            elsif controller_mechanical_ventilation_system_outdoor_air_method == 'IndoorAirQualityProcedure'
              ##### Step F: Calculate total Cost for each AirLoopHVAC
              # Calculate CO2 sensor-related costs of each thermal zone served by each AirLoopHVAC (air_loop)
              quantity_tz_co2_sensor = 1.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_co2_sensor = {
                  row_id_1: nil,
                  row_id_2: 1316
              }
              sheet_name = 'materials_hvac'
              column_1 = nil
              column_2 = 'material_id'
              cost_tz_co2_sensor = assembly_cost(cost_info:search_tz_co2_sensor,
                                                 sheet_name:sheet_name,
                                                 column_1:column_1,
                                                 column_2:column_2,
                                                 quantity:quantity_tz_co2_sensor,
                                                 tags: tags)
              quantity_tz_co2_sensor_wiring = 30.0/100.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_co2_sensor_wiring = {
                  row_id_1: 'CLF',
                  row_id_2: 10
              }
              sheet_name = 'materials_lighting'
              column_1 = 'unit'
              column_2 = 'lighting_type_id'
              cost_tz_co2_sensor_wiring = assembly_cost(cost_info:search_tz_co2_sensor_wiring,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity:quantity_tz_co2_sensor_wiring,
                                                        tags: tags)
              quantity_tz_co2_sensor_pvc_conduit = 30.0 * number_of_thermal_zones_served_by_air_loop.to_f
              search_tz_co2_sensor_pvc_conduit = {
                  row_id_1: 'LF',
                  row_id_2: 17
              }
              sheet_name = 'materials_lighting'
              column_1 = 'unit'
              column_2 = 'lighting_type_id'
              cost_tz_co2_sensor_pvc_conduit = assembly_cost(cost_info:search_tz_co2_sensor_pvc_conduit,
                                                             sheet_name:sheet_name,
                                                             column_1:column_1,
                                                             column_2:column_2,
                                                             quantity:quantity_tz_co2_sensor_pvc_conduit,
                                                             tags: tags)
              dcv_cost_zone_co2 = cost_tz_co2_sensor + cost_tz_co2_sensor_wiring + cost_tz_co2_sensor_pvc_conduit
              dcv_cost_total += dcv_cost_zone_co2 + dcv_cost_box + dcv_cost_vertical_conduit + dcv_cost_roof + dcv_cost_control
              total_cost_for_air_loop = dcv_cost_zone_co2 + dcv_cost_box + dcv_cost_vertical_conduit + dcv_cost_roof + dcv_cost_control
            end

            ##### Gather information for reporting
            @costing_report['ventilation'][:demand_controlled_ventilation] << {
                air_loop_name: air_loop.name().to_s,
                controller_Outdoor_air: controller_outdoorair_name.to_s,
                controller_mechanical_ventilation_name: controller_mechanical_ventilation_name.to_s,
                controller_mechanical_ventilation_demand_controlled_ventilation_status: controller_mechanical_ventilation_demand_controlled_ventilation_status.to_s,
                controller_mechanical_ventilation_system_outdoor_air_method: controller_mechanical_ventilation_system_outdoor_air_method.to_s,
                number_of_floors_served_by_air_loop: number_floors_served_by_air_loop.to_f,
                number_of_thermal_zones_served_by_air_loop: number_of_thermal_zones_served_by_air_loop.to_f,
                number_of_junction_boxes_for_air_loop: number_floors_served_by_air_loop.to_f,
                total_cost_for_air_loop: total_cost_for_air_loop.to_f.round(2)
            }
            a += 1.0

          end

              # puts dcv_cost_total

        end #if !hvac_component.empty?

      end #air_loop.supplyComponents.each do |supply_component|

    end #model.getAirLoopHVACs.each do |air_loop|

    if a > 0.0
      ###### Gather information for reporting
      @costing_report['ventilation'][:demand_controlled_ventilation] << {
          standards_number_of_building_stories: standards_number_of_stories.to_f,
          nominal_floor_to_floor_height: nominal_flr2flr_height_m.to_f.round(2),
          total_cost_for_all_dcvs: dcv_cost_total.to_f.round(2)
      }
    end


    puts "\nDemand-controlled ventilation costing data successfully generated. Total DCV costs: $#{dcv_cost_total.round(2)}"

    return dcv_cost_total
  end #cost_audit_dcv(model, prototype_creator)


end
