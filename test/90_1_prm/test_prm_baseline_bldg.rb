require_relative '../helpers/minitest_helper'
require_relative 'create_performance_rating_method_helper'
require_relative 'baseline_901_2013_helper'

class Baseline9012013Test < Minitest::Test

  include Baseline9012013

  # @author Matt Steen, Eric Ringold, Ambient Energy
  def test_bldg_14_coil_efficiencies
    base_model = create_baseline_model('bldg_14', '90.1-2013', 'ASHRAE 169-2013-5B', 'Warehouse','Xcel Energy CO EDA', false, true)
    check_coil_efficiencies(base_model)
  end

  # @author Matt Steen, Eric Ringold, Ambient Energy
  def test_bldg_14_ventilation_rates
    test_model_name = 'bldg_14'
    base_model = create_baseline_model(test_model_name, '90.1-2013', 'ASHRAE 169-2013-5B', 'Warehouse','Xcel Energy CO EDA', false, true)
    prop_model = load_test_model(test_model_name)
    check_ventilation_rates(base_model, prop_model)
  end

  # @author Taylor Roberts, Group14 Engineering
  def test_bldg_15_retail_standalone
    # Create the baseline model
    model = create_baseline_model('bldg_15', '90.1-2013', 'ASHRAE 169-2013-5B', 'RetailStandalone','Xcel Energy CO EDA', false, true)

    # Conditions expected to be true in the baseline model
    # Check that the office system is a VAV system
    zone = model.getThermalZoneByName("15.Office.Cs Zone").get
    air_terminal = zone.airLoopHVACTerminal.get
    assert(air_terminal.to_AirTerminalSingleDuctVAVReheat.is_initialized, "Office HVAC is not correct, it should be a VAV with hot water heating.  Wrong terminal type.")
    has_hw_coil = false
    air_terminal.airLoopHVAC.get.supplyComponents.each do |supply_component|
      htg_coil = supply_component.to_CoilHeatingWater
      if htg_coil.is_initialized
        has_hw_coil = true
      end
    end
    assert(has_hw_coil, "Office HVAC is not correct, it should be a VAV with hot water heating.  No HW coil found.")

    # Check that their is chilled water system
    model.getPlantLoops.each do |plant_loop|
      next unless plant_loop.sizingPlant.loopType == 'Cooling'
      has_cooling_equip = false
      plant_loop.supplyComponents.each do |supply_component|
        if supply_component.to_ChillerElectricEIR.is_initialized
          has_cooling_equip = true
        end
      end

      # check if secondary loop
      unless has_cooling_equip
        plant_loop.supplyComponents.each do |supply_component|
          if supply_component.to_HeatExchangerFluidToFluid.is_initialized
            has_cooling_equip = true
          end
        end
      end

      assert(has_cooling_equip, "Office HVAC is not correct, it should be a VAV with CHW.  Missing chiller or HX.")
    end #The measure did this correctly

    # Check in window to wall ratio
    total_window_area = 0.0
    model.getSubSurfaces.each do |sub_surface|
      if sub_surface.subSurfaceType == "FixedWindow"
        window_area = sub_surface.grossArea
        total_window_area += window_area
      end
    end
    # The measure did this correctly
    # assert_in_delta(4750, total_window_area, 50.0, "Window area is wrong.")
  end

  # @author Taylor Roberts, Group14 Engineering
  def test_bldg_16_medium_office
    # Create the baseline model
    model = create_baseline_model('bldg_16', '90.1-2013', 'ASHRAE 169-2013-5B', 'MediumOffice','Xcel Energy CO EDA', false, true)

    # Conditions expected to be true in the baseline model
    # Lighting Power Density
    # Open Office LPD should be 0.98 W/ft2
    space = model.getSpaceByName("9.OpenOffice 2").get
    lpd_w_per_m2 = space.lightingPowerPerFloorArea
    lpd_w_per_ft2 = OpenStudio.convert(lpd_w_per_m2,'W/m^2','W/ft^2').get
    assert_in_delta(0.98, lpd_w_per_ft2, 0.01, "Open Office LPD is wrong.") #The measure did this correctly

    # Conference LPD should be 1.23 W/ft2
    space = model.getSpaceByName("9.Conference 1").get
    lpd_w_per_m2 = space.lightingPowerPerFloorArea
    lpd_w_per_ft2 = OpenStudio.convert(lpd_w_per_m2,'W/m^2','W/ft^2').get
    assert_in_delta(1.23, lpd_w_per_ft2, 0.01, "Conference LPD is wrong.") #The measure did this correctly

    # Parking Garage LPD should be 0.19 W/sf
    # *** There is no "Standards Space Type" for Parking Garage ***
    # *** Currently, the space is tagged as office-storage, which has an LPD of 0.63 W/sf ***
    # space = model.getSpaceByName("P3.Parking Garage").get
    # lpd_w_per_m2 = space.lightingPowerPerFloorArea
    # lpd_w_per_ft2 = OpenStudio.convert(lpd_w_per_m2,'W/m^2','W/ft^2').get
    # assert_in_delta(0.19, lpd_w_per_ft2, 0.01, "Parking Garage LPD is wrong.")

    # Occupancy Vacancy Controls
    # Not sure how to check for this Andrew
    # The baseline model should a 10% schedule reduction for all the zones that occupancy sensors are required in
    # BUT because they are required they should already be in the proposed model so really the baseline doesn't have to change anything for those zones
    # for the zones it is NOT required in but the proposed has a schedule adjustment the baseline should go back to the orginal schedule
    # how to do this I am not sure, but maybe they will need to have a flag

    # Daylighting Controls

    # OpenOffice Zones with glass should have daylighting
    zone = model.getThermalZoneByName("9.OpenOffice 16 Zone").get
    primary_daylighting_control = zone.primaryDaylightingControl
    if primary_daylighting_control.is_initialized
      # Zone info - 1,359.5 ft2 zone area, >300 W so primary and secondary sidelighted area
      # Primary sidelighted area - 7'3" head height, 48' 2 11/16" glass and wall width, 349.6 ft2 daylighting area,  25.7% of zone controlled
      primary_fraction_daylight = zone.fractionofZoneControlledbyPrimaryDaylightingControl
      assert_in_delta(0.257, primary_fraction_daylight, 0.02, "Daylighting Control Fraction is wrong.")
      primary_dl_control = primary_daylighting_control.get.lightingControlType
      assert_equal("Stepped", primary_dl_control, "Daylighting control is not correct, it should be Stepped")
    end #The measure did NOT do this correctly - no daylighting control here at all
    secondary_daylighting_control = zone.secondaryDaylightingControl
    if secondary_daylighting_control.is_initialized
      # Zone info - 1,359.5 ft2 zone area, >300 W so primary and secondary sidelighted area
      # Primary sidelighted area - 7'3" head height, 48' 2 11/16" glass and wall width, 174.8 ft2 daylighting area,  12.9% of zone controlled
      secondary_fraction_daylight = zone.fractionofZoneControlledbySecondaryDaylightingControl
      #assert_in_delta(0.129, secondary_fraction_daylight, 0.02, "Daylighting Control Fraction is wrong.")
      secondary_dl_control = secondary_daylighting_control.get.lightingControlType
      assert_equal("Stepped", secondary_dl_control, "Daylighting control is not correct, it should be Stepped")
    end #The measure did NOT do this correctly - no daylighting control here at all

    # OpenOffice Zones with out glass should NOT have daylighting
    zone = model.getThermalZoneByName("9.OpenOffice Zone").get
    primary_daylighting_control = zone.primaryDaylightingControl
    assert(primary_daylighting_control.empty?, "Daylighting control is in zones with no windows")

    # Retail Zones with windows (no skylights) should NOT have daylighting
    zone = model.getThermalZoneByName("1.Retail 2 Zone").get
    primary_daylighting_control = zone.primaryDaylightingControl
    #assert(primary_daylighting_control.empty?, "Daylighting control is in Retail zones, but should not be.")
    #The measure did NOT do this correctly - there is a daylighting control present
  end

  # @author Taylor Roberts, Group14 Engineering
  def test_bldg_17_midrise_apartment_lowrise_iecc_constructions
    # Create the baseline model
    model = create_baseline_model('bldg_17', '90.1-2013', 'ASHRAE 169-2013-5B', 'MidriseApartment','Xcel Energy CO EDA', false, true)

    # Conditions expected to be true in the baseline model

    # *** Note, the point of this test to to test for under three story apartment buildings ***
    # *** Might need a lowrise apartment building type for this ***
    # *** EDA protocol requires that low rise <3 stories residential buildings have baselines with IECC constructions ***

    # Climate zone 5B Residential IECC U-values
    # Walls - 0.06 Btu/ft2*h*F
    # Roof - 0.026 Btu/ft2*h*F
    # Windows - 0.32 Btu/ft2*h*F  note no non-metal or metal, just 0.32 for everything
    # Envelope properties
    # Check for wall construction properties
    space = model.getSpaceByName("3.Apartment 13").get
    space.surfaces.each do |surface|
      if surface.surfaceType == "Wall" && surface.outsideBoundaryCondition == "Outdoors"
        u_value_si = surface.construction.get.thermalConductance.get
        u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
        assert_in_delta(0.06, u_value_ip, 0.003, "Exterior Wall U-value is not correct")
      end
    end

    # Check for wall construction properties
    space = model.getSpaceByName("3.Apartment 13").get
    space.surfaces.each do |surface|
      if surface.surfaceType == "Roof" && surface.outsideBoundaryCondition == "Outdoors"
        u_value_si = surface.construction.get.thermalConductance.get
        u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
        assert_in_delta(0.026, u_value_ip, 0.003, "Roof U-value is not correct")
      end
    end

    # Check for window construction properties
    space = model.getSpaceByName("3.Apartment 13").get
    space.surfaces.each do |surface|
      surface.subSurfaces.each do |sub_surface|
        if sub_surface.subSurfaceType == "FixedWindow" && sub_surface.outsideBoundaryCondition == "Outdoors"
          u_value_si = sub_surface.construction.get.to_Construction.get.uFactor.get
          u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
          assert_in_delta(0.32, u_value_ip, 0.01, "Window u-value is wrong.")
        end
      end
    end
    # The measure also made a VAV system to serve the apartment units, which should be served by a PTHP system
    # Another issue is that the measure deleted the exhuast fans from the apartment units, which are used for the ventilation strategy
  end

  # @author Taylor Roberts, Group14 Engineering
  def test_bldg_18_retail_standalone
    # Create the baseline model
    model = create_baseline_model('bldg_18', '90.1-2013', 'ASHRAE 169-2013-5B', 'RetailStandalone','Xcel Energy CO EDA', false, true)

    # # Conditions expected to be true in the baseline model
    # # Skylight properties
    # # Check for skylight construction properties
    # space = model.getSpaceByName("2.Retail 12").get
    # space.surfaces.each do |surface|
    #   surface.subSurfaces.each do |sub_surface|
    #     if sub_surface.subSurfaceType == "Skylight" and sub_surface.outsideBoundaryCondition == "Outdoors"
    #       sub_surface_construction = sub_surface.construction.get.to_Construction.get
    #       u_value_si = sub_surface_construction.uFactor
    #       u_value_si = u_value_si.get
    #       u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
    #       assert_in_delta(0.50, u_value_ip, 0.04, "Skylight U-value is wrong.") #ashrae 90.1-2013 skylight u-value of 0.50
    #     end
    #   end
    # end

    # Check for reduction in total skylight area to meet 3% SRR
    total_skylight_area = 0.0
    model.getSubSurfaces.each do |sub_surface|
      if sub_surface.subSurfaceType == "Skylight"
        total_skylight_area += sub_surface.grossArea
      end
    end
    assert_in_delta(330, total_skylight_area, 1.0, "Skylight area is wrong.") #The measure did this correctly

    # Retail zones should have PSZ with gas heat
    zone = model.getThermalZoneByName("2.Retail 12 Zone").get
    air_terminal = zone.airLoopHVACTerminal.get
    assert(air_terminal.to_AirTerminalSingleDuctUncontrolled.is_initialized, "Retail HVAC is not correct, it should be a PSZ with Gas Heating.  Wrong terminal type.")
    has_gas_ht = false
    air_terminal.airLoopHVAC.get.supplyComponents.each do |supply_component|
      if supply_component.to_AirLoopHVACUnitarySystem.is_initialized
        htg_coil = supply_component.to_AirLoopHVACUnitarySystem.get.heatingCoil
      else
        htg_coil = supply_component.to_CoilHeatingGas
      end
      if htg_coil.is_initialized
        has_gas_ht = true
      end
    end
    assert(has_gas_ht, "Retail HVAC is not correct, it should be a PSZ with Gas Heating.  Gas heating coil missing.")
    # The measure did NOT do this correctly - all retail zones should have PSZ systems not a VAV system
  end

  # @author Taylor Roberts, Group14 Engineering
  def known_fail_test_bldg_19_medium_office
    # Create the baseline model
    model = create_baseline_model('bldg_19', '90.1-2013', 'ASHRAE 169-2013-5B', 'MediumOffice','Xcel Energy CO EDA', false, true)

    # Conditions expected to be true in the baseline model
    # Check that the office system is a VAV system
    zone = model.getThermalZoneByName("12.Office.C1 Zone").get
    air_terminal = zone.airLoopHVACTerminal.get
    assert(air_terminal.to_AirTerminalSingleDuctVAVReheat.is_initialized, "Office HVAC is not correct, it should be a VAV with hot water heating.  Wrong terminal type.")
    has_hw_coil = false
    air_terminal.airLoopHVAC.get.supplyComponents.each do |supply_component|
      htg_coil = supply_component.to_CoilHeatingWater
      if htg_coil.is_initialized
        has_hw_coil = true
      end
    end
    assert(has_hw_coil, "Office HVAC is not correct, it should be a VAV with hot water heating.  No HW coil found.")

    # Check that the hotel is a PTAC system
    zone = model.getThermalZoneByName("8.Hotel.E1 Zone").get
    zone.equipment.each do |equipment|
      assert(equipment.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized,  "Hotel HVAC is not correct, it should be a PTAC with hot water heating")
      equipment = equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
      assert(equipment.heatingCoil.to_CoilHeatingWater.is_initialized, "Hotel HVAC is not correct, it should be a PTAC with hot water heating")
    end #The measure did NOT do this correctly - it put in a VAV system

    # Check in window to wall ratio
    total_window_area = 0
    model.getSubSurfaces.each do |sub_surface|
      if sub_surface.subSurfaceType == "FixedWindow"
        window_area = sub_surface.grossArea
        total_window_area += window_area
      end
    end
    assert_in_delta(3600, total_window_area, 60.0, "Window area is wrong.")
    # The measure did NOT do this correctly - it did 36.81% W2W ratio for some reason
  end

  # @author Taylor Roberts, Group14 Engineering
  def known_fail_test_bldg_20_large_hotel
    # Create the baseline model
    model = create_baseline_model('bldg_20', '90.1-2013', 'ASHRAE 169-2013-5B', 'LargeHotel','Xcel Energy CO EDA', false, true)
    # Conditions expected to be true in the baseline model
    # Window Properties
    # Check for non-metal frames for hotel room windows
    space = model.getSpaceByName("Level 5.GuestRoom 5").get
    space.surfaces.each do |surface|
      surface.subSurfaces.each do |sub_surface|
        if sub_surface.subSurfaceType == "FixedWindow" and sub_surface.outsideBoundaryCondition == "Outdoors"
          u_value_si = sub_surface.construction.get.to_Construction.get.uFactor.get
          u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
          assert_in_delta(0.32, u_value_ip, 0.01, "Hotel room non-metal framing is wrong.") #ashrae 90.1-2013 non-metal framing u-value of 0.32
        end
      end
    end

    # Check for metal frames for storefront
    space = model.getSpaceByName("Level 1.Lobby 3").get
    space.surfaces.each do |surface|
      surface.subSurfaces.each do |sub_surface|
        if sub_surface.subSurfaceType == "FixedWindow" and sub_surface.outsideBoundaryCondition == "Outdoors"
          u_value_si = sub_surface.construction.get.to_Construction.get.uFactor.get
          u_value_ip = OpenStudio.convert(u_value_si,'W/m^2*K','Btu/ft^2*h*R').get
          assert_in_delta(0.42, u_value_ip, 0.01, "Storefront metal framing is wrong.") #ashrae 90.1-2013 metal framing u-value of 0.42
        end
      end
    end

    # Check to seee that the baseline model does not have shading surfaces
    num_shading_surfaces = 0
    model.getShadingSurfaceGroups.each do |shade_group|
      # Site and Building shading (other buildings) does not count
      next if shade_group.shadingSurfaceType == 'Site' || shade_group.shadingSurfaceType == 'Building'
      # Space shading surfaces should have been removed
      num_shading_surfaces += shade_group.shadingSurfaces.size
    end
    assert_equal(0, num_shading_surfaces, "There should be no space or building shading surfaces in the baseline model")

    # Baseline HVAC systems
    # Check for PTHP in the guest rooms
    zone = model.getThermalZoneByName("Level 2.GuestRoom 1 Zone").get
    zone.equipment.each do |equip|
      assert(equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized, "Guestroom HVAC is not correct, it should be a PTHP")
      # The proposed building has VRF with gas-fired DOAS.  This model should have
      # a mixed-fuel baseline for Xcel
    end

    # check the corridor zones for fuel switching, should be gas or hot water heating
    zone = model.getThermalZoneByName("Level 3.Corridor 1 Zone").get
    zone.airLoopHVACTerminal.each do |air_terminal|
      assert(air_terminal.is_initialized, "Corridor HVAC is not correct, it should be an Air Loop with Gas Heating")
      has_gas_or_hw_htg_coil = false
      air_terminal.airLoopHVAC.supplyComponents.each do |supply_component|
        htg_coil = supply_component.to_CoilHeatingGas || supply_component.to_CoilHeatingWater
        if htg_coil.is_initialized
          has_gas_or_hw_htg_coil = true
        end
      end
      assert(has_gas_or_hw_htg_coil, "Corridor HVAC is not correct, it should be an Air Loop with Gas Heating")
    end
  end
end
