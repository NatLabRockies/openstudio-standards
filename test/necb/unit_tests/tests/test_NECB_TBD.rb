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
      'NECB2015',
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
      'RetailStripmall',
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
      'bad',  # derating from poor thermal bridging details
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
      # true,
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
                cmplies = cmplies ? " ... compliant!" : " ... non-compliant!"
                fdback << cmplies

                err_msg = "BTAP/TBD: Missing TBD 'IO' (#{cas})?"
                assert(st.tbd.model.key?(:io), err_msg)

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

                  # BTAP's use of TBD rests on attic spaces referencing a shared
                  # 'attic' default construction set. Attic space 'floors' are
                  # insulated, yet as insulated 'roofs' of conditioned, occupied
                  # spaces below.
                  types = case stypes
                          when :roofs  then :floors
                          when :floors then :roofs
                          else              :walls
                          end

                  m2   = st.tbd.model[:attic][types][:area]  # initial area
                  lc   = st.tbd.model[:attic][types][:lc]    # initial lc
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
                      refute_equal(uo.round(3), ut.round(3), err_msg)
                    else
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo == Ut (#{cas})?"
                      assert_equal(uo.round(3), ut.round(3), err_msg)
                    end
                  else
                    err_msg = "BTAP/TBD: ATTIC #{stypes} #{id} vs #{type} (#{cas})?"
                    assert_equal(type, stypes.to_s, err_msg)
                    err_msg = "BTAP/TBD: ATTIC #{types} #{id} vs #{type} (#{cas})?"
                    refute_equal(type, types.to_s, err_msg)

                    if option == "uprate"
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo != Ut (#{cas})?"
                      refute_equal(uo.round(3), ut.round(3), err_msg)
                    else
                      err_msg = "BTAP/TBD: ATTIC #{types} Uo == Ut (#{cas})?"
                      assert_equal(uo.round(3), ut.round(3), err_msg)
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
                      refute_equal(uo.round(3), ut.round(3), err_msg)
                    else
                      err_msg = "BTAP/TBD: #{name} #{stypes} Uo == Ut (#{cas})?"
                      assert_equal(uo.round(3), ut.round(3), err_msg)
                    end
                  end
                end

                # Tally wall, roof and exposed floor constructions separately.
                walls  = {m2: 0, film: 0, uo: 0, ut: 0, lcs: {}}
                roofs  = {m2: 0, film: 0, uo: 0, ut: 0, lcs: {}}
                floors = {m2: 0, film: 0, uo: 0, ut: 0, lcs: {}}

                # Start with surface type areas.
                walls[ :m2] += st.tbd.model[:building][:walls ][:area]
                roofs[ :m2] += st.tbd.model[:building][:roofs ][:area]
                floors[:m2] += st.tbd.model[:building][:floors][:area]

                err_msg = "BTAP/TBD: Missing TBD 'surfaces' (#{cas})?"
                assert(st.tbd.model.key?(:surfaces), err_msg)
                err_msg = "BTAP/TBD: TBD 'surfaces' Hash (#{cas})?"
                assert_kind_of(Hash, st.tbd.model[:surfaces], err_msg)
                err_msg = "BTAP/TBD: Empty TBD 'surfaces' (#{cas})?"
                refute_empty(st.tbd.model[:surfaces], err_msg)
                surfaces = st.tbd.model[:surfaces]

                model.getSurfaces.each do |surface|
                  id = surface.nameString
                  err_msg = "BTAP/TBD: Mismatched #{id} surfaces (#{cas})?"
                  assert(surfaces.key?(id), err_msg)
                  next unless surfaces[id].key?(:deratable)
                  next unless surfaces[id].key?(:type)
                  next unless surfaces[id].key?(:heatloss)
                  next unless surfaces[id][:deratable]
                  next unless surfaces[id][:heatloss ].abs > TBD::TOL

                  lc = surface.construction
                  err_msg = "BTAP/TBD: Nilled #{id} construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc.get.to_LayeredConstruction
                  err_msg = "BTAP/TBD: Nilled #{id} layered construction (#{cas})?"
                  refute_empty(lc, err_msg)
                  lc      = lc.get
                  nom     = lc.nameString.downcase
                  err_msg = "Failed TBD processes #{nom} #{id} (#{cas})?"
                  assert_includes(nom, " c tbd", err_msg)
                  prop    = lc.additionalProperties
                  next unless prop.hasFeature("btap_uo")

                  # Any (insulated) layered construction also holds:
                  err_msg = "BTAP/TBD air film resistances (#{cas})?"
                  assert(prop.hasFeature("btap_film"))
                  err_msg = "BTAP/TBD total Ut factor (#{cas})?"
                  assert(prop.hasFeature("btap_ut"))
                  err_msg = "BTAP/TBD costed construction identifier (#{cas})?"
                  assert(prop.hasFeature("btap_id"))
                  uo      = prop.getFeatureAsDouble("btap_uo")
                  film    = prop.getFeatureAsDouble("btap_film")
                  area    = prop.getFeatureAsDouble("btap_area")
                  err_msg = "BTAP/TBD: #{id} Uo (#{cas})?"
                  refute_empty(uo, err_msg)
                  err_msg = "BTAP/TBD: #{id} air film resistances (#{cas})?"
                  refute_empty(film, err_msg)

                  if option == 'uprate'
                    # @todo
                  else
                    # #todo
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
