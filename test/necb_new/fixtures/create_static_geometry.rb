#!/usr/bin/env ruby

# Create Static Geometry Fixtures
# These are simple geometry files checked into git for basic tests
# They do NOT require sizing runs
# Uses OpenstudioStandards::Geometry.create_shape_* methods

require 'bundler/setup'
require 'openstudio'
require 'openstudio-standards'
require 'fileutils'

GEOMETRY_DIR = File.join(__dir__, 'geometry')
FileUtils.mkdir_p(GEOMETRY_DIR)

puts "Creating static geometry fixtures using OpenstudioStandards::Geometry methods..."
puts ""

# Helper to save model
def save_geometry(model, filename, description)
  path = File.join(GEOMETRY_DIR, filename)
  model.save(path, true)
  size_kb = (File.size(path) / 1024.0).round(1)
  puts "Created: #{filename} (#{size_kb} KB) - #{description}"
end

#==============================================================================
# 1. Simple Box - Minimal geometry for construction tests
#==============================================================================

puts "1. Creating simple_box.osm..."
model = OpenStudio::Model::Model.new

# Use create_shape_rectangle for a simple single-zone box
# 10m × 10m, 1 story, 3m floor-to-floor height, no perimeter zoning
OpenstudioStandards::Geometry.create_shape_rectangle(
  model,
  length = 10.0,              # 10m long
  width = 10.0,               # 10m wide
  above_ground_storys = 1,    # Single story
  under_ground_storys = 0,    # No basement
  floor_to_floor_height = 3.0,# 3m height
  plenum_height = 0.0,        # No plenum
  perimeter_zone_depth = 0.0, # Single zone (no perimeter/core split)
  initial_height = 0.0        # Ground level
)

# Add a south-facing window manually (OpenstudioStandards sets WWR, but we want specific window)
model.getSpaces.each do |space|
  space.setName("SimpleSpace")
  space.surfaces.each do |surface|
    if surface.surfaceType == "Wall" && surface.outsideBoundaryCondition == "Outdoors"
      # Find south wall (outward normal pointing south, i.e., negative Y)
      outward_normal = surface.outwardNormal
      if outward_normal.y < -0.9  # South-facing
        surface.setName("South_Wall")

        # Add a centered window (40% WWR approximately)
        vertices = surface.vertices
        min_x = vertices.map(&:x).min
        max_x = vertices.map(&:x).max
        min_z = vertices.map(&:z).min
        max_z = vertices.map(&:z).max

        wall_width = max_x - min_x
        wall_height = max_z - min_z

        # Window: 4m wide, 1.5m tall, centered horizontally, 0.5m from floor
        window_width = 4.0
        window_height = 1.5
        window_sill = 0.5
        window_x_start = min_x + (wall_width - window_width) / 2.0

        y_coord = vertices[0].y  # Same Y as wall

        window_vertices = OpenStudio::Point3dVector.new
        window_vertices << OpenStudio::Point3d.new(window_x_start, y_coord, window_sill)
        window_vertices << OpenStudio::Point3d.new(window_x_start + window_width, y_coord, window_sill)
        window_vertices << OpenStudio::Point3d.new(window_x_start + window_width, y_coord, window_sill + window_height)
        window_vertices << OpenStudio::Point3d.new(window_x_start, y_coord, window_sill + window_height)

        window = OpenStudio::Model::SubSurface.new(window_vertices, model)
        window.setName("South_Window")
        window.setSubSurfaceType("FixedWindow")
        window.setSurface(surface)
      end
    end
  end
end

# Set thermal zone name
model.getThermalZones.each { |zone| zone.setName("SimpleZone") }

# Add minimal site info (Toronto)
site = model.getSite
site.setName("Simple Box Site")
site.setLatitude(43.6532)
site.setLongitude(-79.3832)
site.setTimeZone(-5.0)
site.setElevation(76.0)

save_geometry(model, "simple_box.osm", "Single zone 10m×10m×3m box with south window")

#==============================================================================
# 2. Simple Box with Skylight
#==============================================================================

puts "2. Creating simple_box_with_skylight.osm..."
model2 = OpenStudio::Model::Model.new

# Create same box
OpenstudioStandards::Geometry.create_shape_rectangle(
  model2,
  length = 10.0,
  width = 10.0,
  above_ground_storys = 1,
  under_ground_storys = 0,
  floor_to_floor_height = 3.0,
  plenum_height = 0.0,
  perimeter_zone_depth = 0.0,
  initial_height = 0.0
)

