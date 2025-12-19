class BTAPCosting

  def cost_audit_nv(model:, prototype_creator:)
    @costing_report['ventilation'][:natural_ventilation] = []
    #TODO: expected results file will be updated once labour cost for zn controller, sensor, and usb are updated in costing database

    nv_total_cost = 0.0
    nv_total_cost_tz = 0.0
    nv_total_cost_ahu = 0.0

    nv_airloop_vertical_conduit_hash = {}
    nv_airloop_vertical_conduit_wiring_hash = {}
    nv_airloop_vertical_conduit_box_hash = {}
    nv_airloop_roof_conduit_hash = {}
    nv_airloop_roof_wiring_hash = {}
    nv_airloop_roof_box_hash = {}
    nv_airloop_controller_hash = {}

    #-----------------------------------------------------------------------------------------------------------------
    ##### Get number of stories and nominal floor to floor height.
    ##### These inputs are required for the calculation of the length of conduit for each AirLoopHVAC
    ##### if any thermal zone served by that AirLoopHVAC has the potential for NV.
    util_dist, ht_roof, nominal_flr2flr_height_ft, horizontal_dist, standards_number_of_stories, mechRmInBsmt = getGeometryData(model, prototype_creator)

    #-----------------------------------------------------------------------------------------------------------------
    ##### Find which airloop serves the thermal zone
    thermal_zones_airloop_hash = {}
    model.getAirLoopHVACs.sort.each do |air_loop|
      # puts air_loop.name().to_s
      air_loop.thermalZones.sort.each do |thermal_zone|
        # puts thermal_zone.name().to_s
        thermal_zones_airloop_hash[thermal_zone.name.to_s] = air_loop.name.to_s
      end
    end
    # puts "thermal_zones_airloop_hash is #{thermal_zones_airloop_hash}"

    #-----------------------------------------------------------------------------------------------------------------
    ##### Loop through ZoneHVACEquipmentLists to see which thermal zone(s) has(have) been set to use NV where applicable.
    model.getZoneHVACEquipmentLists.sort.each do |zone_hvac_equipment_list|
      # puts "zone_hvac_equipment_list.name  is #{zone_hvac_equipment_list.name}"

      nv_exist = 0.0 #this variable is to check the thermal zone has been set to use NV where applicable. (1.0: NV is allowed; 0.0: NV is not allowed)

      ### Loop through ZoneHVACEquipmentLists to see which thermal zone(s) has(have) ZoneVentilationWindandStackOpenArea
      hvac_equipment = zone_hvac_equipment_list.equipment
      for i in 0..hvac_equipment.length()
        unless hvac_equipment[i].nil?
          if hvac_equipment[i].to_ZoneVentilationWindandStackOpenArea.is_initialized
            nv_exist = 1.0 #this means that the thermal zone has NV.
          end
        end
      end
      # puts "Is NV allowed? #{nv_exist}"

      ### Loop through thermal zone's spaces to count how many spaces of them have windows to exterior
      if nv_exist == 1.0
        tags = ['ventilation', 'natural_ventilation']
        thermal_zone = zone_hvac_equipment_list.thermalZone
        thermal_zone_name = thermal_zone.name
        thermal_zone_multiplier = thermal_zone.multiplier()
        # puts "thermal_zone_name is #{thermal_zone.name}"

        ##### Find which airloop serves the thermal zone
        thermal_zone_sys = thermal_zones_airloop_hash[thermal_zone_name.to_s]
        # puts "thermal_zone_sys is #{thermal_zone_sys}"

        if !thermal_zone_sys.nil?

          ################################################## Step I: costing for each thermal zone ############################################################
          ##### costing for each thermal zone:  natural ventilation controller -------------------------------------------------------------------------------------------------------------------
          quantity_tz_nv_controller = 1.0 * thermal_zone_multiplier
          # puts "quantity_tz_nv_controller is #{quantity_tz_nv_controller}"
          search_tz_nv_controller = {
              row_id_1: 'nat_vent_control',
              row_id_2: 1537
          }
          sheet_name = 'materials_hvac'
          column_1 = 'Material'
          column_2 = 'material_id'
          nv_costing_tz_nv_controller = assembly_cost(cost_info:search_tz_nv_controller,
                                                      sheet_name:sheet_name,
                                                      column_1:column_1,
                                                      column_2:column_2,
                                                      quantity: quantity_tz_nv_controller,
                                                      tags: tags)
          # puts "quantity_tz_nv_controller is #{quantity_tz_nv_controller}"
          # puts "nv_costing_tz_nv_controller is #{nv_costing_tz_nv_controller}"

          ##### costing for each thermal zone: natural ventilation sensor -------------------------------------------------------------------------------------------------------------------
          quantity_tz_nv_sensor = 1.0 * thermal_zone_multiplier
          search_tz_nv_sensor = {
              row_id_1: 'nat_vent_sensor',
              row_id_2: 1538
          }
          sheet_name = 'materials_hvac'
          column_1 = 'Material'
          column_2 = 'material_id'
          nv_costing_tz_nv_sensor = assembly_cost(cost_info:search_tz_nv_sensor,
                                                  sheet_name:sheet_name,
                                                  column_1:column_1,
                                                  column_2:column_2,
                                                  quantity: quantity_tz_nv_sensor,
                                                  tags: tags)
          # puts "quantity_tz_nv_sensor is #{quantity_tz_nv_sensor}"
          # puts "nv_costing_tz_nv_sensor is #{nv_costing_tz_nv_sensor}"

          ##### costing for each thermal zone: natural ventilation USB -------------------------------------------------------------------------------------------------------------------
          quantity_tz_nv_usb = 1.0 * thermal_zone_multiplier
          search_tz_nv_usb = {
              row_id_1: 'nat_vent_usb',
              row_id_2: 1539
          }
          sheet_name = 'materials_hvac'
          column_1 = 'Material'
          column_2 = 'material_id'
          nv_costing_tz_nv_usb = assembly_cost(cost_info:search_tz_nv_usb,
                                               sheet_name:sheet_name,
                                               column_1:column_1,
                                               column_2:column_2,
                                               quantity: quantity_tz_nv_usb,
                                               tags: tags)
          # puts "quantity_tz_nv_usb is #{quantity_tz_nv_usb}"
          # puts "nv_costing_tz_nv_usb is #{nv_costing_tz_nv_usb}"

          ##### costing for each thermal zone: Tin_sensor_wiring -------------------------------------------------------------------------------------------------------------------
          # Note: assuming distance of 30 ft to each thermal zone per floor
          # for each outdoor sensor (Tout and wind speed) and
          # Tin sensor to the natural ventilation controller,
          # total wiring is 90 ft in below equation.
          quantity_tz_Tin_sensor_wiring = (90.0/100.0) * thermal_zone_multiplier #unit: CLF (hundred linear feet)
          search_tz_Tin_sensor_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_Tin_sensor_wiring = assembly_cost(cost_info:search_tz_Tin_sensor_wiring,
                                                          sheet_name:sheet_name,
                                                          column_1:column_1,
                                                          column_2:column_2,
                                                          quantity: quantity_tz_Tin_sensor_wiring,
                                                          tags: tags)
          # puts "quantity_tz_Tin_sensor_wiring is #{quantity_tz_Tin_sensor_wiring}"
          # puts "nv_costing_tz_Tin_sensor_wiring is #{nv_costing_tz_Tin_sensor_wiring}"

          ##### costing for each thermal zone: PVC_conduit -------------------------------------------------------------------------------------------------------------------
          quantity_tz_Tin_sensor_conduit = 2.0 * 30.0 * thermal_zone_multiplier #unit: LF (linear feet)
          search_tz_Tin_sensor_conduit = {
              row_id_1: 'LF',
              row_id_2: 17
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_Tin_sensor_conduit = assembly_cost(cost_info:search_tz_Tin_sensor_conduit,
                                                           sheet_name:sheet_name,
                                                           column_1:column_1,
                                                           column_2:column_2,
                                                           quantity: quantity_tz_Tin_sensor_conduit,
                                                           tags: tags)
          # puts "quantity_tz_Tin_sensor_conduit is #{quantity_tz_Tin_sensor_conduit}"
          # puts "nv_costing_tz_Tin_sensor_conduit is #{nv_costing_tz_Tin_sensor_conduit}"

          ##### costing for each thermal zone: junction box -------------------------------------------------------------------------------------------------------------------
          quantity_tz_Tin_sensor_box = 1.0 * thermal_zone_multiplier #unit: Ea
          search_tz_Tin_sensor_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_Tin_sensor_box = assembly_cost(cost_info:search_tz_Tin_sensor_box,
                                                       sheet_name:sheet_name,
                                                       column_1:column_1,
                                                       column_2:column_2,
                                                       quantity: quantity_tz_Tin_sensor_box,
                                                       tags: tags)
          # puts "quantity_tz_Tin_sensor_box is #{quantity_tz_Tin_sensor_box}"
          # puts "nv_costing_tz_Tin_sensor_box is #{nv_costing_tz_Tin_sensor_box}"

          ##### costing for each thermal zone: duct_damper_motor -------------------------------------------------------------------------------------------------------------------
          # calculate how many dampers are needed, depending on the system type
          nv_a = ['sys_1', 'sys_2', 'sys_3', 'sys_4', 'sys_5', 'sys_7']
          nv_b = ['sys_6']
          nv_c = thermal_zone_sys
          if nv_a.any? { |s| nv_c.include? s}
            damper_mult = 1.0
          elsif nv_b.any? { |s| nv_c.include? s}
            damper_mult = 2.0
          end
          # puts "damper_mult is #{damper_mult}"

          quantity_tz_duct_damper_motor = 1.0 * damper_mult * thermal_zone_multiplier #unit: Ea
          search_tz_duct_damper_motor = {
              row_id_1: 'duct_damper_motor',
              row_id_2: 6
          }
          sheet_name = 'materials_hvac'
          column_1 = 'Material'
          column_2 = 'Size'
          nv_costing_tz_duct_damper_motor = assembly_cost(cost_info:search_tz_duct_damper_motor,
                                                          sheet_name:sheet_name,
                                                          column_1:column_1,
                                                          column_2:column_2,
                                                          quantity: quantity_tz_duct_damper_motor,
                                                          tags: tags)
          # puts "quantity_tz_duct_damper_motor is #{quantity_tz_duct_damper_motor}"
          # puts "nv_costing_tz_duct_damper_motor is #{nv_costing_tz_duct_damper_motor}"

          ##### costing for each thermal zone: duct_damper_wiring -------------------------------------------------------------------------------------------------------------------
          quantity_tz_duct_damper_wiring = (30.0/100.0) * damper_mult * thermal_zone_multiplier #unit: CLF
          search_tz_duct_damper_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_duct_damper_wiring = assembly_cost(cost_info:search_tz_duct_damper_wiring,
                                                           sheet_name:sheet_name,
                                                           column_1:column_1,
                                                           column_2:column_2,
                                                           quantity: quantity_tz_duct_damper_wiring,
                                                           tags: tags)
          # puts "quantity_tz_duct_damper_wiring is #{quantity_tz_duct_damper_wiring}"
          # puts "nv_costing_tz_duct_damper_wiring is #{nv_costing_tz_duct_damper_wiring}"

          ##### costing for each thermal zone: duct_damper_conduit -------------------------------------------------------------------------------------------------------------------
          quantity_tz_duct_damper_conduit = 30.0 * damper_mult * thermal_zone_multiplier #unit: CLF
          search_tz_duct_damper_conduit = {
              row_id_1: 'LF',
              row_id_2: 17
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_duct_damper_conduit = assembly_cost(cost_info:search_tz_duct_damper_conduit,
                                                            sheet_name:sheet_name,
                                                            column_1:column_1,
                                                            column_2:column_2,
                                                            quantity: quantity_tz_duct_damper_conduit,
                                                            tags: tags)
          # puts "quantity_tz_duct_damper_conduit is #{quantity_tz_duct_damper_conduit}"
          # puts "nv_costing_tz_duct_damper_conduit is #{nv_costing_tz_duct_damper_conduit}"

          ##### costing for each thermal zone: duct_damper_box -------------------------------------------------------------------------------------------------------------------
          quantity_tz_duct_damper_box = 1.0 * damper_mult * thermal_zone_multiplier #unit: CLF
          search_tz_duct_damper_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          nv_costing_tz_duct_damper_box = assembly_cost(cost_info:search_tz_duct_damper_box,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity: quantity_tz_duct_damper_box,
                                                        tags: tags)
          # puts "quantity_tz_duct_damper_box is #{quantity_tz_duct_damper_box}"
          # puts "nv_costing_tz_duct_damper_box is #{nv_costing_tz_duct_damper_box}"

          ################################################## Step II: costing for each AirLoopHVAC - Vertical Conduit ############################################################
          ##### Note: This is completed twice for each AirLoopHVAC:
          # (1) for the wiring and conduit to the rooftop AHU
          # (2) for the wiring and conduit to the rooftop outdoor air temperature and wind speed sensors
          ##### costing for each AirLoopHVAC-VerticalConduit: a single conduit runs the entire height of the building -------------------------------------------------------------------------------------------------------------------
          quantity_nv_vertical_conduit = 2.0 * nominal_flr2flr_height_ft * standards_number_of_stories
          search_nv_vertical_conduit = {
              row_id_1: 'LF',
              row_id_2: 13
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_vertical_conduit_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_vertical_conduit = assembly_cost(cost_info:search_nv_vertical_conduit,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity: quantity_nv_vertical_conduit,
                                                        tags: tags)
            nv_airloop_vertical_conduit_hash[thermal_zone_sys.to_s] = nv_costing_vertical_conduit
          else
            nv_costing_vertical_conduit = 0.0
          end
          # puts "quantity_nv_vertical_conduit is #{quantity_nv_vertical_conduit}"
          # puts "nv_costing_vertical_conduit is #{nv_costing_vertical_conduit}"

          ##### costing for each AirLoopHVAC-VerticalConduit: wiring -------------------------------------------------------------------------------------------------------------------
          quantity_nv_vertical_conduit_wiring = 2.0 * nominal_flr2flr_height_ft * standards_number_of_stories / 100.0
          search_nv_vertical_conduit_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_vertical_conduit_wiring_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_vertical_conduit_wiring = assembly_cost(cost_info:search_nv_vertical_conduit_wiring,
                                                               sheet_name:sheet_name,
                                                               column_1:column_1,
                                                               column_2:column_2,
                                                               quantity: quantity_nv_vertical_conduit_wiring,
                                                               tags: tags)
            nv_airloop_vertical_conduit_wiring_hash[thermal_zone_sys.to_s] = nv_costing_vertical_conduit_wiring
          else
            nv_costing_vertical_conduit_wiring = 0.0
          end
          # puts "quantity_nv_vertical_conduit_wiring is #{quantity_nv_vertical_conduit_wiring}"
          # puts "nv_costing_vertical_conduit_wiring is #{nv_costing_vertical_conduit_wiring}"

          ##### costing for each AirLoopHVAC-VerticalConduit: box -------------------------------------------------------------------------------------------------------------------
          quantity_nv_vertical_conduit_box = 2.0 * standards_number_of_stories
          search_nv_vertical_conduit_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_vertical_conduit_box_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_vertical_conduit_box = assembly_cost(cost_info:search_nv_vertical_conduit_box,
                                                            sheet_name:sheet_name,
                                                            column_1:column_1,
                                                            column_2:column_2,
                                                            quantity: quantity_nv_vertical_conduit_box,
                                                            tags: tags)
            nv_airloop_vertical_conduit_box_hash[thermal_zone_sys.to_s] = nv_costing_vertical_conduit_box
          else
            nv_costing_vertical_conduit_box = 0.0
          end
          # puts "quantity_nv_vertical_conduit_box is #{quantity_nv_vertical_conduit_box}"
          # puts "nv_costing_vertical_conduit_box is #{nv_costing_vertical_conduit_box}"

          ################################################## Step III: costing for each AirLoopHVAC - Roof  ############################################################
          ##### costing for each AirLoopHVAC-Roof: conduit -------------------------------------------------------------------------------------------------------------------
          quantity_nv_roof_conduit = 20.0
          search_nv_roof_conduit = {
              row_id_1: 'LF',
              row_id_2: 13
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_roof_conduit_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_roof_conduit = assembly_cost(cost_info:search_nv_roof_conduit,
                                                    sheet_name:sheet_name,
                                                    column_1:column_1,
                                                    column_2:column_2,
                                                    quantity: quantity_nv_roof_conduit,
                                                    tags: tags)
            nv_airloop_roof_conduit_hash[thermal_zone_sys.to_s] = nv_costing_roof_conduit
          else
            nv_costing_roof_conduit = 0.0
          end
          # puts "quantity_nv_roof_conduit is #{quantity_nv_roof_conduit}"
          # puts "nv_costing_roof_conduit is #{nv_costing_roof_conduit}"

          ##### costing for each AirLoopHVAC-Roof: wiring -------------------------------------------------------------------------------------------------------------------
          quantity_nv_roof_wiring = 20.0 / 100.0
          search_nv_roof_wiring = {
              row_id_1: 'CLF',
              row_id_2: 10
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_roof_wiring_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_roof_wiring = assembly_cost(cost_info:search_nv_roof_wiring,
                                                   sheet_name:sheet_name,
                                                   column_1:column_1,
                                                   column_2:column_2,
                                                   quantity: quantity_nv_roof_wiring,
                                                   tags: tags)
            nv_airloop_roof_wiring_hash[thermal_zone_sys.to_s] = nv_costing_roof_wiring
          else
            nv_costing_roof_wiring = 0.0
          end
          # puts "quantity_nv_roof_wiring is #{quantity_nv_roof_wiring}"
          # puts "nv_costing_roof_wiring is #{nv_costing_roof_wiring}"

          ##### costing for each AirLoopHVAC-Roof: box -------------------------------------------------------------------------------------------------------------------
          quantity_nv_roof_box = 1.0
          search_nv_roof_box = {
              row_id_1: 'Ea',
              row_id_2: 14
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_roof_box_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_roof_box = assembly_cost(cost_info:search_nv_roof_box,
                                                sheet_name:sheet_name,
                                                column_1:column_1,
                                                column_2:column_2,
                                                quantity: quantity_nv_roof_box,
                                                tags: tags)
            nv_airloop_roof_box_hash[thermal_zone_sys.to_s] = nv_costing_roof_box
          else
            nv_costing_roof_box = 0.0
          end
          # puts "quantity_nv_roof_box is #{quantity_nv_roof_box}"
          # puts "nv_costing_roof_box is #{nv_costing_roof_box}"

          ################################################## Step IV: costing for each AirLoopHVAC - Controller  ############################################################
          quantity_nv_ahu_controller = 1.0
          search_nv_ahu_controller = {
              row_id_1: 'Ea',
              row_id_2: 400
          }
          sheet_name = 'materials_lighting'
          column_1 = 'unit'
          column_2 = 'lighting_type_id'
          if nv_airloop_controller_hash.key?(thermal_zone_sys.to_s) == false
            nv_costing_ahu_controller = assembly_cost(cost_info:search_nv_ahu_controller,
                                                      sheet_name:sheet_name,
                                                      column_1:column_1,
                                                      column_2:column_2,
                                                      quantity: quantity_nv_ahu_controller,
                                                      tags: tags)
            nv_airloop_controller_hash[thermal_zone_sys.to_s] = nv_costing_ahu_controller
          else
            nv_costing_ahu_controller = 0.0
          end
          # puts "quantity_nv_ahu_controller is #{quantity_nv_ahu_controller}"
          # puts "nv_costing_ahu_controller is #{nv_costing_ahu_controller}"

          ################################################## Step V: costing for each thermal zone (total); also all previous thermal zones including current thermal zone ############################################################
          costing_for_each_ThermalZone = nv_costing_tz_nv_controller +
                                         nv_costing_tz_nv_sensor +
                                         nv_costing_tz_nv_usb +
                                         nv_costing_tz_Tin_sensor_wiring +
                                         nv_costing_tz_Tin_sensor_conduit +
                                         nv_costing_tz_Tin_sensor_box +
                                         nv_costing_tz_duct_damper_motor +
                                         nv_costing_tz_duct_damper_wiring +
                                         nv_costing_tz_duct_damper_conduit +
                                         nv_costing_tz_duct_damper_box
          # puts "costing_for_each_ThermalZone is #{costing_for_each_ThermalZone}"
          nv_total_cost_tz += costing_for_each_ThermalZone

          ################################################## Step VI: costing for each AirLoopHVAC - Total  ############################################################
          costing_for_each_AirLoopHVAC = nv_costing_vertical_conduit +
                                         nv_costing_vertical_conduit_wiring +
                                         nv_costing_vertical_conduit_box +
                                         nv_costing_roof_conduit +
                                         nv_costing_roof_wiring +
                                         nv_costing_roof_box +
                                         nv_costing_ahu_controller

          ##### Gather information for reporting
          @costing_report['ventilation'][:natural_ventilation] << {
              zone: thermal_zone_name.to_s,
              ahu_serves_the_zone: thermal_zone_sys,
              costing_for_the_zone: costing_for_each_ThermalZone,
              costing_for_the_ahu: costing_for_each_AirLoopHVAC
          }
          ########################################################################################################################################################
        end #if !thermal_zone_sys.nil?
      end #if nv_exist == 1.0
    end #model.getZoneHVACEquipmentLists.sort.each do |zone_hvac_equipment_list|

    ########################################################################################################################################################
    # costing for all AirLoopHVACs if they serve at least one thermal zone with the potential for using NV
    nv_airloop_vertical_conduit_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_vertical_conduit_wiring_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_vertical_conduit_box_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_roof_conduit_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_roof_wiring_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_roof_box_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    nv_airloop_controller_hash.each do |k, v|
      nv_total_cost_ahu += v
    end
    # puts "nv_total_cost_ahu is #{nv_total_cost_ahu}"

    ########################################################################################################################################################
    ##### costing for the roof-top outdoor air temperature sensor and wind speed sensor
    if nv_total_cost_tz > 0.0
      tags = ['ventilation', 'natural_ventilation']
      ### roof-top outdoor air temperature sensor ----------------------------------------------------------------------------------------
      quantity_nv_rooftop_sensor_Tout = 1.0
      search_nv_rooftop_sensor_Tout = {
          row_id_1: 'Temperaturesensor',
          row_id_2: 1326
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      nv_costing_nv_rooftop_sensor_Tout = assembly_cost(cost_info:search_nv_rooftop_sensor_Tout,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity: quantity_nv_rooftop_sensor_Tout,
                                                        tags: tags)
      # puts "nv_costing_nv_rooftop_sensor_Tout is #{nv_costing_nv_rooftop_sensor_Tout}"

      ### roof-top wind speed sensor -----------------------------------------------------------------------------------------------------
      quantity_nv_rooftop_sensor_wind_speed = 1.0
      search_nv_rooftop_sensor_wind_speed = {
          row_id_1: 'Ea',
          row_id_2: 407
      }
      sheet_name = 'materials_lighting'
      column_1 = 'unit'
      column_2 = 'lighting_type_id'
      nv_costing_nv_rooftop_sensor_wind_speed = assembly_cost(cost_info:search_nv_rooftop_sensor_wind_speed,
                                                              sheet_name:sheet_name,
                                                              column_1:column_1,
                                                              column_2:column_2,
                                                              quantity: quantity_nv_rooftop_sensor_wind_speed,
                                                              tags: tags)
      # puts "nv_costing_nv_rooftop_sensor_wind_speed is #{nv_costing_nv_rooftop_sensor_wind_speed}"

      ### roof-top sensors -----------------------------------------------------------------------------------------------------
      nv_total_cost_rooftop_sensors = nv_costing_nv_rooftop_sensor_Tout + nv_costing_nv_rooftop_sensor_wind_speed
      ########################################################################################################################################################
      nv_total_cost = nv_total_cost_tz + nv_total_cost_ahu + nv_total_cost_rooftop_sensors
      ##### Gather information for reporting
      @costing_report['ventilation'][:natural_ventilation] << {
          costing_for_rooftop_sensors: nv_total_cost_rooftop_sensors,
          nv_total_cost: nv_total_cost
      }
    end

    puts "\nNatural ventilation costing data successfully generated. Total NV costs: $#{nv_total_cost.round(2)}"

    return nv_total_cost
  end #def cost_audit_nv(model, prototype_creator)


end
