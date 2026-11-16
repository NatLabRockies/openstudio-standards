Fan power and control for systems 6 and 8

# ASHRAE 90.1-2019
G3.1.3.14
Fans in parallel VAV fan-powered boxes shall run as the first stage of heating before the reheat coil is energized. Fans in parallel VAV fan-powered boxes shall be sized for 50% of the peak design primary air (from the VAV air-handling unit) flow rate and shall be modeled with 0.35 W/cfm fan power. Minimum volume set points for fan-powered boxes shall be equal to 30% of peak design primary airflow rate or the rate required to meet the minimum outdoor air ventilation requirement, whichever is larger. The supply air temperature set point shall be constant at the design condition.
# PRM-RM
* Fan Control: With parallel style fan-powered VAV boxes, the constant volume terminal unit fan is only on when the primary airflow is at design minimum and the zone temperature is less than 2°F above the heating setpoint schedule. When the system is scheduled to operate and the zone terminal fan is running, the box mixes plenum air with primary air.
* Heating Operation: During heating mode, the terminal unit discharge air temperature is increased from minimum to the design heating temperature. Throughout occupied heating the cooling, primary airflow is kept at design minimum and the terminal unit fan is running.
* Deadband Operation: The cooling primary airflow is kept at minimum airflow and the heating valve is closed. The terminal unit fan will energize as the first stage of heating when the zone temperature drops to 2F. above heating setpoint.
* Cooling Operation: As the space temperature increases, the cooling supply airflow is increased from minimum to design cooling maximum. Throughout cooling the box fan is off. To comply with Standard 90.1-2019 Section 6.5.2.1, Exception (1), the minimum primary airflow for this control logic must be no larger than 30% of the zone design cooling airflow or the minimum airflow for ventilation.
* Night Cycle Heating Control: A call for heating during night cycle control shall be met by running the terminal fan and increasing the terminal unit discharge air temperature from minimum to the design heating temperature without the use of primary air.
# Code Requirement Intepretation
The PRM-RM provides a good interpretation of the code requirement. It does miss to describe night cycle cooling operation. We believe that during these periods, the terminal fan should be off and that the central system fan should turn on to allows the central system to meet the load (as the terminals don't have any cooling coils).
# Implementation
Night cycle operation: will be implemented in `air_loop_hvac_enable_unoccupied_fan_shutoff` and the `CycleOnAnyCoolingOrHeatingZone` control type will be used to achieve the desired strategy. Note that we've identified a temporary issue with that control type in OpenStudio (see [here](https://github.com/NREL/OpenStudio/issues/4566)).

Cooling and heating operation: the terminal fan should be off when the primary airflow fraction is greater than the minimum primary air flow. In EnergyPlus, this is dictated by the "Fan On Flow Fraction". The Fan On Flow Fraction will be set to 0.0 to allow operating of the secondary fan only when reheat is needed and when the primary air flow is at the minimum.
# Key Ruby Methods
## Exisiting
* `air_loop_hvac_enable_unoccupied_fan_shutoff`: Shut off the system during unoccupied periods and handle night cycling operation.
## New
* `air_loop_hvac_parallel_piu_air_terminals?`: Determine if the air loop serves parallel PIU air terminals.
* `air_terminal_single_duct_parallel_piu_reheat_fan_on_flow_fraction`: Return the fan on flow fraction for a parallel PIU terminal