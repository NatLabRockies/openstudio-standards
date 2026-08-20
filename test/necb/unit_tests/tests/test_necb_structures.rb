require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

# Checks if BTAP::Structure instances are correctly deployed within BTAP.
class NECB_Structure_Tests < Minitest::Test
  def test_necb_structures()
    outd = "output/test_necb_structures"
    eres = "../expected_results/necb_structures_expected_results.json"
    tres = "../expected_results/necb_structures_test_results.json"
    sizd = "sizing_folder"

    @output_folder         = File.join(__dir__, outd)
    @expected_results_file = File.join(__dir__, eres)
    @test_results_file     = File.join(__dir__, tres)
    @sizing_run_dir        = File.join(@output_folder, sizd)
    @test_results_array    = []

    # Intial test condition.
    @test_passed = true

    @buildings = [
      # 'FullServiceRestaurant',
      # 'HighriseApartment',
      # 'HighriseApartmentMult',
      # 'Hospital',
      # 'LargeHotel',
      # 'LargeOffice',
      # 'LEEPMidriseApartment',
      # 'LEEPMultiTower',
      # 'LEEPPointTower',
      # 'LEEPTownHouse',
      # 'LowriseApartment',
      # 'MediumOffice',
      # 'MidriseApartment',
      # 'NorthernEducation',
      # 'NorthernHealthCare',
      # 'Outpatient',
      # 'PrimarySchool',
      # 'QuickServiceRestaurant',
      # 'RetailStandalone',
      # 'RetailStripmall',
      # 'SecondarySchool',
      # 'SmallHotel',
      # 'SmallOffice',
      'Warehouse'
    ]

    @templates = [
      # "NECB2011",
      # "NECB2015",
      # "NECB2017",
      "NECB2020",
      # "NECB2025"
    ]

    @options = [
      # "",
      "structure"
    ]

    tg  = "co2_structure"
    epw = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"
    tPs = ["walls", "floors", "roofs"]
    xds = ["BTAP-ExteriorWall-WoodFramed-5", "BTAP-ExteriorWall-Mass-2"]

    fdback = []
    fdback << ""
    fdback << "BTAP::Structure Unit Tests"
    fdback << "~~~~  ~~~~~~~~~ ~~~~ ~~~~~"

    @buildings.sort.each   do |building|
      @templates.sort.each do |template|
        @options.sort.each do |option  |
          cas  = "CASE #{building} (#{template})"
          cas += " - #{option}" unless option.empty?
          st   = Standard.build(template)

          # Customizing STRUCTURE options. In this Warehouse example, the
          # building would inherit a steel (or metal) structure by default.
          # This is overridden here as all 3 spaces are customized:
          #   - the office has a user-assigned wood structure
          #   - the fine storage space has user-assigned wood-framing
          #   - the bulk storage area has a user-assigned CMU structure
          if building == "Warehouse"
            id1  = "Zone1 Office"
            id2  = "Zone2 Fine Storage"
            id3  = "Zone3 Bulk Storage"
            opt1 = "btap_structure"
            opt2 = "btap_framing"
            prp1 = "wood"
            prp2 = "cmu"

            model  = st.load_building_type_from_library(building_type: building)
            office = model.getSpaceByName(id1)
            fine   = model.getSpaceByName(id2)
            bulk   = model.getSpaceByName(id3)
            err_msg1 = "Invalid space ID '#{id1}' (#{cas})?"
            err_msg2 = "Invalid space ID '#{id2}' (#{cas})?"
            err_msg3 = "Invalid space ID '#{id3}' (#{cas})?"
            refute_empty(office, err_msg1)
            refute_empty(  fine, err_msg2)
            refute_empty(  bulk, err_msg3)
            office = office.get
            fine   = fine.get
            bulk   = bulk.get

            # Assign custom STRUCTURE or FRAMING properties.
            err_msg1 = "Failed AddProp '#{opt1}' #{id1} (#{cas})?"
            err_msg2 = "Failed AddProp '#{opt2}' #{id2} (#{cas})?"
            err_msg3 = "Failed AddProp '#{opt1}' #{id3} (#{cas})?"
            assert(office.additionalProperties.setFeature(opt1, prp1), err_msg1)
            assert(  fine.additionalProperties.setFeature(opt2, prp1), err_msg2)
            assert(  bulk.additionalProperties.setFeature(opt1, prp2), err_msg3)
            err_msg1 = "Missing AddProp '#{opt1}' #{id1} (#{cas})?"
            err_msg2 = "Missing AddProp '#{opt2}' #{id2} (#{cas})?"
            err_msg3 = "Missing AddProp '#{opt1}' #{id3} (#{cas})?"

            # Validate.
            prop1 = office.additionalProperties.getFeatureAsString(opt1)
            prop2 =   fine.additionalProperties.getFeatureAsString(opt2)
            prop3 =   bulk.additionalProperties.getFeatureAsString(opt1)
            refute_empty(prop1, err_msg1)
            refute_empty(prop2, err_msg2)
            refute_empty(prop3, err_msg3)
            prop1 = prop1.get
            prop2 = prop2.get
            prop3 = prop3.get
            err_msg1 = "Incorrect AddProp '#{prop1}' #{id1} (#{cas})?"
            err_msg2 = "Incorrect AddProp '#{prop2}' #{id2} (#{cas})?"
            err_msg3 = "Incorrect AddProp '#{prop3}' #{id3} (#{cas})?"
            assert_equal(prop1, prp1, err_msg1)
            assert_equal(prop2, prp1, err_msg2)
            assert_equal(prop3, prp2, err_msg3)

            model = st.model_apply_standard(model: model,
                                            epw_file: epw,
                                            construction_opt: option,
                                            sizing_run_dir: @sizing_run_dir)
          else
            model = st.model_create_prototype_model(template: template,
                                                    epw_file: epw,
                                                    building_type: building,
                                                    construction_opt: option,
                                                    sizing_run_dir: @sizing_run_dir)
          end

          co2 = model.getBuilding.additionalProperties.getFeatureAsDouble(tg)

          err_msg = "BLDG kgCO2-e (#{cas})?"
          refute_empty(co2, err_msg)
          co2 = co2.get
          nb  = model.getBuilding.standardsNumberOfAboveGroundStories.get
          nst = nb < 2 ? "#{nb} storey" : "#{nb} stories"

          attics  = []
          plenums = []

          model.getSpaces.each do |space|
            next if space.partofTotalFloorArea

            group = TBD.unconditioned?(space) ? attics : plenums
            group << space
          end

          attics.each do |attic|
            break if option.empty?

            id  = attic.nameString
            set = attic.defaultConstructionSet
            err_msg = "#{id} default construction set (#{cas})?"
            refute_empty(set, err_msg)

            set = set.get
            id  = set.nameString
            err_msg = "Default construction set #{id} (#{cas})?"
            assert_includes(id, "ATTIC", err_msg)

            attic.surfaces.each do |surface|
              id = surface.nameString
              c  = surface.construction.get.to_LayeredConstruction.get
              next unless c.layers.size == 2
              next unless surface.surfaceType.downcase == "floor"

              if id.include?("soffit")
                err_msg = "#{id} insulated (#{cas})?"

                # Soffit 'floor' not insulated.
                c.layers.each do |layer|
                  assert_includes(layer.nameString, "material", err_msg)
                end
              else
                id = c.layers.last.nameString
                err_msg = "#{id} insulation layer (#{cas})?"
                assert_includes(id, "OSut:K", err_msg)
              end
            end
          end

          plenums.each do |plenum|
            break if option.empty?

            id  = plenum.nameString
            set = plenum.defaultConstructionSet
            err_msg = "#{id} default construction set (#{cas})?"
            refute_empty(set, err_msg)

            set = set.get
            id  = set.nameString
            err_msg = "Default construction set #{id} (#{cas})?"
            assert_includes(id, "PLENUM", err_msg)

            plenum.surfaces.each do |surface|
              next unless surface.surfaceType.downcase == "floor"

              id = surface.nameString
              c  = surface.construction.get.to_LayeredConstruction.get
              n  = c.layers.size
              err_msg = "#{id} ##{n} layers (#{cas})?"
              assert_equal(n, 1, err_msg)

              id = c.layers.first.nameString
              err_msg = "#{id} tile (#{cas})?"
              assert_includes(id, "material", err_msg)
            end
          end

          s = st.structure

          err_msg = "#{s.class} (#{cas})?"
          assert_kind_of(BTAP::Structure, s, err_msg)
          err_msg = "Data #{s.data.class} (#{cas})?"
          assert_kind_of(Hash, s.data, err_msg)
          err_msg = "Category #{s.category.class} (#{cas})?"
          assert_kind_of(String, s.category, err_msg)
          err_msg = "Structure #{s.structure.class} (#{cas})?"
          assert_kind_of(Symbol, s.structure, err_msg)
          err_msg = "Liveload #{s.liveload.class} (#{cas})?"
          assert_kind_of(Numeric, s.liveload, err_msg)
          err_msg = "Deadload #{s.deadload.class} (#{cas})?"
          assert_kind_of(Numeric, s.deadload, err_msg)
          err_msg = "Missing categories (#{cas})?"
          assert(s.data.key?(:category), err_msg)
          err_msg = "Missing structures (#{cas})?"
          assert(s.data.key?(:structure), err_msg)

          # Default construction sets?
          csets = model.getDefaultConstructionSets

          # Although all 3 Warehouse spaces are customized, the solution applies
          # one of the customized default construction sets to the whole
          # building - only 2 space-specific default construction sets remain.
          if building == "Warehouse"
            err_msg = "# custom spaces (#{cas})?"
            assert_equal(s.spaces.size, 2, err_msg) # 2x custom spaces
            err_msg = "Custom #{id1} (#{cas})?"
            assert_includes(s.spaces, id1, err_msg)
            err_msg = "Custom #{id2} (#{cas})?"
            assert_includes(s.spaces, id2, err_msg)
            err_msg = "Custom #{id3} (#{cas})?"
            refute_includes(s.spaces, id3, err_msg)
            err_msg = "Custom #{id1} structure (#{cas})?"
            assert_includes(s.spaces[id1], :structure, err_msg)
            err_msg = "Custom #{id2} structure (#{cas})?"
            assert_includes(s.spaces[id2], :structure, err_msg)

            unless option.empty?
              err_msg = "# Default Construction Sets (#{cas})?"
              assert_equal(csets.size, 3, err_msg)    # 1x building + 2x spaces
              offcset = office.defaultConstructionSet
              fineset = fine.defaultConstructionSet
              err_msg1 = "#{id1} Default Construction Set (#{cas})?"
              err_msg2 = "#{id2} Default Construction Set (#{cas})?"
              refute_empty(offcset, err_msg1)
              refute_empty(fineset, err_msg2)
              offcset = offcset.get
              fineset = fineset.get
              err_msg1 = "#{id1} empty ground constructions (#{cas})?"
              err_msg2 = "#{id2} empty ground constructions (#{cas})?"
              assert_empty(offcset.defaultGroundContactSurfaceConstructions, err_msg1)
              assert_empty(offcset.defaultGroundContactSurfaceConstructions, err_msg2)
              err_msg1 = "#{id1} empty exterior subsurface constructions (#{cas})?"
              err_msg2 = "#{id2} empty exterior subsurface constructions (#{cas})?"
              assert_empty(offcset.defaultExteriorSubSurfaceConstructions, err_msg1)
              assert_empty(fineset.defaultExteriorSubSurfaceConstructions, err_msg2)
              err_msg1 = "#{id1} empty interior surface constructions (#{cas})?"
              err_msg2 = "#{id2} empty interior surface constructions (#{cas})?"
              assert_empty(offcset.defaultInteriorSurfaceConstructions, err_msg1)
              assert_empty(fineset.defaultInteriorSurfaceConstructions, err_msg2)
              err_msg1 = "#{id1} empty interior subsurface constructions (#{cas})?"
              err_msg2 = "#{id2} empty interior subsurface constructions (#{cas})?"
              assert_empty(offcset.defaultInteriorSubSurfaceConstructions, err_msg1)
              assert_empty(fineset.defaultInteriorSubSurfaceConstructions, err_msg2)
              err_msg1 = "#{id1} empty space shading construction (#{cas})?"
              err_msg2 = "#{id2} empty space shading construction (#{cas})?"
              assert_empty(offcset.spaceShadingConstruction, err_msg1)
              assert_empty(fineset.spaceShadingConstruction, err_msg2)
              err_msg1 = "#{id1} empty site shading construction (#{cas})?"
              err_msg2 = "#{id2} empty site shading construction (#{cas})?"
              assert_empty(offcset.siteShadingConstruction, err_msg1)
              assert_empty(fineset.siteShadingConstruction, err_msg2)
              err_msg1 = "#{id1} empty building shading construction (#{cas})?"
              err_msg2 = "#{id2} empty building shading construction (#{cas})?"
              assert_empty(offcset.buildingShadingConstruction, err_msg1)
              assert_empty(fineset.buildingShadingConstruction, err_msg2)
              err_msg1 = "#{id1} empty adiabatic surface construction (#{cas})?"
              err_msg2 = "#{id2} empty adiabatic surface construction (#{cas})?"
              assert_empty(offcset.adiabaticSurfaceConstruction, err_msg1)
              assert_empty(fineset.adiabaticSurfaceConstruction, err_msg2)

              # Validate generated constructions.
              cs = model.getLayeredConstructions.select { |c| c.getNetArea > 0 }
              err_msg = "# un/insulated constructions (#{cas})"
              assert_equal(cs.size, 11, err_msg)

              # Isolate insulated constructions, i.e. part of building envelope.
              cs = cs.reject { |c| c.additionalProperties.getFeatureAsDouble("btap_uo").empty? }
              err_msg = "# insulated constructions (#{cas})"
              assert_equal(cs.size, 6, err_msg)

              # Insulated (layered) constructions (i.e. part of the building
              # envelope) inherit area-weighted air film resistances, if relying
              # on the 'structure' option.
              cs.each do |c|
                id = c.nameString
                fR = c.additionalProperties.getFeatureAsDouble("btap_film")
                tP = c.additionalProperties.getFeatureAsString("btap_type")
                err_msg = "#{id} 'btap_film' (#{cas})"
                refute_empty(fR)
                fR = fR.get

                unless tP.empty?
                  tP = tP.get
                  err_msg = "Unknown type #{id} #{tP} (#{cas})"
                  assert_includes(tPs, tP, err_msg)

                  fr = 0.150 # walls
                  fr = 0.136 if tP == "roofs"
                else
                  fr = 0.160 # slabs
                end

                # puts "#{id} : #{fr.round(3)} vs #{fR.round(3)} (#{tP})"
                # OSut:CON:slab   : 0.160 vs 0.160 ()
                # OSut:CON:roof   : 0.136 vs 0.136 (roofs)
                # OSut:CON:roof 3 : 0.136 vs 0.136 (roofs)
                # OSut:CON:wall   : 0.150 vs 0.150 (walls)
                # OSut:CON:wall 1 : 0.150 vs 0.150 (walls)
                # OSut:CON:wall 2 : 0.150 vs 0.150 (walls)
                err_msg = "#{id} #{fR.round(3)} vs #{fr.round(3)} (#{cas})"
                assert_equal(fR.round(3), fr.round(3))
              end

              # NECB2015: No uprating (Uo == NECB prescriptive requirements).
              if template == "NECB2015"
                slab_m2 = 0
                roof_m2 = 0
                wall_m2 = 0

                cs.each do |c|
                  m2 = c.getNetArea
                  id = c.nameString
                  uo = c.additionalProperties.getFeatureAsDouble("btap_uo").get
                  xd = c.additionalProperties.getFeatureAsString("btap_id")
                  fR = c.additionalProperties.getFeatureAsDouble("btap_film").get
                  tP = c.additionalProperties.getFeatureAsString("btap_type")

                  # puts "#{id} U-factor : #{uo.round(3)} W/m2.K (#{m2.round} m2)"
                  # OSut:CON:slab   U-factor : 0.757 W/m2.K (4598 m2) # building
                  # OSut:CON:roof   U-factor : 0.162 W/m2.K (3045 m2) # bulk storage
                  # OSut:CON:roof 3 U-factor : 0.162 W/m2.K (1324 m2) # fine storage
                  # OSut:CON:wall   U-factor : 0.210 W/m2.K (1058 m2) # bulk storage
                  # OSut:CON:wall 1 U-factor : 0.210 W/m2.K ( 100 m2) # office
                  # OSut:CON:wall 2 U-factor : 0.210 W/m2.K ( 507 m2) # fine storage
                  err_msg = "BTAP NECB2015 Uo-factor (#{cas})"

                  unless tP.empty?
                    tP = tP.get
                    err_msg = "Unknown type #{id} #{tP} (#{cas})"
                    assert_includes(tPs, tP, err_msg)

                    if tP == "walls"
                      wall_m2 += m2
                      err_msg = "BTAP wall construction Uo (#{cas})"
                      assert_equal(uo.round(3), 0.210, err_msg)
                      err_msg = "BTAP wall construction ID (#{cas})"
                      refute_empty(xd, err_msg)
                      err_msg = "BTAP costed wall ID (#{cas})"
                      assert_includes(xds, xd.get, err_msg)
                    else # roofs
                      roof_m2 += m2
                      err_msg = "BTAP roof construction Uo (#{cas})"
                      assert_equal(uo.round(3), 0.162, err_msg)
                    end
                  else
                    slab_m2 += m2
                    assert_equal(uo.round(3), 0.757, err_msg)

                    # NECB prescriptive U-factor requirements for slabs-on-grade
                    # are limited to perimeter insulation (1.2m in width) for
                    # climate zones < 8. The "btap_uo" value reflects this. This
                    # should eventually inform BTAP's use of KIVA (@todo).
                    uO = 1 / TBD.rsi(c, fR)

                    err_msg = "BTAP #{id} calculated USI #{uO.round(2)} (#{cas})"
                    assert_equal(uO.round(3), 3.381, err_msg) # not 0.757
                    err_msg = "BTAP #{id} calculated RSI #{uO.round(2)} (#{cas})"
                    refute_equal(uo.round(2), uO.round(2), err_msg)
                  end
                end

                # NECB2015: 5% SSR ratio.
                err_msg = "BTAP NECB2015 slab/roof area (#{cas})"
                assert_equal((0.95 * slab_m2).round, roof_m2.round, err_msg)
              end
            end
          elsif option == "structure"
            nb  = 1
            nb += 1 unless plenums.empty?
            nb += 1 unless attics.empty?

            err_msg = "# Default Construction Sets (#{cas})?"
            assert_equal(csets.size, nb, err_msg)
            err_msg = "# custom spaces (#{cas})?"
            assert_equal(s.spaces.size, 0, err_msg)

            # Validate constructions (QuickServiceRestaurant case):
            #   - unconditioned attic space, sloped roof surfaces
            #   - insulated attic floor
            #   - insulated slab-on-grade
            #   - insulated slab & attic floors should have same area
            if building == "QuickServiceRestaurant"
              cs = model.getLayeredConstructions.select { |c| c.getNetArea > 0 }
              err_msg = "# un/insulated constructions (#{cas})"
              assert_equal(cs.size, 6, err_msg)

              # Isolate insulated constructions, i.e. part of building envelope.
              cs = cs.reject { |c| c.additionalProperties.getFeatureAsDouble("btap_uo").empty? }
              err_msg = "# insulated constructions (#{cas})"
              assert_equal(cs.size, 3, err_msg)

              # Insulated (layered) constructions (i.e. part of the building
              # envelope) inherit area-weighted air film resistances, if relying
              # on the 'structure' option.
              cs.each do |lc|
                id = lc.nameString
                tP = lc.additionalProperties.getFeatureAsString("btap_type")
                fR = lc.additionalProperties.getFeatureAsDouble("btap_film")

                err_msg = "#{id} 'btap_film' (#{cas})"
                refute_empty(fR)

                fR = fR.get

                unless tP.empty?
                  tP = tP.get
                  err_msg = "Unknown type #{id} #{tP} (#{cas})"
                  assert_includes(tPs, tP, err_msg)

                  fr = 0.150
                  fr = 0.266 if tP == "roofs" # i.e. attic floor

                  err_msg = "Unknown type #{id} #{tP} (#{cas})"
                  assert_includes(tPs, tP, err_msg)
                  err_msg = "#{id} #{fR.round(3)} vs #{fr.round(3)} (#{cas})"
                  assert_equal(fR.round(3), fr.round(3))
                else
                  fr = 0.160 # slab-on-grade

                  err_msg = "#{id} #{fR.round(3)} vs #{fr.round(3)} (#{cas})"
                  assert_equal(fR.round(3), fr.round(3))
                end
              end

              # NECB2015: No uprating (Uo == NECB prescriptive requirements).
              if template == "NECB2015"
                slab_m2  = 0
                floor_m2 = 0 # insulated attic 'floors' - no insulated 'roofs'

                cs.each do |c|
                  id = c.nameString
                  m2 = c.getNetArea
                  uo = c.additionalProperties.getFeatureAsDouble("btap_uo").get
                  xd = c.additionalProperties.getFeatureAsString("btap_id")
                  fR = c.additionalProperties.getFeatureAsDouble("btap_film").get
                  tP = c.additionalProperties.getFeatureAsString("btap_type")

                  # puts "#{id} U-factor : #{uo.round(3)} W/m2.K (#{m2.round} m2)"
                  # OSut:CON:slab        U-factor : 0.757 W/m2.K (232 m2)
                  # OSut:CON:partition 4 U-factor : 0.162 W/m2.K (232 m2)
                  # OSut:CON:wall        U-factor : 0.210 W/m2.K (124 m2)

                  unless tP.empty?
                    tP = tP.get
                    err_msg = "Unknown type #{id} #{tP} (#{cas})"
                    assert_includes(tPs, tP, err_msg)

                    if tP == "roofs" # i.e. attic floors
                      floor_m2 += m2
                      err_msg = "BTAP NECB2015 attic floor Uo-factor (#{cas})"
                      assert_equal(uo.round(3), 0.162, err_msg)
                      err_msg = "BTAP attic floor construction ID (#{cas})"
                      refute_empty(xd, err_msg)
                      err_msg = "BTAP costed attic floor construction ID (#{cas})"
                      assert_equal(xd.get, "BTAP-ExteriorRoof-IEAD-4", err_msg)

                      uO = 1/TBD.rsi(c, fR)
                      err_msg = "BTAP #{id} calculated RSI #{uO.round(2)} (#{cas})"
                      assert_equal(uo.round(2), uO.round(2), err_msg)
                    else
                      err_msg = "BTAP NECB2015 wall Uo-factor (#{cas})"
                      assert_equal(uo.round(3), 0.210, err_msg)
                      err_msg = "BTAP wall construction ID (#{cas})"
                      refute_empty(xd, err_msg)
                      err_msg = "BTAP costed wall construction ID (#{cas})"
                      assert_equal(xd.get, "BTAP-ExteriorWall-SteelFramed-2", err_msg)

                      uO = 1 / TBD.rsi(c, fR)
                      err_msg = "BTAP #{id} calculated RSI #{uO.round(2)} (#{cas})"
                      assert_equal(uo.round(2), uO.round(2), err_msg)
                    end
                  else
                    slab_m2 += m2
                    err_msg = "BTAP NECB2015 slab-on-grade Uo-factor (#{cas})"
                    assert_equal(uo.round(3), 0.757, err_msg)
                    err_msg = "BTAP slab-on-grade construction ID (#{cas})"
                    assert_empty(xd, err_msg)

                    # NECB prescriptive U-factor requirements for slabs-on-grade
                    # are limited to perimeter insulation (1.2m in width) for
                    # climate zones < 8. The "btap_uo" value reflects this. This
                    # should eventually inform BTAP's use of KIVA (@todo).
                    uO = 1 / TBD.rsi(c, fR)

                    err_msg = "BTAP #{id} calculated USI #{uO.round(2)} (#{cas})"
                    assert_equal(uO.round(3), 2.346, err_msg) # not 0.757
                    err_msg = "BTAP #{id} calculated RSI #{uO.round(2)} (#{cas})"
                    refute_equal(uo.round(2), uO.round(2), err_msg)
                  end
                end

                # No sloped skylights in initial BTAP SRR solution. Attic floor
                # area should therefore equal slab-on-grade area.
                err_msg = "BTAP NECB2015 slab/roof area (#{cas})"
                assert_equal(slab_m2.round, floor_m2.round, err_msg)
              end
            end
          end

          # Limit anaylsis to CONDITIONED spaces (e.g. no vented attics).
          # Isolate OCCUPIED spaces from UNOCCUPIED spaces (e.g. plenums).
          # Isolate non-customized spaces (may include customized plenums).
          cspaces = model.getSpaces.reject { |sp| TBD.unconditioned?(sp) }
          cspaces = cspaces.reject { |sp| s.spaces.key?(sp.nameString)}
          ospaces = cspaces.select { |sp| sp.partofTotalFloorArea }

          cm2 = 0
          om2 = 0

          cspaces.each do |space|
            zn = space.thermalZone
            next if zn.empty?

            sm2  = space.floorArea
            cm2 += sm2
            om2 += sm2 if ospaces.include?(space)
          end

          if option.empty?
            err_msg = "Internal mass definitions (#{cas})?"
            assert_empty(model.getInternalMassDefinitions)
            err_msg = "Internal mass (#{cas})?"
            assert_empty(model.getInternalMasss)
          else
            kg   = 0
            mkg  = s.deadload * cm2
            mkg += s.liveload * om2

            err_msg = "Missing internal mass definitions (#{cas})?"
            refute_empty(model.getInternalMassDefinitions)
            err_msg = "Missing internal mass (#{cas})?"
            refute_empty(model.getInternalMasss)

            model.getInternalMasss.each do |imass|
              id      = imass.nameString
              m2      = imass.surfaceArea
              err_msg = "#{id} (#{cas})?"
              refute_empty(m2, err_msg)
              m2      = m2.get
              c       = imass.internalMassDefinition.construction
              err_msg = "#{id} construction (#{cas})?"
              refute_empty(c, err_msg)
              c       = c.get.to_LayeredConstruction
              err_msg = "#{id} layered construction (#{cas})?"
              refute_empty(c, err_msg)
              layers  = c.get.layers
              err_msg = "#{id} construction layers (#{cas})?"
              assert_equal(layers.size, 1, err_msg)
              mat     = layers.first.to_StandardOpaqueMaterial
              err_msg = "#{id} material (#{cas})?"
              refute_empty(mat, err_msg)
              mat     = mat.get
              m3      = mat.thickness * m2
              mass    = m3 * mat.density
              kg     += mass
              space   = imass.space
              err_msg = "#{id} space (#{cas})?"
              refute_empty(space, err_msg)
              space   = space.get
              ide     = space.nameString

              if s.spaces.key?(ide)
                fm2     = space.floorArea
                dkg     = s.spaces[ide][:deadload] * fm2
                dkg    += s.liveload * fm2 if space.partofTotalFloorArea
                err_msg = "#{id} #{ide} load (#{cas})?"
                assert_equal(dkg.round(2), mass.round(2), err_msg)
                mkg    += dkg
              end
            end

            unless mkg.round == kg.round
              fdback << "Internal mass #{kg.round} vs #{mkg.round} (#{cas})!"
              @test_passed = false
            end
          end

          unless s.data[:category].include?(s.category)
            fdback << "Invalid category #{s.category} (#{cas})!"
            @test_passed = false
          end

          unless s.data[:structure].include?(s.structure)
            fdback << "Invalid structure #{s.structure} (#{cas})!"
            @test_passed = false
          end

          if @test_passed
            co2_structure = s.co2[:columns] + s.co2[:partitions]

            s.spaces.values.each do |prp|
              co2_structure += prp[:co2][:columns] + prp[:co2][:partitions]
            end

            err_msg = "BUILDING kgCO2-e (#{cas}) 1?"
            assert_equal(co2_structure.round, co2.round, err_msg)
            err_msg = "BUILDING kgCO2-e (#{cas}) 2?"
            assert_equal(co2_structure.round, s.co2[:structure].round, err_msg)

            # Reset for non-customized spaces only.
            co2_structure = s.co2[:columns] + s.co2[:partitions]

            co2m2 = ": #{(co2_structure/cm2).round} kgCO2-e/m2 (A1-A3)"
            fdback << "#{cas} : #{s.category} (#{s.structure}, #{nst})" + co2m2

            s.spaces.each do |id, prp|
              next unless prp.key?(:structure)
              next unless prp.key?(:m2)

              sp_co2 = prp[:co2][:columns] + prp[:co2][:partitions]
              state  = "... #{id} : custom STRUCTURE #{prp[:structure]}"
              state += " #{(sp_co2/prp[:m2]).round} kgCO2-e/m2 (A1-A3)"
              fdback << state
            end
          end

          s.feedback[:logs].each { |log| puts log }
        end                 # |option  |
      end                   # |template|
    end                     # |building|

    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
