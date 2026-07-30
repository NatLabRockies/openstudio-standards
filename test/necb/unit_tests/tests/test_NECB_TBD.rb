require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'tbd'
require 'json'

# Checks whether TBD is correctly deployed within BTAP.
class NECB_TBD_Tests < Minitest::Test
  def test_necb_tbd()
    outd = "output/test_necb_tbd"
    eres = "../expected_results/necb_tbd_expected_results.json"
    tres = "../expected_results/necb_tbd_test_results.json"
    sizd = "sizing_folder"

    @output_folder         = File.join(__dir__, outd)
    @expected_results_file = File.join(__dir__, eres)
    @test_results_file     = File.join(__dir__, tres)
    @sizing_run_dir        = File.join(@output_folder, sizd)
    @test_results_array    = []

    # Intial test condition.
    @test_passed = true

    # Range of test options.
    @templates = [
      # 'NECB2011',
      # 'NECB2015',
      # 'NECB2017',
      'NECB2020',
      # 'NECB2025'
    ]

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
      'SmallOffice',
      # 'Warehouse'
    ]

    @structure = [
      # '',
      'structure'
    ]

    # BTAP currently supports 4 options when enabling linear thermal bridging
    # calculations (e.g. uprating, derating), via the TBD gem.
    @options = [
      # 'none', # ignore linear thermal bridging altogether
      # 'bad',  # derating from poor thermal bridging details
      # 'good', # derating from better thermal bridging details
      'uprate'  # uprating (then derating) per NECB2017, NECB2020, NECB2025
    ]

    # PSI factor sets 'bad' or 'good' refer to costed BTAP details. If set
    # to 'uprate', psi factor sets are determined iteratively, see:
    #
    #   lib/openstudio-standards/btap/bridging.rb
    #
    # AdditionalProperties tag derated surfaces with their initial,
    # code-required Uo factors (whether derating or not).
    #
    # BTAP holds discrete performance levels for each e.g. wall construction:
    # discrete U factors, from 0.314 down to 0.100 (or even 0.080 ... it
    # depends on the construction). When (successfully) uprating, TBD will
    # often report a required Uo factor (a starting point) lying somewhere
    # between discrete BTAP levels, e.g. 0.124. As long as the TBD-reported Uo
    # lies somewhere above the lowest U factor for that BTAP construction, it's
    # compliant.
    #
    # If 'interpolating', the BTAP costing solution would need to interpolate
    # between 2 discrete levels of performance (e.g. 0.130 < 0.124 < 0.100), to
    # determine final costs for a given surface type. If 'not interpolating',
    # the solution becomes more categorical, with the inconvenience of being
    # more expensive (i.e. 0.100 $$$ > 0.124 $$).
    @interpolate = [
      true,
      # false
    ]

    # AdditionalProperty override.
    @addprop = true

    tag = "space_conditioning_category"
    epw = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'

    fdback = []
    fdback << ""
    fdback << "BTAP/TBD Unit Tests"
    fdback << "~~~~ ~~~~ ~~~~ ~~~~"

    @templates.sort.each      do |template |
      @buildings.sort.each    do |building |
        @structure.sort.each  do |structure|
          @options.sort.each  do |option   |
            @interpolate.each do |inter    |
              next if inter && option != "uprate"

              cas  = "CASE #{option} | #{building} (#{template})"
              cas += " - structure" unless structure.empty?
              cas += " - interpolating" if inter && option == 'uprate'
              fdback << ""
              fdback << cas
              st = Standard.build(template)

              # Customizing STRUCTURE options (similar to the unit test
              # 'test_necb_structures'. STRUCTURE customization triggers thermal
              # bridging PSI factor variants in BTAP. In this Warehouse example,
              # the building would inherit a steel (or metal) structure by
              # default. This is overridden here as all 3 spaces are customized:
              #   - the office has a user-assigned wood structure
              #   - the fine storage space has user-assigned wood-framing
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

                # Validate.
                err_msg1 = "Missing AddProp '#{opt1}' #{id1} (#{cas})?"
                err_msg2 = "Missing AddProp '#{opt2}' #{id2} (#{cas})?"
                err_msg3 = "Missing AddProp '#{opt1}' #{id3} (#{cas})?"
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
                                                srr_opt: "osut",
                                                construction_opt: structure,
                                                tbd_option: option,
                                                tbd_interpolate: inter,
                                                sizing_run_dir: @sizing_run_dir)
              else
                model = st.model_create_prototype_model(template: template,
                                                        epw_file: epw,
                                                        building_type: building,
                                                        srr_opt: "osut",
                                                        construction_opt: structure,
                                                        tbd_option: option,
                                                        tbd_interpolate: inter,
                                                        sizing_run_dir: @sizing_run_dir)
              end

              if option == 'none'
                err_msg = "BTAP/TBD: Initialized ('#{cas}')?"
                assert_nil(st.tbd, err_msg)

                model.getSurfaces.each do |surface|
                  id = surface.nameString
                  next if surface.isGroundSurface

                  # Focus on boundary conditions: 'surface' & 'outdoors'.
                  boundary = surface.outsideBoundaryCondition.downcase
                  next unless ["surface", "outdoors"].include?(boundary)

                  # If TBD up/de-rating isn't requested (e.g. pre-NECB 2017),
                  # then all surfaces inherit 'defaulted' constructions, either:
                  #   - building-wide default construction set
                  #   - space-specific default construction sets, e.g.
                  #     - attics
                  #     - plenums
                  #     - customized spaces
                  err_msg  = "BTAP/TBD: #{id} defaulted construction (#{cas})?"
                  assert(surface.isConstructionDefaulted, err_msg)

                  lc      = surface.construction
                  film    = surface.filmResistance
                  err_msg = "BTAP/TBD: #{id} construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc      = lc.get.to_LayeredConstruction
                  err_msg = "BTAP/TBD: #{id} layered construction (#{cas})?"
                  refute_empty(lc, err_msg)

                  # No surface construction IDs hold any "c tbd" stamps.
                  lc      = lc.get
                  name    = lc.nameString.downcase
                  err_msg = "BTAP/TBD processes enabled (#{cas})?"
                  refute_includes(name, " c tbd", err_msg)

                  # The remaining tests are limited to automated construction
                  # generation and assignment using the BTAP's 'structure'
                  # option. These would likely fail with e.g. 3rd-party models
                  # holding uninsulated, mass walls in 19th-century buildings,
                  # or non-compliant curtainwall spandrels.
                  next unless structure == "structure"
                  next if @addprop && building == "Warehouse"

                  space   = surface.space
                  err_msg = "BTAP/TBD: #{id} space (#{cas})?"
                  refute_empty(space, err_msg)

                  # All spaces are tagged as either:
                  #   - 'unconditioned' (e.g. attics, crawlspaces), or
                  #   - 'nonresconditioned' (e.g. plenums, classrooms)
                  space = space.get
                  attic = false
                  prop  = space.additionalProperties.getFeatureAsString(tag)

                  err_msg = "BTAP/TBD: #{id} space condition (#{cas})?"
                  refute_empty(prop, err_msg)

                  unless space.partofTotalFloorArea
                    attic = prop.get.downcase == "unconditioned"
                  end

                  # The greatest (poorest) possible NECB Uo factor in insulated
                  # assemblies is 0.315 W/m2.K, or Rsi 3.17 (R18).
                  #
                  # The lowest possible Uo factor in uninsulated assemblies is
                  # approx. 4.46 W/m2.K, or RSi 0.224 (R 1.27).
                  #
                  # So there's quite a gap between insulated vs uninsulated
                  # constructions when working with the NECBs. A potentially
                  # simple way of determining whether an assembly is indeed
                  # insulated/costed: if TBD.rsi() > 1.0.
                  err_msg = "BTAP/TBD: #{id} attic rsi (#{cas})?"

                  if attic
                    if boundary == "outdoors"
                      assert(TBD.rsi(lc, film) < 1.0, err_msg) # uninsulated
                    else
                      adjacent = surface.adjacentSurface
                      err_msg  = "BTAP/TBD: #{id} adjacent (#{cas})?"
                      refute_empty(adjacent, err_msg)

                      other   = adjacent.get.space
                      err_msg = "BTAP/TBD: #{id} other (#{cas})?"
                      refute_empty(other, err_msg)

                      other = other.get
                      prop  = other.additionalProperties.getFeatureAsString(tag)

                      err_msg = "BTAP/TBD: #{id} space condition 2 (#{cas})?"
                      refute_empty(prop, err_msg)

                      if other.partofTotalFloorArea
                        assert(TBD.rsi(lc, film) > 1.0, err_msg)   # insulated
                      else
                        if prop.get.downcase == "unconditioned"    # 2nd attic?
                          assert(TBD.rsi(lc, film) < 1.0, err_msg) # uninsulated
                        else
                          assert(TBD.rsi(lc, film) > 1.0, err_msg) # insulated
                        end
                      end
                    end
                  else
                    if boundary == "outdoors"
                      assert(TBD.rsi(lc, film) > 1.0, err_msg) # insulated
                    end
                  end
                end

                fdback << "BTAP/TBD processes skipped"
              else
                err_msg = "BTAP/TBD: Uninitialized (#{cas})?"
                assert_kind_of(BTAP::Bridging, st.tbd, err_msg)
                err_msg = "BTAP/TBD: Missing model Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.model, err_msg)
                err_msg = "BTAP/TBD: Missing feedback Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.feedback, err_msg)
                err_msg = "BTAP/TBD: Missing feedback logs (#{cas})?"
                assert(st.tbd.feedback.key?(:logs), err_msg)
                # err_msg = "BTAP/TBD: Invalid feedback logs (#{cas})?"
                # assert_kind_of(Array, st.tbd.feedback[:logs], err_msg)
                # err_msg = "BTAP/TBD: Missing tally Hash (#{cas})?"
                # assert_kind_of(Hash, st.tbd.tally, err_msg)
                # err_msg = "BTAP/TBD: Missing model 'comply' key (#{cas})?"

                # assert(st.tbd.model.key?(:complies), err_msg)

                # if st.tbd.model[:complies]
                  # fdback << " ... compliant!"
                # else
                  # fdback << " ... non-compliant!"
                # end

                # err_msg = "BTAP/TBD: Missing TBD 'surfaces' (#{cas})?"
                # assert(st.tbd.model.key?(:surfaces), err_msg)
                # err_msg = "BTAP/TBD: TBD 'surfaces' Hash (#{cas})?"
                # assert_kind_of(Hash, st.tbd.model[:surfaces], err_msg)
                # err_msg = "BTAP/TBD: Empty TBD 'surfaces' (#{cas})?"
                # refute_empty(st.tbd.model[:surfaces], err_msg)
                # surfaces = st.tbd.model[:surfaces]

                # Regardless of whether BTAP/TBD were successful or not in
                # uprating the building constructions (option == 'uprate'),
                # deratable surfaces should have been derated nonetheless.
                model.getSurfaces.each do |surface|
                  id   = surface.nameString
                  film = surface.filmResistance
                  # err_msg = "BTAP/TBD: Mismatched #{id} surfaces (#{cas})?"
                  # assert(surfaces.key?(id), err_msg)
                  # next unless surfaces[id].key?(:deratable)
                  # next unless surfaces[id].key?(:type     )
                  # next unless surfaces[id].key?(:heatloss )
                  # next unless surfaces[id][:deratable]
                  # next unless surfaces[id][:heatloss ].abs > TBD::TOL
                  next unless surface.outsideBoundaryCondition.downcase == "outdoors" # TEMPORARY!!

                  lc = surface.construction
                  err_msg = "BTAP/TBD: Nilled #{id} construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc.get.to_LayeredConstruction
                  err_msg = "BTAP/TBD: Nilled #{id} layered construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc = lc.get
                  next unless lc.additionalProperties.hasFeature("btap_uo")

                  nom     = lc.nameString.downcase
                  err_msg = "Failed TBD processes #{nom} #{id} (#{cas})?"
                  assert_includes(nom, " c tbd", err_msg)

                  # prop = surface.additionalProperties.getFeatureAsDouble("btap_uo")
                  # err_msg = "BTAP/TBD: #{id} uprated Uo (#{cas})?"

                  if option == 'uprate'
                    # refute_empty(prop, err_msg)
                    # puts "#{id} : #{lc.nameString} #{lc.additionalProperties.getFeatureAsDouble("btap_uo").get}"

                    # Initial, uprated Uo, e.g. (FullServiceRestaurant):
                    #   0:1:1:0:1:Dining : 0.130 (R44) # skylight well wall
                    #   0:1:1:Dining     : 0.100 (R57) # insulated attic ceiling
                    # uo = prop.get
                    # puts "#{id} : #{uo.round(3)} vs #{(1/TBD.rsi(lc, film)).round(3)}"

                    # err_msg = "BTAP/TBD: #{id} Uo vs U (#{cas})?"
                    # assert(uo < 1/TBD.rsi(lc, film))
                  else
                    # assert_empty(prop, err_msg)
                  end
                end

                # Note: BTAP/TBD feedback logs are simple strings. Look up
                #       st.tbd.tally Hash to extract quantities for costing.
                # st.tbd.feedback[:logs].each { |log| fdback << log }
              end
            end                # |inter    |
          end                  # |option   |
        end                    # |structure|
      end                      # |building |
    end                        # |template |

    # Temporary.
    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
