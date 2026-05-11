# Custom changes for the Warehouse prototype
# These are changes that are inconsistent with other prototype building types.
module Warehouse
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    return true
  end

  # swh adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)
    return true
  end

  def model_custom_daylighting_tweaks(building_type, climate_zone, prototype_input, model)
    return true
  end

  # geometry adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_geometry_tweaks(model, building_type, climate_zone, prototype_input)
    # Set original building North axis
    OpenstudioStandards::Geometry.model_set_building_north_axis(model, 90.0)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Adjusting geometry input')
    case template
      when '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        case climate_zone
          when 'ASHRAE 169-2006-6A',
               'ASHRAE 169-2006-6B',
               'ASHRAE 169-2006-7A',
               'ASHRAE 169-2006-8A',
               'ASHRAE 169-2013-6A',
               'ASHRAE 169-2013-6B',
               'ASHRAE 169-2013-7A',
               'ASHRAE 169-2013-8A'
            # Remove existing skylights
            model.getSubSurfaces.each do |subsurf|
              if subsurf.subSurfaceType.to_s == 'Skylight'
                subsurf.remove
              end
            end
            # Load older geometry corresponding to older code versions
            old_geo = load_geometry_osm('geometry/ASHRAE90120042007Warehouse.osm')
            # Clone the skylights from the older geometry
            old_geo.getSubSurfaces.each do |subsurf|
              if subsurf.subSurfaceType.to_s == 'Skylight'
                new_skylight = subsurf.clone(model).to_SubSurface.get
                old_roof = subsurf.surface.get
                # Assign surfaces to skylights
                model.getSurfaces.each do |model_surf|
                  if model_surf.name.to_s == old_roof.name.to_s
                    new_skylight.setSurface(model_surf)
                  end
                end
              end
            end
        end
    end
    return true
  end

  # Get building door information to update infiltration
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # return [Hash] Door infiltration information
  def get_building_door_info(model)
    # Get Bulk storage space infiltration schedule name
    sch = model_add_schedule(model, 'Warehouse INFIL_Door_Opening_SCH')

    if !sch.initialized
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.Warehouse', 'Could not find Bulk storage schedule.')
      return false
    end

    get_building_door_info = {
      'Metal coiling' => {
        'number_of_doors' => 2.95,
        'door_area_ft2' => 80.0, # 8'-0" by 10'-0"
        'schedule' => sch,
        'space' => 'Zone3 Bulk Storage'
      },
      'Rollup' => {
        'number_of_doors' => 8.85,
        'door_area_ft2' => 80.0, # 8'-0" by 10'-0"
        'schedule' => sch,
        'space' => 'Zone3 Bulk Storage'
      },
      'Open' => {
        'number_of_doors' => 3.2,
        'door_area_ft2' => 80.0, # 8'-0" by 10'-0"
        'schedule' => sch,
        'space' => 'Zone3 Bulk Storage'
      }
    }

    return get_building_door_info
  end
end
