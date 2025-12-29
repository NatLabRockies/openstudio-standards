
# This module defines checks that test various aspects
# of the baseline model against 90.1-2013 Appendix G.
module Baseline9012013

  # G3.1.2.7 Economizers. Outdoor air economizers shall not be included in baseline HVAC Systems 1, 2, 9, and 10.
  # Outdoor air economizers shall be included in baseline HVAC Systems 3 through 8, and 11, 12, and 13 based on climate as
  # specified in Table G3.1.2.7.
  # Exceptions: Economizers shall not be included for systems meeting one or more of the exceptions listed below.
  # 1. Systems that include gas-phase air cleaning to meet the requirements of Section 6.1.2 in Standard 62.1.
  # This exception shall be used only if the system in the proposed design does not match thebuilding design.
  # 2. Where the use of outdoor air for cooling will affect supermarket open refrigerated casework systems.
  # This exception shall only be used if the system in the proposed design does not use an economizer.
  # If the exception is used, an economizer shall not be included in the baseline building design.
  # 3. Systems that serve computer rooms complying with Section G3.1.2.7.1.
  # @author Eric Ringold, Ambient Energy
  def check_economizers(model)

    econ_bad = []
    econ_limit_bad = []
    economizer_required = false
    high_limit = nil
    model.getAirLoopHVACs.each do |sys|

      # get systems 3 and 5 in the baseline model
      if sys.name.get.include?('PSZ-AC') || sys.name.get.include?('(Sys5)')
        economizer_required = true
        # models are all zone 5b
        high_limit = 75 #F
        oa_sys = sys.airLoopHVACOutdoorAirSystem
        if !oa_sys.empty?
          oa_sys = oa_sys.get
        end
        oa_control = oa_sys.getControllerOutdoorAir
        # check economizer control setting
        unless oa_control.getEconomizerControlType == "FixedDryBulb"
          econ_bad << "#{sys.name.get} econ type was #{oa_control.getEconomizerControlType}"
        end

        # get economiser db high limit and check if correct
        drybulb_limit_c = oa_control.getEconomizerMaximumLimitDryBulbTemperature
        if drybulb_limit_c.is_initialized
          drybulb_limit_c = drybulb_limit_c.get
        end
        drybulb_limit_f = OpenStudio.convert(drybulb_limit_c,"C","F").get

        if (drybulb_limit_f - high_limit).abs > 0.1
          econ_limit_bad << "#{sys.name.get} high limit was #{drybulb_limit_f}F."
        end
      end
    end
    assert_equal(econ_bad.size, 0, "Systems #{econ_bad.sort.join("\n")} required to have dry-bulb economizer, but do not.")
    assert_equal(econ_limit_bad.size, 0, "Systems #{econ_limit_bad.sort.join("\n")} required to have economizer high-limit of #{high_limit}, but do not.")

    return true

  end

  # G3.1.2.9.1 Baseline All System Types Except System Types 9 and 10.
  # System design supply airflow rates for the baseline building design shall be based on a supply-air-to room-air
  # temperature difference of 20°F or the minimum outdoor airflow rate, or the airflow rate required to comply with
  # applicable codes or accreditation standards, whichever is greater. If return or relief fans are specified in the
  # proposed design, the baseline building design shall also be modeled with fans serving the same functions and sized
  # for the baseline system supply fan air quantity less the minimum outdoorair, or 90% of the supply fan air quantity, whichever is larger.
  # @author Eric Ringold, Ambient Energy
  def check_sat_delta(model)

    delta_good = []
    cool_delta_bad = []
    heat_delta_bad = []

    model.getThermalZones.each do |zone|
      # get zone thermostats
      tstat = zone.thermostatSetpointDualSetpoint
      if !tstat.empty?
        tstat = tstat.get

        heating_sch = tstat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        cooling_sch = tstat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get

        # get heating and cooling setpoints
        heating_min_max = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(heating_sch)
        cooling_min_max = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(cooling_sch)

        heat_set_t = OpenStudio.convert(heating_min_max['max'],"C","F").get
        cool_set_t = OpenStudio.convert(cooling_min_max['min'],"C","F").get

        # don't check zones where the heating or cooling setpoints
        # are such that the heating or cooling equipment never runs
        next if heat_set_t < 41
        next if cool_set_t > 91

        # get sizing:zone supply air temperatures
        cool_sizing = zone.sizingZone.zoneCoolingDesignSupplyAirTemperature
        heat_sizing = zone.sizingZone.zoneHeatingDesignSupplyAirTemperature

        cool_sizing_f = OpenStudio.convert(cool_sizing,"C","F").get
        heat_sizing_f = OpenStudio.convert(heat_sizing,"C","F").get

        # calculate temperature deltas and put zone names in arrays
        cool_delta = (cool_set_t - cool_sizing_f).round
        if (cool_delta - 20).abs > 0.1
          cool_delta_bad << "#{zone.name} Clg delta =#{cool_delta}"
        end

        heat_delta = (heat_sizing_f - heat_set_t).round
        if (heat_delta - 20).abs > 0.1
          heat_delta_bad << "#{zone.name} Htg delta =#{heat_delta}"
        end
      end
    end
    assert_equal(cool_delta_bad.size, 0, "Cooling supply air to room air temperature difference is not 20F for zones #{cool_delta_bad.sort.join("\n")}.")
    assert_equal(heat_delta_bad.size, 0, "Heating supply air to room air temperature difference is not 20F for zones #{heat_delta_bad.sort.join("\n")}.")

    return true

  end

  # G3.1.3.12 Supply Air Temperature Reset (Systems 5 through 8).
  # The air temperature for cooling shall be reset higher by 5°F under the minimum cooling load conditions.
  # @author Eric Ringold, Ambient Energy
  def check_sat_reset(model)

    no_reset = []
    reset_bad = []
    model.getAirLoopHVACs.each do |sys|
      if sys.name.get.include?('(Sys5)') # checking system 5
        supp_node = sys.supplyOutletNode
        supp_node.setpointManagers.each do |spm|
          if spm.to_SetpointManagerWarmest.is_initialized
            spm = spm.to_SetpointManagerWarmest.get
            low_temp = OpenStudio.convert(spm.minimumSetpointTemperature,"C","F").get
            high_temp = OpenStudio.convert(spm.maximumSetpointTemperature ,"C","F").get

            # check if reset is correct
            delta = high_temp - low_temp
            if (delta - 5.0).abs > 0.1
              reset_bad << "#{sys.name} reset = #{delta} delta-F"
            end
          else # no SetpointManager:Warmest
            no_reset << sys.name.get
          end
        end #supp_node.each


      end #if sys.name.get
    end #model.get

    assert_equal(no_reset.size,0,"Supply Air Temperature not reset for systems #{no_reset.sort.join("\n")}.")
    assert_equal(reset_bad.size,0,"Supply Air Temperature is reset, but not by the required 5 degrees F for systems: #{reset_bad.sort.join("\n")}.")

    return true

  end

  # G3.1.3.13 VAV Minimum Flow Setpoints (Systems 5 and 7). Minimum volume setpoints for VAV reheat boxes shall be 30%
  # of zone peak airflow, the minimum outdoor airflow rate or the airflow rate required to comply with applicable codes
  # or accreditation standards, whichever is larger.
  # @author Eric Ringold, Ambient Energy
  def check_min_vav_setpoints(model)
    min_good = []
    min_bad = []
    vent_driven = []
    oa_driven = []
    fixed_min_driven = []
    model.getAirLoopHVACs.sort.each do |sys|
      # get only systems 5 and 7
      if sys.name.get.include?('(Sys5)') || sys.name.get.include?('(Sys7)')

        sys.thermalZones.sort.each do |zone|
          terminal = nil
          zone.equipment.each do |equip|
            next if equip.to_AirTerminalSingleDuctVAVReheat.empty?
            terminal = equip.to_AirTerminalSingleDuctVAVReheat.get
          end
          # get terminal design flow rate
          des_flow = terminal.autosizedMaximumAirFlowRate
          if des_flow.is_initialized
            des_flow = des_flow.get
          else puts "CANT GET TERMINAL DESIGN FLOW"
          end

          #get outdoor air rate from DSOA
          min_oa_flow = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)

          # larger of fixed 20% fraction and fraction based
          # on minimum OA requirement
          expected_fixed_min_frac = 0.3
          expected_oa_min_frac = min_oa_flow/des_flow
          expected_min_frac = [expected_fixed_min_frac, expected_oa_min_frac].max

          # minimum fraction, which is the greater
          # of the min fraction or the min fixed value converted to a fraction.
          act_fixed_min_frac = terminal.constantMinimumAirFlowFraction.get
          act_oa_min_frac = 0.0
          act_min_flow = terminal.fixedMinimumAirFlowRate
          if act_min_flow.is_initialized
            act_min_flow = act_min_flow.get
          else
            act_min_flow = 0.0
          end
          if act_min_flow > 0.0
            act_oa_min_frac = act_min_flow/des_flow
          end
          act_min_frac = [act_fixed_min_frac, act_oa_min_frac].max

          # If expected min OA frac is higher than the fixed minimum, check that
          if act_fixed_min_frac > expected_min_frac
            vent_driven << "#{zone.name} #{act_fixed_min_frac.round(2)} > #{expected_min_frac.round(2)}"
          elsif expected_oa_min_frac > expected_fixed_min_frac
            oa_driven << "#{zone.name} #{expected_oa_min_frac.round(2)} == #{act_oa_min_frac.round(2)}"
            unless (expected_oa_min_frac - act_oa_min_frac).abs < 0.01
              min_bad << "#{zone.name} min VAV is OA driven, but OA min flow #{expected_oa_min_frac.round(2)} != #{act_oa_min_frac.round(2)}"
            end
          else
            fixed_min_driven << "#{zone.name} #{expected_fixed_min_frac.round(2)} == #{act_fixed_min_frac.round(2)}"
            unless (expected_fixed_min_frac - act_fixed_min_frac).abs < 0.01
             min_bad << "#{zone.name} min VAV is OA driven, but fixed minimum fraction #{expected_fixed_min_frac.round(2)} != #{act_fixed_min_frac.round(2)}"
            end
          end

        end
      end
    end #model.getAirLoopHVACs

    puts "******** VAV Minimum Drivers ******"
    puts ""

    puts "*** Ventilation Effectiveness Driven ***"
    puts vent_driven
    puts ""

    puts "*** Min OA Driven ***"
    puts oa_driven
    puts ""

    puts "*** Fixed Minimum Driven ***"
    puts fixed_min_driven
    puts ""

    assert_equal(min_bad.size,0,"The following zones' terminal units do not meet the minimum flow criteria of 30% or minimum outdoor airflow rate: #{min_bad.sort.join("\n")}. They may still may meet the requirement if applicable codes or standards require additional airflow.")

    return true

  end

  # G3.1.2.1 Equipment Efficiencies.
  # All HVAC equipment in the baseline building design shall be modeled at the minimum efficiency levels, both part load and full load,
  # in accordance with Section 6.4. Chillers shall use Path A efficiencies as shown in Table 6.8.1-3 where efficiency ratings include supply fan energy,
  # the efficiency rating shall be adjusted toremove the supply fan energy. For Baseline HVAC Systems 1,2, 3, 4, 5, and 6, calculate the minimum COP_nfcooling
  # and COP_nfheating using the equation for the applicable performance rating as indicated in Tables 6.8.1-1 through 6.8.1-4.
  # Where a full- and part-load efficiency rating is provided in Tables 6.8.1-1 through 6.8.1-4, the full-load equation below shall be used:
  # COP_nfcooling = 7.84E-8 × EER × Q + 0.338 × EER
  # COP_nfcooling = –0.0076 × SEER^2 + 0.3796 × SEER
  # COP_nfheating = 1.48E-7 × COP_47 × Q + 1.062 × COP_47 (applies to heat-pump heating efficiency only)
  # COP_nfheating = –0.0296 × HSPF2 + 0.7134 × HSPF
  # where COP_nfcooling and COP_nfheating are the packaged HVAC equipment cooling and heating energy efficiency, respectively, to be used in the baseline building,
  # which excludes supply fan power, and Q is the AHRI-rated cooling capacity in Btu/h. EER, SEER, COP, and HSPF shall be at AHRI test conditions.
  # Fan energy shall be modeled separately according to Section G3.1.2.10.
  # @author Eric Ringold, Ambient Energy
  def check_coil_efficiencies(model)

    # Cooling efficiency tables:
    # Systems 1 & 2: Table 6.8.1D (6.8.1-4 in 2013)
    # Systems 3, 5, & 6: Table 6.8.1A (6.8.1-1 in 2013)
    # System 4: Table 6.8.1B (6.8.1-2 in 2013)
    # Systems 7-10: N/A

    # Heating efficiency tables:
    # System 2: Table 6.8.1D
    # Systems 3 & 9: Table 6.8.1E
    # System 4: Table 6.8.1B
    # Systems 1, 5-8, 10: N/A

    #conversions
    si_cap = "W"
    ip_cap = "Btu/h"

    #arrays to put same or different values in
    eff_same = []
    eff_diff = []

    #currently only gets coils associated with air loops
    # @todo cover zone system coils
    model.getAirLoopHVACs.sort.each do |lp|
      coil = lp.supplyComponents.each do |comp|
        size = nil
        if !comp.to_CoilCoolingDXTwoSpeed.empty?
          # we have a System 5 or 6
          # system 6 not being created yet
          # @todo add logic to check for heating coil type, changes standard efficiencies
          coil = comp.to_CoilCoolingDXTwoSpeed.get
          name = coil.name.get

          # get assigned coil COP
          coil_cop = coil.ratedHighSpeedCOP.to_f

          # get coil capacity for EER calculation
          if coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
            size = coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
          else
            eff_diff << "#{coil.name} capacity couldn't be found"
            next
          end
          size = OpenStudio.convert(size,si_cap,ip_cap).get

        elsif !comp.to_CoilCoolingDXSingleSpeed.empty?
          # System 3 or system 4
          # @todo refine system type by heating coil - system 4 efficiencies come from different table
          coil = comp.to_CoilCoolingDXSingleSpeed.get
          name = coil.name.get

          # get assigned coil COP
          coil_cop = coil.ratedCOP.to_f

          # get coil capacity for EER calculation
          if coil.autosizedRatedTotalCoolingCapacity.is_initialized
            size = coil.autosizedRatedTotalCoolingCapacity.get
          else
            eff_diff << "#{coil.name} capacity couldn't be found"
            next
          end
          size = OpenStudio.convert(size,si_cap,ip_cap).get
        end

        unless size.nil?

          seer = nil
          eer = nil
          cop = nil
          # tests against 90.1-2013 efficiencies
          if size < 65000
            seer = 14.0
            # Per PNNL, convert SEER to COP with fan
            cop = -0.0076 * seer * seer + 0.3796 * seer
          elsif size >= 65000 && size < 135000
            eer = 11.0
            cop = (eer / OpenStudio.convert(1.0,'W','Btu/h').get + 0.12) / (1 - 0.12)
          elsif size >= 135000 && size < 240000
            eer = 10.8
            # Per PNNL, covert EER to COP using a capacity-agnostic formula
            cop = (eer / OpenStudio.convert(1.0,'W','Btu/h').get + 0.12) / (1 - 0.12)
          elsif size >= 240000 && size < 760000
            eer = 9.8
            # Per PNNL, covert EER to COP using a capacity-agnostic formula
            cop = (eer / OpenStudio.convert(1.0,'W','Btu/h').get + 0.12) / (1 - 0.12)
          else # size >= 760000
            eer = 9.5
            # Per PNNL, covert EER to COP using a capacity-agnostic formula
            cop = (eer / OpenStudio.convert(1.0,'W','Btu/h').get + 0.12) / (1 - 0.12)
          end

          if (coil_cop - cop).abs >= 0.1
            eff_diff << "#{name}, capacity = #{size.round} Btu/hr, expected COP = #{cop.round(2)}, was #{coil_cop.round(2)}"
          else
            eff_same << name
          end

        end #unless size.nil
      end
    end
    assert_equal(eff_diff.size, 0, "Coils #{eff_diff.sort.join("\n")} found with efficiencies that differ from standard-calculated values")

    return true

  end

  # G3.1.2.6 Ventilation.
  # Minimum ventilation system outdoor air intake flow shall be the same for the proposed and baseline building designs.
  # Exceptions:
  # 1. When modeling demand-control ventilation in the proposed design when its use is not required by Section 6.3.2(q) or Section 6.4.3.10.
  # 2. When designing systems in accordance with Standard 62.1, Section 6.2, “Ventilation Rate Procedure,” reduced ventilation airflow rates may be
  # calculated for each HVAC zone in the proposed design with a zone air distribution effectiveness (Ez) > 1.0 as defined by Table 6-2in Standard 62.1.
  # Baseline ventilation airflow rates in those zones shall be calculated using the proposed design Ventilation Rate Procedure calculation with the
  # following change only. Zone air distribution effectiveness shall be changed to (Ez)= 1.0 in each zone having a zone air distributioneffectiveness (Ez) > 1.0.
  # Proposed design and baseline design Ventilation Rate Procedure calculations, as described in Standard 62.1, shall be submitted to the rating authority
  # to claim credit for this exception.
  # 3. If the minimum outdoor air intake flow in the proposed design is provided in excess of the amount required by the rating authority or building official
  # then the baseline building design shall be modeled to reflect the greater of that required by the rating authority or building official and will be less
  # than the proposed design.
  # 4. For baseline systems serving only laboratory spaces that are prohibited from recirculating return air by code or accreditation standards, the baseline system
  # shall be modeled as 100% outdoor air.
  # @author Eric Ringold, Ambient Energy
  def check_ventilation_rates(model, proposed_model)
    standard = Standard.build('90.1-2013')
    # get proposed ventilation from designSpecificationOutdoorAir
    zone_oa = {}
    proposed_model.getThermalZones.sort.each do |zone|
      oa_rate = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
      zone_oa["#{zone.name.get}"] = oa_rate
    end

    zones_same = []
    zones_dif = []

    zone_oa.each do |k,v|
      # get baseline ventilation rates
      bzone = model.getThermalZoneByName(k.to_s)
      if bzone.is_initialized
        bzone = bzone.get
        #puts bzone.name
        oa_rate = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(bzone)
        # compare baseline and proposed rates
        if (oa_rate - zone_oa[k]).abs <= 0.0001
          #puts "#{bzone.name} MEETS Requirement with Prop OA: #{zone_oa[k]}, Base OA: #{oa_rate}"
          zones_same << bzone.name.get
        else
          puts "#{bzone.name} FAILS Requirement with Prop OA: #{zone_oa[k]}, Base OA: #{oa_rate}"
          zones_dif << bzone.name.get
        end
      else puts "can't find #{k}"
      end
    end

    assert_equal(zones_dif.size, 0, "Zones #{zones_dif.sort} found with differing OA rates")

  end

  # @author Matt Steen, Ambient Energy
  def check_baseline_system_type(base_model, prop_model, building_type, climate_zone)

    prm_maj_sec = 'G3.1.1 Baseline HVAC System Type'

    # get model objects
    climate_zone = climate_zone.gsub('ASHRAE 169-2013-', '')
    model_area_si = prop_model.getBuilding.floorArea
    model_area_ip = OpenStudio.convert(model_area_si, 'm^2', 'ft^2').get
    building_storys = prop_model.getBuildingStorys.size
    base_zones = base_model.getThermalZones

    climate_zones_1to3a = ['1A', '1B', '2A', '2B', '3A']
    climate_zones_3bto8 = ['3B', '3C', '4A', '4B', '4C', '5A', '5B', '5C', '6A', '6B', '7A', '7B', '8A', '8B']

    # puts "AREA = #{model_area_ip}"
    # puts "STORYS = #{building_storys}"
    # puts "CZ = #{climate_zone}"
    # #array.any? { |item| string.include?(item) }

    # determine expected baseline system type
    if climate_zones_3bto8.include?(climate_zone)

      if building_type == 'MidriseApartment'
        correct_sys_type = 'PTAC' #building_type_prm = 'Residential'
      # 5. Public assembly building types include
      # houses of worship, auditoriums, movie theaters, performance theaters,
      # concert halls, arenas, enclosed stadiums, ice rinks, gymnasiums,
      # convention centers, exhibition centers, and natatoriums.
      # elsif (building_type == 'PublicAssembly' && model_area_ip < 120000)
      #   correct_sys_type = 'PSZ_AC'
      # @todo add boolean for this PRM building type since not included in prototypes
      # elsif (building_type == 'PublicAssembly' && model_area_ip >= 120000)
      #   correct_sys_type = 'SZ_CV_HW'
      # @todo
      elsif (building_storys <= 3 && model_area_ip < 25000)
        correct_sys_type = 'PSZ_AC'
      elsif ( (building_storys = 4 || building_storys = 5) && model_area_ip < 25000 )
        correct_sys_type = 'PVAV_Reheat'
      elsif ( building_storys <= 5 && (model_area_ip >= 25000 && model_area_ip <= 150000) )
        correct_sys_type = 'PVAV_Reheat'
      elsif (building_storys >= 5 || model_area_ip > 150000)
        correct_sys_type = 'VAV_Reheat'
      else
        puts "#{prm_maj_sec}: baseline system could not be determined"
      end

    elsif climate_zones_1to3a.include?(climate_zone)

      if building_type == 'MidriseApartment'
        correct_sys_type = 'PTHP' #building_type_prm = 'Residential'
      # 5. Public assembly building types include
      # houses of worship, auditoriums, movie theaters, performance theaters,
      # concert halls, arenas, enclosed stadiums, ice rinks, gymnasiums,
      # convention centers, exhibition centers, and natatoriums.
      # elsif building_type == 'PublicAssembly' && model_area_ip < 120000
      #   correct_sys_type = 'PSZ_HP'
      # @todo add boolean for this PRM building type since not included in prototypes
      # elsif building_type == 'PublicAssembly' && model_area_ip >= 120000
      #   correct_sys_type =
      # @todo
      elsif building_storys <= 3 && model_area_ip < 25000
        correct_sys_type = 'PSZ_HP'
      elsif (building_storys = 4 || building_storys = 5) && model_area_ip < 25000
        correct_sys_type = 'PVAV_PFP_Boxes'
      elsif building_storys <= 5 && (model_area_ip >= 25000 && model_area_ip <= 150000)
        correct_sys_type = 'PVAV_PFP_Boxes'
      elsif building_storys >= 5 && model_area_ip > 150000
        correct_sys_type = 'VAV_PFP_Boxes'
      else
        puts "#{prm_maj_sec}: baseline system could not be determined"
      end

    else

      puts 'CLIMATE ZONE NOT FOUND'

    end

    # determine actual baseline system type
    zone_eqpt = []

    base_zones.each do |z|

      unless OpenStudio.convert(z.floorArea, 'm^2', 'ft^2').get > 20000

        z.equipment.each do |ze|
          obj_type = ze.iddObjectType.valueName
          obj_type_name = obj_type.gsub('OS_','').gsub('_','').strip
          # Don't count exhaust fans
          next if obj_type_name == 'FanZoneExhaust'
          zone_eqpt << obj_type_name
        end

      end

    end

    # determine the most frequent zone equipment
    base_model_primary_system = zone_eqpt.max_by { |i| zone_eqpt.count(i) }

    # check baseline cooling type
    if base_model.getChillerElectricEIRs.size > 0
      clg_type = 'CHW'
    else
      clg_type = 'DX'
    end

    # check baseline heating type
    if base_model.getBoilerHotWaters.size > 0
      htg_type = 'HW'
    else
      htg_type = 'Electric'
    end

    # determine the actual system type
    actual_sys_type = nil
    case base_model_primary_system
    when 'ZoneHVACPackagedTerminalAirConditioner'
      actual_sys_type =  'PTAC' #sys1
    when 'ZoneHVACPackagedTerminalHeatPump'
      actual_sys_type =  'PTHP' #sys2
    when 'AirTerminalSingleDuctUncontrolled'
      if clg_type == 'DX' && htg_type == 'HW'
        actual_sys_type =  'PSZ_AC' #sys 3
      elsif clg_type == 'DX' && htg_type == 'Electric'
        actual_sys_type =  'PSZ_HP' #sys 4
      end
    when 'AirTerminalSingleDuctVAVReheat'
      if clg_type == 'DX' && htg_type == 'HW'
        actual_sys_type =  'PVAV_Reheat' #sys 5
      elsif clg_type == 'DX' && htg_type == 'Electric'
        actual_sys_type =  'PVAV_PFP_Boxes' #sys 6
      elsif clg_type == 'CHW' && htg_type == 'HW'
        actual_sys_type = 'VAV_Reheat' #sys 7
      elsif clg_type == 'CHW' && htg_type == 'Electric'
        actual_sys_type = 'VAV_PFP_Boxes'
      end
    else
      puts "Unrecognized base_model_primary_system: '#{base_model_primary_system}'"
    end

    # Compare the correct type to the actual type
    assert_equal(correct_sys_type, actual_sys_type, "#{prm_maj_sec}: primary baseline system type incorrect")

  end

  # @author Matt Steen, Ambient Energy
  def check_purchased_energy(base_model, prop_model)

    prm_maj_sec = 'G3.1.1 Baseline HVAC System Type'

    # get model objects, could use zone.heatinFuelTypes or zone.appGHeatingFuelTypes
    if prop_model.version < OpenStudio::VersionString.new('3.7.0')
      prop_dist_htgs = prop_model.getDistrictHeatings
    else
      prop_dist_htgs = prop_model.getDistrictHeatingWaters
    end
    prop_dist_clgs = prop_model.getDistrictCoolings
    if prop_model.version < OpenStudio::VersionString.new('3.7.0')
      base_dist_htgs = base_model.getDistrictHeatings
    else
      base_dist_htgs = base_model.getDistrictHeatingWaters
    end
    base_dist_clgs = base_model.getDistrictCoolings

    # tests

    if prop_dist_htgs.size > 0 && prop_dist_clgs.size > 0

      assert(base_dist_clgs.size >= 1 && base_dist_htgs.size >= 1, "#{prm_maj_sec}: baseline model missing district cooling and heating.")

    elsif prop_dist_htgs.size > 0

      assert(base_dist_htgs.size >= 1, "#{prm_maj_sec}: baseline model missing district heating.")

    elsif prop_dist_clgs.size > 0

      assert(base_dist_clgs.size >= 1, "#{prm_maj_sec}: baseline model missing district cooling.")

    else

      puts 'NA: Test Purchased Energy'

    end

  end

  # @author Matt Steen, Ambient Energy
  def check_num_boilers(base_model, prop_model)

    prm_maj_sec = 'G3.1.3 System-Specific Baseline HVAC System Requirements'

    # get model objects
    model_area_si = prop_model.getBuilding.floorArea
    model_area_ip = OpenStudio.convert(model_area_si, 'm^2', 'ft^2').get
    boilers = base_model.getBoilerHotWaters
    boiler_num = boilers.size

    unless boiler_num == 0

      if model_area_ip <= 15000

        assert(boiler_num = 1, "#{prm_maj_sec}")

      elsif model_area_ip > 15000

        assert(boiler_num = 2, "#{prm_maj_sec}")

        sizing = []

        boilers.each do |b|

          autosized = b.isNominalCapacityAutosized()
          case autosized
          when true
            sizing << autosized
          when false
            size = b.nominalCapacity.get
            sizing << size
          end

        end

        assert_equal(sizing[0], sizing[1], "#{prm_maj_sec}")

      end

    end

  end

  # @author Matt Steen, Ambient Energy
  def check_num_chillers(base_model, prop_model)

    prm_maj_sec = 'G3.1.3 System-Specific Baseline HVAC System Requirements'

    # get model objects
    chillers = base_model.getChillerElectricEIRs

    model_area_si = prop_model.getBuilding.floorArea
    model_area_ip = OpenStudio.convert(model_area_si, 'm^2', 'ft^2').get
    chiller_num = chillers.size

    # get baseline peak cooling laod
    base_peak_clg_si = '' # @todo get from sql
    base_peak_clg_ip = 200 # OpenStudio.convert(base_peak_clg_si, 'W', 'tons').get

    chiller_cap = []

    unless chiller_num == 0

      if base_peak_clg_ip <= 300
        assert_equal(1, chiller_num, "#{prm_maj_sec}: number of chillers")
      elsif base_peak_clg_ip > 300 && base_peak_clg_ip < 600
        assert_equal(2, chiller_num, "#{prm_maj_sec}: number of chillers")
      elsif base_peak_clg_ip >= 600
        assert(chiller_num >= 2, "#{prm_maj_sec}: number of chillers")
        chillers.each do |c|
          # @todo get size

        end
      end

    end

  end

  # @author Matt Steen, Ambient Energy
  def check_plant_controls(base_model, prop_model)
    standard = Standard.build('90.1-2013')
    prm_maj_sec = 'G3.1.3 System-Specific Baseline HVAC System Requirements'

    # get model objects
    base_plant_loops = base_model.getPlantLoops
    des_days = base_model.getDesignDays

    # tests
    if base_plant_loops.size > 0

      base_plant_loops.each do |pl|

        # get plant components
        sizing_plant = pl.sizingPlant
        loop_type = sizing_plant.loopType
        supply_outlet_node = pl.supplyOutletNode
        setpoint_managers = supply_outlet_node.setpointManagers

        # set assert delta to account for unit conversions
        delta = 0.1

        case loop_type
        when 'Heating'
          # Don't check Service Water Heating loops
          next if OpenstudioStandards::HVAC.plant_loop_swh_loop?(pl)

          # G3.1.3.3 Hot-Water Supply Temperature (Systems 1, 5, 7, and 12)
          prm_min_sec = 'Hot-Water Supply Temperature'
          assert_msg = "#{prm_maj_sec}: #{prm_min_sec}"

          des_temp = OpenStudio.convert(sizing_plant.designLoopExitTemperature, 'C', 'F').get
          des_temp_diff = OpenStudio.convert(sizing_plant.loopDesignTemperatureDifference, 'K', 'R').get
          assert_in_delta(180, des_temp, delta, assert_msg)
          assert_in_delta(50, des_temp_diff, delta, assert_msg)

          # G3.1.3.4 Hot-Water Supply Temperature Reset (Systems 1, 5, 7, 11, and 12)
          prm_min_sec = 'Hot-Water Supply Temperature Reset'
          assert_msg = "#{prm_maj_sec}: #{prm_min_sec}"

          if setpoint_managers[0].to_SetpointManagerOutdoorAirReset.is_initialized
            spm_oar = setpoint_managers[0].to_SetpointManagerOutdoorAirReset.get
          else
            assert(setpoint_managers[0].to_SetpointManagerOutdoorAirReset.is_initialized, assert_msg)
          end

          set_oat_lo = OpenStudio.convert(spm_oar.setpointatOutdoorLowTemperature, 'C', 'F').get
          oat_lo = OpenStudio.convert(spm_oar.outdoorLowTemperature, 'C', 'F').get
          set_oat_hi = OpenStudio.convert(spm_oar.setpointatOutdoorHighTemperature, 'C', 'F').get
          oat_hi = OpenStudio.convert(spm_oar.outdoorHighTemperature, 'C', 'F').get

          assert_in_delta(180, set_oat_lo, delta, assert_msg)
          assert_in_delta(20, oat_lo, delta, assert_msg)
          assert_in_delta(150, set_oat_hi, delta, assert_msg)
          assert_in_delta(50, oat_hi, delta, assert_msg)

        when 'Cooling'

          # G3.1.3.8 Chilled-Water Design Supply Temperature (Systems 7, 8, 11, 12, and 13)
          prm_min_sec = 'Chilled-Water Design Supply Temperature'
          assert_msg = "#{prm_maj_sec}: #{prm_min_sec}"

          des_temp = OpenStudio.convert(sizing_plant.designLoopExitTemperature, 'C', 'F').get
          des_temp_diff = OpenStudio.convert(sizing_plant.loopDesignTemperatureDifference, 'K', 'R').get
          assert_in_delta(44, des_temp, delta, assert_msg)
          assert_in_delta(12, des_temp_diff, delta, assert_msg)

          # G3.1.3.9 Chilled-Water Supply Temperature Reset (Systems 7, 8, 11, 12, and 13)
          prm_min_sec = 'Chilled-Water Supply Temperature Reset'
          assert_msg = "#{prm_maj_sec}: #{prm_min_sec}"

          if setpoint_managers[0].to_SetpointManagerOutdoorAirReset.is_initialized
            spm_oar = setpoint_managers[0].to_SetpointManagerOutdoorAirReset.get
          else
            assert(setpoint_managers[0].to_SetpointManagerOutdoorAirReset.is_initialized, assert_msg)
          end

          set_oat_lo = OpenStudio.convert(spm_oar.setpointatOutdoorLowTemperature, 'C', 'F').get
          oat_lo = OpenStudio.convert(spm_oar.outdoorLowTemperature, 'C', 'F').get
          set_oat_hi = OpenStudio.convert(spm_oar.setpointatOutdoorHighTemperature, 'C', 'F').get
          oat_hi = OpenStudio.convert(spm_oar.outdoorHighTemperature, 'C', 'F').get

          assert_in_delta(54, set_oat_lo, delta, assert_msg)
          assert_in_delta(60, oat_lo, delta, assert_msg)
          assert_in_delta(44, set_oat_hi, delta, assert_msg)
          assert_in_delta(80, oat_hi, delta, assert_msg)

        when 'Condenser'

          # 90.1-2013
          # G3.1.3.11 Heat Rejection (Systems 7, 8, 9, 12, and 13)
          prm_min_sec = 'Heat Rejection'
          assert_msg = "#{prm_maj_sec}: #{prm_min_sec}"

          if setpoint_managers[0].to_SetpointManagerFollowOutdoorAirTemperature.is_initialized
            spm_follow_oat = setpoint_managers[0].to_SetpointManagerFollowOutdoorAirTemperature.get
          else
            assert(setpoint_managers[0].to_SetpointManagerFollowOutdoorAirTemperature.is_initialized, assert_msg)
          end

          spm_ctrl_var = spm_follow_oat.controlVariable
          spm_ref_temp = spm_follow_oat.referenceTemperatureType
          spm_offset_temp_diff_si = spm_follow_oat.offsetTemperatureDifference
          spm_max_temp_si = spm_follow_oat.maximumSetpointTemperature
          spm_min_temp_si = spm_follow_oat.minimumSetpointTemperature
          spm_offset_temp_diff_ip = OpenStudio.convert(spm_offset_temp_diff_si, 'K', 'R').get
          spm_max_temp_ip = OpenStudio.convert(spm_max_temp_si, 'C', 'F').get
          spm_min_temp_ip = OpenStudio.convert(spm_min_temp_si, 'C', 'F').get

          des_day_wb_ip = []

          des_days.each do |dd|

            next unless dd.dayType == 'SummerDesignDay'
            next unless dd.name.get.to_s.include?('WB=>MDB')

            if base_model.version < OpenStudio::VersionString.new('3.3.0')
              if dd.humidityIndicatingType == 'Wetbulb'
                des_day_wb_si = dd.humidityIndicatingConditionsAtMaximumDryBulb
                des_day_wb_ip << OpenStudio.convert(des_day_wb_si, 'C', 'F').get
                puts "DD WB = #{des_day_wb_ip}"
              else
                puts "#{prm_maj_sec}: #{prm_min_sec}: cannot determine design day information"
              end
            else
              if dd.humidityConditionType == 'Wetbulb' && dd.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
                des_day_wb_ip << OpenStudio.convert(dd.wetBulbOrDewPointAtMaximumDryBulb.get, 'C', 'F').get
                puts "DD WB = #{des_day_wb_ip}"
              else
                puts "#{prm_maj_sec}: #{prm_min_sec}: cannot determine design day information"
              end
            end
          end

          if des_day_wb_ip.size == 0
            wb = 78
          else
            wb = des_day_wb_ip.max
          end

          # EnergyPlus limit
          if wb > 80
            wb = 80
          end
          # @todo reconcile EP and PRM limits
          # PRM limits
          if wb < 55
            wb = 55
          elsif wb > 90
            wb = 90
          end

          prm_approach = 25.72 - (0.24*wb)
          prm_max_temp = prm_approach + wb #approach = LWT - Twb

          assert_equal('Temperature', spm_ctrl_var, assert_msg)
          assert_equal('OutdoorAirWetBulb', spm_ref_temp, assert_msg)
          assert_in_delta(prm_approach, spm_offset_temp_diff_ip, delta, assert_msg)
          assert_in_delta(prm_max_temp, spm_max_temp_ip, delta, assert_msg)
          assert_in_delta(70, spm_min_temp_ip, delta, assert_msg)

          # puts "PRM WB = #{wb}"
          # puts "PRM APPROACH = #{prm_approach}"
          # puts "PRM MAX = #{prm_max_temp}"
          # puts "SPM MAX = #{spm_max_temp_ip}"

        end

      end

    else

      puts "#{prm_maj_sec}: NA plant loops not found in baseline"

    end

  end

  # @author Matt Steen, Ambient Energy
  def check_shw(base_model, prop_model, building_type)

    prm_maj_sec = 'Table G3.1 No. 11: Service Hot Water'

    # get model objects
    base_wtr_htr_mixeds = base_model.getWaterHeaterMixeds
    prop_wtr_htr_mixeds = prop_model.getWaterHeaterMixeds

    # test baseline water heater
    if prop_wtr_htr_mixeds.size > 0
      # assert(base_wtr_htr_mixeds.size > 0, 'PRM: proposed model contains water heater(s), but baseline model does not')
    end

    # determine building area type
    # 90.1-2013, Table G3.1.1-2
    prm_shw_fuel = nil
    case building_type
    when 'SecondarySchool', 'PrimarySchool', # School/university
         'SmallHotel', # Motel
         'LargeHotel', # Hotel
         'QuickServiceRestaurant', # Dining: Cafeteria/fast food
         'FullServiceRestaurant', # Dining: Family
         'MidriseApartment', 'HighriseApartment', # Multifamily
         'Hospital', # Hospital
         'Outpatient' # Health-care clinic
      prm_shw_fuel = 'NaturalGas'
    when 'SmallOffice', 'MediumOffice', 'LargeOffice', # Office
         'RetailStandalone', 'RetailStripmall', # Retail
         'Warehouse' # Warehouse
      prm_shw_fuel = 'Electricity'
    else
      prm_shw_fuel = 'NaturalGas'
    end

    # 90.1-2013 Table 7.8
    prm_cap_elec = OpenStudio.convert(12, 'kW', 'Btu/h').get
    prm_vol_elec = 12 #gal
    prm_cap_gas = 75000

    base_wtr_htr_mixeds.each do |wh|

      if wh.to_WaterHeaterMixed.is_initialized

        wh = wh.to_WaterHeaterMixed.get
        fuel = wh.heaterFuelType
        eff = wh.heaterThermalEfficiency.get
        cap = wh.heaterMaximumCapacity.get
        cap = OpenStudio.convert(cap,'W','Btu/h').get
        vol = wh.tankVolume.get
        vol = OpenStudio.convert(vol,'m^3','gal').get
        ua_off = wh.offCycleLossCoefficienttoAmbientTemperature.get
        ua_off = OpenStudio.convert(ua_off,'W/K','Btu/hr*R').get
        ua_on = wh.onCycleLossCoefficienttoAmbientTemperature.get
        ua_on = OpenStudio.convert(ua_on,'W/K','Btu/hr*R').get

        # Estimate storage tank volume
        tank_volume = vol > 100 ? (vol - 100).round(0) : 0
        wh_tank_volume = vol > 100 ? 100 : vol
        # SL Storage Tank: polynomial regression based on a set of manufacturer data
        sl_tank = 0.0000005 * tank_volume**3 - 0.001 * tank_volume**2 + 1.3519 * tank_volume + 64.456 # in Btu/h

        # test baseline water heater fuel
         assert_equal(prm_shw_fuel, fuel, "#{prm_maj_sec}: baseline water heater fuel type")

        # test baseline water heater efficiency
        # e_ht = EnergyPlus Heater Thermal Efficiency, which is gross
        # e_t = thermal efficiency, which is net

        case prm_shw_fuel

        when 'Electricity'

          if cap <= prm_cap_elec && vol >= prm_vol_elec
            # from standard
            ef = 0.97 - 0.00035 * vol
            # from PNNL
            e_ht = 1
            ua = (41094 * (1/ef - 1)) / (24 * 67.5)
            # test
            assert_equal(e_ht, eff, "#{prm_maj_sec}: baseline water heater efficiency")
          elsif cap > prm_cap_elec && vol >= prm_vol_elec
            e_ht = 1
            # ua = sl * 1 / 70
            # @todo
          end

        when 'NaturalGas'

          if cap <= prm_cap_gas
            # from standard
            ef = 0.67 - 0.0005 * vol
            # from PNNL
            e_ht = 0.82
            # @todo solve equations
            assert_in_delta(0.82, eff, delta=0, "#{prm_maj_sec}: baseline water heater efficiency")
          elsif cap > prm_cap_gas
            # from standard
            e_t = 0.8
            # from PNNL
            p_on = cap / e_t
            sl = p_on / 800 + 110 * Math.sqrt(vol) + sl_tank #per 2013 errata
            ua = sl * e_t / 70
            e_ht = (ua * 70 + p_on * e_t) / p_on

            # test
            assert_in_delta(e_ht, eff, delta=0.01, "#{prm_maj_sec}: baseline water heater efficiency")
            assert_in_delta(ua, ua_off, delta=0.1, "#{prm_maj_sec}: baseline water heater UA")
            assert_in_delta(ua, ua_on, delta=0.1, "#{prm_maj_sec}: baseline water heater UA")
          end

        end

      end

    end

  end

  # @author Matt Leach, NORESCO
  def calculate_motor_efficiency(bhp)
    if bhp > 150
      # 200 hp
      motor_efficiency = 0.962
    elsif bhp > 125
      # 150 hp
      motor_efficiency = 0.958
    elsif bhp > 100
      # 125 hp
      motor_efficiency = 0.954
    elsif bhp > 75
      # 100 hp
      motor_efficiency = 0.954
    elsif bhp > 60
      # 75 hp
      motor_efficiency = 0.954
    elsif bhp > 50
      # 60n hp
      motor_efficiency = 0.950
    elsif bhp > 40
      # 50 hp
      motor_efficiency = 0.945
    elsif bhp > 30
      # 40 hp
      motor_efficiency = 0.941
    elsif bhp > 25
      # 30 hp
      motor_efficiency = 0.936
    elsif bhp > 20
      # 25 hp
      motor_efficiency = 0.936
    elsif bhp > 15
      # 20 hp
      motor_efficiency = 0.930
    elsif bhp > 10
      # 15 hp
      motor_efficiency = 0.924
    elsif bhp > 7.5
      # 10 hp
      motor_efficiency = 0.917
    elsif bhp > 5
      # 7.5 hp
      motor_efficiency = 0.917
    elsif bhp > 3
      # 5 hp
      motor_efficiency = 0.895
    elsif bhp > 2
      # 3 hp
      motor_efficiency = 0.895
    elsif bhp > 1.5
      # 2 hp
      motor_efficiency = 0.865
    elsif bhp > 1
      # 1.5 hp
      motor_efficiency = 0.865
    elsif bhp > 1/12.0
      # 1 hp
      motor_efficiency = 0.855
    else
      motor_efficiency = 0.70
    end
    return motor_efficiency
  end

  # @author Matt Leach, NORESCO
  def check_dx_cooling_single_speed_efficiency(model, dx_coil_hash, failure_array)
    model.getCoilCoolingDXSingleSpeeds.each do |cooling_coil|
      cooling_coil_name = cooling_coil.name.get.to_s
      dx_coil_hash.keys.each do |cooling_coil_name_keyword|
        next unless cooling_coil_name.include? cooling_coil_name_keyword
        next unless dx_coil_hash[cooling_coil_name_keyword]["CoilType"] == "SingleSpeedCooling"
        # OptionalDouble < 3.5.0, double after
        cop_ = OpenStudio::OptionalDouble.new(cooling_coil.ratedCOP)
        if cop_.is_initialized
          coil_cop = cop_.get
          if dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"] == "EER"
            expected_coil_cop = (7.84e-8*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]*dx_coil_hash[cooling_coil_name_keyword]["Capacity"]*1000.0)+(0.338*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"])
          elsif dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"] == "SEER"
            expected_coil_cop = -0.0076*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]**2+0.3796*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]
          elsif dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"] == "PTAC"
            if dx_coil_hash[cooling_coil_name_keyword]["Capacity"] < 7
              capacity_for_calculation = 7
            elsif dx_coil_hash[cooling_coil_name_keyword]["Capacity"] > 15
              capacity_for_calculation = 15
            else
              capacity_for_calculation = dx_coil_hash[cooling_coil_name_keyword]["Capacity"]
            end
            expected_coil_eer = 13.8 - (0.3*capacity_for_calculation)
            expected_coil_cop = (7.84e-8*expected_coil_eer*dx_coil_hash[cooling_coil_name_keyword]["Capacity"]*1000.0)+(0.338*expected_coil_eer)
          else
            failure_array << "Test Error: unexpected Efficiency Type (#{dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"]}) for #{cooling_coil_name}; expected 'EER' or 'SEER'"
          end
          unless (expected_coil_cop - coil_cop).abs < 0.1
            failure_array << "Expected COP of #{expected_coil_cop.round(2)} for #{cooling_coil_name}; got #{coil_cop.round(2)} instead"
          end
        else
          failure_array << "Expected COP to be set for #{cooling_coil_name}"
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_dx_cooling_two_speed_efficiency(model, dx_coil_hash, failure_array)
    model.getCoilCoolingDXTwoSpeeds.each do |cooling_coil|
      cooling_coil_name = cooling_coil.name.get.to_s
      dx_coil_hash.keys.each do |cooling_coil_name_keyword|
        next unless cooling_coil_name.include? cooling_coil_name_keyword
        next unless dx_coil_hash[cooling_coil_name_keyword]["CoilType"] == "TwoSpeedCooling"
        # OptionalDouble < 3.5.0, double after
        cop_ = OpenStudio::OptionalDouble.new(cooling_coil.ratedHighSpeedCOP)
        if cop_.is_initialized
          coil_cop = cop_.get
          if dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"] == "EER"
            expected_coil_cop = (7.84e-8*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]*dx_coil_hash[cooling_coil_name_keyword]["Capacity"]*1000.0)+(0.338*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"])
          elsif dx_coil_hash[cooling_coil_name_keyword]["EfficiencyType"] == "SEER"
            expected_coil_cop = -0.0076*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]**2+0.3796*dx_coil_hash[cooling_coil_name_keyword]["Efficiency"]
          else
            failure_array << "Test Error: unexpected Efficiency Type (#{}) for #{cooling_coil_name}; expected 'EER' or 'SEER'"
          end
          unless (expected_coil_cop - coil_cop).abs < 0.02
            failure_array << "Expected COP of #{expected_coil_cop.round(2)} for #{cooling_coil_name}; got #{coil_cop.round(2)} instead"
          end
        else
          failure_array << "Expected COP to be set for #{cooling_coil_name}"
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_dx_heating_single_speed_efficiency(model, dx_coil_hash, failure_array)
    model.getCoilHeatingDXSingleSpeeds.each do |heating_coil|
      heating_coil_name = heating_coil.name.get.to_s
      dx_coil_hash.keys.each do |heating_coil_name_keyword|
        next unless heating_coil_name.include? heating_coil_name_keyword
        next unless dx_coil_hash[heating_coil_name_keyword]["CoilType"] == "SingleSpeedHeating"
        coil_cop = heating_coil.ratedCOP
        if dx_coil_hash[heating_coil_name_keyword]["EfficiencyType"] == "COP"
          expected_coil_cop = (1.48e-7*dx_coil_hash[heating_coil_name_keyword]["Efficiency"]*dx_coil_hash[heating_coil_name_keyword]["Capacity"]*1000.0)+(1.062*dx_coil_hash[heating_coil_name_keyword]["Efficiency"])
        elsif dx_coil_hash[heating_coil_name_keyword]["EfficiencyType"] == "HSPF"
          expected_coil_cop = -0.0296*dx_coil_hash[heating_coil_name_keyword]["Efficiency"]**2+0.7134*dx_coil_hash[heating_coil_name_keyword]["Efficiency"]
        else
          failure_array << "Test Error: unexpected Efficiency Type (#{}) for #{heating_coil_name}; expected 'COP' or 'HSPF'"
        end
        unless (expected_coil_cop - coil_cop).abs < 0.02
          failure_array << "Expected COP of #{expected_coil_cop.round(2)} for #{heating_coil_name}; got #{coil_cop.round(2)} instead"
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_variable_speed_fan_power(model, supply_fan_hash, failure_array)
    model.getFanVariableVolumes.each do |supply_fan|
      supply_fan_name = supply_fan.name.get.to_s
      supply_fan_hash.keys.each do |supply_fan_name_to_match|
        next unless supply_fan_name == supply_fan_name_to_match

        fan_total_efficiency = supply_fan.fanEfficiency
        fan_pressure_rise_pa = supply_fan.pressureRise
        fan_pressure_rise_in_h2o = fan_pressure_rise_pa/249.1
        fan_watts_per_cfm = fan_pressure_rise_in_h2o / (8.5605*fan_total_efficiency)

        expected_fan_bhp = 0.0013*supply_fan_hash[supply_fan_name]["CFM"]+supply_fan_hash[supply_fan_name]["PressureDifferential"]*supply_fan_hash[supply_fan_name]["CFM"]/4131
        expected_motor_efficiency = calculate_motor_efficiency(expected_fan_bhp)
        expected_fan_watts_per_cfm = (expected_fan_bhp*746/expected_motor_efficiency)/supply_fan_hash[supply_fan_name]["CFM"]

        unless (fan_watts_per_cfm - expected_fan_watts_per_cfm).abs < 0.02
          failure_array << "Expected Fan Power of #{expected_fan_watts_per_cfm.round(2)} W/cfm for #{supply_fan_name}; got #{fan_watts_per_cfm.round(2)} W/cfm instead"
        end

      end
      # check fan curves
      # Skip single-zone VAV fans
      next if supply_fan.airLoopHVAC.get.thermalZones.size == 1
      # coefficient 1
      if supply_fan.fanPowerCoefficient1.is_initialized
        expected_coefficient = 0.0013
        coefficient = supply_fan.fanPowerCoefficient1.get
        unless (coefficient - expected_coefficient).abs < 0.01
          failure_array << "Expected Coefficient 1 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead"
        end
      else
        failure_array << "Expected Coefficient 1 for #{supply_fan_name} to be set"
      end
      # coefficient 2
      if supply_fan.fanPowerCoefficient2.is_initialized
        expected_coefficient = 0.1470
        coefficient = supply_fan.fanPowerCoefficient2.get
        unless (coefficient - expected_coefficient).abs < 0.01
          failure_array << "Expected Coefficient 2 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead"
        end
      else
        failure_array << "Expected Coefficient 2 for #{supply_fan_name} to be set"
      end
      # coefficient 3
      if supply_fan.fanPowerCoefficient3.is_initialized
        expected_coefficient = 0.9506
        coefficient = supply_fan.fanPowerCoefficient3.get
        unless (coefficient - expected_coefficient).abs < 0.01
          failure_array << "Expected Coefficient 3 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead"
        end
      else
        failure_array << "Expected Coefficient 3 for #{supply_fan_name} to be set"
      end
      # coefficient 4
      if supply_fan.fanPowerCoefficient4.is_initialized
        expected_coefficient = -0.0998
        coefficient = supply_fan.fanPowerCoefficient4.get
        unless (coefficient - expected_coefficient).abs < 0.01
          failure_array << "Expected Coefficient 4 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead"
        end
      else
        failure_array << "Expected Coefficient 4 for #{supply_fan_name} to be set"
      end
      # coefficient 5
      if supply_fan.fanPowerCoefficient5.is_initialized
        expected_coefficient = 0
        coefficient = supply_fan.fanPowerCoefficient5.get
        unless (coefficient - expected_coefficient).abs < 0.01
          failure_array << "Expected Coefficient 5 for #{supply_fan_name} to be equal to #{expected_coefficient}; found #{coefficient} instead"
        end
      else
        failure_array << "Expected Coefficient 5 for #{supply_fan_name} to be set"
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_constant_speed_fan_power(model, supply_fan_hash, failure_array)
    model.getFanConstantVolumes.each do |fan|
      fan_name = fan.name.get.to_s
      # check PFP terminal fans
      if fan_name.include? "PFP Term Fan"
        # check if fan power is 0.35 W/cfm
        fan_total_efficiency = fan.fanEfficiency
        fan_pressure_rise_pa = fan.pressureRise
        fan_pressure_rise_in_h2o = fan_pressure_rise_pa/249.1
        fan_watts_per_cfm = fan_pressure_rise_in_h2o / (8.5605*fan_total_efficiency)
        expected_fan_watts_per_cfm = 0.35
        unless (fan_watts_per_cfm - expected_fan_watts_per_cfm).abs < 0.02
          failure_array << "Expected Fan Power of #{expected_fan_watts_per_cfm} W/cfm for #{fan_name}; got #{fan_watts_per_cfm.round(2)} W/cfm instead"
        end
      elsif (fan_name.include? "PTAC" or fan_name.include? "PTHP")
        # check if fan power is 0.3 W/cfm
        fan_total_efficiency = fan.fanEfficiency
        fan_pressure_rise_pa = fan.pressureRise
        fan_pressure_rise_in_h2o = fan_pressure_rise_pa/249.1
        fan_watts_per_cfm = fan_pressure_rise_in_h2o / (8.5605*fan_total_efficiency)
        expected_fan_watts_per_cfm = 0.30
        unless (fan_watts_per_cfm - expected_fan_watts_per_cfm).abs < 0.01
          failure_array << "Expected Fan Power of #{expected_fan_watts_per_cfm} W/cfm for #{fan_name}; got #{fan_watts_per_cfm.round(2)} W/cfm instead"
        end
      elsif fan_name.include? "UnitHeater"
        # check if fan power is 0.3 W/cfm
        fan_total_efficiency = fan.fanEfficiency
        fan_pressure_rise_pa = fan.pressureRise
        fan_pressure_rise_in_h2o = fan_pressure_rise_pa/249.1
        fan_watts_per_cfm = fan_pressure_rise_in_h2o / (8.5605*fan_total_efficiency)
        expected_fan_watts_per_cfm = 0.30
        unless (fan_watts_per_cfm - expected_fan_watts_per_cfm).abs < 0.01
          failure_array << "Expected Fan Power of #{expected_fan_watts_per_cfm} W/cfm for #{fan_name}; got #{fan_watts_per_cfm.round(2)} W/cfm instead"
        end
      else
        supply_fan_hash.keys.each do |supply_fan_name_to_match|
          next unless fan_name == supply_fan_name_to_match
          fan_total_efficiency = fan.fanEfficiency
          fan_pressure_rise_pa = fan.pressureRise
          fan_pressure_rise_in_h2o = fan_pressure_rise_pa/249.1
          fan_watts_per_cfm = fan_pressure_rise_in_h2o / (8.5605*fan_total_efficiency)
          expected_fan_bhp = 0.00094*supply_fan_hash[fan_name]["CFM"]+supply_fan_hash[fan_name]["PressureDifferential"]*supply_fan_hash[fan_name]["CFM"]/4131
          expected_motor_efficiency = calculate_motor_efficiency(expected_fan_bhp)
          expected_fan_watts_per_cfm = (expected_fan_bhp*746/expected_motor_efficiency)/supply_fan_hash[fan_name]["CFM"]
          unless (fan_watts_per_cfm - expected_fan_watts_per_cfm).abs < 0.01
            failure_array << "Expected Fan Power of #{expected_fan_watts_per_cfm.round(2)} W/cfm for #{fan_name}; got #{fan_watts_per_cfm.round(2)} W/cfm instead"
          end
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_chillers(model, total_chilled_water_capacity_tons, failure_array)
    # chillers
    chiller_check_output_hash = {}
    number_of_chillers = 0
    if total_chilled_water_capacity_tons >= 600
      model.getChillerElectricEIRs.each do |chiller|
        number_of_chillers += 1
        # check curves (should be centrifugal)
        unless chiller.coolingCapacityFunctionOfTemperature.name.get.to_s.include? "Cent"
          failure_array << "Expected Chiller(s) of Type Centrifugal but Curve #{chiller.coolingCapacityFunctionOfTemperature.name} does not contain 'Cent'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name.get.to_s.include? "Cent"
          failure_array << "Expected Chiller(s) of Type Centrifugal but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name} does not contain 'Cent'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name.get.to_s.include? "Cent"
          failure_array << "Expected Chiller(s) of Type Centrifugal but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name} does not contain 'Cent'"
        end
      end
      # check for two chillers
      unless number_of_chillers == 2
        failure_array << "Total CHW Capacity is #{total_chilled_water_capacity_tons} tons.  For capacities larger than 600 tons, 2 chillers are expected; found #{number_of_chillers} chillers instead"
      end
      # check chiller efficiency
      chiller_capacity = total_chilled_water_capacity_tons/number_of_chillers
      # Centrifugal, Path B efficiencies, Effective 1/1/2010
      if chiller_capacity >= 600
        expected_kw_per_ton = 0.56
      elsif chiller_capacity >= 400
        expected_kw_per_ton = 0.56
      elsif chiller_capacity >= 300
        expected_kw_per_ton = 0.56
      elsif chiller_capacity >= 150
        expected_kw_per_ton = 0.61
      else
        expected_kw_per_ton = 0.61
      end
      expected_cop = (12/expected_kw_per_ton)/3.412
      model.getChillerElectricEIRs.each do |chiller|
        cop = chiller.referenceCOP
        unless (cop - expected_cop).abs < 0.05
          failure_array << "Expected COP of #{expected_cop.round(2)} for Chiller #{chiller.name}; found #{cop.round(2)} instead"
        end
      end
    elsif total_chilled_water_capacity_tons > 300
      model.getChillerElectricEIRs.each do |chiller|
        number_of_chillers += 1
        # check curves (should be positive displacement)
        unless chiller.coolingCapacityFunctionOfTemperature.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.coolingCapacityFunctionOfTemperature.name} does not contain 'PosDisp'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name} does not contain 'PosDisp'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name} does not contain 'PosDisp'"
        end
      end
      # check for two chillers
      unless number_of_chillers == 2
        failure_array << "Total CHW Capacity is #{total_chilled_water_capacity_tons} tons.  For capacities larger than 600 tons, 2 chillers are expected; found #{number_of_chillers} chillers instead"
      end
      # check chiller efficiency
      unless number_of_chillers == 0
        chiller_capacity = total_chilled_water_capacity_tons/number_of_chillers
        # Positive Displacement, Path A efficiencies, Effective 1/1/2015
        if chiller_capacity >= 600
          expected_kw_per_ton = 0.560
        elsif chiller_capacity >= 300
          expected_kw_per_ton = 0.610
        elsif chiller_capacity >= 150
          expected_kw_per_ton = 0.660
        elsif chiller_capacity >= 75
          expected_kw_per_ton = 0.720
        else
          expected_kw_per_ton = 0.750
        end
        expected_cop = (12/expected_kw_per_ton)/3.412
        model.getChillerElectricEIRs.each do |chiller|
          cop = chiller.referenceCOP
          unless (cop - expected_cop).abs < 0.05
            failure_array << "Expected COP of #{expected_cop.round(2)} for Chiller #{chiller.name}; found #{cop.round(2)} instead"
          end
        end
      end
    else
      model.getChillerElectricEIRs.each do |chiller|
        number_of_chillers += 1
        # check curves (should be positive displacement)
        unless chiller.coolingCapacityFunctionOfTemperature.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.coolingCapacityFunctionOfTemperature.name} does not contain 'PosDisp'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfTemperature.name} does not contain 'PosDisp'"
        end
        unless chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name.get.to_s.include? "PosDisp"
          failure_array << "Expected Chiller(s) of Type Screw but Curve #{chiller.  electricInputToCoolingOutputRatioFunctionOfPLR.name} does not contain 'PosDisp'"
        end
      end
      # check for two chillers
      unless number_of_chillers == 1
        failure_array << "Total CHW Capacity is #{total_chilled_water_capacity_tons} tons.  For capacities larger than 600 tons, 1 chiller is expected; found #{number_of_chillers} chillers instead"
      end
      # check chiller efficiency
      unless number_of_chillers == 0
        chiller_capacity = total_chilled_water_capacity_tons/number_of_chillers
        # Positive Displacement, Path A efficiencies, Effective 1/1/2015
        if chiller_capacity >= 600
          expected_kw_per_ton = 0.560
        elsif chiller_capacity >= 300
          expected_kw_per_ton = 0.610
        elsif chiller_capacity >= 150
          expected_kw_per_ton = 0.660
        elsif chiller_capacity >= 75
          expected_kw_per_ton = 0.720
        else
          expected_kw_per_ton = 0.750
        end
        expected_cop = (12/expected_kw_per_ton)/3.412
        model.getChillerElectricEIRs.each do |chiller|
          cop = chiller.referenceCOP
          unless (cop - expected_cop).abs < 0.05
            failure_array << "Expected COP of #{expected_cop.round(2)} for Chiller #{chiller.name}; found #{cop.round(2)} instead"
          end
        end
      end
    end
    chiller_check_output_hash["Failure_Array"] = failure_array
    chiller_check_output_hash["Number_Of_Chillers"] = number_of_chillers
    return chiller_check_output_hash
  end

  # @author Matt Leach, NORESCO
  def calculate_zones_served_by_hot_water_loop(hw_loop, zones_served)
    airloops_to_check = []
    zone_hvacs_to_check = []
    vav_reheat_terminals_to_check = []
    # get zones served by hot water coils
    hw_loop.demandComponents.each do |demand_component|
      next if demand_component.to_Node.is_initialized
      next if demand_component.to_PipeAdiabatic.is_initialized
      next if demand_component.to_ConnectorMixer.is_initialized
      next if demand_component.to_ConnectorSplitter.is_initialized
      next if demand_component.to_ConnectorSplitter.is_initialized
      next if demand_component.to_WaterUseConnections.is_initialized
      if demand_component.to_CoilHeatingWater.is_initialized
        # get thermal zone
        hot_water_coil = demand_component.to_CoilHeatingWater.get
        # get airloop if relevant
        if hot_water_coil.airLoopHVAC.is_initialized
          airloops_to_check << hot_water_coil.airLoopHVAC.get
          airloops_to_check = airloops_to_check.uniq
        elsif hot_water_coil.containingZoneHVACComponent.is_initialized
          zone_hvacs_to_check << hot_water_coil.containingZoneHVACComponent.get
          zone_hvacs_to_check = zone_hvacs_to_check.uniq
        elsif hot_water_coil.containingHVACComponent.is_initialized
          hvac_component = hot_water_coil.containingHVACComponent.get
          if hvac_component.to_AirTerminalSingleDuctVAVReheat.is_initialized
            vav_reheat_terminals_to_check << hvac_component.to_AirTerminalSingleDuctVAVReheat.get
          end
        end
      else
        failure_array << "Expected demand components for Loop #{hw_loop.name} to be CoilHeatingWater"
      end
    end
    airloops_to_check.each do |airloop|
      airloop.thermalZones.each do |zone|
        zones_served << zone
      end
    end
    zone_hvacs_to_check.each do |zone_hvac|
      if zone_hvac.thermalZone.is_initialized
        zones_served << zone_hvac.thermalZone.get
      end
    end
    vav_reheat_terminals_to_check.each do |vav_reheat_terminal|
      if vav_reheat_terminal.outletModelObject.is_initialized
        if vav_reheat_terminal.outletModelObject.get.to_Node.is_initialized
          if vav_reheat_terminal.outletModelObject.get.to_Node.get.outletModelObject.is_initialized
            if vav_reheat_terminal.outletModelObject.get.to_Node.get.outletModelObject.get.to_PortList.is_initialized
              zones_served << vav_reheat_terminal.outletModelObject.get.to_Node.get.outletModelObject.get.to_PortList.get.thermalZone
            end
          end
        end
      end
    end
    return zones_served
  end

  # @author Matt Leach, NORESCO
  def check_boilers(model, failure_array)
    hw_loops = []
    hot_water_area_served_ft2 = 0
    number_of_boilers = 0
    zones_served = []
    # get hot water loop
    model.getBoilerHotWaters.each do |boiler|
      number_of_boilers += 1
      if boiler.plantLoop.is_initialized
        plant_loop = boiler.plantLoop.get
        hw_loops << plant_loop
        hw_loops = hw_loops.uniq
      else
        failure_array << "Boiler #{boiler.name} is not attached to a Plant Loop"
      end
    end
    if hw_loops.length > 1
      failure_array << "Expected only one HW Loop"
    elsif  hw_loops.length == 0
      failure_array << "Could not find a hot water loop with a Boiler"
    end
    # get zones served by hot water coils
    hw_loops.each do |hw_loop|
      zones_served = calculate_zones_served_by_hot_water_loop(hw_loop, zones_served)
    end
    # calculate area served
    zones_served = zones_served.uniq
    zones_served.each do |zone|
      hot_water_area_served_ft2 += zone.floorArea * 10.7639
    end
    # check number of boilers
    if hot_water_area_served_ft2 > 15000
      # should be two boilers
      unless number_of_boilers == 2
        failure_array << "Hot water plant serves #{hot_water_area_served_ft2.round()} ft2 of floor area; expected 2 boilers but found #{number_of_boilers}"
      end
    else
      # should be one boiler
      unless number_of_boilers == 1
        failure_array << "Hot water plant serves #{hot_water_area_served_ft2.round()} ft2 of floor area; expected 1 boiler but found #{number_of_boilers}"
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_cooling_towers(model, number_of_chillers, failure_array)
    # towers (should be one tower per chiller)
    number_of_towers = 0
    model.getCoolingTowerVariableSpeeds.each do |tower|
      number_of_towers += 1
    end
    unless number_of_towers == number_of_chillers
      failure_array << "Number of towers should match number of chillers; found #{number_of_towers} towers and #{number_of_chillers} chillers"
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_chw_pumps(model, number_of_chillers, total_chilled_water_capacity_tons, failure_array)
    # should be one constant speed pump per chiller on the supply side with 9 W/gpm power
    chw_loops = []
    model.getChillerElectricEIRs.each do |chiller|
      if chiller.plantLoop.is_initialized
        chw_loops << chiller.plantLoop.get
        chw_loops = chw_loops.uniq
      else
        failure_array << "Chiller #{chiller.name} is not connected to a plant loop"
      end
    end
    # get pumps from chw loop
    if chw_loops.length > 1
      failure_array << "Expected 1 CHW Loop; found #{chw_loops.length}"
    elsif  chw_loops.length == 0
      failure_array << "Could not find a chilled water loop with a Chiller"
    else
      chw_loops.each do |chw_loop|

        constant_speed_supply_pumps = []
        variable_speed_supply_pumps = []
        num_constant_speed_supply_pumps = 0
        num_variable_speed_supply_pumps = 0
        # supply side
        chw_loop.supplyComponents('OS_Pump_ConstantSpeed'.to_IddObjectType).each do |hp|
          num_constant_speed_supply_pumps += 1
          constant_speed_supply_pumps << hp.to_PumpConstantSpeed.get
        end
        chw_loop.supplyComponents('OS_HeaderedPumps_ConstantSpeed'.to_IddObjectType).each do |hp|
          hp = hp.to_HeaderedPumpsConstantSpeed.get
          num_constant_speed_supply_pumps += hp.numberofPumpsinBank
          constant_speed_supply_pumps << hp
        end
        chw_loop.supplyComponents('OS_Pump_VariableSpeed'.to_IddObjectType).each do |hp|
          num_variable_speed_supply_pumps += 1
          variable_speed_supply_pumps << hp.to_PumpVariableSpeed.get
        end
        chw_loop.supplyComponents('OS_HeaderedPumps_VariableSpeed'.to_IddObjectType).each do |hp|
          hp = hp.to_HeaderedPumpsVariableSpeed.get
          num_variable_speed_supply_pumps += hp.numberofPumpsinBank
          variable_speed_supply_pumps << hp
        end
        # check number of pumps
        number_of_pumps = num_constant_speed_supply_pumps + num_variable_speed_supply_pumps

        # check number of pumps
        unless number_of_pumps == number_of_chillers
          failure_array << "Expected #{number_of_chillers} supply-side pumps for #{chw_loop.name} because Loop has #{number_of_chillers} Chillers; found #{number_of_pumps} pump(s) instead"
        end
        # check type of pumps
        unless number_of_pumps == num_constant_speed_supply_pumps
          failure_array << "Expected supply-side pumps for #{chw_loop.name} to be of type ConstantSpeed, but #{number_of_pumps - num_constant_speed_supply_pumps} of #{number_of_pumps} pump(s) is/are of type VariableSpeed"
        end
        # check pump power
        expected_pump_watts_per_gpm = 9
        # constant speed
        constant_speed_supply_pumps.each do |pump|
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected supply-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
        end
        # variable speed
        variable_speed_supply_pumps.each do |pump|
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected supply-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
        end
        # should be one variable speed pump on the demand side with 13 W/gpm (riding curve if CHW capacity less than 300 tons)
        constant_speed_supply_pumps = chw_loop.demandComponents('OS_Pump_ConstantSpeed'.to_IddObjectType)
        variable_speed_supply_pumps = chw_loop.demandComponents('OS_Pump_VariableSpeed'.to_IddObjectType)
        number_of_pumps = constant_speed_supply_pumps.length + variable_speed_supply_pumps.length
        # check number of pumps
        unless number_of_pumps == 1
          failure_array << "Expected 1 demand-side pump for #{chw_loop.name}; found #{number_of_pumps} pump instead"
        end
        # check type of pumps
        unless number_of_pumps == variable_speed_supply_pumps.length
          failure_array << "Expected demand-side pump for #{chw_loop.name} to be of type VariableSpeed, but #{number_of_pumps - variable_speed_supply_pumps.length} of #{number_of_pumps} pump(s) is/are of type ConstantSpeed"
        end
        # check pump power
        expected_pump_watts_per_gpm = 13
        # constant speed
        constant_speed_supply_pumps.each do |pump|
          pump = pump.to_PumpConstantSpeed.get
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected demand-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
        end
        # variable speed
        variable_speed_supply_pumps.each do |pump|
          pump = pump.to_PumpVariableSpeed.get
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected demand-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
          # check pump curve
          if total_chilled_water_capacity_tons < 300
            # riding the curve
            pump_type = "Riding the Pump Curve"
            expected_coefficient_1 = 0
            expected_coefficient_2 = 3.2485
            expected_coefficient_3 = -4.7443
            expected_coefficient_4 = 2.5294
          else
            # variable speed drive
            pump_type = "Variable Speed Drive"
            expected_coefficient_1 = 0
            expected_coefficient_2 = 0.5726
            expected_coefficient_3 = -0.301
            expected_coefficient_4 = 0.7347
          end
          # coefficient 1
          coefficient_1 = pump.coefficient1ofthePartLoadPerformanceCurve
          unless (coefficient_1 - expected_coefficient_1).abs < 0.01
            failure_array << "Expected Coefficient 1 for #{pump.name} to be equal to #{expected_coefficient_1} (#{pump_type}); found #{coefficient_1} instead"
          end
          # coefficient 2
          coefficient_2 = pump.coefficient2ofthePartLoadPerformanceCurve
          unless (coefficient_2 - expected_coefficient_2).abs < 0.01
            failure_array << "Expected Coefficient 2 for #{pump.name} to be equal to #{expected_coefficient_2} (#{pump_type}); found #{coefficient_2} instead"
          end
          # coefficient 3
          coefficient_3 = pump.coefficient3ofthePartLoadPerformanceCurve
          unless (coefficient_3 - expected_coefficient_3).abs < 0.01
            failure_array << "Expected Coefficient 3 for #{pump.name} to be equal to #{expected_coefficient_3} (#{pump_type}); found #{coefficient_3} instead"
          end
          # coefficient 4
          coefficient_4 = pump.coefficient4ofthePartLoadPerformanceCurve
          unless (coefficient_4 - expected_coefficient_4).abs < 0.01
            failure_array << "Expected Coefficient 4 for #{pump.name} to be equal to #{expected_coefficient_4} (#{pump_type}); found #{coefficient_4} instead"
          end
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_district_chw_pumps(model, total_chilled_water_capacity_tons, failure_array)
    # should be one variable speed pump on supply side with 16 W/gpm power (riding the pump curve if chw capacity less than 300 tons)
    chw_loops = []
    model.getDistrictCoolings.each do |district_cooling|
      if district_cooling.plantLoop.is_initialized
        chw_loops << district_cooling.plantLoop.get
        chw_loops = chw_loops.uniq
      else
        failure_array << "DistrictCooling #{district_cooling.name} is not connected to a plant loop"
      end
    end

    if chw_loops.length > 1
      failure_array << "Expected 1 CHW Loop; found #{chw_loops.length}"
    elsif  chw_loops.length == 0
      failure_array << "Could not find a chilled water loop with a DistrictCooling object"
    else
      chw_loops.each do |chw_loop|
        # should be one variable speed pump on the supply side with 16 W/gpm (riding curve if CHW capacity less than 300 tons)
        constant_speed_supply_pumps = chw_loop.supplyComponents('OS_Pump_ConstantSpeed'.to_IddObjectType)
        variable_speed_supply_pumps = chw_loop.supplyComponents('OS_Pump_VariableSpeed'.to_IddObjectType)
        number_of_pumps = constant_speed_supply_pumps.length + variable_speed_supply_pumps.length
        # check number of pumps
        unless number_of_pumps == 1
          failure_array << "Expected 1 supply-side pump for #{chw_loop.name}; found #{number_of_pumps} pump instead"
        end
        # check type of pumps
        unless number_of_pumps == variable_speed_supply_pumps.length
          failure_array << "Expected supply-side pump for #{chw_loop.name} to be of type VariableSpeed, but #{number_of_pumps - variable_speed_supply_pumps.length} of #{number_of_pumps} pump(s) is/are of type ConstantSpeed"
        end
        # check pump power
        expected_pump_watts_per_gpm = 16
        # constant speed
        constant_speed_supply_pumps.each do |pump|
          pump = pump.to_PumpConstantSpeed.get
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected supply-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
        end
        # variable speed
        variable_speed_supply_pumps.each do |pump|
          pump = pump.to_PumpVariableSpeed.get
          motor_efficiency = pump.motorEfficiency
          impeller_efficiency = 0.78
          pump_efficiency = motor_efficiency * impeller_efficiency
          pump_head_pa = pump.ratedPumpHead
          pump_head_ft = pump_head_pa / (12*249.09)
          pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
          unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
            failure_array << "Expected supply-side pumps for #{chw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
          end
          # check pump curve
          if total_chilled_water_capacity_tons < 300
            # riding the curve
            pump_type = "Riding the Pump Curve"
            expected_coefficient_1 = 0
            expected_coefficient_2 = 3.2485
            expected_coefficient_3 = -4.7443
            expected_coefficient_4 = 2.5294
          else
            # variable speed drive
            pump_type = "Variable Speed Drive"
            expected_coefficient_1 = 0
            expected_coefficient_2 = 0.5726
            expected_coefficient_3 = -0.301
            expected_coefficient_4 = 0.7347
          end
          # coefficient 1
          coefficient_1 = pump.coefficient1ofthePartLoadPerformanceCurve
          unless (coefficient_1 - expected_coefficient_1).abs < 0.01
            failure_array << "Expected Coefficient 1 for #{pump.name} to be equal to #{expected_coefficient_1} (#{pump_type}); found #{coefficient_1} instead"
          end
          # coefficient 2
          coefficient_2 = pump.coefficient2ofthePartLoadPerformanceCurve
          unless (coefficient_2 - expected_coefficient_2).abs < 0.01
            failure_array << "Expected Coefficient 2 for #{pump.name} to be equal to #{expected_coefficient_2} (#{pump_type}); found #{coefficient_2} instead"
          end
          # coefficient 3
          coefficient_3 = pump.coefficient3ofthePartLoadPerformanceCurve
          unless (coefficient_3 - expected_coefficient_3).abs < 0.01
            failure_array << "Expected Coefficient 3 for #{pump.name} to be equal to #{expected_coefficient_3} (#{pump_type}); found #{coefficient_3} instead"
          end
          # coefficient 4
          coefficient_4 = pump.coefficient4ofthePartLoadPerformanceCurve
          unless (coefficient_4 - expected_coefficient_4).abs < 0.01
            failure_array << "Expected Coefficient 4 for #{pump.name} to be equal to #{expected_coefficient_4} (#{pump_type}); found #{coefficient_4} instead"
          end
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_cw_pumps(model, number_of_chillers, failure_array)
    # should be one constant speed pump per cooling tower with 19 W/gpm
    constant_speed_supply_pumps = []
    variable_speed_supply_pumps = []
    num_constant_speed_supply_pumps = 0
    num_variable_speed_supply_pumps = 0
    # get cw loop(s)
    cw_loops = []
    model.getChillerElectricEIRs.each do |chiller|
      if chiller.secondaryPlantLoop.is_initialized
        cw_loops << chiller.secondaryPlantLoop.get
        cw_loops = cw_loops.uniq
      else
        failure_array << "Chiller #{chiller.name} is not connected to a condenser loop"
      end
    end
    # get cw pump(s)
    cw_loops.each do |cw_loop|
      # supply side
      cw_loop.supplyComponents('OS_Pump_ConstantSpeed'.to_IddObjectType).each do |hp|
        num_constant_speed_supply_pumps += 1
        constant_speed_supply_pumps << hp.to_PumpConstantSpeed.get
      end
      cw_loop.supplyComponents('OS_HeaderedPumps_ConstantSpeed'.to_IddObjectType).each do |hp|
        hp = hp.to_HeaderedPumpsConstantSpeed.get
        num_constant_speed_supply_pumps += hp.numberofPumpsinBank
        constant_speed_supply_pumps << hp
      end
      cw_loop.supplyComponents('OS_Pump_VariableSpeed'.to_IddObjectType).each do |hp|
        num_variable_speed_supply_pumps += 1
        variable_speed_supply_pumps << hp.to_PumpVariableSpeed.get
      end
      cw_loop.supplyComponents('OS_HeaderedPumps_VariableSpeed'.to_IddObjectType).each do |hp|
        hp = hp.to_HeaderedPumpsVariableSpeed.get
        num_variable_speed_supply_pumps += hp.numberofPumpsinBank
        variable_speed_supply_pumps += hp * hp.numberofPumpsinBank
      end
    end
    # check number of pumps
    number_of_pumps = num_constant_speed_supply_pumps + num_variable_speed_supply_pumps
    unless number_of_pumps == number_of_chillers
      failure_array << "Expected #{number_of_chillers} supply-side condenser pumps because model has #{number_of_chillers} Chillers; found #{number_of_pumps} pump(s) instead"
    end
    # check type of pumps
    unless number_of_pumps == num_constant_speed_supply_pumps
      failure_array << "Expected supply-side condenser pumps to be of type ConstantSpeed, but #{number_of_pumps - num_constant_speed_supply_pumps} of #{number_of_pumps} pump(s) is/are of type VariableSpeed"
    end
    # check pump power
    expected_pump_watts_per_gpm = 19
    # constant speed
    constant_speed_supply_pumps.each do |pump|
      motor_efficiency = pump.motorEfficiency
      impeller_efficiency = 0.78
      pump_efficiency = motor_efficiency * impeller_efficiency
      pump_head_pa = pump.ratedPumpHead
      pump_head_ft = pump_head_pa / (12*249.09)
      pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
      unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
        failure_array << "Expected supply-side condenser pumps to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
      end
    end
    # variable speed
    variable_speed_supply_pumps.each do |pump|
      motor_efficiency = pump.motorEfficiency
      impeller_efficiency = 0.78
      pump_efficiency = motor_efficiency * impeller_efficiency
      pump_head_pa = pump.ratedPumpHead
      pump_head_ft = pump_head_pa / (12*249.09)
      pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
      unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
        failure_array << "Expected supply-side condenser pumps to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_hw_pumps(model, failure_array)
    # get floor area served by boiler(s)
    hw_loops = []
    hot_water_area_served_ft2 = 0
    zones_served = []
    # get hot water loop
    model.getBoilerHotWaters.each do |boiler|
      if boiler.plantLoop.is_initialized
        plant_loop = boiler.plantLoop.get
        next if plant_loop.name.get.to_s.include? "DHW" or plant_loop.name.get.to_s.include? "Service Water Heating"
        hw_loops << plant_loop
        hw_loops = hw_loops.uniq
      else
        failure_array << "Boiler #{boiler.name} is not attached to a Plant Loop"
      end
    end
    if hw_loops.length > 1
      failure_array << "Expected only one HW Loop"
    elsif  hw_loops.length == 0
      failure_array << "Could not find a hot water loop with a District Heating object"
    else
      # get area served by hot water coils
      hw_loops.each do |hw_loop|
        zones_served = calculate_zones_served_by_hot_water_loop(hw_loop, zones_served)
      end
      # calculate area served
      zones_served = zones_served.uniq
      zones_served.each do |zone|
        hot_water_area_served_ft2 += zone.floorArea * 10.7639
      end
      # should be one supply-side pump with 19 W/gpm
      if hw_loops.length == 1
        hw_loops.each do |hw_loop|
          # should be one variable speed pump on the supply side with 14 W/gpm (riding curve if HW loop serves less than 120,000 ft2)
          constant_speed_supply_pumps = hw_loop.supplyComponents('OS_Pump_ConstantSpeed'.to_IddObjectType)
          variable_speed_supply_pumps = hw_loop.supplyComponents('OS_Pump_VariableSpeed'.to_IddObjectType)
          number_of_pumps = constant_speed_supply_pumps.length + variable_speed_supply_pumps.length
          # check number of pumps
          unless number_of_pumps == 1
            failure_array << "Expected 1 supply-side pump for #{hw_loop.name}; found #{number_of_pumps} pump instead"
          end
          # check type of pumps
          unless number_of_pumps == variable_speed_supply_pumps.length
            failure_array << "Expected supply-side pump for #{hw_loop.name} to be of type VariableSpeed, but #{number_of_pumps - variable_speed_supply_pumps.length} of #{number_of_pumps} pump(s) is/are of type ConstantSpeed"
          end
          # check pump power
          expected_pump_watts_per_gpm = 19
          # constant speed
          constant_speed_supply_pumps.each do |pump|
            pump = pump.to_PumpConstantSpeed.get
            motor_efficiency = pump.motorEfficiency
            impeller_efficiency = 0.78
            pump_efficiency = motor_efficiency * impeller_efficiency
            pump_head_pa = pump.ratedPumpHead
            pump_head_ft = pump_head_pa / (12*249.09)
            pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
            unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
              failure_array << "Expected supply-side pumps for #{hw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
            end
          end
          # variable speed
          variable_speed_supply_pumps.each do |pump|
            pump = pump.to_PumpVariableSpeed.get
            motor_efficiency = pump.motorEfficiency
            impeller_efficiency = 0.78
            pump_efficiency = motor_efficiency * impeller_efficiency
            pump_head_pa = pump.ratedPumpHead
            pump_head_ft = pump_head_pa / (12*249.09)
            pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
            unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
              failure_array << "Expected supply-side pumps for #{hw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
            end
            # check pump curve
            if hot_water_area_served_ft2 < 120000
              # riding the curve
              pump_type = "Riding the Pump Curve"
              expected_coefficient_1 = 0
              expected_coefficient_2 = 3.2485
              expected_coefficient_3 = -4.7443
              expected_coefficient_4 = 2.5294
            else
              # variable speed drive
              pump_type = "Variable Speed Drive"
              expected_coefficient_1 = 0
              expected_coefficient_2 = 0.5726
              expected_coefficient_3 = -0.301
              expected_coefficient_4 = 0.7347
            end
            # coefficient 1
            coefficient_1 = pump.coefficient1ofthePartLoadPerformanceCurve
            unless (coefficient_1 - expected_coefficient_1).abs < 0.01
              failure_array << "Expected Coefficient 1 for #{pump.name} to be equal to #{expected_coefficient_1} (#{pump_type}); found #{coefficient_1} instead"
            end
            # coefficient 2
            coefficient_2 = pump.coefficient2ofthePartLoadPerformanceCurve
            unless (coefficient_2 - expected_coefficient_2).abs < 0.01
              failure_array << "Expected Coefficient 2 for #{pump.name} to be equal to #{expected_coefficient_2} (#{pump_type}); found #{coefficient_2} instead"
            end
            # coefficient 3
            coefficient_3 = pump.coefficient3ofthePartLoadPerformanceCurve
            unless (coefficient_3 - expected_coefficient_3).abs < 0.01
              failure_array << "Expected Coefficient 3 for #{pump.name} to be equal to #{expected_coefficient_3} (#{pump_type}); found #{coefficient_3} instead"
            end
            # coefficient 4
            coefficient_4 = pump.coefficient4ofthePartLoadPerformanceCurve
            unless (coefficient_4 - expected_coefficient_4).abs < 0.01
              failure_array << "Expected Coefficient 4 for #{pump.name} to be equal to #{expected_coefficient_4} (#{pump_type}); found #{coefficient_4} instead"
            end
          end
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_district_hw_pumps(model, failure_array)
    # get floor area served by district heating
    hw_loops = []
    hot_water_area_served_ft2 = 0
    zones_served = []
    # get hot water loop
    if model.version < OpenStudio::VersionString.new('3.7.0')
      district_heatings = model.getDistrictHeatings
    else
      district_heatings = model.getDistrictHeatingWaters
    end
    district_heatings.each do |district_heating|
      if district_heating.plantLoop.is_initialized
        plant_loop = district_heating.plantLoop.get
        next if plant_loop.name.get.to_s.include? "DHW" or plant_loop.name.get.to_s.include? "Service Water Heating"
        hw_loops << plant_loop
        hw_loops = hw_loops.uniq
      else
        failure_array << "District Heating #{district_heating.name} is not attached to a Plant Loop"
      end
    end
    if hw_loops.length > 1
      failure_array << "Expected only one HW Loop"
    elsif  hw_loops.length == 0
      failure_array << "Could not find a hot water loop with a District Heating object"
    else
      # get area served by hot water coils
      hw_loops.each do |hw_loop|
        zones_served = calculate_zones_served_by_hot_water_loop(hw_loop, zones_served)
      end
      # calculate area served
      zones_served = zones_served.uniq
      zones_served.each do |zone|
        hot_water_area_served_ft2 += zone.floorArea * 10.7639
      end
      # should be one supply-side pump with 14 W/gpm
      if hw_loops.length == 1
        hw_loops.each do |hw_loop|
          # should be one variable speed pump on the supply side with 14 W/gpm (riding curve if HW loop serves less than 120,000 ft2)
          constant_speed_supply_pumps = hw_loop.supplyComponents('OS_Pump_ConstantSpeed'.to_IddObjectType)
          variable_speed_supply_pumps = hw_loop.supplyComponents('OS_Pump_VariableSpeed'.to_IddObjectType)
          number_of_pumps = constant_speed_supply_pumps.length + variable_speed_supply_pumps.length
          # check number of pumps
          unless number_of_pumps == 1
            failure_array << "Expected 1 supply-side pump for #{hw_loop.name}; found #{number_of_pumps} pump instead"
          end
          # check type of pumps
          unless number_of_pumps == variable_speed_supply_pumps.length
            failure_array << "Expected supply-side pump for #{hw_loop.name} to be of type VariableSpeed, but #{number_of_pumps - variable_speed_supply_pumps.length} of #{number_of_pumps} pump(s) is/are of type ConstantSpeed"
          end
          # check pump power
          expected_pump_watts_per_gpm = 14
          # constant speed
          constant_speed_supply_pumps.each do |pump|
            pump = pump.to_PumpConstantSpeed.get
            motor_efficiency = pump.motorEfficiency
            impeller_efficiency = 0.78
            pump_efficiency = motor_efficiency * impeller_efficiency
            pump_head_pa = pump.ratedPumpHead
            pump_head_ft = pump_head_pa / (12*249.09)
            pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
            unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
              failure_array << "Expected supply-side pumps for #{hw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
            end
          end
          # variable speed
          variable_speed_supply_pumps.each do |pump|
            pump = pump.to_PumpVariableSpeed.get
            motor_efficiency = pump.motorEfficiency
            impeller_efficiency = 0.78
            pump_efficiency = motor_efficiency * impeller_efficiency
            pump_head_pa = pump.ratedPumpHead
            pump_head_ft = pump_head_pa / (12*249.09)
            pump_watts_per_gpm = pump_head_ft / (5.302*pump_efficiency)
            unless (pump_watts_per_gpm - expected_pump_watts_per_gpm).abs < 0.05
              failure_array << "Expected supply-side pumps for #{hw_loop.name} to be #{expected_pump_watts_per_gpm} W/gpm; #{pump.name} is #{pump_watts_per_gpm.round(2)} W/gpm"
            end
            # check pump curve
            if hot_water_area_served_ft2 < 120000
              # riding the curve
              pump_type = "Riding the Pump Curve"
              expected_coefficient_1 = 0
              expected_coefficient_2 = 3.2485
              expected_coefficient_3 = -4.7443
              expected_coefficient_4 = 2.5294
            else
              # variable speed drive
              pump_type = "Variable Speed Drive"
              expected_coefficient_1 = 0
              expected_coefficient_2 = 0.5726
              expected_coefficient_3 = -0.301
              expected_coefficient_4 = 0.7347
            end
            # coefficient 1
            coefficient_1 = pump.coefficient1ofthePartLoadPerformanceCurve
            unless (coefficient_1 - expected_coefficient_1).abs < 0.01
              failure_array << "Expected Coefficient 1 for #{pump.name} to be equal to #{expected_coefficient_1} (#{pump_type}); found #{coefficient_1} instead"
            end
            # coefficient 2
            coefficient_2 = pump.coefficient2ofthePartLoadPerformanceCurve
            unless (coefficient_2 - expected_coefficient_2).abs < 0.01
              failure_array << "Expected Coefficient 2 for #{pump.name} to be equal to #{expected_coefficient_2} (#{pump_type}); found #{coefficient_2} instead"
            end
            # coefficient 3
            coefficient_3 = pump.coefficient3ofthePartLoadPerformanceCurve
            unless (coefficient_3 - expected_coefficient_3).abs < 0.01
              failure_array << "Expected Coefficient 3 for #{pump.name} to be equal to #{expected_coefficient_3} (#{pump_type}); found #{coefficient_3} instead"
            end
            # coefficient 4
            coefficient_4 = pump.coefficient4ofthePartLoadPerformanceCurve
            unless (coefficient_4 - expected_coefficient_4).abs < 0.01
              failure_array << "Expected Coefficient 4 for #{pump.name} to be equal to #{expected_coefficient_4} (#{pump_type}); found #{coefficient_4} instead"
            end
          end
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_chw_controls(model, failure_array)
    # get chilled water loops
    chw_loops = []
    model.getDistrictCoolings.each do |district_cooling|
      if district_cooling.plantLoop.is_initialized
        chw_loops << district_cooling.plantLoop.get
        chw_loops = chw_loops.uniq
      else
        failure_array << "DistrictCooling #{district_cooling.name} is not connected to a plant loop"
      end
    end
    model.getChillerElectricEIRs.each do |chiller|
      if chiller.plantLoop.is_initialized
        chw_loops << chiller.plantLoop.get
        chw_loops = chw_loops.uniq
      else
        failure_array << "Chiller #{chiller.name} is not connected to a plant loop"
      end
    end
    if chw_loops.length > 1
      failure_array << "Expected 1 CHW Loop; found #{chw_loops.length}"
    elsif  chw_loops.length == 0
      failure_array << "Could not find a chilled water loop with a Chiller or DistrictCooling object"
    else
      chw_loops.each do |chw_loop|
        found_correct_setpoint_manager = false
        # get temperature setpoint manager
        model.getSetpointManagerOutdoorAirResets.each do |oa_reset_manager|
          next unless oa_reset_manager.plantLoop.is_initialized
          plant_loop = oa_reset_manager.plantLoop.get
          next unless plant_loop == chw_loop
          found_correct_setpoint_manager = true
          # check setpoint manager inputs
          expected_oa_high_temp = (80 - 32)/1.8
          expected_oa_low_temp = (60 - 32)/1.8
          expected_setpoint_at_oa_high_temp = (44 - 32)/1.8
          expected_setpoint_at_oa_low_temp = (54 - 32)/1.8
          oa_high_temp = oa_reset_manager.outdoorHighTemperature
          oa_low_temp = oa_reset_manager.outdoorLowTemperature
          setpoint_at_oa_high_temp = oa_reset_manager.setpointatOutdoorHighTemperature
          setpoint_at_oa_low_temp = oa_reset_manager.setpointatOutdoorLowTemperature
          unless (expected_oa_high_temp - oa_high_temp).abs < 0.05
            failure_array << "Expected OA High Temp to be #{(expected_oa_high_temp*1.8+32).round(2)} F for OA Reset Manager on #{chw_loop.name}; found #{(oa_high_temp*1.8+32).round(2)} F instead"
          end
          unless (expected_oa_low_temp - oa_low_temp).abs < 0.05
            failure_array << "Expected OA Low Temp to be #{(expected_oa_low_temp*1.8+32).round(2)} F for OA Reset Manager on #{chw_loop.name}; found #{(oa_low_temp*1.8+32).round(2)} F instead"
          end
          unless (expected_setpoint_at_oa_high_temp - setpoint_at_oa_high_temp).abs < 0.05
            failure_array << "Expected Setpoint at OA High Temp to be #{(expected_setpoint_at_oa_high_temp*1.8+32).round(2)} F for OA Reset Manager on #{chw_loop.name}; found #{(setpoint_at_oa_high_temp*1.8+32).round(2)} F instead"
          end
          unless (expected_setpoint_at_oa_low_temp - setpoint_at_oa_low_temp).abs < 0.05
            failure_array << "Expected Setpoint at OA Low Temp to be #{(expected_setpoint_at_oa_low_temp*1.8+32).round(2)} F for OA Reset Manager on #{chw_loop.name}; found #{(setpoint_at_oa_low_temp*1.8+32).round(2)} F instead"
          end
        end
        unless found_correct_setpoint_manager
          failure_array << "Expected to find Setpoint Manager of Type OA Reset for #{chw_loop.name} but did not"
        end
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_cw_controls(model, failure_array)
    # get condenser water loops
    cw_loops = []
    model.getCoolingTowerVariableSpeeds.each do |cooling_tower|
      if cooling_tower.plantLoop.is_initialized
        cw_loops << cooling_tower.plantLoop.get
        cw_loops = cw_loops.uniq
      else
        failure_array << "Cooling Tower #{cooling_tower.name} is not connected to a plant loop"
      end
    end
    design_wb_f_global = nil
    expected_offset_temperature_difference_global = nil
    cw_loops.each do |cw_loop|
      found_correct_setpoint_manager = false
      # get temperature setpoint manager
      model.getSetpointManagerFollowOutdoorAirTemperatures.each do |follow_oa_manager|
        next unless follow_oa_manager.plantLoop.is_initialized
        plant_loop = follow_oa_manager.plantLoop.get
        next unless plant_loop == cw_loop
        found_correct_setpoint_manager = true
        # check setpoint manager inputs
        # control variable
        control_variable = follow_oa_manager.controlVariable
        unless control_variable == "Temperature"
          failure_array << "Expected Control Variable for #{follow_oa_manager.name} to be 'Temperature'; found '#{control_variable}' instead"
        end
        # reference temperature type
        reference_temperature_type = follow_oa_manager.referenceTemperatureType
        unless reference_temperature_type == "OutdoorAirWetBulb"
          failure_array << "Expected Reference Temperature Type for #{follow_oa_manager.name} to be 'OutdoorAirWetBulb'; found '#{reference_temperature_type}' instead"
        end
        # offset temperature difference
        offset_temperature_difference_k = follow_oa_manager.offsetTemperatureDifference
        offset_temperature_difference_r = offset_temperature_difference_k * 1.8
        # get relevant design day
        design_wb_f_max = nil
        model.getDesignDays.each do |design_day|
          design_day_name = design_day.name.get.to_s
          next unless design_day.dayType == "SummerDesignDay"
          next unless design_day_name.include? "WB=>MDB"

          if model.version < OpenStudio::VersionString.new('3.3.0')
            next unless design_day.humidityIndicatingType == "Wetbulb"
            design_wb_c = design_day.humidityIndicatingConditionsAtMaximumDryBulb
            design_wb_f = OpenStudio.convert(design_wb_c, 'C', 'F').get
          else
            next unless design_day.humidityConditionType == "Wetbulb"
            if design_day.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
              design_wb_c = design_day.wetBulbOrDewPointAtMaximumDryBulb
              design_wb_f = OpenStudio.convert(design_wb_c, 'C', 'F').get
            end
          end

          if design_wb_f_max.nil?
            design_wb_f_max = design_wb_f
          else
            if design_wb_f > design_wb_f_max
              design_wb_f_max = design_wb_f
            end
          end
        end
        if design_wb_f_max.nil?
          design_wb_f_max = 78
        elsif design_wb_f_max > 80
          design_wb_f_max = 80
        elsif  design_wb_f_max < 55
          design_wb_f_max = 55
        end
        design_wb_f_global = design_wb_f_max
        expected_offset_temperature_difference_r = 25.72 - (0.24 * design_wb_f_max)
        expected_offset_temperature_difference_global = expected_offset_temperature_difference_r
        expected_maximum_setpoint_temperature_f = design_wb_f_max + expected_offset_temperature_difference_r
        if expected_maximum_setpoint_temperature_f < 70
          expected_maximum_setpoint_temperature_f = 70
        end
        # minimum setpoint temperature
        minimum_setpoint_temperature_c = follow_oa_manager.minimumSetpointTemperature
        minimum_setpoint_temperature_f = OpenStudio.convert(minimum_setpoint_temperature_c, 'C', 'F').get
        unless (70 - minimum_setpoint_temperature_f).abs < 0.05
          failure_array << "Expected Minimum Setpoint Temperature for #{follow_oa_manager.name} to be 70 F; found #{minimum_setpoint_temperature_f.round(2)} F instead"
        end
        unless (expected_offset_temperature_difference_r - offset_temperature_difference_r).abs < 0.05
          failure_array << "Expected Offset Temperature Difference for #{follow_oa_manager.name} to be #{expected_offset_temperature_difference_r.round(2)} F; found #{offset_temperature_difference_r.round(2)} F instead"
        end
        # maximum setpoint temperature
        maximum_setpoint_temperature_c = follow_oa_manager.maximumSetpointTemperature
        maximum_setpoint_temperature_f = OpenStudio.convert(maximum_setpoint_temperature_c, 'C', 'F').get
        unless (expected_maximum_setpoint_temperature_f - maximum_setpoint_temperature_f).abs < 0.05
          failure_array << "Expected Maximum Setpoint Temperature for #{follow_oa_manager.name} to be #{expected_maximum_setpoint_temperature_f.round(2)} F; found #{maximum_setpoint_temperature_f.round(2)} F instead"
        end
      end
      unless found_correct_setpoint_manager
        failure_array << "Expected to find Setpoint Manager of Type Follow OA for #{cw_loop.name} but did not"
      end
    end
    # check cooling tower inputs
    model.getCoolingTowerVariableSpeeds.each do |cooling_tower|
      next unless cooling_tower.plantLoop.is_initialized
      # check cooling tower inputs
      # design oa wb (should match design day condition
      if cooling_tower.designInletAirWetBulbTemperature.is_initialized
        design_inlet_air_wb_c = cooling_tower.designInletAirWetBulbTemperature.get
        design_inlet_air_wb_f = OpenStudio.convert(design_inlet_air_wb_c, 'C', 'F').get
        next if design_wb_f_global.nil?
        if design_wb_f_global < 68
          design_wb_f_global = 68
        end
        unless (design_inlet_air_wb_f - design_wb_f_global).abs < 0.05
          failure_array << "Expected Design Inlet Air WB to be #{design_wb_f_global.round(2)} F (matching WB Design Day condition) for #{cooling_tower.name}; found #{design_inlet_air_wb_f.round(2)} F instead"
        end
      else
        failure_array << "Expected Design Inlet Air WB to be specified for #{cooling_tower.name}"
      end
      # approach (should match setpoint manager temperature difference
      if cooling_tower.designApproachTemperature.is_initialized
        approach_k = cooling_tower.designApproachTemperature.get
        approach_r = approach_k * 1.8
        next if expected_offset_temperature_difference_global.nil?
        unless (expected_offset_temperature_difference_global - approach_r).abs < 0.05
          failure_array << "Expected Approach to be #{expected_offset_temperature_difference_global.round(2)} F for #{cooling_tower.name}; found #{approach_r.round(2)} F instead"
        end
      else
        failure_array << "Expected Approach to be specified for #{cooling_tower.name}"
      end
      if cooling_tower.designRangeTemperature.is_initialized
        # range (10 F)
        range_k = cooling_tower.designRangeTemperature.get
        range_r = range_k * 1.8
        unless (range_r - 10).abs < 0.05
          failure_array << "Expected Range to be 10 F for #{cooling_tower.name}; found #{range_r.round(2)} F instead"
        end
      else
        failure_array << "Expected Range to be specified for #{cooling_tower.name}"
      end
    end
    return failure_array
  end

  # @author Matt Leach, NORESCO
  def check_hw_controls(model, failure_array)
    # get hot water loops
    hw_loops = []
    if model.version < OpenStudio::VersionString.new('3.7.0')
      district_heatings = model.getDistrictHeatings
    else
      district_heatings = model.getDistrictHeatingWaters
    end
    district_heatings.each do |district_heating|
      if district_heating.plantLoop.is_initialized
        next if district_heating.plantLoop.get.name.get.to_s.include? "DHW" or district_heating.plantLoop.get.name.get.to_s.include? "Service Water Heating"
        hw_loops << district_heating.plantLoop.get
        hw_loops = hw_loops.uniq
      else
        failure_array << "DistrictHeating #{district_heating.name} is not connected to a plant loop"
      end
    end
    model.getBoilerHotWaters.each do |boiler|
      if boiler.plantLoop.is_initialized
        next if boiler.plantLoop.get.name.get.to_s.include? "DHW" or boiler.plantLoop.get.name.get.to_s.include? "Service Water Heating"
        hw_loops << boiler.plantLoop.get
        hw_loops = hw_loops.uniq
      else
        failure_array << "Boiler #{boiler.name} is not connected to a plant loop"
      end
    end
    if hw_loops.length > 1
      failure_array << "Expected 1 HW Loop; found #{hw_loops.length}"
    elsif  hw_loops.length == 0
      failure_array << "Could not find a hot water loop with a Boiler or DistrictHeating object"
    else
      hw_loops.each do |hw_loop|
        found_correct_setpoint_manager = false
        # get temperature setpoint manager
        model.getSetpointManagerOutdoorAirResets.each do |oa_reset_manager|
          next unless oa_reset_manager.plantLoop.is_initialized
          plant_loop = oa_reset_manager.plantLoop.get
          next unless plant_loop == hw_loop
          found_correct_setpoint_manager = true
          # check setpoint manager inputs
          expected_oa_high_temp = (50 - 32)/1.8
          expected_oa_low_temp = (20 - 32)/1.8
          expected_setpoint_at_oa_high_temp = (150 - 32)/1.8
          expected_setpoint_at_oa_low_temp = (180 - 32)/1.8
          oa_high_temp = oa_reset_manager.outdoorHighTemperature
          oa_low_temp = oa_reset_manager.outdoorLowTemperature
          setpoint_at_oa_high_temp = oa_reset_manager.setpointatOutdoorHighTemperature
          setpoint_at_oa_low_temp = oa_reset_manager.setpointatOutdoorLowTemperature
          unless (expected_oa_high_temp - oa_high_temp).abs < 0.05
            failure_array << "Expected OA High Temp to be #{(expected_oa_high_temp*1.8+32).round(2)} F for OA Reset Manager on #{hw_loop.name}; found #{(oa_high_temp*1.8+32).round(2)} F instead"
          else
          end
          unless (expected_oa_low_temp - oa_low_temp).abs < 0.05
            failure_array << "Expected OA Low Temp to be #{(expected_oa_low_temp*1.8+32).round(2)} F for OA Reset Manager on #{hw_loop.name}; found #{(oa_low_temp*1.8+32).round(2)} F instead"
          end
          unless (expected_setpoint_at_oa_high_temp - setpoint_at_oa_high_temp).abs < 0.05
            failure_array << "Expected Setpoint at OA High Temp to be #{(expected_setpoint_at_oa_high_temp*1.8+32).round(2)} F for OA Reset Manager on #{hw_loop.name}; found #{(setpoint_at_oa_high_temp*1.8+32).round(2)} F instead"
          end
          unless (expected_setpoint_at_oa_low_temp - setpoint_at_oa_low_temp).abs < 0.05
            failure_array << "Expected Setpoint at OA Low Temp to be #{(expected_setpoint_at_oa_low_temp*1.8+32).round(2)} F for OA Reset Manager on #{hw_loop.name}; found #{(setpoint_at_oa_low_temp*1.8+32).round(2)} F instead"
          end
        end
        unless found_correct_setpoint_manager
          failure_array << "Expected to find Setpoint Manager of Type OA Reset for #{hw_loop.name} but did not"
        end
      end
    end
    return failure_array
  end

  # method to calculate oa rate per space in m3/s
  # @author Matt Leach, NORESCO
  def calculate_oa_per_space(space)
    space_oa_rate = 0
    if space.spaceType.is_initialized
      space_type = space.spaceType.get
      # get space area
      space_area = space.floorArea
      # get space volume
      space_volume = space.volume
      # get number of people
      people = 0
      space_type_name = space_type.name.get.to_s
      space_type.people.each do |people_object|
        people_definition = people_object.peopleDefinition
        # get people calc method
        people_calc_method = people_definition.numberofPeopleCalculationMethod
        if people_calc_method == "People"
          next unless people_definition.numberofPeople.is_initialized
          people += people_definition.numberofPeople.get
        elsif people_calc_method == "People/Area"
          next unless people_definition.peopleperSpaceFloorArea.is_initialized
          people += (people_definition.peopleperSpaceFloorArea.get * space_area)
        elsif people_calc_method == "Area/Person"
          next unless people_definition.spaceFloorAreaperPerson.is_initialized
          people += (space_area / people_definition.spaceFloorAreaperPerson.get)
        end
      end
      # calculate min flow rate for space from design spec oa object
      if space_type.designSpecificationOutdoorAir.is_initialized
        design_oa_spec = space_type.designSpecificationOutdoorAir.get
        # calculate space outside air requirement from design spec outside air object
        design_oa_spec_method = design_oa_spec.outdoorAirMethod
        if design_oa_spec_method == "Flow/Person"
          space_oa_rate = people*design_oa_spec.outdoorAirFlowperPerson
        elsif design_oa_spec_method == "Flow/Area"
          space_oa_rate = space_area*design_oa_spec.outdoorAirFlowperFloorArea
        elsif design_oa_spec_method == "Flow/Zone"
          space_oa_rate = design_oa_spec.outdoorAirFlowRate
        elsif design_oa_spec_method == "AirChanges/Hour"
          space_oa_rate = space_volume*design_oa_spec.outdoorAirFlowAirChangesperHour/3600
        elsif design_oa_spec_method == "Sum"
          space_oa_rate = people*design_oa_spec.outdoorAirFlowperPerson + space_area*design_oa_spec.outdoorAirFlowperFloorArea + design_oa_spec.outdoorAirFlowRate + space_volume*design_oa_spec.outdoorAirFlowAirChangesperHour/3600
        elsif design_oa_spec_method == "Maximum"
          space_oa_rate = [people*design_oa_spec.outdoorAirFlowperPerson,space_area*design_oa_spec.outdoorAirFlowperFloorArea,design_oa_spec.outdoorAirFlowRate,space_volume*design_oa_spec.outdoorAirFlowAirChangesperHour/3600].max
        end
      end
    end
    return space_oa_rate
  end

end



