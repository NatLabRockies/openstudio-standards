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

    plnums = ["LargeOffice", "MediumOffice", "NorthernEducation"]
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
      "NECB2011",
      # "NECB2015",
      # "NECB2017",
      # "NECB2020"
    ]

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
      # 'Warehouse'
    ]

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

          # Some buildings have NECB-listed 'ancillary' spacetypes. Comment in
          # the 'fdback' assignment below (which buildings? which spaces?).
          model.getSpaces.each do |space|
            next unless space.partofTotalFloorArea

            id      = space.nameString
            width   = BTAP::Geometry::Spaces.space_width(space)
            area    = space.floorArea
            err_msg = "BTAP::Activity mismatched space #{id} (#{cas})?"
            assert(a.activities.key?(space), err_msg)

            sptype  = space.spaceType
            err_msg = "BTAP::Activity #{id} empty spacetype (#{cas})?"
            refute_empty(sptype, err_msg)

            sptype   = sptype.get
            sttype   = sptype.standardsSpaceType
            err_msg  = "BTAP::Activity #{id} empty stds spacetype (#{cas})?"
            refute_empty(sttype, err_msg)

            sttype   = sttype.get
            keyword  = a.keyword(space)
            schedule = a.schedule(space)
            activity = a.act(space)
            err_msg  = "BTAP::Activity #{id} schedule (#{cas})?"
            refute_equal(schedule, "*", err_msg)

            # fdback << "- #{id}: #{sttype} | #{keyword} : #{schedule}"

            if a.occsensing_deprecated?(space)
              # fdback << "#{id}: #{sttype} OCCSENSING"
              assert(a.occsensing?(space))
            end

            # if sttype.downcase.include?("corr")
            #   fdback << "BTAP::Activity #{id}: #{width.round(2)}m"
            # end

            # if sttype.downcase.include?("suppl")
            #   fdback << "BTAP::Activity #{id}: #{area.round(2)} m2"
            # end

            next unless a.ancillary?(keyword)

            # fdback << "#{id} : #{st.determine_necb_schedule_type(space)}"
            # fdback << "   ANCILLARY: #{id} (#{keyword}, #{schedule})"

            # A handful of ancillary spaces are considered 'wetspaces'.
            next unless a.wet?(keyword)

            err_msg = "BTAP::Activity #{id} wetspace (#{cas})?"
            assert(activity == "washroom" || activity == "locker", err_msg)

            # fdback << "   WETSPACES: #{id} (#{keyword})"
          end

          ecm = ECMS.new

          model.getThermalZones.each do |zone|
            id = zone.nameString
            next if ecm.zone_terminal_vrf?(zone, a)

            # fdback << "#{id} can't have a terminal VRF unit (#{cas})"
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

  def test_space_types_json()
    # pth = "lib/openstudio-standards/standards/necb/NECB2011/data/space_types.json"
    # pth = "lib/openstudio-standards/standards/necb/NECB2015/data/space_types.json"
    # pth = "lib/openstudio-standards/standards/necb/NECB2017/data/space_types.json"
    pth = "lib/openstudio-standards/standards/necb/NECB2020/data/space_types.json"
    jfile = File.read(pth)
    jcontent = JSON.parse(jfile, symbolize_names: true)

    assert_equal(jcontent.keys.size, 1)
    assert_equal(jcontent.keys[0], :tables)

    tables = jcontent[:tables]
    assert_equal(tables.keys.size, 1)
    assert_equal(tables.keys[0], :space_types)

    sptypes = tables[:space_types]
    assert_equal(sptypes.keys.size, 3)
    assert(sptypes.key?(:table))

    table = sptypes[:table]
    assert_instance_of(Array, table)
    # assert_equal(table.size, 224) # NECB2011
    # assert_equal(table.size, 319) # NECB2015, NECB2017
    assert_equal(table.size, 308) # NECB2020

    puts; puts "RESULTS :"

    # Validation of existing JSON entries.
    table.each do |entry|
      if entry[:building_type] == "Space Function"
        type = entry[:space_type]
      else
        type = entry[:building_type]
      end

      # Assuming each of the following keys deserve a unique JSON entry:
      # ________________________________________________________________
      # building_type
      # space_type
      # lighting_per_area
      # rel_absence_occ
      # occ_sense
      # lighting_schedule
      # target_illuminance_setpoint
      # ventilation_standard # 2020
      # ventilation_secondary_space_type
      # ventilation_per_area
      # ventilation_per_person
      # occupancy_per_area
      # occupancy_schedule
      # occupancy_activity_schedule
      # electric_equipment_per_area
      # electric_equipment_schedule
      # heating_setpoint_schedule
      # cooling_setpoint_schedule
      # service_water_heating_peak_flow_per_area
      # service_water_heating_schedule
      # exhaust_schedule
      # necb_hvac_system_selection_type
      # necb_schedule_type
      # ventilation_occupancy_rate_people_per_1000ft2
      # ventilation_standard_space_type
      # ventilation_occupancy_standard
      #
      # Note: all schedule assignements can be instead automated
      # Note: ventilation_secondary_space_type can be fully auto-generated

      # NECB2011 DEFAULTS:
      # _______________________________________________________________________
      # key = :rgb;                                      value = "255_255_255"
      # key = :lighting_standard;                        value = "NECB2020"
      # key = :lighting_primary_space_type;              value = entry[:building_type]
      # key = :lighting_secondary_space_type;            value = entry[:space_type]
      # key = :lighting_per_person;                      value = nil
      # key = :additional_lighting_per_area;             value = nil
      # key = :personal_control;                         value = 0.0
      # key = :lighting_fraction_to_return_air;          value = 0.0
      # key = :lighting_fraction_radiant;                value = 0.5
      # key = :lighting_fraction_visible;                value = 0.2
      # key = :lighting_fraction_replaceable;            value = nil
      # key = :lpd_fraction_linear_fluorescent;          value = 1.0
      # key = :lpd_fractionlinear_fluorescent;           value = 1.0
      # key = :lpd_fraction_compact_fluorescent;         value = nil
      # key = :lpd_fractioncompact_fluorescent;          value = nil
      # key = :lpd_fraction_high_bay;                    value = nil
      # key = :lpd_fractionhigh_bay;                     value = nil
      # key = :lpd_fraction_specialty_lighting;          value = nil
      # key = :lpd_fractionspecialty_lighting;           value = nil
      # key = :lpd_fraction_exit_lighting;               value = nil
      # key = :lpd_fractionexit_lighting;                value = nil
      # key = :compact_fluorescent_lighting_schedule;    value = nil
      # key = :high_bay_lighting_schedule;               value = nil
      # key = :specialty_lighting_schedule;              value = nil
      # key = :exit_lighting_schedule;                   value = nil
      # key = :target_illuminance_setpoint_ref;          value = "IES 2011 Lighting Handbook"     # 2011
      # key = :target_illuminance_setpoint_ref;          value = "NECB2015 Table A-8.4.3.2.(2)-A" # 2015
      # key = :target_illuminance_setpoint_ref;          value = "NECB2017 Table A-8.4.3.2.(2)-A" # 2017
      # key = :target_illuminance_setpoint_ref;          value = "NECB2020 Table A-8.4.3.2.(2)-A" # 2020
      # key = :psa_nongeometry_fraction;                 value = nil
      # key = :ssa_nongeometry_fraction;                 value = nil
      # key = :ventilation_standard;                     value = "ASHRAE 62-2001 Table 2" # 2011 - 2017
      # key = :ventilation_standard;                     value = "ASHRAE 62.1-2016 Table 6-1" # 2020
      # key = :ventilation_primary_space_type;           value = entry[:building_type]
      # key = :ventilation_air_changes;                  value = 0
      # key = :minimum_total_air_changes;                value = nil
      # key = :infiltration_per_exterior_area;           value = 0.049225
      # key = :infiltration_per_exterior_wall_area;      value = nil
      # key = :infiltration_air_changes;                 value = nil
      # key = :infiltration_schedule;                    value = "Always On"
      # key = :infiltration_schedule_perimeter;          value = nil
      # key = :gas_equipment_per_area;                   value = nil
      # key = :gas_equipment_fraction_latent;            value = nil
      # key = :gas_equipment_fraction_radiant;           value = nil
      # key = :gas_equipment_fraction_lost;              value = nil
      # key = :gas_equipment_schedule;                   value = nil
      # key = :electric_equipment_fraction_latent;       value = 0.0
      # key = :electric_equipment_fraction_radiant;      value = 0.5
      # key = :electric_equipment_fraction_lost;         value = 0.0
      # key = :additional_electric_equipment_schedule;   value = nil
      # key = :additional_gas_equipment_schedule;        value = nil
      # key = :service_water_heating_peak_flow_rate;     value = 0.0 # (or nil) *
      # key = :service_water_heating_area;               value = nil
      # key = :service_water_heating_target_temperature; value = 60.0
      # key = :service_water_heating_fraction_sensible;  value = nil
      # key = :service_water_heating_fraction_latent;    value = nil
      # key = :exhaust_per_area;                         value = nil
      # key = :exhaust_fan_efficiency;                   value = nil
      # key = :exhaust_fan_power;                        value = nil
      # key = :exhaust_fan_pressure_rise;                value = nil
      # key = :exhaust_fan_maximum_flow_rate;            value = nil
      # key = :balanced_exhaust_fraction_schedule;       value = nil
      # key = :is_residential;                           value = nil
      # key = :notes;                                    value = nil
      # key = :ventilation_occupancy_standard;           value = "ASHRAE 62-2001 Table 2"
      key = :ventilation_occupancy_standard;           value = "ASHRAE 62.1-2016 Occupancy" # 2020
      next unless entry.key?(key)
      next if entry[key] == value

      puts "#{key} :: #{type} :: #{entry[key]}"

      # NECB2011 EXCEPTIONS ?
      #
      # KEY                                      BUILDING/SPACE TYPE                   :: VALUE                                 :: EDITION
      # __________________________________________________________________________________________________________________________________
      # rgb                                      :: Food preparation - vented             :: 255_255_256                        :: 2011
      # rgb                                      ::                                       ::                                    :: 2015, 2017, 2020
      # lighting_standard                        :: Food preparation - vented             :: NECB 2012                          :: 2011
      # lighting_standard                        ::                                       ::                                    :: 2015, 2017, 2020
      # lighting_primary_space_type              :: Warehouse - refrigerated              :: Warehouse                          :: 2011
      # lighting_primary_space_type              ::                                       ::                                    :: 2015, 2017, 2020
      # lighting_secondary_space_type            :: Food preparation - vented             :: Food preparation                   :: 2011
      # lighting_secondary_space_type            :: Hospital - medical supply - occsens   :: Hospital - medical supply          :: 2011
      # lighting_secondary_space_type            :: Office - enclosed - occsens           :: Office - enclosed                  :: 2011
      # lighting_secondary_space_type            :: Storage area - occsens                :: Storage area                       :: 2011
      # lighting_secondary_space_type            :: Storage area - refrigerated           :: Storage area                       :: 2011
      # lighting_secondary_space_type            :: Storage area - refrigerated - occsens :: Storage area                       :: 2011
      # lighting_secondary_space_type            :: Warehouse - fine - refrigerated       :: Warehouse - fine                   :: 2011
      # lighting_secondary_space_type            :: Warehouse - med/blk - refrigerated    :: Warehouse - med/blk                :: 2011
      # lighting_secondary_space_type            :: Warehouse - med/blk2 - refrigerated   :: Warehouse - med/blk2               :: 2011
      # lighting_secondary_space_type            :: Washroom other-sch-K                  :: Washroom - other-sch-K             :: 2015, 2017, 2020
      # lighting_per_person                      ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # additional_lighting_per_area             ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # personal_control                         :: Laboratory - classrooms               :: 0.1                                :: 2015, 2017, 2020
      # personal_control                         :: Office enclosed <= 25 m2              :: 0.1                                :: 2015, 2017, 2020
      # personal_control                         :: Office enclosed > 25 m2               :: 0.1                                :: 2015, 2017, 2020
      # personal_control                         :: Office open plan                      :: 0.1                                :: 2015, 2017, 2020
      # personal_control                         :: Health care facility patient room     :: 0.1                                :: 2015, 2017, 2020
      # lighting_fraction_to_return_air          :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # lighting_fraction_radiant                :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # lighting_fraction_visible                :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # lighting_fraction_replaceable            ::                                       :: null                               :: 2011, 2015, 2017, 2020
      # lpd_fraction_linear_fluorescent          ::                                       ::                                    :: 2011
      # lpd_fractionlinear_fluorescent           ::                                       ::                                    :: 2015, 2017, 2020
      # lpd_fraction_compact_fluorescent         ::                                       ::                                    :: 2011
      # lpd_fractioncompact_fluorescent          ::                                       ::                                    :: 2015, 2017, 2020
      # lpd_fraction_high_bay                    ::                                       ::                                    :: 2011
      # lpd_fractionhigh_bay                     ::                                       ::                                    :: 2015, 2017, 2020
      # lpd_fraction_specialty_lighting          ::                                       ::                                    :: 2011
      # lpd_fractionspecialty_lighting           ::                                       ::                                    :: 2015, 2017, 2020
      # lpd_fraction_exit_lighting               ::                                       ::                                    :: 2011
      # lpd_fractionexit_lighting                ::                                       ::                                    :: 2015, 2017, 2020
      # compact_fluorescent_lighting_schedule    ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # high_bay_lighting_schedule               ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # specialty_lighting_schedule              ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exit_lighting_schedule                   ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # target_illuminance_setpoint_ref          ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # psa_nongeometry_fraction                 ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # ssa_nongeometry_fraction                 ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # ventilation_standard                     :: - undefined -                         :: N/A                                :: 2011, 2015, 2017
      # ventilation_primary_space_type           :: Warehouse - refrigerated              :: Warehouse                          :: 2011
      # ventilation_primary_space_type           :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # ventilation_air_changes                  ::                                       ::                                    :: 2011, 2015, 2017
      # ventilation_air_changes                  :: Health care clinic                    :: 2                                  :: 2020
      # ventilation_air_changes                  :: Hospital                              :: 2                                  :: 2020
      # ventilation_air_changes                  :: Lounge/Break room - health care ...   :: 4                                  :: 2020
      # ventilation_air_changes                  :: Health care facility exam/treat ...   :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility imaging ...      :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility medical ...      :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility nursery          :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility nurses station   :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility operating room   :: 4                                  :: 2020
      # ventilation_air_changes                  :: Health care facility patient room     :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility physical ...     :: 2                                  :: 2020
      # ventilation_air_changes                  :: Health care facility recovery room    :: 2                                  :: 2020
      # minimum_total_air_changes                ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # infiltration_per_exterior_area           ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # infiltration_per_exterior_wall_area      ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # infiltration_air_changes                 ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # infiltration_schedule                    ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # infiltration_schedule_perimeter          ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # gas_equipment_per_area                   ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # gas_equipment_fraction_latent            ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # gas_equipment_fraction_radiant           ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # gas_equipment_fraction_lost              ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # gas_equipment_schedule                   ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # electric_equipment_fraction_latent       :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # electric_equipment_fraction_radiant      :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # electric_equipment_fraction_lost         :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # additional_electric_equipment_schedule   ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # additional_gas_equipment_schedule        ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # service_water_heating_peak_flow_rate     ::                                       ::                                    :: 2011, 2015, 2017, 2020 *
      # service_water_heating_area               ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # service_water_heating_target_temperature :: - undefined -                         :: null                               :: 2011, 2015, 2017, 2020
      # service_water_heating_fraction_sensible  ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # service_water_heating_fraction_latent    ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exhaust_per_area                         ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exhaust_fan_efficiency                   ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exhaust_fan_power                        ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exhaust_fan_pressure_rise                ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # exhaust_fan_maximum_flow_rate            ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # balanced_exhaust_fraction_schedule       ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # is_residential                           ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # notes                                    ::                                       ::                                    :: 2011, 2015, 2017, 2020
      # ventilation_occupancy_standard           :: - undefined -                         :: N/A                                :: 2011, 2015, 2017
      # ventilation_occupancy_standard           :: Washroom-sch-A                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-B                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-C                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-D                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-E                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-F                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-G                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-H                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
      # ventilation_occupancy_standard           :: Washroom-sch-I                        :: ASHRAE 62-1999 Occupancy (assumed) :: 2011
    end
  end

end
