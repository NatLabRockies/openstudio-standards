require 'json'
require_relative 'costing_database_wrapper'

class SimpleLinearRegression
  #https://gist.github.com/rweald/3516193#file-full-slr-class-snippet-rb
  def initialize(xs, ys)
    @xs, @ys = xs, ys
    if @xs.length != @ys.length
      raise "Unbalanced data. xs need to be same length as ys"
    end
  end

  def y_intercept
    return mean(@ys) - (slope * mean(@xs))
  end

  def slope
    x_mean = mean(@xs)
    y_mean = mean(@ys)

    numerator = (0...@xs.length).reduce(0) do |sum, i|
      sum + ((@xs[i] - x_mean) * (@ys[i] - y_mean))
    end

    denominator = @xs.reduce(0) do |sum, x|
      sum + ((x - x_mean) ** 2)
    end

    return (numerator / denominator)
  end

  def mean(values)
    total = values.reduce(0) { |sum, x| x + sum }
    return Float(total) / Float(values.length)
  end
end


class BTAPCosting
  # May be initialized with custom databases:
  #   costs_csv:   Path to custom costing
  #   factors_csv: Path to custom localization factors
  def initialize(costs_csv: nil, factors_csv: nil, attributes:)
    @cp               = CommonPaths.instance
    @costing_database = CostingDatabase.instance
    @attributes       = attributes

    # If the path for custom costing is defined, use custom costing.
    if (not costs_csv.nil?) and File.exist?(costs_csv)
      @cp.costs_path = costs_csv
    end

    # If the path for custom factors is defined, use custom factors.
    if (not factors_csv.nil?) and File.exist?(factors_csv)
      @cp.costs_local_factors_path = factors_csv
    end
  end

  def validate_database()
    @costing_database.validate_database
  end

  def generate_construction_cost_database_for_all_cities()
    result = Array.new
    @costing_database['raw']['locations'].each do |location|
      province_state = location["province_state"]
      city = location['city']
      result.concat(generate_construction_cost_database_for_city(city, province_state))
    end
    return result
  end

  def generate_construction_cost_database_for_city(city, province_state)
    @costing_database['constructions_costs'] = Array.new
    puts "Costing for: #{province_state},#{city}"
    @costing_database["raw"]['constructions_opaque'].each do |construction|
      cost_construction(construction, {"province_state" => province_state, "city" => city}, 'opaque')
    end
    @costing_database["raw"]['constructions_glazing'].each do |construction|
      cost_construction(construction, {"province_state" => province_state, "city" => city}, 'glazing')
    end
    puts "#{@costing_database['constructions_costs'].size} Costed Constructions for #{province_state},#{city}."
    return @costing_database['constructions_costs']
  end


  def cost_audit_all(model:,
                     prototype_creator:,
                     envelope_costing: true,
                     lighting_costing: true,
                     boilers_costing: true,
                     chillers_costing: true,
                     cooling_towers_costing: true,
                     shw_costing: true,
                     ventilation_costing: true,
                     zone_system_costing: true,
                     renewables_costing: true,
                     template_type: nil
  )
    # Create a Hash to collect costing data.
    @costing_report = {}

    #Use closest city.
    closest_loc = get_closest_cost_location(model.getWeatherFile.latitude, model.getWeatherFile.longitude)
    @costing_report['city'] = closest_loc['city']
    @costing_report['province_state'] = closest_loc['province_state']

    # Create array to collect costed item information.  First element is the costing location.
    @cost_items = {
      'City' => closest_loc['city'],
      'Province' => closest_loc['province_state'],
      'Items' => []
    }

    # Create a Hash in the hash for categories of costing.
    @costing_report['envelope'] = {}
    @costing_report['lighting'] = {}
    @costing_report['lighting']['daylighting_sensor_control'] = []
    @costing_report['lighting']['led_lighting'] = []
    @costing_report['heating_and_cooling'] = {}
    @costing_report['heating_and_cooling']['plant_equipment'] = []
    @costing_report['heating_and_cooling']['zonal_systems'] = []
    @costing_report['shw'] = {}
    @costing_report['ventilation'] = {}
    @costing_report['renewables'] = {}
    @costing_report['renewables']['pv'] = []
    @costing_report['totals'] = {}

    # Check to see if standards building type and the number of stories has been defined.  The former may be omitted in the future.
    if model.getBuilding.standardsBuildingType.empty? or model.getBuilding.standardsNumberOfAboveGroundStories.empty?
      raise("Building information is not complete, please ensure that the standardsBuildingType and standardsNumberOfAboveGroundStories are entered in the model. ")
    end

    # Find the mechanical room
    mech_room, cond_spaces = prototype_creator.find_mech_room(model)

    envCost = envelope_costing ? self.cost_audit_envelope(model, prototype_creator) : 0.0
    lgtCost = lighting_costing ? self.cost_audit_lighting(model, prototype_creator) : 0.0
    boilerCost = boilers_costing ? self.boiler_costing(model, prototype_creator) : 0.0
    chillerCost = chillers_costing ? self.chiller_costing(model, prototype_creator) : 0.0
    coolingTowerCost = cooling_towers_costing ? self.coolingtower_costing(model, prototype_creator) : 0.0
    shwCost = shw_costing ? self.shw_costing(model, prototype_creator) : 0.0
    ventCost = ventilation_costing ? self.ventilation_costing(model, prototype_creator,template_type, mech_room, cond_spaces) : 0.0
    zonalSystemCost = zone_system_costing ? self.zonalsys_costing(model, prototype_creator, mech_room, cond_spaces) : 0.0
    pvGroundCost = renewables_costing ? self.cost_audit_pv_ground(model, prototype_creator) : 0.0
    thermalBridgingCost = 0.0

    @costing_report["totals"] = {
      'envelope' => envCost.round(0),
      'thermal_bridging' => thermalBridgingCost.round(0),
      'lighting' => lgtCost.round(0),
      'heating_and_cooling' => (boilerCost + chillerCost + coolingTowerCost + zonalSystemCost).round(0),
      'shw' => shwCost.round(0),
      'ventilation' => ventCost.round(0),
      'renewables' => pvGroundCost.round(0),
      'grand_total' => (envCost + thermalBridgingCost + lgtCost + boilerCost + chillerCost + coolingTowerCost +
        shwCost + ventCost + zonalSystemCost + pvGroundCost).round(0)
    }

    return @costing_report, @cost_items
  end

  def get_regional_cost_factors(provinceState, city, material)
    @costing_database['localization_factors'].select { |code|
      code['province_state'] == provinceState && code['city'] == city }.each do |code|
      prefix_id = material['id'][0..1]
      prefix_stored = code['code_prefix']
      if prefix_id == prefix_stored
        return code['material'], code['installation'], code['total']
      end

    end
    error = [material, "Could not find regional adjustment factor for material used in #{city}, #{provinceState}."]
    @costing_database['db_errors'] << error unless @costing_database['db_errors'].include?(error)
    return 100.0, 100.0, 100.0
  end

  # Interpolate array of hashes that contain 2 values (key=rsi, data=cost)
  def interpolate(x_y_array:, x2:, exterpolate_percentage_range: 30.0)
    ratio_range = exterpolate_percentage_range / 100.0
    array = x_y_array.uniq.sort { |a, b| a[0] <=> b[0] }
    #if there is only one...return what you got.
    if array.size == 1
      return array.first[1].to_f
    end
    # Check if value x2 is within range of array for interpolation
    # Extrapolate when x2 is out-of-range by +/- 10% of end values.
    if array.empty? || x2 < ((1.0 - ratio_range) * array.first[0].to_f) || x2 > ((1.0 + ratio_range) * array.last[0].to_f)
      return nil
    elsif x2 < array.first[0].to_f
      # Extrapolate down using first and second cost value to this out-of-range input
      x_array = [array[0][0].to_f, array[1][0].to_f]
      y_array = [array[0][1].to_f, array[1][1].to_f]
      linear_model = SimpleLinearRegression.new(x_array, y_array)
      y2 = linear_model.y_intercept + linear_model.slope * x2
      return y2
    elsif x2 > array.last[0].to_f
      # Extrapolate up using second to last and last cost value to this out-of-range input
      x_array = [array[-2][0].to_f, array[-1][0].to_f]
      y_array = [array[-2][1].to_f, array[-1][1].to_f]
      linear_model = SimpleLinearRegression.new(x_array, y_array)
      y2 = linear_model.y_intercept + linear_model.slope * x2
      return y2
    else
      array.each_index do |counter|

        # skip last value.
        next if array[counter] == array.last

        x0 = array[counter][0]
        y0 = array[counter][1]
        x1 = array[counter + 1][0]
        y1 = array[counter + 1][1]

        # skip to next if x2 is not between x0 and x1
        next if x2 < x0 || x2 > x1

        # Do interpolation
        y2 = y0 # just in-case x0, x1 and x2 are identical!
        if (x1 - x0) > 0.0
          y2 = y0.to_f + ((y1 - y0).to_f * (x2 - x0).to_f / (x1 - x0).to_f)
        end
        return y2
      end
    end
  end

  # Enter in [latitude, longitude] for each loc and this method will return the distance.
  def distance(loc1, loc2)
    rad_per_deg = Math::PI / 180 # PI / 180
    rkm = 6371 # Earth radius in kilometers
    rm = rkm * 1000 # Radius in meters

    dlat_rad = (loc2[0] - loc1[0]) * rad_per_deg # Delta, converted to rad
    dlon_rad = (loc2[1] - loc1[1]) * rad_per_deg

    lat1_rad, lon1_rad = loc1.map { |i| i * rad_per_deg }
    lat2_rad, lon2_rad = loc2.map { |i| i * rad_per_deg }

    a = Math.sin(dlat_rad / 2) ** 2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2) ** 2
    c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1 - a))
    rm * c # Delta in meters
  end

  def get_closest_cost_location(lat, long)
    dist = 1000000000000000000000.0
    closest_loc = nil
    # province_state	city	latitude	longitude	source
    @costing_database['raw']['locations'].each do |location|
      if distance([lat, long], [location['latitude'].to_f, location['longitude'].to_f]) < dist
        closest_loc = location
        dist = distance([lat, long], [location['latitude'].to_f, location['longitude'].to_f])
      end
    end
    return closest_loc
  end

  # This will expand the two letter province abbreviation to a full uppercase province name
  def expandProvAbbrev(abbrev)

    # Note that the proper abbreviation for Quebec is QC not PQ. However, we've used PQ in openstudio-standards!
    Hash provAbbrev = {"AB" => "ALBERTA",
                       "BC" => "BRITISH COLUMBIA",
                       "MB" => "MANITOBA",
                       "NB" => "NEW BRUNSWICK",
                       "NL" => "NEWFOUNDLAND AND LABRADOR",
                       "NT" => "NORTHWEST TERRITORIES",
                       "NS" => "NOVA SCOTIA",
                       "NU" => "NUNAVUT",
                       "ON" => "ONTARIO",
                       "PE" => "PRINCE EDWARD ISLAND",
                       "PQ" => "QUEBEC",
                       "SK" => "SASKATCHEWAN",
                       "YT" => "YUKON"
    }
    return provAbbrev[abbrev]
  end

  def read_mech_sizing()
    file = File.read(@cp.mech_sizing_data_file)
    return JSON.parse(file)
  end

  # This adds costed items to the array of cousted items which end up in btap_itmes.json.  Note that the array this
  # method uses is created in the cost_audit_all method.  The array is created with an initial element that contains the
  # city and province whose localiazation factors are used for costing.
  # The inputs are:
  # id: (string)  The costing database id for the item being costed.
  # quantity: (float)  The total amount of the item being costed in whatever units the item is costed in.  This should
  #                    include all multiplier used to determine this cost (e.g. such as thermal_zone multipliers).  As
  #                    an example, if 32 ft. of wire were required for a piece of equipment used in a thermal zone with
  #                    a multiplier of 10, the quantity would be 3.2 (32 ft. * 10 / 100 since wire is costed per
  #                    100 ft.).
  # material_mult: (float)  The multiplier used to estimate the cost of an item from the base cost.  For example, high
  #                 efficiency SHW tanks are estimated to cost 30% higher than regular SHW tanks so the cost of these
  #                 tanks are calculated by the cost * 1.3.  Thus, the material_mult for high efficiency tanks
  #                 would be 1.3.  This is defauted to 1.0 if it is not provided.
  # labour_mult: (float) Similar to material_mult only applied to labour costs.  The labour_mult can be different than
  #              the material_mult.  This is defaulted to 1.0 if it is not provided.
  # equipment_mult: (float)  Similar to material_mult and labour_mult only for equipment.  This will always be 1.0 until
  #                  equipment costs are supported.
  # tags: (array of strings)  This is an array which links the costed item to a component of the model that is being
  #       costed.  For example, a material_id related to a boiler pump might have tags like ["boiler", "pump"].
  #
  def add_costed_item(material_id:, quantity:, material_mult: 1.0, labour_mult: 1.0, equip_mult: 1.0, tags: [])
    # Do some error handling for the tags argument
    tags_out = [tags] if tags.kind_of?(String)
    tags_out = tags if tags.kind_of?(Array)

    # Validate the type of the arguments.
    if (tags_out.kind_of?(Array) == false)
      raise("The tags for the item #{material_id} were not properly defined.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    if (material_id.kind_of?(String) == false)
      raise("The material_id for the item #{material_id} is not a string.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    if (quantity.kind_of?(Float) == false)
      raise("The quantity for the item #{material_id} is not a float.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    if (material_mult.kind_of?(Float) == false)
      raise("The material_mult for the item #{material_id} is not a float.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    if (labour_mult.kind_of?(Float) == false)
      raise("The labour_mult for the item #{material_id} is not a float.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    if (equip_mult.kind_of?(Float) == false)
      raise("The equip_mult for the item #{material_id} is not a float.  Please search for where the item is being added to the @cost_items hash via the add_costed_item method and correct the entry.")
    end

    # Add the costed item to the output output hash.
    @cost_items['Items'] << {
      'id' => material_id,
      'quantity' => quantity,
      'material_mult' => material_mult,
      'labour_mult' => labour_mult,
      'equipment_mult' => equip_mult,
      'tags' => tags_out
    }
  end

  # This method takes the list of costed items in the building generated with the help of the above add_costed_item
  # method and finds the costs for the list of items.  It takes in:
  # btap_items: (array of hashes)  This array contains all the items that must be costed.  The first element of the
  #             array is:
  #       {
  #         City: (string) City used for cost lacalization factor
  #         Province: (string) Province used for cost localization factor
  #       }
  # The remaining arrays look like:
  # {
  #       id: (string)  ID of the coested item in question.
  #       quantity: (float) Amount of costed item (should include all multipliers except localization factors,
  #                 material_mult, labour_mult, equipment_mult).
  #       material_mult: (float) Material multiplier from cost spreadsheet used mainly for higher performance equipment
  #                      (for example, regular and high performance boilers share the same id but high performance
  #                      boilers have a material_mult of around 1.3-that is they are estimated to be 1.3 times as
  #                      expensive as regular boilers).
  #       labour_mult: (float) Same idea as material_mult only for labour (often this will be 1.0 even if material_mult
  #                    is something else).
  #       equipment_mult: (float) Same idea as labour_mult only for equipment.  It will always be 1.0 until equipment
  #                       costs are implemented in costing.
  #       tags: (array of strings) An array of strings used to define what part of the building is being costed (e.g.
  #             an component for a ccashp might have these tags: "Ventilation", "CCASHP", "ccashp_condensor")
  #     }
  # custom_costing: (array of hashes) A custom costing database if you do not want to use the default one.  This must
  #                 have the same format as that found by @costing_database['costs']
  # custCity: (string) A custom cost localization city if you do not want to use the one in the first item in the
  #           btap_itmes hash.
  # custProvince: (string) A custom cost localization province if you do not want to use the one in the first item in
  #               the btap_items hash.
  #
  # The output of the method is a hash containing these summary costs:
  #     costRetHash = {
  #       envelope: (float) Building envelope costs (to 2 decimal places).
  #       lighting: (float) Ligting costs (to 2 decimal places).
  #       heating_and_cooling: (float) Heating and cooling costs (not related to ventilation) (to 2 decimal places).
  #       shw: (float) Service hot water costs (to 2 decimal places).
  #       ventilation: (float) Ventilation (including ventilation air heating and cooling) costs (to 2 decimal places).
  #       grand_total: (float) Total costs (to 2 decimal places).
  #     }
  #
  def cost_list_items(btap_items:, custom_costing: nil, custCity: nil, custProvince: nil)
    # Check if costing is for a custom city and province.  If not use the city and province found in the first entry
    # of the array of costed items.
    if custCity.nil? || custProvince.nil?
      costCity = btap_items['City'].to_s
      costProvince = btap_items['Province'].to_s
    else
      costCity = custCity
      costProvince = custProvince
    end

    # Initialize cost counters
    totCost = 0.0
    envCost = 0.0
    lightCost = 0.0
    heatCoolCost = 0.0
    shwCost = 0.0
    ventCost = 0.0
    renewCost = 0.0

    custom_costing.nil? ? costingDB = @costing_database['costs'] : costingDB = custom_costing

    btap_items['Items'].each do |costing_item|
      # Look for the costing information for the piece of equipment in the costing database.
      costing_data = costingDB.detect {|data| data['id'].to_s.upcase == costing_item['id'].to_s.upcase}
      # If no costing information is found then return an error.
      if costing_data.nil?
        raise "Error: no costing information available for material id #{costing_item['id']}!"
      elsif costing_data['baseCosts']['materialOpCost'].nil? && costing_data['baseCosts']['laborOpCost'].nil?
        #This is a stub for some work that needs to be done to account for equipment costing. For now this is zeroed out.
        # A similar test is done on reading the data from the database and collected in the error file when the
        # costing database is generated.
        raise "Error: costing information for material id #{costing_item['id']} is nil.  Please check costing data."
      end
      costing_data['baseCosts']['equipmentOpCost'].nil? ? equip_base_cost = 0.0 : equip_base_cost = costing_data['baseCosts']['equipmentOpCost'].to_f
      costing_data['baseCosts']['materialOpCost'].nil? ? mat_base_cost = 0.0 : mat_base_cost = costing_data['baseCosts']['materialOpCost'].to_f
      costing_data['baseCosts']['laborOpCost'].nil? ? lab_base_cost = 0.0 : lab_base_cost = costing_data['baseCosts']['laborOpCost'].to_f

      # The costs from the costing database are US national average costs (for placeholder costs) or whatever is in the
      # 'province_state' and 'city' fields (for custom costs).  These costs need to be adjusted to reflect the costs
      # expected in the location of interest.  The 'get_regional_cost_factors' method finds the appropriate cost
      # adjustment factors.

      mat_mult, inst_mult, eq_mult = get_regional_cost_factors(costProvince, costCity, costing_item)
      if mat_mult.nil? || inst_mult.nil?
        raise("Error: no localization information available for material id #{costing_item['material_id']}!")
      end
      # Get any associated material or labour multiplier for the equipment present in the 'materials_hvac' sheet in the
      # costing spreadsheet.
      costing_item['material_mult'].to_f == 0 ? mat_quant = 1.0 : mat_quant = costing_item['material_mult'].to_f
      costing_item['labour_mult'].to_f == 0 ? lab_quant = 1.0 : lab_quant = costing_item['labour_mult'].to_f
      costing_item['equipment_mult'].to_f == 0 || costing_item['equipment_mult'].nil? ? eq_quant = 1.0 : eq_quant = costing_item['equipment_mult'].to_f
      # Calculate the adjusted material and labour costs.
      mat_cost = mat_base_cost*(mat_mult/100.0)*mat_quant
      lab_cost = lab_base_cost*(inst_mult/100.0)*lab_quant
      eq_cost = equip_base_cost*(eq_mult/100.0)*eq_quant
      # Calculate the total item cost.
      item_cost = (mat_cost + lab_cost + eq_cost)*(costing_item["quantity"].to_f)

      # Add cost to sub-type counters
      envCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "ENVELOPE"}).empty?
      lightCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "LIGHTING"}).empty?
      heatCoolCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "HEATING_COOLING"}).empty?
      shwCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "SHW"}).empty?
      ventCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "VENTILATION"}).empty?
      renewCost += item_cost unless (costing_item['tags'].select{|data| data.to_s.upcase == "RENEWABLES"}).empty?
      totCost += item_cost
    end

    # Create and return hash containing costing results
    costRetHash = {
      'envelope' => envCost.round(2),
      'lighting' => lightCost.round(2),
      'heating_and_cooling' => heatCoolCost.round(2),
      'shw' => shwCost.round(2),
      'ventilation' => ventCost.round(2),
      'renewables' => renewCost.round(2),
      'grand_total' => totCost.round(2)
    }
    return costRetHash
  end

end
