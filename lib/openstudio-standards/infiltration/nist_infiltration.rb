module OpenstudioStandards
  # The Infiltration module provides methods create, modify, and get information about model infiltration
  module Infiltration
    # @!group NIST Infiltration

    # DOE prototype buildings for which there are NIST infiltration coefficients.
    #
    # @return [OpenStudio::StringVector] vector of strings of valid building types
    def self.nist_building_types
      building_types = OpenStudio::StringVector.new
      building_types << 'SecondarySchool'
      building_types << 'PrimarySchool'
      building_types << 'SmallOffice'
      building_types << 'MediumOffice'
      building_types << 'SmallHotel'
      building_types << 'LargeHotel'
      building_types << 'RetailStandalone'
      building_types << 'RetailStripmall'
      building_types << 'Hospital'
      building_types << 'MidriseApartment'
      building_types << 'HighriseApartment'

      return building_types
    end

    # Infer the building type to use for NIST correlations, as only a subset of building types are available.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Schedule] OpenStudio Schedule object
    def self.model_infer_nist_building_type(model)
      if model.getBuilding.standardsBuildingType.is_initialized
        model_building_type = model.getBuilding.standardsBuildingType.get
      else
        model_building_type = ''
      end

      case model_building_type
      when 'Office', 'SmallOffice', 'SmallOfficeDetailed', 'MediumOffice', 'MediumOfficeDetailed', 'LargeOffice', 'LargeOfficeDetailed', 'Outpatient', 'OfS', 'OfL', 'SmallDataCenterLowITE', 'SmallDataCenterHighITE', 'LargeDataCenterLowITE', 'LargeDataCenterHighITE'
        # map office or data center building type to small, medium or large
        floor_area = model.getBuilding.floorArea
        if floor_area < 2750.0
          nist_building_type = 'SmallOffice'
        else
          nist_building_type = 'MediumOffice'
        end
      when 'Retail'
        # map retal building type to RetailStripmall or RetailStandalone based on building name
        building_name = model.getBuilding.name.get
        if building_name.include? 'RetailStandalone'
          nist_building_type = 'RetailStandalone'
        else
          nist_building_type = 'RetailStripmall'
        end
      when 'RetailStripmall', 'StripMall', 'Warehouse', 'QuickServiceRestaurant', 'FullServiceRestaurant', 'RtS', 'RSD', 'RFF', 'SCn', 'SUn', 'WRf', 'Asm', 'MLI'
        nist_building_type = 'RetailStripmall'
      when 'RetailStandalone', 'SuperMarket', 'RtL', 'Rt3', 'Gro'
        nist_building_type = 'RetailStandalone'
      when 'PrimarySchool', 'EPr', 'ERC'
        nist_building_type = 'PrimarySchool'
      when 'SecondarySchool', 'ESe'
        nist_building_type = 'SecondarySchool'
      when 'SmallHotel', 'Mtl'
        nist_building_type = 'SmallHotel'
      when 'LargeHotel', 'Htl'
        nist_building_type = 'LargeHotel'
      when 'Hospital', 'Hsp', 'Nrs'
        nist_building_type = 'Hospital'
      when 'MidriseApartment', 'MFm'
        nist_building_type = 'MidriseApartment'
      when 'HighriseApartment'
        nist_building_type = 'HighriseApartment'
      when 'TallBuilding', 'SuperTallBuilding'
        nist_building_type = 'LargeHotel'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.nist_infiltration', "NIST coefficients aren't available for model building type #{model_building_type}. Since the building type is for a tall building, using nist building type #{nist_building_type} to best represent infiltration coefficients.")
      when 'College', 'Laboratory', 'EUn', 'ECC', 'MBT'
        nist_building_type = 'SecondarySchool'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.nist_infiltration', "NIST coefficients aren't available for model building type #{model_building_type}. Since the building may involve complex geometry, using nist building type #{nist_building_type} to best represent infiltration coefficients.")
      when 'Courthouse'
        nist_building_type = 'MediumOffice'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.nist_infiltration', "NIST coefficients aren't available for model building type #{model_building_type}. Using nist building type #{nist_building_type} to best represent infiltration coefficients.")
      else
        nist_building_type = model_building_type
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "Using building type #{nist_building_type} for model building type #{model_building_type}.")

      return nist_building_type
    end

    # This method applies infiltration to a model that varies with weather and HVAC operation, and takes into account building geometry (height, above-ground exterior surface area, and volume). It is based on work published by Ng et al. (2018) <a href='https://doi.org/10.1016/j.buildenv.2017.10.029'>'Weather correlations to calculate infiltration rates for U.S. commercial building energy models'</a> and Ng et al. (2021) <a href='https://doi.org/10.1016/j.buildenv.2021.107783'>'Evaluating potential benefits of air barriers in commercial buildings using NIST infiltration correlations in EnergyPlus'</a>. This method of calculating infiltration was developed using eleven of the DOE commercial prototype building models (<a href='https://www.energycodes.gov/development/commercial/prototype_models'>Goel et al. 2014</a>) and TMY3 weather files for eight climate zones (CZ). Guidance on implementing the infiltration correlations are explained in the NIST technical report <a href='https://doi.org/10.6028/NIST.TN.2221'>'Implementing NIST Infiltration Correlations'</a>. Ng et al. (2018) shows that when analyzing the benefits of building envelope airtightening, greater HVAC energy savings were predicted using the infiltration inputs included in this method compared with using the default inputs that are included in the prototype building models.
    # This method will remove any existing infiltration objects (OS:SpaceInfiltration:DesignFlowRate and OS:SpaceInfiltration:EffectiveLeakageArea). Every zone will then get two OS:SpaceInfiltration:DesignFlowRate objects that add infiltration using the 'Flow per Exterior Surface Area' input option, one infiltration object when the HVAC system is on and one object when the HVAC system is off. The method assumes that HVAC operation is set by a schedule, though it may not reflect actual simulation/operation when fan operation may depend on internal loads and temperature setpoints. By default, interior zones will receive no infiltration. The user may enter a design building envelope airtightness at a specific design pressure, and whether the design value represents a 4-sided, 5-sided, or 6-sided normalization.  By default, the method assumes an airtightness design value of 13.8 (m^3/h-m^2) at 75 Pa. The method assumes that infiltration is evenly distributed across the entire building envelope, including the roof. The user may select the HVAC system operating schedule in the model, or infer it based on the availability schedule of the air loop that serves the largest amount of floor area. The method will make a copy of the HVAC operating schedule, 'Infiltration HVAC On Schedule', which is used with the HVAC on infiltration correlations.  The method will also make an 'Infiltration HVAC Off Schedule' with inverse operation, used with the HVAC off infiltration correlations. OS:SpaceInfiltration:DesignFlowRate object coefficients (A, B, C, and D) come from Ng et al. (2018). The user may select the Building Type and Climate Zone, or the method will infer them from the model.
    # @author Matthew Dahlhausen <matthew.dahlhausen@nrel.gov>
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param airtightness_value [Double] Airtightness design value (m^3/h-m^2).
    #   The airtightness design value from a building pressurization test. Use 5.0 (m^3/h-m^2) as a default for buildings with air barriers. Convert (cfm/ft^2) to (m^3/h-m^2) by multiplying by 18.288 (m-min/ft-hr). (0.3048 m/ft)*(60 min/hr) = 18.288 (m-min/ft-hr).'
    # @param airtightness_pressure [Double] Airtightness design pressure (Pa).
    #   The corresponding pressure for the airtightness design value, typically 75 Pa for commercial buildings and 50 Pa for residential buildings.
    # @param airtightness_area_covered [String] Airtightness exterior surface area scope.
    #   Airtightness measurements are weighted by exterior surface area. 4-sided values divide infiltration by exterior wall area. 5-sided values additionally include roof area. 6-sided values additionally include floor and ground area.
    # @param air_barrier [Boolean] Does the building have an air barrier?
    #   Buildings with air barriers use a different set of coefficients.
    # @param hvac_schedule_name [String] HVAC Operating Schedule. Default will look up from model.
    # @param nist_building_type [String] NIST building type. If the building type is not available, pick the one with the most similar geometry and exhaust fan flow rates. Default will lookup from model.
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_nist_infiltration(model,
                                         airtightness_value: 13.8,
                                         airtightness_pressure: 75.0,
                                         airtightness_area_covered: '5-sided',
                                         air_barrier: false,
                                         hvac_schedule_name: nil,
                                         nist_building_type: nil)
      # validate airtightness value and pressure
      if airtightness_value < 0.0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', 'Airtightness value must be postive.')
        return false
      end

      if airtightness_pressure < 0.0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', 'Airtightness pressure must be postive.')
        return false
      end

      # calculate infiltration design value at 4 Pa
      airtightness_value_4pa_per_hr = airtightness_value * ((4.0 / airtightness_pressure)**0.65)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "User-inputed airtightness design value #{airtightness_value} (m^3/h-m^2) at #{airtightness_pressure} Pa converts to #{airtightness_value_4pa_per_hr.round(7)} (m^3/h-m^2) at 4 Pa")

      # convert to m^3/s-m^2
      airtightness_value_4pa_per_s = airtightness_value_4pa_per_hr / 3600.0

      # get 4-sided, 5-sided, and 6-sided areas
      exterior_wall_area = 0.0
      exterior_roof_area = 0.0
      exterior_floor_area = 0.0
      ground_wall_area = 0.0
      ground_roof_area = 0.0
      ground_floor_area = 0.0
      model.getSurfaces.each do |surface|
        bc = surface.outsideBoundaryCondition
        type = surface.surfaceType
        area = surface.grossArea
        exterior_wall_area += area if bc == 'Outdoors' && type == 'Wall'
        exterior_roof_area += area if bc == 'Outdoors' && type == 'RoofCeiling'
        exterior_floor_area += area if bc == 'Outdoors' && type == 'Floor'
        ground_wall_area += area if bc == 'Ground' && type == 'Wall'
        ground_roof_area += area if bc == 'Ground' && type == 'RoofCeiling'
        ground_floor_area += area if bc == 'Ground' && type == 'Floor'
      end
      four_sided_area = exterior_wall_area + ground_wall_area
      five_sided_area = exterior_wall_area + ground_wall_area + exterior_roof_area + ground_roof_area
      six_sided_area = exterior_wall_area + ground_wall_area + exterior_roof_area + ground_roof_area + exterior_floor_area + ground_floor_area
      energy_plus_area = exterior_wall_area + exterior_roof_area
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "4-sided area = #{four_sided_area.round(2)} m^2, 5-sided area = #{five_sided_area.round(2)} m^2, 6-sided area = #{six_sided_area.round(2)} m^2.")

      # The SpaceInfiltrationDesignFlowRate object FlowperExteriorSurfaceArea method only counts surfaces with the 'Outdoors' boundary conditions towards exterior surface area, not surfaces with the 'Ground' boundary conditions.  That means all values need to be normalized to exterior wall and roof area.
      case airtightness_area_covered
      when '4-sided'
        design_infiltration_4pa = airtightness_value_4pa_per_s * (four_sided_area / energy_plus_area)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "#{airtightness_area_covered} infiltration design value #{airtightness_value_4pa_per_s.round(7)} (m^3/s-m^2) converted to #{design_infiltration_4pa.round(7)} (m^3/s-m^2) based on 4-sided area #{four_sided_area.round(2)} m^2 and 5-sided area #{energy_plus_area.round(2)} m^2 excluding ground boundary surfaces for energyplus.")
      when '5-sided'
        design_infiltration_4pa = airtightness_value_4pa_per_s * (five_sided_area / energy_plus_area)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "#{airtightness_area_covered} infiltration design value #{airtightness_value_4pa_per_s.round(7)} (m^3/s-m^2) converted to #{design_infiltration_4pa.round(7)} (m^3/s-m^2) based on 5-sided area #{five_sided_area.round(2)} m^2 and 5-sided area #{energy_plus_area.round(2)} m^2 excluding ground boundary surfaces for energyplus.")
      when '6-sided'
        design_infiltration_4pa = airtightness_value_4pa_per_s * (six_sided_area / energy_plus_area)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "#{airtightness_area_covered} infiltration design value #{airtightness_value_4pa_per_s.round(7)} (m^3/s-m^2) converted to #{design_infiltration_4pa.round(7)} (m^3/s-m^2) based on 6-sided area #{six_sided_area.round(2)} m^2 and 5-sided area #{energy_plus_area.round(2)} m^2 excluding ground boundary surfaces for energyplus.")
      end

      # validate hvac schedule
      if hvac_schedule_name.nil?
        hvac_schedule = OpenstudioStandards::Schedules.model_get_hvac_schedule(model)
      else
        hvac_schedule = model.getScheduleByName(hvac_schedule_name)
        unless hvac_schedule.is_initialized
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "HVAC schedule argument #{hvac_schedule} not found in the model. It may have been removed by another measure.")
          return false
        end
        hvac_schedule = hvac_schedule.get
        if hvac_schedule.to_ScheduleRuleset.is_initialized
          hvac_schedule = hvac_schedule.to_ScheduleRuleset.get
        elsif hvac_schedule.to_ScheduleConstant.is_initialized
          hvac_schedule = hvac_schedule.to_ScheduleConstant.get
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "HVAC schedule argument #{hvac_schedule} is not a Schedule Constant or Schedule Ruleset object.")
          return false
        end

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "Using HVAC schedule #{hvac_schedule.name} from user arguments to determine infiltration on/off schedule.")
      end

      # creating infiltration schedules based on hvac schedule
      if hvac_schedule.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.nist_infiltration', 'Unable to determine the building HVAC schedule. Treating the building as if there is no HVAC system with outdoor air. This may be appropriate for design sizing, particularly heating design sizing. If this is not the case, input a schedule argument, or assign one to an air loop in the model.')
        on_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        on_schedule.setName('Infiltration HVAC On Schedule')
        on_schedule.setValue(0.0)
        off_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        off_schedule.setName('Infiltration HVAC Off Schedule')
        off_schedule.setValue(1.0)
      elsif hvac_schedule.to_ScheduleConstant.is_initialized
        hvac_schedule = hvac_schedule.to_ScheduleConstant.get
        on_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        on_schedule.setName('Infiltration HVAC On Schedule')
        on_schedule.setValue(hvac_schedule.value)
        off_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        off_schedule.setName('Infiltration HVAC Off Schedule')
        if hvac_schedule.value > 0
          off_schedule.setValue(0.0)
        else
          off_schedule.setValue(1.0)
        end
      elsif hvac_schedule.to_ScheduleRuleset.is_initialized
        hvac_schedule = hvac_schedule.to_ScheduleRuleset.get
        on_schedule = hvac_schedule.clone.to_ScheduleRuleset.get
        on_schedule.setName('Infiltration HVAC On Schedule')
        off_schedule = OpenstudioStandards::Schedules.create_inverted_schedule_ruleset(hvac_schedule, schedule_name: 'Infiltration HVAC Off Schedule')
      end

      # get climate zone number
      climate_zone_number = OpenstudioStandards::Weather.model_get_ashrae_climate_zone_number(model)

      # there is no data for climate zone 0, so use data for climate zone 1
      climate_zone_number = 1 if climate_zone_number == 0

      # get nist building type
      if nist_building_type.nil?
        nist_building_type = model_infer_nist_building_type(model)
      end

      # check that model building type is supported
      unless nist_building_types.include? nist_building_type
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "NIST coefficients are not available for model building type #{nist_building_type}.")
        return false
      end

      # remove existing infiltration objects
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "The modeled started with #{model.getSpaceInfiltrationDesignFlowRates.size} infiltration objects and #{model.getSpaceInfiltrationEffectiveLeakageAreas.size} effective leakage area objects.")
      model.getSpaceInfiltrationDesignFlowRates.each(&:remove)
      model.getSpaceInfiltrationEffectiveLeakageAreas.each(&:remove)

      # load NIST infiltration correlations file and convert to hash table
      nist_infiltration_correlations_json = "#{File.dirname(__FILE__)}/data/NISTInfiltrationCorrelations.json"
      unless File.file?(nist_infiltration_correlations_json)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "Unable to find file: #{nist_infiltration_correlations_json}")
        return false
      end
      coefficients_hsh = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/NISTInfiltrationCorrelations.json"), symbolize_names: true)
      coefficients_hsh = coefficients_hsh[:infiltration]

      # select down to building type and climate zone
      coefficients = coefficients_hsh.select { |r| (r[:building_type] == nist_building_type) && (r[:climate_zone].to_i == climate_zone_number) }

      # filter by air barrier
      if air_barrier
        coefficients = coefficients.select { |r| r[:air_barrier] == 'yes' }
      else
        coefficients = coefficients.select { |r| r[:air_barrier] == 'no' }
      end

      # determine coefficients
      # if no off coefficients are defined, use 0 for a and the on coefficients for b and d
      on_coefficients = coefficients.select { |r| r[:hvac_status] == 'on' }[0]
      off_coefficients = coefficients.select { |r| r[:hvac_status] == 'off' }[0]
      a_on = on_coefficients[:a]
      b_on = on_coefficients[:b]
      d_on = on_coefficients[:d]
      a_off = off_coefficients[:a].nil? ? on_coefficients[:a] : off_coefficients[:a]
      b_off = off_coefficients[:b].nil? ? on_coefficients[:b] : off_coefficients[:b]
      d_off = off_coefficients[:d].nil? ? on_coefficients[:d] : off_coefficients[:d]

      # add new infiltration objects
      # define infiltration as flow per exterior area
      model.getSpaces.each do |space|
        next unless space.exteriorArea > 0.0

        hvac_on_infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        hvac_on_infiltration.setName("#{space.name.get} HVAC On Infiltration")
        hvac_on_infiltration.setFlowperExteriorSurfaceArea(design_infiltration_4pa)
        hvac_on_infiltration.setConstantTermCoefficient(a_on)
        hvac_on_infiltration.setTemperatureTermCoefficient(b_on)
        hvac_on_infiltration.setVelocityTermCoefficient(0.0)
        hvac_on_infiltration.setVelocitySquaredTermCoefficient(d_on)
        hvac_on_infiltration.setSpace(space)
        hvac_on_infiltration.setSchedule(on_schedule)

        hvac_off_infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        hvac_off_infiltration.setName("#{space.name.get} HVAC Off Infiltration")
        hvac_off_infiltration.setFlowperExteriorSurfaceArea(design_infiltration_4pa)
        hvac_off_infiltration.setConstantTermCoefficient(a_off)
        hvac_off_infiltration.setTemperatureTermCoefficient(b_off)
        hvac_off_infiltration.setVelocityTermCoefficient(0.0)
        hvac_off_infiltration.setVelocitySquaredTermCoefficient(d_off)
        hvac_off_infiltration.setSpace(space)
        hvac_off_infiltration.setSchedule(off_schedule)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "The modeled finished with #{model.getSpaceInfiltrationDesignFlowRates.size} infiltration objects.")

      return true
    end

    # Loops through SpaceInfiltrationDesignFlowRate objects and adjusts the infiltration schedules to account building HVAC operation
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param hvac_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Default will look up from model.
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_nist_infiltration_schedules(model, hvac_schedule: nil)
      # delete existing schedules if present
      on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule')
      on_schedule.get.remove if on_schedule.is_initialized
      off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule')
      off_schedule.get.remove if off_schedule.is_initialized

      # validate hvac schedule
      if hvac_schedule.nil?
        hvac_schedule = OpenstudioStandards::Schedules.model_get_hvac_schedule(model)
      else
        unless hvac_schedule.to_Schedule.is_initialized
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "HVAC schedule argument #{hvac_schedule} not found in the model or is not a Schedule object. It may have been removed by another measure.")
          return false
        end
        hvac_schedule = hvac_schedule.to_Schedule.get
        if hvac_schedule.to_ScheduleRuleset.is_initialized
          hvac_schedule = hvac_schedule.to_ScheduleRuleset.get
        elsif hvac_schedule.to_ScheduleConstant.is_initialized
          hvac_schedule = hvac_schedule.to_ScheduleConstant.get
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Infiltration.nist_infiltration', "HVAC schedule argument #{hvac_schedule} is not a Schedule Constant or Schedule Ruleset object.")
          return false
        end

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.nist_infiltration', "Using HVAC schedule #{hvac_schedule.name} from user arguments to determine infiltration on/off schedule.")
      end

      # creating infiltration schedules based on hvac schedule
      if hvac_schedule.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.nist_infiltration', 'Unable to determine the HVAC schedule. Treating the building as if there is no HVAC system with outdoor air.  If this is not the case, input a schedule argument, or assign one to an air loop in the model.')
        on_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        on_schedule.setName('Infiltration HVAC On Schedule')
        on_schedule.setValue(0.0)
        off_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        off_schedule.setName('Infiltration HVAC Off Schedule')
        off_schedule.setValue(1.0)
      elsif hvac_schedule.to_ScheduleConstant.is_initialized
        hvac_schedule = hvac_schedule.to_ScheduleConstant.get
        on_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        on_schedule.setName('Infiltration HVAC On Schedule')
        on_schedule.setValue(hvac_schedule.value)
        off_schedule = OpenStudio::Model::ScheduleConstant.new(model)
        off_schedule.setName('Infiltration HVAC Off Schedule')
        if hvac_schedule.value > 0
          off_schedule.setValue(0.0)
        else
          off_schedule.setValue(1.0)
        end
      elsif hvac_schedule.to_ScheduleRuleset.is_initialized
        hvac_schedule = hvac_schedule.to_ScheduleRuleset.get
        on_schedule = hvac_schedule.clone.to_ScheduleRuleset.get
        on_schedule.setName('Infiltration HVAC On Schedule')
        off_schedule = OpenstudioStandards::Schedules.create_inverted_schedule_ruleset(hvac_schedule, schedule_name: 'Infiltration HVAC Off Schedule')
      end


      model.getSpaceInfiltrationDesignFlowRates.each do |infil|
        if infil.name.get.include?('HVAC On Infiltration')
          infil.setSchedule(on_schedule)
        end

        if infil.name.get.include?('HVAC Off Infiltration')
          infil.setSchedule(off_schedule)
        end
      end

      return true
    end

    # @!endgroup NIST Infiltration
  end
end
