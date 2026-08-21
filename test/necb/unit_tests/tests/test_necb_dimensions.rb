require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

# This checks if space dimensions are adequately calculated (e.g. width, height).
class NECB_Dimensions_Tests < Minitest::Test
  def test_necb_dimensions()
    translator = OpenStudio::OSVersion::VersionTranslator.new
    osm_path   = "lib/openstudio-standards/standards/necb/NECB2011/data/geometry"
    osm_dir    = File.join(__dir__, "/../../../../", osm_path)

    # Tested models are limited to NECB2011 Prototypes holding concave volumes:
    @buildings = [
      # "Warehouse.osm",          # 'Zone2 Fine Storage' (height?) ... mezzanine
      # "NorthernHealthCare.osm", # F-shaped 'corridors' (width?)
      # "SmallHotel.osm"          # F-shaped 'corridors' (width?)
    ]

    fdback = []
    fdback << ""
    fdback << "BTAP/Dimensions Unit Tests"
    fdback << "~~~~~~~~~~~~~~~ ~~~~ ~~~~~"

    @buildings.sort.each do |building|
      cas   = "CASE #{building}"
      file  = File.join(osm_dir, building)
      path  = OpenStudio::Path.new(file)
      model = translator.loadModel(path)
      emsg  = "BTAP/Dimensions: empty model (#{cas})?"
      refute_empty(model, emsg)
      model = model.get

      id = case building
           when "Warehouse.osm"          then "Zone2 Fine Storage"
           when "NorthernHealthCare.osm" then "Corridor 2"
           when "SmallHotel.osm"         then "CorridorFlr2"
           else next
           end

      space = model.getSpaceByName(id)
      emsg  = "BTAP/Dimensions: empty space '#{id}' (#{cas})?"
      refute_empty(space, emsg)
      space = space.get

      # Un-initialized AdditionalProperties.
      emsg = "BTAP/Dimensions: height property '#{id}' (#{cas})!"
      refute(space.additionalProperties.hasFeature("space_height"), emsg)
      emsg = "BTAP/Dimensions: width property '#{id}' (#{cas})!"
      refute(space.additionalProperties.hasFeature("space_width"), emsg)

      height = BTAP::Geometry::Spaces.space_height(space)
      width  = BTAP::Geometry::Spaces.space_width(space)

      hauteur = case id
                when "Zone2 Fine Storage" then 8.53
                when "Corridor 2"         then 4.11
                when "CorridorFlr2"       then 2.74
                else next
                end

      largeur = case id
                when "Zone2 Fine Storage" then 21.33
                when "Corridor 2"         then 2.44
                when "CorridorFlr2"       then 1.83
                else next
                end

      emsg = "BTAP/Dimensions: height '#{id}' (#{cas})?"
      assert_in_delta(height, hauteur, 0.01, emsg)
      emsg = "BTAP/Dimensions: width '#{id}' (#{cas})?"
      assert_in_delta(width, largeur, 0.01, emsg)

      # Initialized AdditionalProperties.
      emsg = "BTAP/Dimensions: height property '#{id}' (#{cas})?"
      assert(space.additionalProperties.hasFeature("space_height"), emsg)
      emsg = "BTAP/Dimensions: width property '#{id}' (#{cas})?"
      assert(space.additionalProperties.hasFeature("space_width"), emsg)

      hgt  = space.additionalProperties.getFeatureAsDouble("space_height")
      wdt  = space.additionalProperties.getFeatureAsDouble("space_width")
      emsg = "BTAP/Dimensions: height feature '#{id}' (#{cas})?"
      refute_empty(hgt, emsg)
      emsg = "BTAP/Dimensions: width feature '#{id}' (#{cas})?"
      refute_empty(wdt, emsg)

      emsg = "BTAP/Dimensions: height '#{id}' (#{cas})!"
      assert_in_delta(height, hgt.get, 0.01, emsg)
      emsg = "BTAP/Dimensions: width '#{id}' (#{cas})!"
      assert_in_delta(width, wdt.get, 0.01, emsg)

      # Higher level feedback.
      fdback << "#{cas} : #{id} : height = #{height.round(2)} : width = #{width.round(2)}"
      # CASE NorthernHealthCare.osm : Corridor 2         : 4.11 :  2.44
      # CASE SmallHotel.osm         : CorridorFlr2       : 2.74 :  1.83
      # CASE Warehouse.osm          : Zone2 Fine Storage : 8.53 : 21.33
    end

    # Temporary.
    fdback.each { |msg| puts msg }
  end

  def test_necb_slab_perimeters()
    translator = OpenStudio::OSVersion::VersionTranslator.new
    osm_path   = "lib/openstudio-standards/standards/necb/NECB2011/data/geometry"
    osm_dir    = File.join(__dir__, "/../../../../", osm_path)

    # Tested models are limited to NECB2011 Prototypes with slabs-on-grade:
    @buildings = [
      "FullServiceRestaurant.osm",
      "HighriseApartment.osm",
      "HighriseApartmentMult.osm",
      "LEEPMidriseApartment.osm",
      "LEEPPointTower.osm",
      "LowriseApartment.osm",
      "MediumOffice.osm",
      "MidriseApartment.osm",
      "PrimarySchool.osm",
      "QuickServiceRestaurant.osm",
      "RetailStandalone.osm",
      "RetailStripmall.osm",
      "SecondarySchool.osm",
      "SmallHotel.osm",
      "SmallOffice.osm",
      "Warehouse.osm"
    ]
    # Prototype              slab m2  union? cutout m2    perimeter m2
    # ---------------------- ------- ------- ---------- ---------------
    # FullServiceRestaurant   511.15     OK     408.39      102.76
    # HighriseApartment       783.65     OK     637.63      146.02
    # HighriseApartmentMult   783.65     OK     637.63      146.02
    # Hospital               3739.35     OK    3448.84      290.51
    # LargeHotel             1978.83     OK    1721.97      256.86
    # LEEPMidriseApartment    787.84     OK     647.41      140.42
    # LEEPPointTower          676.95     OK     556.43      120.52
    # LowriseApartment        587.74     OK     469.51      118.23
    # MediumOffice           1660.73     OK    1466.85      193.88
    # MidriseApartment        783.65     OK     637.63      146.02
    # PrimarySchool          6871.00     OK    6123.16      747.84
    # QuickServiceRestaurant  232.34     OK     164.94       67.41
    # RetailStandalone       2293.99     OK    2068.06      225.94
    # RetailStripmall        2090.32     OK    1821.76      268.56
    # SecondarySchool       11902.00     OK   11012.56      889.44
    # SmallHotel             1003.40     OK     833.59      169.81
    # SmallOffice             511.16     OK     406.16      105.00
    # Warehouse              4598.25     OK    4252.90      345.35
    #
    # LEEPTownHouse1          466.15     OK     364.44      101.71
    # LEEPTownHouse2          699.22     OK     563.52      135.70
    # ---------------------- ------- ------- ---------- ---------------
    # LEEPTownHouse TOTAL    1165.37     OK     927.96      237.41  OK
    #
    #
    # SKIPPED CASES (as expected):
    # ----------------------------------------------------------------------
    # LargeOffice        : full basement
    # Hospital           : full basement
    # NortherEducation   : no ground-facing floors
    # NorthernHealthCare : no ground-facing floors
    #
    #
    # PROBLEM CASES (doesn't work initially, works after BTAP modifications):
    # ----------------------------------------------------------------------
    # LargeHotel
    # LEEPTownHouse
    #
    #
    # PROBLEM CASES (Boost feedback: "union has inner loops"):
    # ----------------------------------------------------------------------
    # Prototype          slab         union?          cutout
    # LEEPMultiTower  2814.72 (2441)  2434.49 (2043)  380.23 (397)
    # Outpatient      1373.29 (1199)  1164.31 ( 875)  208.98 (324)

    fdback = []
    fdback << ""
    fdback << "BTAP/Dimensions Unit Tests"
    fdback << "~~~~~~~~~~~~~~~ ~~~~ ~~~~~"

    @buildings.sort.each do |building|
      cas   = "CASE #{building}"
      file  = File.join(osm_dir, building)
      path  = OpenStudio::Path.new(file)
      model = translator.loadModel(path)
      emsg  = "BTAP/Dimensions: empty model (#{cas})?"
      refute_empty(model, emsg)
      model = model.get

      # NECBs require 1.2 m of perimeter insulation for slabs-on-grade (CZ 4-7).
      m2   = BTAP::Geometry::Spaces.perimeter_m2(model.getSpaces, 1.2)
      area = case building
             when "FullServiceRestaurant.osm"  then 102.76
             when "HighriseApartment.osm"      then 146.02
             when "HighriseApartmentMult.osm"  then 146.02
             when "Hospital.osm"               then 290.51
             when "LargeHotel.osm"             then 256.86
             when "LEEPMidriseApartment.osm"   then 140.42
             when "LEEPPointTower.osm"         then 120.52
             when "LowriseApartment.osm"       then 118.23
             when "MediumOffice.osm"           then 193.88
             when "MidriseApartment.osm"       then 146.02
             when "PrimarySchool.osm"          then 747.84
             when "QuickServiceRestaurant.osm" then  67.41
             when "RetailStandalone.osm"       then 225.94
             when "RetailStripmall.osm"        then 268.56
             when "SecondarySchool.osm"        then 889.44
             when "SmallHotel.osm"             then 169.81
             when "SmallOffice.osm"            then 105.00
             when "Warehouse.osm"              then 345.35
             else                                     0.00
             end

      emsg = "BTAP/Dimensions: slab perimeter (#{cas})"
      assert_in_delta(m2, area, 0.02, emsg)
    end
  end
end
