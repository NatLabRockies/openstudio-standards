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
      'FullServiceRestaurant',
      # 'HighriseApartment',
      # 'Hospital',
      # 'LargeHotel',
      # 'LargeOffice',
      # 'LEEPMidriseApartment',
      # 'LEEPPointTower',
      # 'LEEPTownHouse',
      # 'LEEPMultiTower',
      'LowriseApartment',
      'MediumOffice',
      'MidriseApartment',
      # 'Outpatient',
      # 'PrimarySchool',
      'QuickServiceRestaurant',
      'RetailStandalone',
      'RetailStripmall',
      # 'SecondarySchool',
      'SmallHotel',
      'SmallOffice',
      'Warehouse'
    ]

    @templates = [
      "NECB2011",
      # "NECB2015",
      # "NECB2017",
      "NECB2020"
    ]

    @options = [
      "",
      "structure"
    ]

    fdback = []
    fdback << ""
    fdback << "BTAP::Structure Unit Tests"
    fdback << "~~~~  ~~~~~~~~~ ~~~~ ~~~~~"

    @epws.sort.each          do |epw      |
      @buildings.sort.each   do |building |
        @templates.sort.each do |template |
          @options.sort.each do |option   |
            cas   = "CASE #{building} (#{template})"
            cas  += " #" unless option.empty?
            tag   = "space_conditioning_category"
            st    = Standard.build(template)
            model = st.model_create_prototype_model(template: template,
                                                    epw_file: epw,
                                                    building_type: building,
                                                    construction_opt: option,
                                                    sizing_run_dir: @sizing_run_dir)

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
              err_msg = "BTAP::Structure #{id} default construction set (#{cas})?"
              refute_empty(set, err_msg)

              set = set.get
              id  = set.nameString
              err_msg = "BTAP::Structure default construction set #{id} (#{cas})?"
              assert_includes(id, "ATTIC", err_msg)

              attic.surfaces.each do |surface|
                id = surface.nameString
                c  = surface.construction.get.to_LayeredConstruction.get
                next unless c.layers.size == 2
                next unless surface.surfaceType.downcase == "floor"

                if id.include?("soffit")
                  err_msg = "BTAP::Structure #{id} insulated (#{cas})?"

                  # Soffit 'floor' not insulated.
                  c.layers.each do |layer|
                    assert_includes(layer.nameString, "material", err_msg)
                  end
                else
                  id = c.layers.last.nameString
                  err_msg = "BTAP::Structure #{id} insulation layer (#{cas})?"
                  assert_includes(id, "cellulose", err_msg)
                end
              end
            end

            plenums.each do |plenum|
              break if option.empty?

              id  = plenum.nameString
              set = plenum.defaultConstructionSet
              err_msg = "BTAP::Structure #{id} default construction set (#{cas})?"
              refute_empty(set, err_msg)

              set = set.get
              id  = set.nameString
              err_msg = "BTAP::Structure default construction set #{id} (#{cas})?"
              assert_includes(id, "PLENUM", err_msg)

              plenum.surfaces.each do |surface|
                next unless surface.surfaceType.downcase == "floor"

                id = surface.nameString
                c  = surface.construction.get.to_LayeredConstruction.get
                n  = c.layers.size
                err_msg = "BTAP::Structure #{id} ##{n} layers (#{cas})?"
                assert_equal(n, 1, err_msg)

                id = c.layers.first.nameString
                err_msg = "BTAP::Structure #{id} tile (#{cas})?"
                assert_includes(id, "material", err_msg)
              end
            end

            s = st.structure

            err_msg = "BTAP::Structure #{s.class} (#{cas})?"
            assert_kind_of(BTAP::Structure, s, err_msg)
            err_msg = "BTAP::Structure data #{s.data.class} (#{cas})?"
            assert_kind_of(Hash, s.data, err_msg)
            err_msg = "BTAP::Structure category #{s.category.class} (#{cas})?"
            assert_kind_of(String, s.category, err_msg)
            err_msg = "BTAP::Structure structure #{s.structure.class} (#{cas})?"
            assert_kind_of(Symbol, s.structure, err_msg)
            err_msg = "BTAP::Structure liveload #{s.liveload.class} (#{cas})?"
            assert_kind_of(Float, s.liveload, err_msg)
            err_msg = "BTAP::Structure deadload #{s.deadload.class} (#{cas})?"
            assert_kind_of(Float, s.deadload, err_msg)
            err_msg = "BTAP::Structure missing categories (#{cas})?"
            assert(s.data.key?(:category), err_msg)
            err_msg = "BTAP::Structure missing structures (#{cas})?"
            assert(s.data.key?(:structure), err_msg)

            tload    = s.liveload + s.deadload
            cspaces  = model.getSpaces.select { |sp| sp.partofTotalFloorArea }
            floor_m2 = TBD.facets(cspaces, "all", "floor").map(&:grossArea).sum

            if option.empty?
              err_msg = "BTAP::Structure internal mass definitions (#{cas})?"
              assert_empty(model.getInternalMassDefinitions)
              err_msg = "BTAP::Structure internal mass (#{cas})?"
              assert_empty(model.getInternalMasss)
            else
              err_msg = "BTAP::Structure misisng internal mass definitions (#{cas})?"
              refute_empty(model.getInternalMassDefinitions)
              err_msg = "BTAP::Structure missing internal mass (#{cas})?"
              refute_empty(model.getInternalMasss)

              kg = 0

              model.getInternalMasss.each do |imass|
                id      = imass.nameString
                m2      = imass.surfaceArea
                err_msg = "BTAP::Structure #{id} (#{cas})?"
                refute_empty(m2, err_msg)
                m2      = m2.get
                c       = imass.internalMassDefinition.construction
                err_msg = "BTAP::Structure #{id} construction (#{cas})?"
                refute_empty(c, err_msg)
                c       = c.get.to_LayeredConstruction
                err_msg = "BTAP::Structure #{id} layered construction (#{cas})?"
                refute_empty(c, err_msg)
                layers  = c.get.layers
                err_msg = "BTAP::Structure #{id} construction layers (#{cas})?"
                assert_equal(layers.size, 1, err_msg)
                mat     = layers.first.to_StandardOpaqueMaterial
                err_msg = "BTAP::Structure #{id} material (#{cas})?"
                refute_empty(mat, err_msg)
                mat     = mat.get
                m3      = mat.thickness * m2
                kg     += m3 * mat.density
              end

              kgm2 = kg / floor_m2

              unless kgm2.round == (s.liveload + s.deadload).round
                fdback << "BTAP::Structure internal mass #{kgm2.round} (#{cas})!"
                @test_passed = false
              end
            end

            unless s.data[:category].include?(s.category)
              fdback << "BTAP::Structure invalid category #{s.category} (#{cas})!"
              @test_passed = false
            end

            unless s.data[:structure].include?(s.structure)
              fdback << "BTAP::Structure invalid structure #{s.structure} (#{cas})!"
              @test_passed = false
            end

            if @test_passed
              co2m2 = ": #{(s.co2[:structure]/floor_m2).round} kgCO2-e/m2 (A1-A3)"
              fdback << "#{cas} : #{s.category} (#{s.structure}, #{nst})" + co2m2
            end

            s.feedback[:logs].each { |log| puts log }
          end                 # |option   |
        end                   # |template |
      end                     # |building |
    end                       # |epw      |

    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
