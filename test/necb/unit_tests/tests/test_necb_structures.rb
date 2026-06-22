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

    # Range of test options.
    @epws = ["CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"]

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
      "NECB2020"
    ]

    @options = [
      # "",
      "structure"
    ]

    # AdditionalProperty override.
    @addprop = true

    tg  = "co2_structure"
    tag = "space_conditioning_category"

    fdback = []
    fdback << ""
    fdback << "BTAP::Structure Unit Tests"
    fdback << "~~~~  ~~~~~~~~~ ~~~~ ~~~~~"

    @epws.sort.each          do |epw     |
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
            #   - the fine storage space has a user-assigned wood-framing only
            #   - the bulk storage area has a user-assigned CMU structure
            if @addprop && building == "Warehouse"
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
              prop = space.additionalProperties.getFeatureAsString(tag)
              next if prop.empty?
              next if space.partofTotalFloorArea

              prop = prop.get.downcase
              attics  << space if prop == "unconditioned"
              plenums << space if prop == "nonresconditioned"
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

            if @addprop && building == "Warehouse"
              err_msg = "# Default Construction Sets (#{cas})?"
              assert_equal(csets.size, 3, err_msg)
              err_msg = "# custom spaces (#{cas})?"
              assert_equal(s.spaces.size, 2, err_msg)

              # id1  = "Zone1 Office"
              # id2  = "Zone2 Fine Storage"

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
            else
              nb  = 1
              nb += 1 unless plenums.empty?
              nb += 1 unless attics.empty?

              err_msg = "# Default Construction Sets (#{cas})?"
              assert_equal(csets.size, nb, err_msg)

              err_msg = "# custom spaces (#{cas})?"
              assert_equal(s.spaces.size, 0, err_msg)
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

              sm2  = space.floorArea * space.multiplier * zn.get.multiplier
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
                fdback << "Internal mass #{kg.round} (#{cas})!"
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

              if @addprop
                s.spaces.values.each do |prp|
                  co2_structure += prp[:co2][:columns] + prp[:co2][:partitions]
                end
              end

              err_msg = "BUILDING kgCO2-e (#{cas}) 1?"
              assert_equal(co2_structure.round, co2.round, err_msg)
              err_msg = "BUILDING kgCO2-e (#{cas}) 2?"
              assert_equal(co2_structure.round, s.co2[:structure].round, err_msg)

              # Reset for non-customized spaces only.
              co2_structure = s.co2[:columns] + s.co2[:partitions]

              co2m2 = ": #{(co2_structure/cm2).round} kgCO2-e/m2 (A1-A3)"
              fdback << "#{cas} : #{s.category} (#{s.structure}, #{nst})" + co2m2

              if @addprop
                s.spaces.each do |id, prp|
                  next unless prp.key?(:structure)
                  next unless prp.key?(:m2)

                  sp_co2 = prp[:co2][:columns] + prp[:co2][:partitions]
                  state  = "... #{id} : custom STRUCTURE #{prp[:structure]}"
                  state += " #{(sp_co2/prp[:m2]).round} kgCO2-e/m2 (A1-A3)"
                  fdback << state
                end
              end
            end

            s.feedback[:logs].each { |log| puts log }
          end                 # |option  |
        end                   # |template|
      end                     # |building|
    end                       # |epw     |

    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
