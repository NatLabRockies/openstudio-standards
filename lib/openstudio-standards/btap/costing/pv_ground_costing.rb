class BTAPCosting

  def cost_audit_pv_ground(model, prototype_creator)
    @costing_report['renewables']['pv'] = []
    a = 0 # This is for reporting purposes.
    pv_ground_total_cost = 0.0
    #-------------------------------------------------------------------------------------------------------------------
    # summary of all steps as per Mike Lubun's spec:
    # Step 2: costing of concrete base
    # Step 3: pv modules' racking costing
    # Step 4: pv module costing
    # Step 5: pv wiring costing
    # Step 6: pv inverter costing
    # Step 7: transformer costing
    # Step 8: circuit breakers costing
    # Step 9: circuit breaker fuses costing
    # Step 10: PV fuses costing
    # Step 11: disconnects costing
    # Step 12: total cost (sum of Step 2 to 11)
    #-------------------------------------------------------------------------------------------------------------------
    ##### Gather PV information from the model
    model.getGeneratorPVWattss.sort.each do |generator_PVWatt|

      tags = ['renewables','pv']

      dc_system_capacity_w = generator_PVWatt.dcSystemCapacity()
      module_type = generator_PVWatt.moduleType()
      dc_system_capacity_kw = dc_system_capacity_w/1000
      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 2: costing of concrete base (#Note: steps' numbers are based on Mike Lubun's spec document)
      ### Step 2a: costing of concrete
      ### Step 2b: costing of excavation
      ### Step 2c: costing of concrete footing
      ### Step 2d: costing of backfill
      ### Step 2e: costing of compaction
      ### Step 2f: costing of underground electrical duct
      ### Step 2g: costing of grounding
      ### Step 2h: sum of 2a,b,c,d,e,f,g
      ### Step 2a: costing of concrete -------------------------------
      quantity_concrete = 0.5 * dc_system_capacity_kw #unit: yd3
      search_concrete_3000psi = {
          row_id_1: 'concrete',
          row_id_2: 3000.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_costing_concrete = assembly_cost(cost_info:search_concrete_3000psi,
                                                 sheet_name:sheet_name,
                                                 column_1:column_1,
                                                 column_2:column_2,
                                                 quantity: quantity_concrete,
                                                 tags: tags)
      # puts "quantity_concrete is #{quantity_concrete}"
      # puts "pv_ground_costing_concrete is #{pv_ground_costing_concrete}"

      ### Step 2b: costing of excavation -------------------------------
      quantity_excavation = 3.0 * dc_system_capacity_kw #unit: yd3
      search_excavation = {
          row_id_1: 'Excavation_trench_4_6',
          row_id_2: 0.75
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_costing_excavation = assembly_cost(cost_info:search_excavation,
                                                   sheet_name:sheet_name,
                                                   column_1:column_1,
                                                   column_2:column_2,
                                                   quantity: quantity_excavation,
                                                   tags: tags)
      # puts "quantity_excavation is #{quantity_excavation}"
      # puts "pv_ground_costing_excavation is #{pv_ground_costing_excavation}"

      ### Step 2c: costing of concrete footing -------------------------------
      quantity_concrete_form = 1.0 * dc_system_capacity_kw #unit: each
      search_concrete_footing = {
          row_id_1: 'concreteforms',
          row_id_2: nil
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = nil
      pv_ground_concrete_footing = assembly_cost(cost_info:search_concrete_footing,
                                                 sheet_name:sheet_name,
                                                 column_1:column_1,
                                                 column_2:column_2,
                                                 quantity: quantity_concrete_form,
                                                 tags: tags)
      # puts "quantity_concrete_form is #{quantity_concrete_form}"
      # puts "pv_ground_concrete_footing is #{pv_ground_concrete_footing}"

      ### Step 2d: costing of backfill -------------------------------
      quantity_backfill = 3.0 * dc_system_capacity_kw #unit: each
      search_backfill = {
          row_id_1: 'Backfill ',
          row_id_2: nil
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = nil
      pv_ground_backfill = assembly_cost(cost_info:search_backfill,
                                         sheet_name:sheet_name,
                                         column_1:column_1,
                                         column_2:column_2,
                                         quantity: quantity_backfill,
                                         tags: tags)
      # puts "quantity_backfill is #{quantity_backfill}"
      # puts "pv_ground_backfill is #{pv_ground_backfill}"

      ### Step 2e: costing of compaction -------------------------------
      quantity_compaction = 3.0 * dc_system_capacity_kw #unit: yd3
      search_compaction = {
          row_id_1: 'Compaction_WalkBehind',
          row_id_2: 4.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_compaction = assembly_cost(cost_info:search_compaction,
                                           sheet_name:sheet_name,
                                           column_1:column_1,
                                           column_2:column_2,
                                           quantity: quantity_compaction,
                                           tags: tags)
      # puts "quantity_compaction is #{quantity_compaction}"
      # puts "pv_ground_compaction is #{pv_ground_compaction}"

      ### Step 2f: costing of underground electrical duct -------------------------------
      quantity_underground_electrical_duct = 100.0
      search_underground_electrical_duct = {
          row_id_1: 'groundconduit',
          row_id_2: 1470.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_underground_electrical_duct = assembly_cost(cost_info:search_underground_electrical_duct,
                                                            sheet_name:sheet_name,
                                                            column_1:column_1,
                                                            column_2:column_2,
                                                            quantity: quantity_underground_electrical_duct,
                                                            tags: tags)
      # puts "quantity_underground_electrical_duct is #{quantity_underground_electrical_duct}"
      # puts "pv_ground_underground_electrical_duct is #{pv_ground_underground_electrical_duct}"

      ### Step 2g: costing of grounding -------------------------------
      # Step 2g-1: costing of ground rod
      quantity_grounding_ground_rod = 1.0
      search_grounding_ground_rod = {
          row_id_1: 'Ground_Rod',
          row_id_2: 1356.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_grounding_ground_rod = assembly_cost(cost_info:search_grounding_ground_rod,
                                                     sheet_name:sheet_name,
                                                     column_1:column_1,
                                                     column_2:column_2,
                                                     quantity: quantity_grounding_ground_rod,
                                                     tags: tags)
      # puts "quantity_grounding_ground_rod is #{quantity_grounding_ground_rod}"
      # puts "pv_grounding_ground_rod is #{pv_ground_grounding_ground_rod}"

      # Step 2g-2: costing of exo weld
      quantity_grounding_exo_weld = 2.0
      search_grounding_exo_weld = {
          row_id_1: 'Exo_weld',
          row_id_2: 1373.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_grounding_exo_weld = assembly_cost(cost_info:search_grounding_exo_weld,
                                                   sheet_name:sheet_name,
                                                   column_1:column_1,
                                                   column_2:column_2,
                                                   quantity: quantity_grounding_exo_weld,
                                                   tags: tags)
      # puts "quantity_grounding_exo_weld is #{quantity_grounding_exo_weld}"
      # puts "pv_grounding_exo_weld is #{pv_ground_grounding_exo_weld}"

      # Step 2g-3: costing of ground wire #4
      quantity_grounding_ground_wire_4 = 100.0 / 100.0
      search_grounding_ground_wire_4 = {
          row_id_1: 'Wire_copper_stranded',
          row_id_2: 1372.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_grounding_ground_wire_4 = assembly_cost(cost_info:search_grounding_ground_wire_4,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity: quantity_grounding_ground_wire_4,
                                                        tags: tags)
      # puts "quantity_grounding_ground_wire_4 is #{quantity_grounding_ground_wire_4}"
      # puts "pv_grounding_ground_wire_4 is #{pv_ground_grounding_ground_wire_4}"

      # Step 2g-4: costing of ground wire #6
      quantity_grounding_ground_wire_6 = 20.0
      search_grounding_ground_wire_6 = {
          row_id_1: 'Wire_copper_solid',
          row_id_2: 1361.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_grounding_ground_wire_6 = assembly_cost(cost_info:search_grounding_ground_wire_6,
                                                        sheet_name:sheet_name,
                                                        column_1:column_1,
                                                        column_2:column_2,
                                                        quantity: quantity_grounding_ground_wire_6,
                                                        tags: tags)
      # puts "quantity_grounding_ground_wire_6 is #{quantity_grounding_ground_wire_6}"
      # puts "pv_grounding_ground_wire_6 is #{pv_ground_grounding_ground_wire_6}"

      # Step 2g-5: costing of wire brazing
      quantity_grounding_wire_brazing = 1.0
      search_grounding_wire_brazing = {
          row_id_1: 'Brazed_connection',
          row_id_2: 1374.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_grounding_wire_brazing = assembly_cost(cost_info:search_grounding_wire_brazing,
                                                       sheet_name:sheet_name,
                                                       column_1:column_1,
                                                       column_2:column_2,
                                                       quantity: quantity_grounding_wire_brazing,
                                                       tags: tags)
      # puts "quantity_grounding_wire_brazing is #{quantity_grounding_wire_brazing}"
      # puts "pv_grounding_wire_brazing is #{pv_ground_grounding_wire_brazing}"

      # total cost of grounding
      pv_ground_grounding = pv_ground_grounding_ground_rod +
                            pv_ground_grounding_exo_weld +
                            pv_ground_grounding_ground_wire_4 +
                            pv_ground_grounding_ground_wire_6 +
                            pv_ground_grounding_wire_brazing
      # puts "pv_ground_grounding is #{pv_ground_grounding}"

      ### Step 2h: sum of 2a,b,c,d,e,f,g ------------------------------
      # calculate total cost of concrete base (2a + 2b + 2c + 2d + 2e + 2f + 2g)
      costing_of_concrete_base = pv_ground_costing_concrete +
                                pv_ground_costing_excavation +
                                pv_ground_concrete_footing +
                                pv_ground_backfill +
                                pv_ground_compaction +
                                pv_ground_underground_electrical_duct +
                                pv_ground_grounding
      # puts "costing_of_concrete_base is #{costing_of_concrete_base}"
      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 3: pv modules' racking costing
      quantity_racking = dc_system_capacity_kw * 1.0
      search_pv_racking = {
          row_id_1: 'pvgroundmount',
          row_id_2: 6.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_racking = assembly_cost(cost_info:search_pv_racking,
                                        sheet_name:sheet_name,
                                        column_1:column_1,
                                        column_2:column_2,
                                        quantity:quantity_racking,
                                        tags: tags)
      # puts "quantity_racking is #{quantity_racking}"
      # puts "pv_ground_racking is #{pv_ground_racking}"
      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 4: pv module costing
      # Note: osm file does not show total area of PV panels; instead it shows the total wattage of PV panels.
      # So, for the calculation of number of PV panels, we have assumed that a specific module is being used based on
      # the module type that we can get from the osm file. In this way, we know the wattage of each PV panel;
      # so, we can calculate number of PV panels.
      if module_type == 'Standard' #As per Mike Lubun's comment, we assume using 'HES-160-36PV 26.6  x 58.3 x 1.38' as 'Standard' (i.e. 'poly'/'perc')
        row_id_1 = 'HES-160-36PV 26.6  x 58.3 x 1.38'
        row_id_2 = 160.0 #wattage of each module of 'HES-160-36PV 26.6  x 58.3 x 1.38'
        quantity_number_of_panels = dc_system_capacity_w / row_id_2
      elsif module_type == 'Premium'   #As per Mike Lubun's comment, we assume using 'Heliene 36HD 26.6  x 58.6 x 1.6' as 'Premium' (i.e. 'mono')
        row_id_1 = 'Heliene 36HD 26.6  x 58.6 x 1.6'
        row_id_2 = 160.0  #wattage of each module of 'Heliene 36HD 26.6  x 58.6 x 1.6'
        quantity_number_of_panels = dc_system_capacity_w / row_id_2
      elsif module_type == 'ThinFilm'  #As per Mike Lubun's comment, we assume using 'Powerfilm, Soltronic Semi-Flex with Sunpower cells, 21 x 44.5 x 0.08' as 'ThinFilm' (i.e. 'thin')
        row_id_1 = 'Powerfilm, Soltronic Semi-Flex with Sunpower cells, 21 x 44.5 x 0.08'
        row_id_2 = 100.0   #wattage of each module of 'Powerfilm, Soltronic Semi-Flex with Sunpower cells, 21 x 44.5 x 0.08'
        quantity_number_of_panels = dc_system_capacity_w / row_id_2
      end
      search_pv_module = {
          row_id_1: row_id_1,
          row_id_2: row_id_2
      }
      sheet_name = 'materials_hvac'
      column_1 = 'description'
      column_2 = 'Size'
      pv_ground_costing_pv_module = assembly_cost(cost_info:search_pv_module,
                                                  sheet_name:sheet_name,
                                                  column_1:column_1,
                                                  column_2:column_2,
                                                  quantity:quantity_number_of_panels,
                                                  tags: tags)
      # puts "quantity_number_of_panels is #{quantity_number_of_panels}"
      # puts "pv_ground_costing_pv_module is #{pv_ground_costing_pv_module}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 5: pv wiring costing
      # Step 5-1
      quantity_wiring_wire = dc_system_capacity_kw * 1.0#unit: CLF (Hundred Linear Feet)
      search_pv_wire = {
          row_id_1: 'Wire_copper_stranded',
          row_id_2: 6.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_wiring_wire = assembly_cost(cost_info:search_pv_wire,
                                            sheet_name:sheet_name,
                                            column_1:column_1,
                                            column_2:column_2,
                                            quantity:quantity_wiring_wire,
                                            tags: tags)
      # puts "quantity_wiring_wire is #{quantity_wiring_wire}"
      # puts "pv_ground_wiring_wire is #{pv_ground_wiring_wire}"

      # Step 5-2
      quantity_wiring_conduit = dc_system_capacity_kw * 27.0 #unit: LF
      search_pv_conduit = {
          row_id_1: 'Conduit',
          row_id_2: 851.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_wiring_conduit = assembly_cost(cost_info:search_pv_conduit,
                                               sheet_name:sheet_name,
                                               column_1:column_1,
                                               column_2:column_2,
                                               quantity:quantity_wiring_conduit,
                                               tags: tags)
      # puts "quantity_wiring_conduit is #{quantity_wiring_conduit}"
      # puts "pv_ground_wiring_conduit is #{pv_ground_wiring_conduit}"

      pv_ground_wiring = pv_ground_wiring_wire + pv_ground_wiring_conduit
      # puts "pv_ground_wiring is #{pv_ground_wiring}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 6: pv inverter costing
      # Step 6-1: inverters themselves
      if dc_system_capacity_kw < 4.0
        inverter_size = 3.0
        inverter_multiplier = 1.0
      elsif dc_system_capacity_kw == 4.0
        inverter_size = 4.0
        inverter_multiplier = 1.0
      elsif dc_system_capacity_kw > 4.0
        inverter_size = 4.0
        inverter_multiplier = dc_system_capacity_kw / 4.0
        inverter_multiplier = inverter_multiplier.ceil
      end
      # puts "inverter_multiplier is #{inverter_multiplier}"
      quantity_inverter_itself = inverter_multiplier.to_f
      search_pv_inverter_itself = {
          row_id_1: 'inverter24',
          row_id_2: inverter_size
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_inverter_itself = assembly_cost(cost_info:search_pv_inverter_itself,
                                                sheet_name:sheet_name,
                                                column_1:column_1,
                                                column_2:column_2,
                                                quantity:quantity_inverter_itself,
                                                tags: tags)
      # puts "quantity_inverter_itself is #{quantity_inverter_itself}"
      # puts "pv_ground_inverter_itself is #{pv_ground_inverter_itself}"

      # Step 6-2: inverters' boxes
      quantity_inverter_box = inverter_multiplier.to_f
      search_pv_inverter_box = {
          row_id_1: 'pvbox',
          row_id_2: 1135.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_inverter_box = assembly_cost(cost_info:search_pv_inverter_box,
                                             sheet_name:sheet_name,
                                             column_1:column_1,
                                             column_2:column_2,
                                             quantity:quantity_inverter_box,
                                             tags: tags)
      # puts "quantity_inverter_box is #{quantity_inverter_box}"
      # puts "pv_ground_inverter_box is #{pv_ground_inverter_box}"

      pv_ground_inverter = pv_ground_inverter_itself + pv_ground_inverter_box
      # puts "pv_ground_inverter is #{pv_ground_inverter}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 7: transformer costing
      transformer_types = [1.0, 2.0, 3.0, 5.0, 7.5, 10.0, 15.0, 25.0, 37.5, 50.0, 75.0, 100.0, 167.0] #based on Mike Lubun's costing spreadsheet
      transformer_closet_to_pv_kw = transformer_types.sort_by { |item| (dc_system_capacity_kw-item).abs }.first(1)
      # puts "transformer_closet_to_pv_kw is #{transformer_closet_to_pv_kw}"
      if dc_system_capacity_kw <= 167.0
        transformer_multiplier = 1.0
        row_id_2 = transformer_closet_to_pv_kw[0]
      else #i.e. dc_system_capacity_kw > 167.0
        transformer_multiplier = dc_system_capacity_kw / 167.0
        transformer_multiplier = transformer_multiplier.ceil
        row_id_2 = 167.0
      end
      # puts "transformer_multiplier is #{transformer_multiplier}"
      quantity_transformer = transformer_multiplier.to_f
      search_transformer = {
          row_id_1: 'Transformer_dry_low_voltage',
          row_id_2: row_id_2
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_transformer = assembly_cost(cost_info:search_transformer,
                                            sheet_name:sheet_name,
                                            column_1:column_1,
                                            column_2:column_2,
                                            quantity:quantity_transformer,
                                            tags: tags)
      # puts "quantity_transformer is #{quantity_transformer}"
      # puts "pv_ground_transformer is #{pv_ground_transformer}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 8: circuit breakers costing
      circuit_breaker240_types = [30.0, 60.0, 100.0, 200.0, 400.0, 600.0]
      circuit_breaker_amps = (dc_system_capacity_kw * 1000.0 * 1.5 / 24.0) * 1.25
      # puts "circuit_breaker_amps is #{circuit_breaker_amps}"
      circuit_breaker_closet_to_pv_amps = circuit_breaker240_types.sort_by { |item| (circuit_breaker_amps-item).abs }.first(1)
      # puts "circuit_breaker_closet_to_pv_amps is #{circuit_breaker_closet_to_pv_amps}"
      if circuit_breaker_amps <= 600.0
        circuit_breaker_multiplier = 1.0
        row_id_2 = circuit_breaker_closet_to_pv_amps[0]
      else #i.e. circuit_breaker_amps > 600.0
        circuit_breaker_multiplier = circuit_breaker_amps / 600.0
        circuit_breaker_multiplier = circuit_breaker_multiplier.ceil
        row_id_2 = 600.0
      end
      quantity_circuit_breakers = circuit_breaker_multiplier.to_f
      search_circuit_breakers = {
          row_id_1: 'Circuit_breaker240',
          row_id_2: row_id_2
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_circuit_breakers = assembly_cost(cost_info:search_circuit_breakers,
                                                 sheet_name:sheet_name,
                                                 column_1:column_1,
                                                 column_2:column_2,
                                                 quantity:quantity_circuit_breakers,
                                                 tags: tags)
      # puts "quantity_circuit_breakers is #{quantity_circuit_breakers}"
      # puts "pv_ground_circuit_breakers is #{pv_ground_circuit_breakers}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 9: circuit breaker fuses costing
      circuit_breaker_fuse = circuit_breaker_amps
      circuit_breaker_fuse_250V_timedelay_types = [30.0, 5.0, 60.0, 100.0, 200.0, 400.0, 600.0]
      circuit_breaker_fuse_closet_to_pv_amps = circuit_breaker_fuse_250V_timedelay_types.sort_by { |item| (circuit_breaker_fuse-item).abs }.first(1)
      # puts "circuit_breaker_fuse_closet_to_pv_amps is #{circuit_breaker_fuse_closet_to_pv_amps}"
      if circuit_breaker_fuse <= 600.0
        circuit_breaker_fuse_multiplier = 1.0
        row_id_2 = circuit_breaker_fuse_closet_to_pv_amps[0]
      else #i.e. circuit_breaker_fuse > 600.0
        circuit_breaker_fuse_multiplier = circuit_breaker_fuse / 600.0
        circuit_breaker_fuse_multiplier = circuit_breaker_fuse_multiplier.ceil
        row_id_2 = 600.0
      end
      quantity_circuit_breaker_fuses = circuit_breaker_fuse_multiplier.to_f
      search_circuit_breaker_fuses = {
          row_id_1: 'fuse_250V_timedelay',
          row_id_2: row_id_2
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_circuit_breaker_fuses = assembly_cost(cost_info:search_circuit_breaker_fuses,
                                                      sheet_name:sheet_name,
                                                      column_1:column_1,
                                                      column_2:column_2,
                                                      quantity:quantity_circuit_breaker_fuses,
                                                      tags: tags)
      # puts "quantity_circuit_breaker_fuses is #{quantity_circuit_breaker_fuses}"
      # puts "pv_ground_circuit_breaker_fuses is #{pv_ground_circuit_breaker_fuses}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 10: PV fuses costing
      # Step 10-1: PV fuses
      quantity_pv_fuse_itself = (dc_system_capacity_kw * 1.0).ceil.to_f
      search_pv_fuse = {
          row_id_1: 'fuse_120V',
          row_id_2: 15.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'Size'
      pv_ground_pv_fuse_itself = assembly_cost(cost_info:search_pv_fuse,
                                               sheet_name:sheet_name,
                                               column_1:column_1,
                                               column_2:column_2,
                                               quantity:quantity_pv_fuse_itself,
                                               tags: tags)
      # puts "quantity_pv_fuse_itself is #{quantity_pv_fuse_itself}"
      # puts "pv_ground_pv_fuse_itself is #{pv_ground_pv_fuse_itself}"

      # Step 10-2: PV combiner box
      quantity_pv_combiner_box = (dc_system_capacity_kw / 10.0).ceil.to_f
      search_pv_combiner_box = {
          row_id_1: 'pvcombinerbox',
          row_id_2: 1125.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_pv_combiner_box = assembly_cost(cost_info:search_pv_combiner_box,
                                                sheet_name:sheet_name,
                                                column_1:column_1,
                                                column_2:column_2,
                                                quantity:quantity_pv_combiner_box,
                                                tags: tags)
      # puts "quantity_pv_combiner_box is #{quantity_pv_combiner_box}"
      # puts "pv_ground_pv_combiner_box is #{pv_ground_pv_combiner_box}"

      pv_ground_pv_fuses = pv_ground_pv_fuse_itself + pv_ground_pv_combiner_box
      # puts "pv_ground_pv_fuses is #{pv_ground_pv_fuses}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 11: disconnects costing
      quantity_disconnect_before_inverter = 1.0
      search_disconnect_before_inverter = {
          row_id_1: 'Circuit_breaker240',
          row_id_2: 1403.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_disconnect_before_inverter = assembly_cost(cost_info:search_disconnect_before_inverter,
                                                           sheet_name:sheet_name,
                                                           column_1:column_1,
                                                           column_2:column_2,
                                                           quantity:quantity_disconnect_before_inverter,
                                                           tags: tags)
      # puts "quantity_disconnect_before_inverter is #{quantity_disconnect_before_inverter}"
      # puts "pv_ground_disconnect_before_inverter is #{pv_ground_disconnect_before_inverter}"


      quantity_disconnect_after_transformer = 1.0
      search_disconnect_after_transformer = {
          row_id_1: 'Circuit_breaker240',
          row_id_2: 1407.0
      }
      sheet_name = 'materials_hvac'
      column_1 = 'Material'
      column_2 = 'material_id'
      pv_ground_disconnect_after_transformer = assembly_cost(cost_info:search_disconnect_after_transformer,
                                                             sheet_name:sheet_name,
                                                             column_1:column_1,
                                                             column_2:column_2,
                                                             quantity:quantity_disconnect_after_transformer,
                                                             tags: tags)
      # puts "quantity_disconnect_after_transformer is #{quantity_disconnect_after_transformer}"
      # puts "pv_ground_disconnect_after_transformer is #{pv_ground_disconnect_after_transformer}"

      pv_ground_disconnects = pv_ground_disconnect_before_inverter + pv_ground_disconnect_after_transformer
      # puts "pv_ground_disconnects is #{pv_ground_disconnects}"

      #-----------------------------------------------------------------------------------------------------------------
      ##### Step 12: calculate total cost of the ground mount PV system (sum of steps 2 to 11)
      pv_ground_total_cost_handle = costing_of_concrete_base +
                                     pv_ground_racking +
                                     pv_ground_costing_pv_module +
                                     pv_ground_wiring +
                                     pv_ground_inverter +
                                     pv_ground_transformer +
                                     pv_ground_circuit_breakers +
                                     pv_ground_circuit_breaker_fuses +
                                     pv_ground_pv_fuses +
                                     pv_ground_disconnects

      pv_ground_total_cost += pv_ground_total_cost_handle

      # puts "pv_ground_total_cost_handle is #{pv_ground_total_cost_handle}"

      ##### Gather information for reporting
      @costing_report['renewables']['pv'] << {
          'generator_PVWatt_name' => generator_PVWatt.name.to_s,
          'costing_of_concrete_base' => costing_of_concrete_base,
          'pv_ground_racking' => pv_ground_racking,
          'pv_ground_costing_pv_module' => pv_ground_costing_pv_module,
          'pv_ground_wiring' => pv_ground_wiring,
          'pv_ground_inverter' => pv_ground_inverter,
          'pv_ground_transformer' => pv_ground_transformer,
          'pv_ground_circuit_breakers' => pv_ground_circuit_breakers,
          'pv_ground_circuit_breaker_fuses' => pv_ground_circuit_breaker_fuses,
          'pv_ground_pv_fuses' => pv_ground_pv_fuses,
          'pv_ground_disconnects' => pv_ground_disconnects,
          'the_generator_PVWatt_total_cost' => pv_ground_total_cost_handle
      }

      a += 1

    end
    if a > 0
      @costing_report['renewables']['pv'] << {
          'pv_ground_total_cost' => pv_ground_total_cost
      }
    end

    puts "\nGround-mounted PV costing data successfully generated. Total PV costs: $#{pv_ground_total_cost.round(2)}"

    return pv_ground_total_cost
  end #cost_audit_pv_ground(model, prototype_creator)


  def assembly_cost(cost_info:, sheet_name:, column_1:, column_2:, quantity:, tags:)
    #-------------------------------------------------------------------------------------------------------------------
    ### Step I: find mat_id
    mat_data = nil
    mat_data = @costing_database['raw'][sheet_name].select { |data|
      data[column_1].to_s.upcase == cost_info[:row_id_1].to_s.upcase and
          data[column_2].to_f.round(1) == cost_info[:row_id_2].to_f.round(1)
    }.first
    mat_id = mat_data['id']
    material_adjust = mat_data['material_mult']
    labour_adjust = mat_data['labour_mult']
    material_adjust = 1.0 if material_adjust.nil?
    labour_adjust = 1.0 if labour_adjust.nil?
    #-------------------------------------------------------------------------------------------------------------------
    ### Step II: calculate unit cost
    mat_cost_info = @costing_database['costs'].select { |data| data['id'] == mat_id.to_s.upcase }.first
    regional_material, regional_installation, regional_equipment = get_regional_cost_factors(@costing_report["province_state"], @costing_report["city"], mat_cost_info)
    # puts "regional_material, regional_installation, regional_equipment #{regional_material}, #{regional_installation}, #{regional_equipment}"

    if mat_cost_info['baseCosts']['materialOpCost'].nil?
      cost_material = 0.0
    else
      cost_material = mat_cost_info['baseCosts']['materialOpCost'] * (regional_material / 100.0) * material_adjust.to_f
    end
    if mat_cost_info['baseCosts']['laborOpCost'].nil?
      cost_labour = 0.0
    else
      cost_labour = mat_cost_info['baseCosts']['laborOpCost'] * (regional_installation / 100.0) * labour_adjust.to_f
    end
    if mat_cost_info['baseCosts']['equipmentOpCost'].nil?
      cost_equipment = 0.0
    else
      cost_equipment = mat_cost_info['baseCosts']['equipmentOpCost'] * (regional_equipment / 100.0)
    end

    cost_unit = cost_material + cost_labour + cost_equipment
    # puts "cost_unit is #{cost_unit}"
    #-------------------------------------------------------------------------------------------------------------------
    ### Step III: calculate total cost
    cost_total = cost_unit * quantity
    # puts "cost_total is #{cost_total}"
    #-------------------------------------------------------------------------------------------------------------------
    # Gather info for costed items output file
    unless mat_data['Material'].nil?
      tags << mat_data['Material']
    end
    unless mat_data['description'].nil?
      tags << mat_data['description']
    end
    if not tags.empty?
      add_costed_item(material_id: mat_id.to_s,
                      quantity: quantity,
                      material_mult: material_adjust.to_f,
                      labour_mult: labour_adjust.to_f,
                      equip_mult: 1.0,
                      tags: tags)
    end

    return cost_total
  end

end