# Add south window (same as above)
model2.getSpaces.each do |space|
  space.setName("SimpleSpace")
  space.surfaces.each do |surface|
    if surface.surfaceType == "Wall" && surface.outsideBoundaryCondition == "Outdoors"
      outward_normal = surface.outwardNormal
      if outward_normal.y < -0.9  # South-facing
        surface.setName("South_Wall")
        vertices = surface.vertices
        min_x = vertices.map(&:x).min
        max_x = vertices.map(&:x).max
        wall_width = max_x - min_x
        window_width = 4.0
        window_height = 1.5
        window_sill = 0.5
        window_x_start = min_x + (wall_width - window_width) / 2.0
        y_coord = vertices[0].y

        window_vertices = OpenStudio::Point3dVector.new
        window_vertices << OpenStudio::Point3d.new(window_x_start, y_coord, window_sill)
        window_vertices << OpenStudio::Point3d.new(window_x_start + window_width, y_coord, window_sill)
        window_vertices << OpenStudio::Point3d.new(window_x_start + window_width, y_coord, window_sill + window_height)
        window_vertices << OpenStudio::Point3d.new(window_x_start, y_coord, window_sill + window_height)

        window = OpenStudio::Model::SubSurface.new(window_vertices, model2)
        window.setName("South_Window")
        window.setSubSurfaceType("FixedWindow")
        window.setSurface(surface)
      end
    end

    # Add skylight to roof
    if surface.surfaceType == "RoofCeiling" && surface.outsideBoundaryCondition == "Outdoors"
      surface.setName("Roof")

      # Add centered 2m × 2m skylight
      vertices = surface.vertices
      min_x = vertices.map(&:x).min
      max_x = vertices.map(&:x).max
      min_y = vertices.map(&:y).min
      max_y = vertices.map(&:y).max
      z = vertices[0].z

      roof_length = max_x - min_x
      roof_width = max_y - min_y

      skylight_size = 2.0
      skylight_x_start = min_x + (roof_length - skylight_size) / 2.0
      skylight_y_start = min_y + (roof_width - skylight_size) / 2.0

      skylight_vertices = OpenStudio::Point3dVector.new
      skylight_vertices << OpenStudio::Point3d.new(skylight_x_start, skylight_y_start, z)
      skylight_vertices << OpenStudio::Point3d.new(skylight_x_start + skylight_size, skylight_y_start, z)
      skylight_vertices << OpenStudio::Point3d.new(skylight_x_start + skylight_size, skylight_y_start + skylight_size, z)
      skylight_vertices << OpenStudio::Point3d.new(skylight_x_start, skylight_y_start + skylight_size, z)

      skylight = OpenStudio::Model::SubSurface.new(skylight_vertices, model2)
      skylight.setName("Roof_Skylight")
      skylight.setSubSurfaceType("Skylight")
      skylight.setSurface(surface)
    end
  end
end

# Set thermal zone name
model2.getThermalZones.each { |zone| zone.setName("SimpleZone") }

# Add site info
site2 = model2.getSite
site2.setName("Simple Box with Skylight Site")
site2.setLatitude(43.6532)
site2.setLongitude(-79.3832)
site2.setTimeZone(-5.0)
site2.setElevation(76.0)

save_geometry(model2, "simple_box_with_skylight.osm", "Single zone box with window and skylight (4% SRR)")

#==============================================================================
# 3. Multi-zone Rectangle - For perimeter/core zoning tests
#==============================================================================

puts "3. Creating multi_zone_rectangle.osm..."
model3 = OpenStudio::Model::Model.new

# Create a larger rectangle with perimeter/core zoning
# 20m × 15m, 1 story, 4.57m perimeter depth (standard NECB)
OpenstudioStandards::Geometry.create_shape_rectangle(
  model3,
  length = 20.0,              # 20m long
  width = 15.0,               # 15m wide
  above_ground_storys = 1,    # Single story
  under_ground_storys = 0,    # No basement
  floor_to_floor_height = 3.0,# 3m height
  plenum_height = 0.0,        # No plenum
  perimeter_zone_depth = 4.57,# 4.57m perimeter (standard NECB)
  initial_height = 0.0        # Ground level
)

# Add site info
site3 = model3.getSite
site3.setName("Multi-zone Rectangle Site")
site3.setLatitude(43.6532)
site3.setLongitude(-79.3832)
site3.setTimeZone(-5.0)
site3.setElevation(76.0)

save_geometry(model3, "multi_zone_rectangle.osm", "20m×15m rectangle with perimeter/core zoning (5 zones)")

puts ""
puts "="*80
puts "Static geometry fixtures created successfully!"
puts "Location: #{GEOMETRY_DIR}"
puts ""
puts "Fixtures created:"
puts "  1. simple_box.osm - Single zone for construction/FDWR tests"
puts "  2. simple_box_with_skylight.osm - Single zone for SRR tests"
puts "  3. multi_zone_rectangle.osm - Perimeter/core for autozone tests"
puts ""
puts "Usage in tests:"
puts "  model = BTAP::FileIO.load_osm('#{File.expand_path(GEOMETRY_DIR)}/simple_box.osm')"
puts ""
puts "Note: 5ZoneNoHVAC.osm already exists in test/necb/unit_tests/resources/"
puts "="*80
