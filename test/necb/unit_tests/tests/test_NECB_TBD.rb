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
      'FullServiceRestaurant',
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
      'MediumOffice',
      # 'MidriseApartment',
      # 'NorthernEducation',
      # 'NorthernHealthCare',
      # 'Outpatient',
      # 'PrimarySchool',
      'QuickServiceRestaurant',
      # 'RetailStandalone',
      # 'RetailStripmall',
      # 'SecondarySchool',
      # 'SmallHotel',
      'SmallOffice',
      'Warehouse'
    ]

    @structure = [
      '',
      'structure'
    ]

    # BTAP currently supports 4 options when enabling linear thermal bridging
    # calculations (e.g. uprating, derating), all relying on the TBD gem.
    @options = [
      # 'none', # ignore linear thermal bridging altogether
      # 'bad',  # derating from poor thermal bridging details
      # 'good', # derating from better thermal bridging details
      'uprate'  # uprating (then derating) per NECB2017, NECB2020, NECB2025
    ]

    # PSI factor set variants 'bad' or 'good' refer to costed BTAP items. If set
    # to 'uprate', psi factor sets are determined iteratively, see:
    #
    #   lib/openstudio-standards/btap/bridging.rb
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
    # more expensive (i.e. $$$ Uo 0.100 > $$ Uo 0.124).
    @interpolate = [
      true,
      false
    ]

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

              # Customizing STRUCTURE options - similar to the unit test
              # 'test_necb_structures'. STRUCTURE customization triggers thermal
              # bridging PSI factor variants in BTAP. In this Warehouse example,
              # the building would inherit a steel (or metal) structure by
              # default. This is overridden here as all 3 spaces are customized:
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
                  err_msg = "BTAP/TBD: #{id} construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc      = lc.get.to_LayeredConstruction
                  err_msg = "BTAP/TBD: #{id} layered construction (#{cas})?"
                  refute_empty(lc, err_msg)

                  # No surface construction IDs hold any "c tbd" suffixes.
                  lc      = lc.get
                  name    = lc.nameString.downcase
                  err_msg = "BTAP/TBD processes enabled (#{cas})?"
                  refute_includes(name, " c tbd", err_msg)
                  prop    = lc.additionalProperties
                  next unless prop.hasFeature("btap_uo")

                  # Any (insulated) layered construction also holds:
                  err_msg = "BTAP/TBD air film resistances (#{cas})?"
                  assert(prop.hasFeature("btap_film"))
                  err_msg = "BTAP/TBD net area (#{cas})?"
                  assert(prop.hasFeature("btap_area"))
                  err_msg = "BTAP/TBD total Ut factor (#{cas})?"
                  assert(prop.hasFeature("btap_ut"))
                  err_msg = "BTAP/TBD costed construction identifier (#{cas})?"
                  assert(prop.hasFeature("btap_id"))
                end

                fdback << "BTAP/TBD processes skipped."
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
                err_msg = "BTAP/TBD: Missing model 'complies' key (#{cas})?"
                assert(st.tbd.model.key?(:complies), err_msg)
                cmplies = st.tbd.model[:complies]
                cpl_msg = cmplies ? " ... compliant!" : " ... non-compliant!"
                fdback << cpl_msg

                err_msg = "BTAP/TBD: Missing TBD 'IO' (#{cas})?"
                assert(st.tbd.model.key?(:io), err_msg)
                err_msg = "BTAP/TBD: Missing TBD 'surfaces' (#{cas})?"
                assert(st.tbd.model.key?(:surfaces), err_msg)
                err_msg = "BTAP/TBD: TBD 'surfaces' Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.model[:surfaces], err_msg)
                err_msg = "BTAP/TBD: Empty TBD 'surfaces' (#{cas})?"
                refute_empty(st.tbd.model[:surfaces], err_msg)
                surfaces = st.tbd.model[:surfaces]

                # Regardless of whether BTAP/TBD were successful or not in
                # uprating the building constructions (option == 'uprate'),
                # deratable surfaces should have been nonetheless derated.
                #
                # BTAP assigns to default constructions (targeted for derating)
                # a handful of key parameters, as both BTAP::Bridging.model
                # variables and AdditionalProperties ... inter alia:
                #   - btap_type : targeted surface type (e.g. :walls)
                #   - btap_area : net m2 of surfaces referencing construction
                #   - btap_film : surface area-weighted air film resistances
                #   - btap_ut   : prescriptive NECB U-factor targets
                #   - btap_uo   : uprated Uo required for NECB2017+ compliance
                #   - btap_id   : matching BTAP-costed construction ID
                #
                # TBD ultimately hard-assigns 'derated' constructions to each
                # individual envelope 'deratable' surface. In so doing, initial
                # default construction sets may no longer be relied upon when
                # forward-translating the model (to IDF).
                #
                # Outdoor-facing surface construction not derated by TBD? The
                # BTAP NorthernEducation prototype model holds a single example
                # of an (exposed) floor (Surface 48, 150 m2) entirely surrounded
                # by other exposed floor surfaces sharing the same 3D plane. All
                # of its surrounding edges are "transition" edges, which won't
                # derate the surface construction ("transition" == PSI 0 W/m per
                # linear meter). In such circumstances, TBD still tracks the
                # (theoretically deratable) surface construction, yet does not
                # hard-assign a new derated construction. In BTAP, such surfaces
                # therefore inherit from the default construction set. Caution
                # is warranted when trying to reconcile a default construction
                # initial vs final 'getNetArea' results.
                #
                # Nonetheless, (now potentially unused) default constructions
                # maintain aforementioned thermal bridging-related variables.
                # It is usually more efficient (and simpler) to parse the
                # latter than looping through all derated surfaces.

                # Building default (exterior) constructions. If uprating, Uo
                # represents the (costed) assembly U-factors required to meet
                # NECB Ut targets. If simply derating, Uo == Ut.
                [:walls, :roofs, :floors].each do |stypes|
                  m2   = st.tbd.model[:building][stypes][:area] # initial area
                  lc   = st.tbd.model[:building][stypes][:lc]   # initial lc
                  area = st.tbd.prop(lc, "btap_area", Float)
                  uo   = st.tbd.prop(lc, "btap_uo",   Float)    # required Uo
                  ut   = st.tbd.prop(lc, "btap_ut",   Float)    # required Ut
                  film = st.tbd.prop(lc, "btap_film", Float)    # film RSi
                  type = st.tbd.prop(lc, "btap_type", String)
                  id   = lc.nameString
                  net  = lc.getNetArea                          # rarely > 0
                  next unless m2 > 0
                  next unless area

                  err_msg = "BTAP/TBD: BLDG #{stypes} #{id} Uo (#{cas})?"
                  refute_nil(uo, err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} #{id} Ut (#{cas})?"
                  refute_nil(ut, err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} #{id} film (#{cas})?"
                  refute_nil(film, err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} #{id} type (#{cas})?"
                  refute_nil(type, err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} #{id} vs #{type} (#{cas})?"
                  assert_equal(type, stypes.to_s, err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} m2 vs area (#{cas})?"
                  assert_equal(m2.round(1), area.round(1), err_msg)
                  err_msg = "BTAP/TBD: BLDG #{stypes} m2 vs net (#{cas})?"
                  refute_equal(m2.round(1), net.round(1), err_msg)

                  if option == "uprate"
                    err_msg = "BTAP/TBD: BLDG #{stypes} Uo != Ut (#{cas})?"
                    refute_equal(uo.round(3), ut.round(3), err_msg)
                  else
                    err_msg = "BTAP/TBD: BLDG #{stypes} Uo == Ut (#{cas})?"
                    assert_equal(uo.round(3), ut.round(3), err_msg)
                  end
                end

                # Attic default (interior) constructions - if applicable.
                attics = []

                model.getSpaces.each do |space|
                  next if space.partofTotalFloorArea

                  attics << space if TBD.unconditioned?(space)
                end

                # No unconditioned attics with "structure" option.
                if structure != "structure"
                  err_msg = "BTAP/TBD: attics (#{cas})?"
                  assert_empty(attics, err_msg)
                end

                [:walls, :roofs, :floors].each do |stypes|
                  break if attics.empty?

                  # BTAP/TBD rest on attic spaces referencing a shared 'attic'
                  # default construction set. Attic 'floors' are insulated, yet
                  # as insulated 'roofs' of conditioned, occupied spaces below.
                  types = case stypes
                          when :roofs  then :floors
                          when :floors then :roofs
                          else              :walls
                          end

                  m2   = st.tbd.model[:attic][types][:area]   # initial area
                  lc   = st.tbd.model[:attic][types][:lc]     # initial lc
                  area = st.tbd.prop(lc, "btap_area", Float)
                  uo   = st.tbd.prop(lc, "btap_uo",   Float)  # required Uo
                  ut   = st.tbd.prop(lc, "btap_ut",   Float)  # required Ut
                  film = st.tbd.prop(lc, "btap_film", Float)  # film RSi
                  type = st.tbd.prop(lc, "btap_type", String)
                  id   = lc.nameString
                  net  = lc.getNetArea                        # rarely > 0
                  next unless m2 > 0
                  next unless area

                  err_msg = "BTAP/TBD: ATTIC #{types} #{id} Uo (#{cas})?"
                  refute_nil(uo, err_msg)
                  err_msg = "BTAP/TBD: ATTIC #{types} #{id} Ut (#{cas})?"
                  refute_nil(ut, err_msg)
                  err_msg = "BTAP/TBD: ATTIC #{types} #{id} film (#{cas})?"
                  refute_nil(film, err_msg)
                  err_msg = "BTAP/TBD: ATTIC #{types} #{id} type (#{cas})?"
                  refute_nil(type, err_msg)
                  err_msg = "BTAP/TBD: ATTIC #{types} m2 vs area (#{cas})?"
                  assert_equal(m2.round(1), area.round(1), err_msg)
                  err_msg = "BTAP/TBD: ATTIC #{types} m2 vs net (#{cas})?"
                  refute_equal(m2.round(1), net.round(1), err_msg)

                  if stypes == :walls
                    err_msg = "BTAP/TBD: ATTIC #{stypes} #{id} vs #{type} (#{cas})?"
                    assert_equal(type, stypes.to_s, err_msg)
                    err_msg = "BTAP/TBD: ATTIC #{types} #{id} vs #{type} (#{cas})?"
                    assert_equal(type, types.to_s, err_msg)

                    if option == "uprate"
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo != Ut (#{cas})?"
                      refute_in_epsilon(uo, ut, 0.01, err_msg)
                    else
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo == Ut (#{cas})?"
                      assert_in_epsilon(uou, ut, 0.01, err_msg)
                    end
                  else
                    err_msg = "BTAP/TBD: ATTIC #{stypes} #{id} vs #{type} (#{cas})?"
                    assert_equal(type, stypes.to_s, err_msg)
                    err_msg = "BTAP/TBD: ATTIC #{types} #{id} vs #{type} (#{cas})?"
                    refute_equal(type, types.to_s, err_msg)

                    if option == "uprate"
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo != Ut (#{cas})?"
                      refute_in_epsilon(uo, ut, 0.01, err_msg)
                    else
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo == Ut (#{cas})?"
                      assert_in_epsilon(uo, ut, 0.01, err_msg)
                    end
                  end
                end

                st.tbd.model[:spaces].each do |name, sp|
                  [:walls, :roofs, :floors].each do |stypes|
                    m2   = sp[stypes][:area]                    # initial area
                    lc   = sp[stypes][:lc]                      # initial lc
                    area = st.tbd.prop(lc, "btap_area", Float)
                    uo   = st.tbd.prop(lc, "btap_uo",   Float)  # required Uo
                    ut   = st.tbd.prop(lc, "btap_ut",   Float)  # required Ut
                    film = st.tbd.prop(lc, "btap_film", Float)  # film RSi
                    type = st.tbd.prop(lc, "btap_type", String)
                    id   = lc.nameString
                    net  = lc.getNetArea                        # rarely > 0
                    next unless m2 > 0
                    next unless area

                    err_msg = "BTAP/TBD: #{name} #{stypes} #{id} Uo (#{cas})?"
                    refute_nil(uo, err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} #{id} Ut (#{cas})?"
                    refute_nil(ut, err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} #{id} film (#{cas})?"
                    refute_nil(film, err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} #{id} type (#{cas})?"
                    refute_nil(type, err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} #{id} vs type (#{cas})?"
                    assert_equal(type, stypes.to_s, err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} m2 vs area (#{cas})?"
                    assert_equal(m2.round(1), area.round(1), err_msg)
                    err_msg = "BTAP/TBD: #{name} #{stypes} m2 vs net (#{cas})?"
                    refute_equal(m2.round(1), net.round(1), err_msg)

                    if option == "uprate"
                      err_msg = "BTAP/TBD: #{name} #{stypes} Uo != Ut (#{cas})?"
                      refute_in_epsilon(uo, ut, 0.01, err_msg)
                    else
                      err_msg = "BTAP/TBD: #{name} #{stypes} Uo == Ut (#{cas})?"
                      assert_in_epsilon(uo, ut, 0.01, err_msg)
                    end
                  end
                end

                # Tally wall and roof/ceiling constructions properties
                # separately, as maintained in BTAP/TBD attributes:
                #   - m2: initial construction 'getNetArea'
                #   - fa: m2 / area-weighted surface air film resistances
                #   - ua: m2 x Uo factor
                walls  = {m2: 0, fa: 0, ua: 0}
                roofs  = {m2: 0, fa: 0, ua: 0}
                floors = {m2: 0, fa: 0, ua: 0}

                # Start with BUILDING constructions.
                unless st.tbd.model[:building][:walls].empty?
                  wA = st.tbd.model[:building][:walls][:area]

                  if wA > 0
                    walls[:m2] = wA
                    walls[:fa] = wA / st.tbd.model[:building][:walls][:film]
                    walls[:ua] = wA * st.tbd.model[:building][:walls][:uo]
                  end
                end

                unless st.tbd.model[:building][:roofs].empty?
                  rA = st.tbd.model[:building][:roofs][:area]

                  if rA > 0
                    roofs[:m2] = rA
                    roofs[:fa] = rA / st.tbd.model[:building][:roofs][:film]
                    roofs[:ua] = rA * st.tbd.model[:building][:roofs][:uo]
                  end
                end

                # Attic constructions.
                unless attics.empty?
                  unless st.tbd.model[:attic][:walls].empty?
                    wA = st.tbd.model[:attic][:walls][:area]

                    if wA > 0
                      walls[:m2] += wA
                      walls[:fa] += wA / st.tbd.model[:attic][:walls][:film]
                      walls[:ua] += wA * st.tbd.model[:attic][:walls][:uo]
                    end
                  end

                  unless st.tbd.model[:attic][:floors].empty?
                    rA =  st.tbd.model[:attic][:floors][:area] # !roofs

                    if rA > 0
                      roofs[:m2] += rA
                      roofs[:fa] += rA / st.tbd.model[:attic][:floors][:film]
                      roofs[:ua] += rA * st.tbd.model[:attic][:floors][:uo]
                    end
                  end
                end

                # Customized space constructions.
                st.tbd.model[:spaces].values.each do |sp|
                  unless sp[:walls].empty?
                    wA = sp[:walls][:area]

                    if wA > 0
                      walls[:m2] += wA
                      walls[:fa] += wA / sp[:walls][:film]
                      walls[:ua] += wA * sp[:walls][:uo]
                    end
                  end

                  unless sp[:roofs].empty?
                    rA = sp[:roofs][:area]

                    if rA > 0
                      roofs[:m2] += rA
                      roofs[:fa] += rA / sp[:roofs][:film]
                      roofs[:ua] += rA * sp[:roofs][:uo]
                    end
                  end
                end

                wM2 = 0 # sum of wall surface areas
                rM2 = 0 # sum of roof and/or (attic) floor areas
                wFA = 0 # sum of wall surface-specific area / air film RSi
                rFA = 0 # sum of roof surface-specific area / air film RSi
                wUA = 0 # sum of wall surface-specific area / construction RSi
                rUA = 0 # sum of roof surface-specific area / construction RSi

                # Non- 'attic' surfaces.
                model.getSurfaces.each do |surface|
                  next if attics.include?(surface.space.get)
                  next unless surface.surfaceType.downcase == "wall"
                  next unless surface.outsideBoundaryCondition.downcase == "outdoors"

                  id = surface.nameString
                  wA = surface.netArea * surface.space.get.multiplier
                  lc = surface.construction.get.to_LayeredConstruction.get
                  fR = TBD.filmResistances(:wall, surface.tilt)
                  next unless fR.round(4) > 0

                  wM2 += wA
                  wFA += wA / fR
                  wUA += wA / TBD.rsi(lc, fR)
                end

                model.getSurfaces.each do |surface|
                  next if attics.include?(surface.space.get)
                  next unless surface.surfaceType.downcase == "roofceiling"
                  next unless surface.outsideBoundaryCondition.downcase == "outdoors"

                  id = surface.nameString
                  rA = surface.netArea * surface.space.get.multiplier
                  lc = surface.construction.get.to_LayeredConstruction.get
                  fR = TBD.filmResistances(:roof, surface.tilt)
                  next unless fR.round(4) > 0

                  rM2 += rA
                  rFA += rA / fR
                  rUA += rA / TBD.rsi(lc, fR)
                end

                # 'Attic' surfaces.
                attics.each do |attic|
                  attic.surfaces.each do |surface|
                    next unless surface.surfaceType.downcase == "wall"
                    next unless surface.outsideBoundaryCondition.downcase == "surface"

                    id = surface.nameString
                    wA = surface.netArea * surface.space.get.multiplier
                    lc = surface.construction.get.to_LayeredConstruction.get
                    fR = TBD.filmResistances(:partition, surface.tilt)
                    next unless fR.round(4) > 0

                    wM2 += wA
                    wFA += wA / fR
                    wUA += wA / TBD.rsi(lc, fR)
                  end
                end

                attics.each do |attic|
                  attic.surfaces.each do |surface|
                    next unless surface.surfaceType.downcase == "floor"
                    next unless surface.outsideBoundaryCondition.downcase == "surface"

                    id = surface.nameString
                    rA = surface.netArea * surface.space.get.multiplier
                    lc = surface.construction.get.to_LayeredConstruction.get
                    fR = TBD.filmResistances(:ceiling, surface.tilt)
                    next unless fR.round(4) > 0

                    rM2 += rA
                    rFA += rA / fR
                    rUA += rA / TBD.rsi(lc, fR)
                  end
                end

                # Tally of 'deratable' wall surface areas should match BTAP/TBD-
                # stored aggregate attributes (easier/quicker for QAQC/testing).
                err_msg = "BTAP/TBD: wall area tallies (#{cas})?"
                assert_equal(walls[:m2].round(1), wM2.round(1))

                # Tally of 'deratable' roof surface areas should also match
                # BTAP/TBD tallies. In some attic or plenum cases, there may be
                # discrepencies linked to OpenStudio/EnergyPlus limitations
                # (see unit test_necb_skylights for discussion). As the NECB
                # required SRR% has gradually gone down from 5% to 2%, the
                # impact on thermal bridging tallies has gradually lessened.
                #
                # Examples (-2% SRR):
                #   - 'SmallOffice'  (roofs[:m2]  501.01) vs (rM2  501.01)
                #   - 'MediumOffice' (roofs[:m2] 1627.51) vs (rM2 1627.51)
                #
                # OSut gross roof area (includes 2% SRR, excludes overhangs):
                #   - 'SmallOffice'  graX  538.80 - 2% SRR =  528.02 (poor)
                #   - 'MediumOffice' grax 1660.73 - 2% SRR = 1627.51 (good)
                err_msg = "BTAP/TBD: roof area tallies (#{cas})"
                assert_equal(roofs[:m2].round(1), rM2.round(1))

                # The walls[:fA] tally represents the inverse of area-weighted
                # surface air film resistances: fA = sum(A / film RSi), when
                # strictly processing stored aggregate values for:
                #   - 1. BUILDING,
                #   - 2. ATTIC and
                #   - 3. CUSTOMIZED spaces
                #
                # The calculated wFA represents the inverse of area-weighted
                # surface air film resistances: fA = sum(A / film RSi), when
                # processing individual deratable surfaces (one by one).
                #
                # There are observable gaps/errors between aggregate values:
                #   - 'SmallOffice' : (wFA 1379.362) vs (walls[:fa] 1379.876)
                #   - 'MediumOffice': (wFA 8814.859) vs (walls[:fa] 8818.470)
                #
                # Yet this has a negligible impact of the final inverse:
                #   - 'SmallOffice':
                #        - 1 / (wFA        / wM2) = film RSi 0.158 m2.K/W
                #        - 1 / (walls[:fa] / wM2) = film RSi 0.158 m2.K/W
                #   - 'MediumOffice':
                #        - 1 / (wFA        / wM2) = film RSi 0.150 m2.K/W
                #        - 1 / (walls[:fa] / wM2) = film RSi 0.150 m2.K/W
                #
                # Reminder: The 'MediumOffice' has plenums. All deratble
                #           surfaces are outdoor-facing. So all walls inherit
                #           a surface air film resistance of 0.150 m2.K/W.
                #
                #           The 'SmallOffice' has either a plenum (under the
                #           current BTAP approach), or an attic (with the new
                #           BTAP structure-based option). This affects whether
                #           skylight well walls are insulated or not, and
                #           consequently applicable air film resistances (the
                #           above results reflect the latter BTAP option).
                wfRSi = 1 / (wFA        / wM2)
                wFrsi = 1 / (walls[:fa] / wM2)
                err_msg = "BTAP/TBD: wall film RSi (#{cas})"
                assert_in_epsilon(wfRSi, wFrsi, 0.01, err_msg)

                rfRSi = 1 / (rFA        / rM2)
                rFrsi = 1 / (roofs[:fa] / rM2)
                err_msg = "BTAP/TBD: roof film RSi (#{cas})"
                assert_in_epsilon(rfRSi, rFrsi, 0.01, err_msg)

                # The walls[:ua] tally should match required (uprated, costed)
                # wall Uo factors. The wUA tally should match NECB required Ut.
                # This implies that post-simulation operations (e.g. costing)
                # can safely access aggregate tallies as take-offs (i.e. without
                # post-processing individual surfaces and constructions).
                if option == "uprate" && cmplies && inter == true
                  wUo  = walls[:ua] / wM2
                  wUt  = wUA        / wM2
                  rUo  = roofs[:ua] / rM2
                  rUt  = rUA        / rM2

                  unless st.tbd.model[:building][:walls].empty?
                    film = st.tbd.model[:building][:walls][:film]
                    lc   = st.tbd.model[:building][:walls][:lc  ]
                    bwUo = st.tbd.model[:building][:walls][:uo  ]
                    bwUt = st.tbd.model[:building][:walls][:ut  ]
                    uo   = 1/TBD.rsi(lc, film)
                    err_msg = "BTAP/TBD: BLDG uprated wall Uo (#{cas})"
                    assert_in_epsilon(wUo, bwUo, 0.01, err_msg)
                    err_msg = "BTAP/TBD: BLDG uprated wall Uo 2 (#{cas})"
                    assert_in_epsilon(wUo, uo, 0.01, err_msg)
                    err_msg = "BTAP/TBD: BLDG wall Ut (#{cas})"
                    assert_in_delta(wUt, bwUt, 0.02, err_msg)
                  end

                  unless st.tbd.model[:building][:roofs].empty?
                    film = st.tbd.model[:building][:roofs][:film]
                    lc   = st.tbd.model[:building][:roofs][:lc  ]
                    brUo = st.tbd.model[:building][:roofs][:uo  ]
                    brUt = st.tbd.model[:building][:roofs][:ut  ]
                    uo   = 1/TBD.rsi(lc, film)
                    err_msg = "BTAP/TBD: BLDG uprated roof Uo (#{cas})"
                    assert_in_epsilon(rUo, brUo, 0.01, err_msg)
                    err_msg = "BTAP/TBD: BLDG uprated roof Uo 2 (#{cas})"
                    assert_in_epsilon(rUo, uo, 0.01, err_msg)
                    err_msg = "BTAP/TBD: BLDG roof Ut (#{cas})"
                    assert_in_delta(rUt, brUt, 0.02, err_msg)
                  end

                  unless attics.empty?
                    unless st.tbd.model[:attic][:walls].empty?
                      film = st.tbd.model[:attic][:walls][:film]
                      lc   = st.tbd.model[:attic][:walls][:lc  ]
                      awUo = st.tbd.model[:attic][:walls][:uo  ]
                      awUt = st.tbd.model[:attic][:walls][:ut  ]
                      uo   = 1/TBD.rsi(lc, film)
                      err_msg = "BTAP/TBD: ATTIC uprated wall Uo (#{cas})"
                      assert_in_epsilon(wUo, awUo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: ATTIC uprated wall Uo 2 (#{cas})"
                      assert_in_epsilon(wUo, uo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: ATTIC wall Ut (#{cas})"
                      assert_in_delta(wUt, awUt, 0.02, err_msg)
                    end

                    unless st.tbd.model[:attic][:floors].empty?
                      film = st.tbd.model[:attic][:floors][:film]
                      lc   = st.tbd.model[:attic][:floors][:lc  ]
                      arUo = st.tbd.model[:attic][:floors][:uo  ]
                      arUt = st.tbd.model[:attic][:floors][:ut  ]
                      uo   = 1/TBD.rsi(lc, film)
                      err_msg = "BTAP/TBD: ATTIC uprated floor Uo (#{cas})"
                      assert_in_epsilon(rUo, arUo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: ATTIC uprated floor Uo 2 (#{cas})"
                      assert_in_epsilon(rUo, uo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: ATTIC floor Ut (#{cas})"
                      assert_in_delta(rUt, arUt, 0.02, err_msg)
                    end
                  end

                  st.tbd.model[:spaces].each do |id, sp|
                    unless sp[:walls].empty?
                      film = sp[:walls][:film]
                      lc   = sp[:walls][:lc  ]
                      swUo = sp[:walls][:uo  ]
                      swUt = sp[:walls][:ut  ]
                      uo   = 1/TBD.rsi(lc, film)
                      err_msg = "BTAP/TBD: #{id} uprated wall Uo (#{cas})"
                      assert_in_epsilon(wUo, swUo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: #{id} uprated wall Uo 2 (#{cas})"
                      assert_in_epsilon(wUo, uo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: #{id} wall Ut (#{cas})"
                      assert_in_delta(wUt, swUo, 0.02, err_msg)
                    end

                    unless sp[:roofs].empty?
                      film = sp[:roofs][:film]
                      lc   = sp[:roofs][:lc  ]
                      srUo = sp[:roofs][:uo  ]
                      srUt = sp[:roofs][:ut  ]
                      uo   = 1/TBD.rsi(lc, film)
                      err_msg = "BTAP/TBD: #{id} uprated roof Uo (#{cas})"
                      assert_in_epsilon(rUo, srUo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: #{id} uprated roof Uo 2 (#{cas})"
                      assert_in_epsilon(rUo, uo, 0.01, err_msg)
                      err_msg = "BTAP/TBD: #{id} roof Ut (#{cas})"
                      assert_in_delta(rUo, srUo, 0.02, err_msg)
                    end
                  end
                end

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
