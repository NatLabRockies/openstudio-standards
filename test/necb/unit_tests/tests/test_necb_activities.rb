require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'


# Checks if BTAP::Activity instances are correctly deployed within BTAP.
class NECB_Activity_Tests < Minitest::Test
  def test_necb_activities()
    outd = "output/test_necb_activities"
    eres = "../expected_results/necb_activities_expected_results.json"
    tres = "../expected_results/necb_activities_test_results.json"
    sizd = "sizing_folder"

    plnums = ["LargeOffice", "MediumOffice"]
    attics = ["FullServiceRestaurant", "QuickServiceRestaurant", "SmallOffice"]

    @output_folder         = File.join(__dir__, outd)
    @expected_results_file = File.join(__dir__, eres)
    @test_results_file     = File.join(__dir__, tres)
    @sizing_run_dir        = File.join(@output_folder, sizd)
    @test_results_array    = []

    # Intial test condition.
    @test_passed = true

    # Range of NECB templates.
    @templates = [
      # "NECB2011",
      "NECB2015",
      # "NECB2017",
      # "NECB2020"
    ]

    @epws = ["CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"]

    @buildings = [
      'FullServiceRestaurant',
      'HighriseApartment',
      'Hospital',
      'LargeHotel',
      'LargeOffice',
      'LEEPMidriseApartment',
      'LEEPMultiTower',
      'LEEPPointTower',
      'LEEPTownHouse',
      'LowriseApartment',
      'MediumOffice',
      'MidriseApartment',
      # 'NorthernEducation',  # *
      # 'NorthernHealthCare', # *
      'Outpatient',
      'PrimarySchool',
      'QuickServiceRestaurant',
      'RetailStandalone',
      'RetailStripmall',
      'SecondarySchool',
      'SmallHotel',
      'SmallOffice',
      'Warehouse'
    ]

    # (*) 'NorthernEducation' and 'NorthernHealthCare' have neither:
    #       - Building.standardsNumberOfStories
    #       - Building.standardsNumberOfAboveStories
    #
    #     ... and so both templates/models fail early on, irrespective of
    #         BTAP::Activity features - @todo.

    fdback = []
    fdback << ""
    fdback << "BTAP::Activity Unit Tests"
    fdback << "~~~~  ~~~~~~~~ ~~~~ ~~~~~ "

    @epws.sort.each          do |epw      |
      @buildings.sort.each   do |building |
        @templates.sort.each do |template |
          cas = "CASE #{building} (#{template})"
          tag = "space_conditioning_category"

          st    = Standard.build(template)
          model = st.model_create_prototype_model(template: template,
                                                  epw_file: epw,
                                                  building_type: building,
                                                  construction_opt: 'structure',
                                                  sizing_run_dir: @sizing_run_dir)

          # BTAP initializes thermal zones and thermostats of unoccupied spaces
          # like plenums and attics, while maintaining empty thermostat heating
          # and cooling setpoint schedules. In activity.rb, such unoccupied
          # spaces are nontheless tagged using the AdditionalProperty:
          #
          #   "space_conditioning_category"
          #
          # Unconditioned spaces like attics are expected to be tagged as
          # "unconditioned". Indirectly-conditioned spaces like plenums are
          # instead expected to be tagged as "nonresconditioned" (just like the
          # conditioned spaces they serve).
          #
          # Keeping track of which unoccupied spaces are unconditioned matters
          # greatly for building envelope parameters (ex. construction, thermal
          # bridging, embodied carbon, costing).
          model.getSpaces.each do |space|
            id   = space.nameString
            zone = space.thermalZone
            prop = space.additionalProperties.getFeatureAsString(tag)

            err_msg = "BTAP::Activity #{id} empty property (#{cas})?"
            refute_empty(prop, err_msg)
            err_msg = "BTAP::Activity #{id} empty zone (#{cas})?"
            refute_empty(zone, err_msg)

            prop  = prop.get
            zone  = zone.get
            id    = zone.nameString
            tstat = zone.thermostatSetpointDualSetpoint

            err_msg = "BTAP::Activity #{id} empty thermostat (#{cas})?"
            refute_empty(tstat, err_msg)

            tstat = tstat.get
            heat  = tstat.heatingSetpointTemperatureSchedule
            cool  = tstat.coolingSetpointTemperatureSchedule
            next if space.partofTotalFloorArea

            err_msg = "BTAP::Activity #{id} thermostat, heating (#{cas})?"
            assert_empty(heat, err_msg)
            err_msg = "BTAP::Activity #{id} thermostat, cooling (#{cas})?"
            assert_empty(cool, err_msg)

            # Original OSM identifiers.
            # ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----
            # CASE FullServiceRestaurant (NECB2011) : restaurant (commerce) :
            #   'attic'              : UNCONDITIONED
            # CASE LargeOffice (NECB2011) : office (commerce) :
            #   'GroundFloor_Plenum' : INDIRECTLYCONDITIONED
            #   'TopFloor_Plenum'    : INDIRECTLYCONDITIONED
            #   'MidFloor_Plenum'    : INDIRECTLYCONDITIONED
            # CASE MediumOffice (NECB2011) : office (commerce) :
            #   'TopFloor_Plenum'    : INDIRECTLYCONDITIONED
            #   'FirstFloor_Plenum'  : INDIRECTLYCONDITIONED
            #   'MidFloor_Plenum'    : INDIRECTLYCONDITIONED
            # CASE QuickServiceRestaurant (NECB2011) : restaurant (commerce) :
            #   'attic'              : UNCONDITIONED
            # CASE SmallOffice (NECB2011) : office (commerce) :
            #   'Attic'              : UNCONDITIONED
            if attics.include?(building)
              err_msg = "BTAP::Activity #{id} conditioned (#{cas})?"
              assert_equal(prop, "unconditioned", err_msg)
            else
              err_msg = "BTAP::Activity #{id} plenum (#{cas})?"
              assert_includes(plnums, building, err_msg)

              err_msg = "BTAP::Activity #{id} unconditioned (#{cas})?"
              assert_equal(prop, "nonresconditioned", err_msg)
            end
          end

          a = st.activity

          err_msg = "Empty BTAP::Activity (#{cas})?"
          assert_kind_of(BTAP::Activity, a, err_msg)
          err_msg = "BTAP::Activity activity (#{cas})?"
          assert_kind_of(String, a.activity, err_msg)
          err_msg = "BTAP::Activity category (#{cas})?"
          assert_kind_of(String, a.category, err_msg)
          err_msg = "BTAP::Activity liveload (#{cas})?"
          assert_kind_of(Numeric, a.liveload, err_msg)

          load = "liveload #{a.liveload.round} kg/m2"

          if a.activity.empty?
            fdback << "Empty BTAP::Activity activity (#{cas})!"
            @test_passed = false
          elsif a.category.empty?
            fdback << "Empty BTAP::Activity category (#{cas})!"
            @test_passed = false
          elsif a.category == "common"
            fdback << "Common BTAP::Activity (#{cas})!"
            @test_passed = false
          else
            fdback << "#{cas} : #{a.activity} (#{a.category}) : #{load}"
          end

          a.feedback[:logs].each { |log| puts log }
        end                   # |template |
      end                     # |building |
    end                       # |epw      |

    # Temporary.
    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
