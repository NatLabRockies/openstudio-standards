# This module defines codes, standards, reference documents,
# reports, and other technical resources that assumptions or
# methodologies in the standard are taken from.  These methods
# perform no action, and are not used in the source code except
# to store reference information.
#
# @example Linking to a Reference from methods or classes
#   # @ref [References::ASHRAE9012004] section G.3.1, table 3
#   def some_method()
#     ...

module References
  # ASHRAE 90.1-2004
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2004-i-p?product_id=1199725 Purchase in the ASHRAE Bookstore
  class ASHRAE9012004; end

  # ASHRAE 90.1-2007
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2007-i-p?product_id=1536065 Purchase in the ASHRAE Bookstore
  class ASHRAE9012007; end

  # ASHRAE 90.1-2010
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2010-i-p?product_id=1739526 Purchase in the ASHRAE Bookstore
  class ASHRAE9012010; end

  # ASHRAE 90.1-2013
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2013-i-p?product_id=1865966 Purchase in the ASHRAE Bookstore
  class ASHRAE9012013; end

  # ASHRAE 90.1-2016
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2016-i-p?product_id=1931793 Purchase in the ASHRAE Bookstore
  class ASHRAE9012016; end

  # ASHRAE 90.1-2019 Appendix G PRM
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2019-i-p?product_id=2088527 Purchase in the ASHRAE Bookstore
  class ASHRAE901PRM2019; end

  # ASHRAE 90.1-2022 Appendix G PRM
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2022-i-p Purchase in the ASHRAE Bookstore
  class ASHRAE901PRM2022; end

  # ASHRAE 90.1-2019
  # @see https://www.techstreet.com/ashrae/standards/ashrae-90-1-2019-i-p?product_id=2088527 Purchase in the ASHRAE Bookstore
  class ASHRAE9012019; end

  # NREL ZNE Ready 2017
  # This is not an actual code or standard, but rather describes what NREL believes
  # to be a reasonable set of assumptions for achieving a building that is Zero Net Energy Ready
  # as of 2017.
  class NRELZNEReady2017; end

  # ZE AEDG Multifamily
  # This template contains values from the ASHRAE Zero Energy Advanced Energy Design Guide for Multifamily Buildings
  class ZEAEDGMultifamily; end

  # NECB2011
  # @see https://www.nrc-cnrc.gc.ca/eng/publications/codes_centre/2011_national_energy_code_buildings.html Purchase in the NRC Virtual Store
  class NECB2011; end

  # U.S. Department of Energy Commercial Reference Building Models of the National Building Stock.
  # This document describes the DOE Reference Buildings including key assumptions and data sources.
  # @see https://www.nrel.gov/docs/fy11osti/46861.pdf The NREL technical report
  class USDOEReferenceBuildings; end

  # Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010.
  # This document describes the DOE Prototype Buildings including key assumptions and data sources.
  # The DOE Prototype Buildings are a continuation of the DOE Reference Buildings.
  # @see https://www.energycodes.gov/sites/default/files/documents/BECP_Energy_Cost_Savings_STD2010_May2011_v00.pdf The PNNL technical report
  class USDOEPrototypeBuildings; end

  # Enhancements to ASHRAE Standard 90.1 Prototype Building Models
  # This document describes changes that were made to the DOE Prototype Buildings
  # during the process of evaluating the impact of ASHRAE 90.1-2013.
  # @see https://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf The PNNL technical report
  class USDOEPrototypeBuildingEnhancements; end

  # ANSI/ASHRAE/IES Standard 90.1-2016 Performance Rating Method Reference Manual.
  # This document describes detailed assumptions that could be used by software developers to implement
  # the Performance Rating Method (Appendix G).
  # @see http://www.pnnl.gov/main/publications/external/technical_reports/PNNL-26917.pdf The PNNL technical report
  class PNNLPRMReferenceManual2016; end

  # Infiltration Modeling Guidelines for Commercial Building Energy Analysis.
  # This report presents a methodology for modeling air infiltration in EnergyPlus to account for
  # envelope air barrier characteristics
  # @see http://www.pnl.gov/main/publications/external/technical_reports/PNNL-18898.pdf The PNNL technical report
  class PNNLInfiltration; end

  # DEER and MASControl
  # The Database for Energy Efficient Resources (DEER) contains information on selected energy-efficient technologies and measures.
  # The DEER provides estimates of the energy-savings potential for these technologies in residential and nonresidential applications.
  # To determine the energy-savings potential, a DOE-2-based system called MASControl was developed by consultants of
  # the California Public Utility Commission. The DEER "Standards" in this library represent the input assumptions used
  # inside of MASControl to represent CA buildings of different vintages.
  # @see http://deeresources.com/index.php/deer-versions
  class DEERMASControl; end

  # OEESC 2014
  # The Oregon Energy Efficiency Specialty Code is the building energy code for the
  # state of Oregon.  It is very similar to ASHRAE 90.1-2013, but has been tailored
  # to meet the needs of Oregon.
  # @see http://www.oregon.gov/bcd/codes-stand/Pages/energy-efficiency.aspx
  class OEESC2014; end

  # ICC IECC 2015
  # The International Code Council's International Energy Conservation Code is widely
  # used across the United States.
  # @see https://codes.iccsafe.org/public/document/toc/545/
  class ICCIECC2015; end

  # CBES
  # The LBNL Commercial Building Energy Saver is an online tool that is used to perform
  # benchmarking and retrofit analysis for small to medium sized office buildings in California.
  # @see http://cbes.lbl.gov/
  class CBES; end

  # University of California Berkeley Center for the Built Environment
  # These EnergyPlus objects implement a proportional control for a single
  # thermal zone with a radiant system. The full details of the control
  # strategy are described in the paper Raftery et al. (2017), "A new control
  # strategy for high thermal mass radiant systems". The work was supported
  # by the California Energy Commission (CEC) Electric Program Investment
  # Charge (EPIC) (EPC-14-009) "Optimizing Radiant Systems for Energy Efficiency
  # and Comfort", and the Center for the Built Environment, UC Berkeley, California.
  # For more information please contact the following:
  # Paul Raftery p.raftery@berkeley.edu
  # Carlos Duarte cduarte@berkeley.edu
  # @see https://cbe.berkeley.edu/project/optimizing-radiant-systems-energy-efficiency-comfort/
  class CBERadiantSystems; end
end
