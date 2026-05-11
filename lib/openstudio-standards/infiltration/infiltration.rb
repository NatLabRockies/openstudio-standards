module OpenstudioStandards
  # The Infiltration module provides methods create, modify, and get information about model infiltration
  module Infiltration
    # @!group Calculations

    # Convert an infiltration rate at a given pressure to another pressure (typically lower)
    # Method from Gowri, Krishnan, Winiarski, David W, and Jarnagin, Ronald E. Infiltration modeling guidelines for commercial building energy analysis. United States: N. p., 2009. Web. doi:10.2172/968203.
    #
    # @param infiltration_rate [Double] initial infiltration rate
    # @param initial_pressure [Double] pressure difference at which initial infiltration rate was determined, typically 75 Pa
    # @param final_pressure [Double] desired pressure difference to adjust infiltration rate, typically 4 Pa
    # @param infiltration_coefficient [Double] infiltration coeffiecient
    # @return [Double] adjusted infiltration rate in the same units as infiltration_rate
    def self.adjust_infiltration_to_new_pressure(infiltration_rate,
                                                 initial_pressure: 75.0,
                                                 final_pressure: 4.0,
                                                 infiltration_coefficient: 0.65)
      adjusted_infiltration_rate = infiltration_rate * ((final_pressure / initial_pressure)**infiltration_coefficient)

      return adjusted_infiltration_rate
    end

    # Convert the infiltration rate to the pressures and conditions assumed in the PNNL prototype buildings
    # Details described in Gowri, Krishnan, Winiarski, David W, and Jarnagin, Ronald E. Infiltration modeling guidelines for commercial building energy analysis. United States: N. p., 2009. Web. doi:10.2172/968203.
    #
    # @param infiltration_rate [Double] initial infiltration rate
    # @param initial_pressure [Double] pressure difference at which initial infiltration rate was determined in Pa, default 75 Pa
    # @return [Double] adjusted infiltration rate in the same units as infiltration_rate
    def self.adjust_infiltration_to_prototype_building_conditions(infiltration_rate, initial_pressure: 75.0)
      alpha = 0.22 # terrain adjustment factor for an urban environment, unitless
      uh = 4.47 # wind speed, m/s
      rho = 1.18 # air density, kg/m^3
      cs = 0.1617 # positive surface pressure coefficient, unitless
      n = 0.65 # infiltration coefficient, unitless

      # Calculate the typical pressure - same for all building types
      final_pressure_pa = 0.5 * cs * rho * (uh**2)
      adjusted_infiltration_rate = (1.0 + alpha) * infiltration_rate * ((final_pressure_pa / initial_pressure)**n)

      return adjusted_infiltration_rate
    end

    # @!endgroup Calculations

    # @!group Surface

    # Determine the component infiltration rate for a surface
    # Details described in Table 5.7 of Thornton, Brian A, Rosenberg, Michael I, Richman, Eric E, Wang, Weimin, Xie, YuLong, Zhang, Jian, Cho, Heejin, Mendon, Vrushali V, Athalye, Rahul A, and Liu, Bing. Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010. United States: N. p., 2011. Web. doi:10.2172/1015277.
    #
    # @param surface [OpenStudio::Model::Surface] OpenStudio Surface object
    # @param type [String] choices are 'baseline' and 'advanced'
    # @return [Double] component infiltration rate in m^3/s
    def self.surface_component_infiltration_rate(surface, type: 'baseline')
      # Define the envelope component infiltration rates
      component_infil_rates_cfm_per_ft2 = {
        'baseline' => {
          'roof' => 0.12,
          'exterior_wall' => 0.12,
          'below_grade_wall' => 0.12,
          'floor_over_unconditioned' => 0.12,
          'slab_on_grade' => 0.12
        },
        'advanced' => {
          'roof' => 0.04,
          'exterior_wall' => 0.04,
          'below_grade_wall' => 0.04,
          'floor_over_unconditioned' => 0.04,
          'slab_on_grade' => 0.04
        }
      }

      # Skip non-outdoor surfaces
      boundary_condition = surface.outsideBoundaryCondition
      unless boundary_condition == 'Outdoors' || boundary_condition == 'Ground'
        return 0.0
      end

      # Per area infiltration rate for this surface
      surface_type = surface.surfaceType
      infil_rate_cfm_per_ft2 = nil
      case boundary_condition
      when 'Outdoors'
        case surface_type
        when 'RoofCeiling'
          infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['roof']
        when 'Wall'
          infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['exterior_wall']
        when 'Floor'
          infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['floor_over_unconditioned']
        end
      when 'Ground'
        case surface_type
        when 'Wall'
          infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['below_grade_wall']
        when 'Floor'
          infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['slab_on_grade']
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.infiltration', "Could not determine infiltration surface type for #{surface.name}, defaulting to 0 component infiltration rate.")
        return 0.0
      end

      # Area of the surface
      area_m2 = surface.netArea
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

      # Rate for this surface
      comp_infil_rate_cfm = area_ft2 * infil_rate_cfm_per_ft2
      comp_infil_rate_m3_per_s = OpenStudio.convert(comp_infil_rate_cfm, 'cfm', 'm^3/s').get

      return comp_infil_rate_m3_per_s
    end

    # @!endgroup Surface

    # @!group SubSurface

    # Determine the component infiltration rate for a sub surface
    # Details described in Table 5.7 of Thornton, Brian A, Rosenberg, Michael I, Richman, Eric E, Wang, Weimin, Xie, YuLong, Zhang, Jian, Cho, Heejin, Mendon, Vrushali V, Athalye, Rahul A, and Liu, Bing. Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010. United States: N. p., 2011. Web. doi:10.2172/1015277.
    #
    # @param sub_surface [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @param type [String] choices are 'baseline' and 'advanced'
    # @return [Double] component infiltration rate in m^3/s
    def self.sub_surface_component_infiltration_rate(sub_surface, type: 'baseline')
      # Define the envelope component infiltration rates
      component_infil_rates_cfm_per_ft2 = {
        'baseline' => {
          'opaque_door' => 0.40,
          'loading_dock_door' => 0.40,
          'swinging_or_revolving_glass_door' => 1.0,
          'vestibule' => 1.0,
          'sliding_glass_door' => 0.40,
          'window' => 0.40,
          'skylight' => 0.40
        },
        'advanced' => {
          'opaque_door' => 0.20,
          'loading_dock_door' => 0.20,
          'swinging_or_revolving_glass_door' => 1.0,
          'vestibule' => 1.0,
          'sliding_glass_door' => 0.20,
          'window' => 0.20,
          'skylight' => 0.20
        }
      }

      # Skip non-outdoor surfaces
      unless sub_surface.outsideBoundaryCondition == 'Outdoors'
        return 0.0
      end

      # Per area infiltration rate for this sub surface
      case sub_surface.subSurfaceType
      when 'Door'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['opaque_door']
      when 'OverheadDoor'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['loading_dock_door']
      when 'GlassDoor'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Infiltration.infiltration', "Assuming swinging_or_revolving_glass_door for #{sub_surface.name} for component infiltration rate.")
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['swinging_or_revolving_glass_door']
      when 'FixedWindow', 'OperableWindow'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['window']
      when 'Skylight', 'TubularDaylightDome', 'TubularDaylightDiffuser'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['skylight']
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Infiltration.infiltration', "Could not determine infiltration sub surface type for #{sub_surface.name}, defaulting to 0 component infiltration rate.")
        return 0.0
      end

      # Area of the sub surface
      area_m2 = sub_surface.netArea
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

      # Rate for this sub surface
      comp_infil_rate_cfm = area_ft2 * infil_rate_cfm_per_ft2
      comp_infil_rate_m3_per_s = OpenStudio.convert(comp_infil_rate_cfm, 'cfm', 'm^3/s').get

      return comp_infil_rate_m3_per_s
    end

    # @!endgroup SubSurface
  end
end
