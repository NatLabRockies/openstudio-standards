require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

# Checks if BTAP::Structure instances are correctly deployed within BTAP.
class MURB_OA_Tests < Minitest::Test
  def test_murb_oa()
    outd = "output/test_murb_oa"
    eres = "../expected_results/murb_oa_expected_results.json"
    tres = "../expected_results/murb_oa_results.json"
    sizd = "sizing_folder"

    @output_folder         = File.join(__dir__, outd)
    @expected_results_file = File.join(__dir__, eres)
    @test_results_file     = File.join(__dir__, tres)
    @szg_dir               = File.join(@output_folder, sizd)
    @test_results_array    = []

    # Intial test condition.
    @test_passed = true

    @buildings = [
      # 'HighriseApartment',
      # 'HighriseApartmentMult',
      'LEEPMidriseApartment',
      # 'LEEPMultiTower',
      # 'LEEPPointTower',
      # 'LEEPTownHouse',
      # 'LowriseApartment',
      # 'MidriseApartment'
    ]

    @templates = [
      # "NECB2011",
      # "NECB2015",
      # "NECB2017",
      "NECB2020",
      # "NECB2025"
    ]

    @options = [
      "",      # BTAP default solution
      "a622",  # ANSI/ASHRAE 62.2 2016
      # "a621",  # ANSI/ASHRAE 62.1 2016
      # "nbc932" # National Building Code of Canada (NBC 9.32, 2025)
    ]

    @dryers = ["vented", "ventless"]

    epw = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"

    fdback = []
    fdback << ""
    fdback << "BTAP: MURB OA Unit Tests"
    fdback << "~~~~  ~~~~~~~~~~~~~~~~~~"

    @buildings.sort.each    do |building|
      @templates.sort.each  do |template|
        @options.sort.each  do |option  |
          @dryers.sort.each do |dryer   |
            cas   = "CASE #{building} (#{template})"
            cas  += " - #{option}" unless option.empty?
            st    = Standard.build(template)
            vtl   = dryer == "vented" ? false : true
            model = st.model_create_prototype_model(template: template,
                                                    epw_file: epw,
                                                    building_type: building,
                                                    construction_opt: 'structure',
                                                    murb_oa: option,
                                                    ventless: vtl,
                                                    sizing_run_dir: @szg_dir)
            model.getSpaceTypes.each do |type|
              next if type.spaces.empty?

              stOA  = type.designSpecificationOutdoorAir
              refute_empty(stOA, "#{cas}: spacetype OA empty?")
              stOA  = stOA.get
              stOAp = stOA.additionalProperties
              units = type.spaces.select { |sp| st.activity.act(sp) == "units" }

              units.each do |space|
                id    = space.nameString
                spOA  = space.designSpecificationOutdoorAir
                refute_empty(spOA, "#{cas}: #{id} OA empty?")
                spOA  = spOA.get
                spOAp = spOA.additionalProperties

                emsg = "#{cas}: spacetype non-defaulted OA method?"
                refute(stOA.isOutdoorAirMethodDefaulted, emsg)
                emsg = "#{cas}: spacetype OA method?"
                assert_equal(stOA.outdoorAirMethod.downcase, "sum", emsg)

                # Convert from m^3/s to L/s, or from cfm to L/s.
                q      = spOA.outdoorAirFlowRate * 1000
                qM2    = spOA.outdoorAirFlowperFloorArea * 1000
                qP     = spOA.outdoorAirFlowperPerson * 1000
                qACH   = spOA.outdoorAirFlowAirChangesperHour * 1000
                r      = spOAp.getFeatureAsDouble("Ref OA cfm")
                rM2    = spOAp.getFeatureAsDouble("Ref OA per area")
                rP     = spOAp.getFeatureAsDouble("Ref OA per person")
                rACH   = spOAp.getFeatureAsDouble("Ref OA ach")
                rHOOD  = spOAp.getFeatureAsDouble("HOOD EXH cfm")
                rDRYER = spOAp.getFeatureAsDouble("DRYER EXH cfm")
                refute_empty(     r, "#{cas}Ref OA cfm?")
                refute_empty(   rM2, "#{cas}Ref OA rM2?")
                refute_empty(    rP, "#{cas}Ref OA rP?")
                refute_empty(  rACH, "#{cas}Ref OA rACH?")
                refute_empty( rHOOD, "#{cas}Ref OA rP?")
                refute_empty(rDRYER, "#{cas}Ref OA rACH?")
                r      =      r.get
                rM2    =    rM2.get * 10.76 # from ft^2 to m^2
                rP     =     rP.get
                rACH   =   rACH.get
                rHOOD  =  rHOOD.get
                rDRYER = rDRYER.get
                r      = OpenStudio.convert(     r, "cfm", "L/s").get
                rM2    = OpenStudio.convert(   rM2, "cfm", "L/s").get
                rP     = OpenStudio.convert(    rP, "cfm", "L/s").get
                rACH   = OpenStudio.convert(  rACH, "cfm", "L/s").get
                rHOOD  = OpenStudio.convert( rHOOD, "cfm", "L/s").get
                rDRYER = OpenStudio.convert(rDRYER, "cfm", "L/s").get
                assert_in_delta(qACH, 0.00, 0.01, "#{cas} qACH != 0?")
                assert_in_delta(rACH, 0.00, 0.01, "#{cas} rACH != 0?")

                if option.empty?
                  emsg = "#{cas} #{id} OA not defaulted?"
                  assert(space.isDesignSpecificationOutdoorAirDefaulted, emsg)
                  assert_equal( stOA,  spOA, "Defaulted #{id} OA")
                  assert_equal(stOAp, spOAp, "Defaulted #{id} OA props")
                  assert_in_delta(     q, 0.00, 0.01, "#{cas} q != 0?")
                  refute_in_delta(   qM2, 0.00, 0.01, "#{cas} qM2 == 0?")
                  refute_in_delta(    qP, 0.00, 0.01, "#{cas} qP == 0?")
                  assert_in_delta(     r, 0.00, 0.01, "#{cas} r != 0?")
                  refute_in_delta(   rM2, 0.00, 0.01, "#{cas} rM2 == 0?")
                  refute_in_delta(    rP, 0.00, 0.01, "#{cas} q == 0?")
                  assert_in_delta( rHOOD, 0.00, 0.01, "#{cas} qHOOD != 0?")
                  assert_in_delta(rDRYER, 0.00, 0.01, "#{cas} qDRYER != 0?")
                  assert_in_delta(   qM2,  rM2, 0.01, "#{cas} qM2 != rM2?")
                  assert_in_delta(    qP,   rP, 0.01, "#{cas} qP != rP?")
                else
                  emsg = "#{cas} #{id} OA defaulted?"
                  refute(space.isDesignSpecificationOutdoorAirDefaulted, emsg)
                  refute_equal( stOA,  spOA, "Non-defaulted #{id} OA")
                  refute_equal(stOAp, spOAp, "Non-Defaulted #{id} OA props")
                  refute_in_delta(     q, 0.00, 0.01, "#{cas} q == 0?")
                  assert_in_delta(   qM2, 0.00, 0.01, "#{cas} qM2 != 0?")
                  assert_in_delta(    qP, 0.00, 0.01, "#{cas} qP != 0?")
                  refute_in_delta(     r, 0.00, 0.01, "#{cas} q == 0?")
                  assert_in_delta(   rM2, 0.00, 0.01, "#{cas} qrM2 != 0?")
                  assert_in_delta(    rP, 0.00, 0.01, "#{cas} rP != 0?")
                  refute_in_delta( rHOOD, 0.00, 0.01, "#{cas} rHOOD == 0?")
                  refute_in_delta(rDRYER, 0.00, 0.01, "#{cas} rDRYER == 0?")
                  assert_in_delta(     q,    r, 0.01, "#{cas} q != r?")

                  exh  = rHOOD
                  exh += rDRYER if dryer
                  assert(rHOOD + rDRYER <= r / 10.0, "#{cas} EXH > 10% OA?")

                  emsg = "#{cas}: #{id} defaulted OA method?"
                  assert(spOA.isOutdoorAirMethodDefaulted, emsg)
                  emsg = "#{cas}: #{id} OA method?"
                  assert_equal(spOA.outdoorAirMethod.downcase, "sum", emsg)
                end
              end
            end
          end               # |dryer   |
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
