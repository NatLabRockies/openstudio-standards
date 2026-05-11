# %% setup
import sqlite3, os

inputPath = "output/"
branch = "osstd"
outputFilePath = "test_performance_expected_dd_results.csv"

# EnergyPlus I/O Reference Manual Table 5.3
end_uses = [
    "InteriorLights",
    "ExteriorLights",
    "InteriorEquipment",
    "ExteriorEquipment",
    "Fans",
    "Pumps",
    "Heating",
    "Cooling",
    "HeatRejection",
    "Humidifier",
    "HeatRecovery",
    "DHW",
    "Cogeneration",
    "Refrigeration",
    "WaterSystems",
]

# EnergyPlus I/O Reference Manual Table 5.1
fuels = [
    "Electricity",
    "Gas",
    "Gasoline",
    "Diesel",
    "Coal",
    "FuelOilNo1",
    "FuelOilNo2",
    "Propane",
    "OtherFuel1",
    "OtherFuel2",
    "Water",
    "DistrictCooling",
    "DistrictHeatingWater",
    "DistrictHeatingSteam",
    "ElectricityPurchased",
    "ElectricitySurplusSold",
    "ElectricityNet",
]

building_types = [
    "SecondarySchool",
    "PrimarySchool",
    "SmallOffice",
    "MediumOffice",
    "LargeOffice",
    "SmallHotel",
    "LargeHotel",
    "Warehouse",
    "RetailStandalone",
    "RetailStripmall",
    "QuickServiceRestaurant",
    "FullServiceRestaurant",
    "MidriseApartment",
    "HighriseApartment",
    "Hospital",
    "Outpatient",
    "SmallOfficeDetailed",
    "MediumOfficeDetailed",
    "LargeOfficeDetailed",
]

code_versions = [
    "90.1-2004",
    "90.1-2007",
    "90.1-2010",
    "90.1-2013",
    "90.1-2016",
    "90.1-2019",
]

climate_zones = [
    "ASHRAE 169-2013-0A",
    "ASHRAE 169-2013-0B",
    "ASHRAE 169-2013-1A",
    "ASHRAE 169-2013-1B",
    "ASHRAE 169-2013-2A",
    "ASHRAE 169-2013-2B",
    "ASHRAE 169-2013-3A",
    "ASHRAE 169-2013-3B",
    "ASHRAE 169-2013-3C",
    "ASHRAE 169-2013-4A",
    "ASHRAE 169-2013-4B",
    "ASHRAE 169-2013-4C",
    "ASHRAE 169-2013-5A",
    "ASHRAE 169-2013-5B",
    "ASHRAE 169-2013-5C",
    "ASHRAE 169-2013-6A",
    "ASHRAE 169-2013-6B",
    "ASHRAE 169-2013-7A",
    "ASHRAE 169-2013-7B",
    "ASHRAE 169-2013-8A",
    "ASHRAE 169-2013-8B",
]

# %% write header

output = open(outputFilePath, "w")
headers = "Building Type,Template,Climate Zone"
for end_use in end_uses:
    for fuel in fuels:
        headers = headers + "," + end_use + "|" + fuel
output.write(headers + "\n")

# %% read write results data
for building_type in building_types:
    for code_version in code_versions:
        for climate_zone in climate_zones:
            modelFolder = (
                inputPath
                + "performance-"
                + building_type
                + "-"
                + code_version
                + "-"
                + climate_zone
            )
            if os.path.isdir(modelFolder):  # only do it for existing model
                modelFile = modelFolder + "/DsnDayRun/run/eplusout.sql"
                if not os.path.isfile(modelFile):
                    print(
                        "***************** "
                        + modelFile
                        + " DOES NOT EXIST!"
                        + " *****************"
                    )
                else:
                    print("Query from: " + modelFile)
                    conn = sqlite3.connect(modelFile)
                    end_use_results = ""
                    for end_use in end_uses:
                        for fuel_type in fuels:
                            get_rpt_mtr_data_dic_idx = "SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableName='{}:{}'".format(
                                end_use, fuel_type
                            )
                            curs = conn.cursor()
                            curs.execute(get_rpt_mtr_data_dic_idx)
                            idx = curs.fetchone()
                            if idx == None:
                                idx = 0
                            else:
                                idx = idx[0]
                            get_energy_j = "SELECT SUM (VariableValue) FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex='{}'".format(
                                idx
                            )
                            curs = conn.cursor()
                            curs.execute(get_energy_j)
                            energy_j = curs.fetchone()
                            if energy_j == None:
                                energy_j = 0
                            else:
                                energy_j = energy_j[0]
                            if energy_j == None or energy_j == "None":
                                energy_j = 0
                            end_use_results = end_use_results + "," + str(energy_j)
                    oneRow = (
                        building_type
                        + ","
                        + code_version
                        + ","
                        + climate_zone
                        + end_use_results
                        + "\n"
                    )
                    output.write(oneRow)
                    conn.close
output.close()
print(outputFilePath + " generated")
