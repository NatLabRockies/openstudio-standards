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
      "Warehouse.osm",          # 'Zone2 Fine Storage' (height?) ... mezzanine
      "NorthernHealthCare.osm", # F-shaped 'corridors' (width?)
      "SmallHotel.osm"          # F-shaped 'corridors' (width?)
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

      err_msg = "BTAP/Dimensions: empty model (#{cas})?"
      refute_empty(model, err_msg)
      model = model.get

      id = case building
           when "Warehouse.osm"          then "Zone2 Fine Storage"
           when "NorthernHealthCare.osm" then "Corridor 2"
           when "SmallHotel.osm"         then "CorridorFlr2"
           else next
           end

      space = model.getSpaceByName(id)

      err_msg = "BTAP/Dimensions: empty space '#{id}' (#{cas})?"
      refute_empty(space, err_msg)
      space  = space.get

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

      err_msg = "BTAP/Dimensions: height '#{id}' (#{cas})?"
      assert_in_delta(height, hauteur, 0.01, err_msg)
      err_msg = "BTAP/Dimensions: width '#{id}' (#{cas})?"
      assert_in_delta(width, largeur, 0.01, err_msg)

      # Higher level feedback.
      fdback << "#{cas} : #{id} : height = #{height.round(2)} : width = #{width.round(2)}"
      # CASE NorthernHealthCare.osm : Corridor 2         : 4.11 :  2.44
      # CASE SmallHotel.osm         : CorridorFlr2       : 2.74 :  1.83
      # CASE Warehouse.osm          : Zone2 Fine Storage : 8.53 : 21.33
    end

    # Temporary.
    fdback.each { |msg| puts msg }
  end
end
