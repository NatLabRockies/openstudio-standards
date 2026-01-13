require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'tbd'
require 'json'

# This checks whether TBD is correctly deployed within BTAP.
class NECB_TBD_Tests < Minitest::Test
  def test_necb_tbd()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_necb_tbd')
    @expected_results_file = File.join(__dir__, '../expected_results/necb_tbd_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/necb_tbd_test_results.json')
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')
    @test_results_array = [] # test results storage array

    # Intial test condition.
    @test_passed = true

    # Hard setting climate & fuel.
    @epw  = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    @fuel = 'Electricity'
    @srr  = 'osut'

    # Range of test options.
    @templates = [
      'NECB2011',
      # 'NECB2015',
      # 'NECB2017',
      'NECB2020'
    ]

    @buildings = [
      'FullServiceRestaurant',
      # 'HighriseApartment',
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
      # 'NorthernEducation',  # *
      # 'NorthernHealthCare', # *
      # 'Outpatient',
      # 'PrimarySchool',
      # 'QuickServiceRestaurant',
      # 'RetailStandalone',
      # 'RetailStripmall',
      # 'SecondarySchool',
      # 'SmallHotel',
      'SmallOffice',
      'Warehouse'
    ]

    # (*) 'NorthernEducation' and 'NorthernHealthCare' have neither:
    #       - Building.standardsNumberOfStories
    #       - Building.standardsNumberOfAboveStories
    #
    #     ... and so both templates/models fail early on, irrespective of
    #         BTAP::Activity features - @todo.

    @structure = [
      '',
      'structure'
    ]

    # Optional PSI factor sets (e.g. optional for pre-NECB2017 templates). If
    # :none, neither TBD 'uprating' nor 'derating' calculations (and subsequent
    # modifications to generated OpenStudio models) are carried out. If instead
    # set to :uprate, psi factor sets are determined iteratively, see:
    #
    #   lib/openstudio-standards/btap/bridging.rb
    #
    # Otherwise, :bad vs :good PSI factor sets refer to costed BTAP details.
    #
    # @todo: For options 'bad' and 'good' (simple derating), deploy a similar
    #        AdditionalProperty strategy (when uprating) to tag derated
    #        surfaces with their initial, code-required Uo factors.
    #
    @options = [
      'none',
      'bad',
      # 'good',
      'uprate'
    ]

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
      # true,
      false
    ]

    tag = "space_conditioning_category"
    tg  = "uprated_Uo"

    fdback = []
    fdback << ""
    fdback << "BTAP/TBD Unit Tests"
    fdback << "~~~~ ~~~~ ~~~~ ~~~~"

    @templates.sort.each      do |template |
      @buildings.sort.each    do |building |
        @structure.sort.each  do |structure|
          @options.sort.each  do |option   |
            @interpolate.each do |inter    |
              next if building == "NorthernEducation"
              next if building == "NorthernHealthCare"
              next if inter && option != "uprate"

              cas  = "CASE #{option} | #{building} (#{template})"
              cas += " - structure" unless structure.empty?
              cas += " - interpolating" if inter && option == 'uprate'
              fdback << ""
              fdback << cas
              st = Standard.build(template)
              model = st.model_create_prototype_model(template:template,
                                                      construction_opt: structure,
                                                      epw_file: @epw,
                                                      srr_opt: @srr,
                                                      building_type: building,
                                                      primary_heating_fuel: @fuel,
                                                      tbd_option: option,
                                                      tbd_interpolate: inter,
                                                      sizing_run_dir: @sizing_run_dir)

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
                  #       - attics
                  #       - plenums
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
                err_msg = "BTAP/TBD: Invalid feedback logs (#{cas})?"
                assert_kind_of(Array, st.tbd.feedback[:logs], err_msg)
                err_msg = "BTAP/TBD: Missing tally Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.tally, err_msg)
                err_msg = "BTAP/TBD: Missing model 'comply' key (#{cas})?"

                assert(st.tbd.model.key?(:complies), err_msg)

                if st.tbd.model[:complies]
                  fdback << " ... compliant!"
                else
                  fdback << " ... non-compliant!"
                end

                err_msg = "BTAP/TBD: Missing TBD 'surfaces' (#{cas})?"
                assert(st.tbd.model.key?(:surfaces), err_msg)
                err_msg = "BTAP/TBD: TBD 'surfaces' Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.model[:surfaces], err_msg)
                err_msg = "BTAP/TBD: Empty TBD 'surfaces' (#{cas})?"
                refute_empty(st.tbd.model[:surfaces], err_msg)
                surfaces = st.tbd.model[:surfaces]

                # Regardless of whether BTAP/TBD were successful or not in
                # uprating the building constructions (option == 'uprate'),
                # deratable surfaces should have been derated nonetheless.
                model.getSurfaces.each do |surface|
                  id = surface.nameString
                  err_msg = "BTAP/TBD: Mismatched #{id} surfaces (#{cas})?"
                  assert(surfaces.key?(id), err_msg)
                  next unless surfaces[id].key?(:deratable)
                  next unless surfaces[id].key?(:type     )
                  next unless surfaces[id].key?(:heatloss )
                  next unless surfaces[id][:deratable]
                  next unless surfaces[id][:heatloss ].abs > TBD::TOL

                  lc      = surface.construction
                  film    = surface.filmResistance
                  err_msg = "BTAP/TBD: #{id} construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc      = lc.get.to_LayeredConstruction
                  err_msg = "BTAP/TBD: #{id} layered construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc      = lc.get
                  nom     = lc.nameString.downcase
                  err_msg = "Failed TBD processes (#{cas})?"
                  assert_includes(nom, " c tbd", err_msg)

                  prop = surface.additionalProperties.getFeatureAsDouble(tg)
                  err_msg = "BTAP/TBD: #{id} uprated Uo (#{cas})?"

                  unless option == 'uprate'
                    assert_empty(prop, err_msg)
                  else
                    refute_empty(prop, err_msg)

                    # Initial, uprated Uo, e.g. (FullServiceRestaurant):
                    #   0:1:1:0:1:Dining : 0.130 (R44) # skylight well wall
                    #   0:1:1:Dining     : 0.100 (R57) # insulated attic ceiling
                    uo = prop.get
                    # puts "#{id} : #{uo.round(3)} vs #{(1/TBD.rsi(lc, film)).round(3)}"

                    err_msg = "BTAP/TBD: #{id} Uo vs U (#{cas})?"
                    assert(uo < 1/TBD.rsi(lc, film))
                  end
                end

                # Note: BTAP/TBD feedback logs are simple strings. Look up
                #       st.tbd.tally Hash to extract quantities for costing.
                st.tbd.feedback[:logs].each { |log| fdback << log }
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
