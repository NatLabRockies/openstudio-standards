
# Add require for Spreadsheet::Workbook
require 'rubyXL'
require 'csv'
require_relative './libs.rb'
WEATHER_FILE = 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'
# Create NECB2011 objects
NECB = NECB2011.new
$base_model = nil
$failures = []
$successes = []

def create_model()
        # create model
        standard = Standard.build('NECB2011') 
        if $base_model.nil?  
            $base_model = standard.load_building_type_from_library(building_type: 'SmallOffice')
            standard.apply_weather_data(model: $base_model, epw_file: WEATHER_FILE)
            standard.apply_loads(model: $base_model)
            standard.apply_envelope(model: $base_model)
            standard.apply_fdwr_srr_daylighting(model: $base_model)
            standard.apply_auto_zoning(model: $base_model)
        end
        return BTAP::FileIO.deep_copy($base_model)
end

def system1()
    create_model()
    mau_type = [true]
    mau_heating_types = ["DX","Hot Water", "Electric"]
    necb_reference_hp_types = [true, false] 
    necb_reference_hp_supp_fuel_types = ["NaturalGas", "Electricity","None"]
    baseboard_types = ["Hot Water", "Electric"]
    multispeed_type = [false]
    # Generate all possible combinations of the above arrays
    mau_type.product(mau_heating_types, necb_reference_hp_types, necb_reference_hp_supp_fuel_types, baseboard_types,multispeed_type).each do |mau_type, mau_heating_type, necb_reference_hp, necb_reference_hp_supp_fuel, baseboard_type,multispeed|
        model = create_model()

        # Create hot water loop
        hw_loop = OpenStudio::Model::PlantLoop.new(model)


        # Create NECB2011 objects
        necb = NECB2011.new
        
        
        if (mau_type == false and necb_reference_hp == true) or 
            (necb_reference_hp == true and mau_heating_type != 'DX') or 
            (necb_reference_hp == false and mau_heating_type == 'DX') or 
            (necb_reference_hp == false and necb_reference_hp_supp_fuel != 'None')or 
            (necb_reference_hp == true and necb_reference_hp_supp_fuel == 'None')


            next
        end
        arguments = Hash[
                            "mau_type", mau_type, 
                            "mau_heating_type", mau_heating_type, 
                            "necb_reference_hp", necb_reference_hp, 
                            "necb_reference_hp_supp_fuel", necb_reference_hp_supp_fuel, 
                            "baseboard_type", baseboard_type,
                            "multispeed", multispeed
                        ]

        old_name,new_name,updated_name,desc = necb.add_sys1_unitary_ac_baseboard_heating_single_speed(
            model: model,
            necb_reference_hp: necb_reference_hp,
            necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
            zones: model.getThermalZones,
            mau_type: mau_type,
            mau_heating_coil_type: mau_heating_type,
            baseboard_type: baseboard_type,
            hw_loop: hw_loop
            )
            if old_name == new_name
                arguments["system"] = "sys_1"
                arguments["description"] = desc
                # Make the "name" key the first key in the hash
                arguments = arguments.sort.to_h
                arguments = { "name" => updated_name}.merge(arguments)
                arguments = { "description" => desc}.merge(arguments)
                $successes.append(arguments)
            else
                $failures.push([arguments,old_name,new_name])
            end
    end
end

def system2()
    fan_coil_types = ['FPFC']
    chiller_types = ["Scroll","Centrifugal","RotaryScrew","Reciprocating"]
    mau_cooling_types = ["DX","Hydronic"]
    # Generate all possible combinations of the above arrays
    mau_cooling_types.product( chiller_types, fan_coil_types).each do |mau_cooling_type, chiller_type, fan_coil_type|
        puts("mau_cooling_type: #{mau_cooling_type}, chiller_types: #{chiller_type}, fan_coil_types: #{fan_coil_type}")
        arguments = Hash[
            "mau_cooling_type", mau_cooling_type, 
            "chiller_type", chiller_type, 
            "fan_coil_type", fan_coil_type, 
        ]

        #Create model
        model = create_model

        # Create hot water loop
        hw_loop = OpenStudio::Model::PlantLoop.new(model)

        # Create NECB2011 objects
        old_name,new_name,updated_name,desc = NECB2011.new.add_sys2_FPFC_sys5_TPFC( model: model,
                                                zones:model.getThermalZones,
                                                chiller_type: chiller_type,
                                                fan_coil_type: fan_coil_type,
                                                mau_cooling_type: mau_cooling_type,
                                                hw_loop: hw_loop)
        if old_name == new_name
            arguments["system"] = "sys_2"
            arguments["description"] = desc
            # Make the "name" key the first key in the hash
            arguments = arguments.sort.to_h
            arguments = { "name" => updated_name}.merge(arguments)
            arguments = { "description" => desc}.merge(arguments)
            $successes.append(arguments)
        else
            $failures.push([arguments,old_name,new_name])
        end
    end
end

def system3()
    mau_type = [true]
    heating_coil_types = ["DX","Gas", "Electric"]
    necb_reference_hp_types = [true, false] 
    necb_reference_hp_supp_fuel_types = ["NaturalGas", "Electricity","None"]
    baseboard_types = ["Hot Water", "Electric"]
    multispeed_type = [false]
    # Generate all possible combinations of the above arrays
    mau_type.product(heating_coil_types, necb_reference_hp_types, necb_reference_hp_supp_fuel_types, baseboard_types,multispeed_type).each do |mau_type, heating_coil_type, necb_reference_hp, necb_reference_hp_supp_fuel, baseboard_type,multispeed|
        arguments = Hash[
            "mau_type", mau_type, 
            "heating_coil_type", heating_coil_type, 
            "necb_reference_hp", necb_reference_hp, 
            "necb_reference_hp_supp_fuel", necb_reference_hp_supp_fuel, 
            "baseboard_type", baseboard_type,
            "multispeed", multispeed
        ]


        #Create model
        model = create_model

        hw_loop = nil
        if (baseboard_type == "Hot Water")
            hw_loop = OpenStudio::Model::PlantLoop.new(model)
            NECB.setup_hw_loop_with_components( model, 
                                                hw_loop, 
                                                'Electricity', 
                                                'Electricity',
                                                model.alwaysOnDiscreteSchedule)
        end

        if (mau_type == false and necb_reference_hp == true) or 
            (necb_reference_hp == true and heating_coil_type != 'DX') or 
            (necb_reference_hp == false and heating_coil_type == 'DX') or
            (necb_reference_hp == false and necb_reference_hp_supp_fuel != 'None') or 
            (necb_reference_hp == true and necb_reference_hp_supp_fuel == 'None')
            next
        end
        old_name,new_name,updated_name,desc = NECB.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
            model: model,
            necb_reference_hp: necb_reference_hp,
            necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
            zones: model.getThermalZones,
            heating_coil_type: heating_coil_type,
            baseboard_type: baseboard_type,
            hw_loop: hw_loop,
            new_auto_zoner: true)
            if old_name == new_name
                arguments["system"] = "sys_3"
                arguments["description"] = desc
                # Make the "name" key the first key in the hash
                arguments = arguments.sort.to_h
                arguments = { "name" => updated_name}.merge(arguments)
                arguments = { "description" => desc}.merge(arguments)
                $successes.append(arguments)
            else
                $failures.push([arguments,old_name,new_name])
            end
    end
    
end


def system4()
    necb_reference_hp_types = [true, false] 
    necb_reference_hp_supp_fuel_types = ["NaturalGas", "Electricity","None"]
    heating_coil_types = ["DX","Gas", "Electric"]
    baseboard_types = ["Hot Water", "Electric"]
    necb_reference_hp_types.product(necb_reference_hp_supp_fuel_types, heating_coil_types, baseboard_types).each do |necb_reference_hp, necb_reference_hp_supp_fuel, heating_coil_type, baseboard_type|
        #Create model
        model = create_model
        hw_loop = nil
        if (baseboard_type == "Hot Water")
            hw_loop = OpenStudio::Model::PlantLoop.new(model)
            NECB.setup_hw_loop_with_components( model, 
                                                hw_loop, 
                                                'Electricity',
                                                'Electricity',
                                                 model.alwaysOnDiscreteSchedule)
        end
        arguments = Hash[
            "necb_reference_hp", necb_reference_hp, 
            "necb_reference_hp_supp_fuel", necb_reference_hp_supp_fuel, 
            "heating_coil_type", heating_coil_type, 
            "baseboard_type", baseboard_type
        ]

        if (necb_reference_hp == true and heating_coil_type != 'DX') or 
            (necb_reference_hp == false and heating_coil_type == 'DX') or
            (necb_reference_hp == false and necb_reference_hp_supp_fuel != 'None') or 
            (necb_reference_hp == true and necb_reference_hp_supp_fuel == 'None')
            next
        end

        old_name,new_name,updated_name,desc = NECB2011.new.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                   necb_reference_hp: necb_reference_hp,
                                                                   necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                   zones: model.getThermalZones,
                                                                   heating_coil_type: heating_coil_type,
                                                                   baseboard_type: baseboard_type,
                                                                   hw_loop: hw_loop)

        if old_name == new_name
            arguments["system"] = "sys_4"
            arguments["description"] = desc
            # Make the "name" key the first key in the hash
            arguments = arguments.sort.to_h
            arguments = { "name" => updated_name}.merge(arguments)
            arguments = { "description" => desc}.merge(arguments)
            $successes.append(arguments)
        else
            $failures.push([arguments,old_name,new_name])
        end
    end
end




def system5()
    fan_coil_types = ['TPFC']
    chiller_types = ["Scroll","Centrifugal","RotaryScrew","Reciprocating"]
    mau_cooling_types = ["DX","Hydronic"]
    # Generate all possible combinations of the above arrays
    mau_cooling_types.product( chiller_types, fan_coil_types).each do |mau_cooling_type, chiller_type, fan_coil_type|
        puts("mau_cooling_type: #{mau_cooling_type}, chiller_types: #{chiller_type}, fan_coil_types: #{fan_coil_type}")
        arguments = Hash[
            "mau_cooling_type", mau_cooling_type, 
            "chiller_type", chiller_type, 
            "fan_coil_type", fan_coil_type, 
        ]


        #Create model
        model = create_model

        # Create hot water loop
        hw_loop = OpenStudio::Model::PlantLoop.new(model)

        # Create NECB2011 objects
        old_name,new_name,updated_name,desc = NECB2011.new.add_sys2_FPFC_sys5_TPFC( model: model,
                                                zones:model.getThermalZones,
                                                chiller_type: chiller_type,
                                                fan_coil_type: fan_coil_type,
                                                mau_cooling_type: mau_cooling_type,
                                                hw_loop: hw_loop)
        if old_name == new_name
            arguments["system"] = "sys_5"
            arguments["description"] = desc
            # Make the "name" key the first key in the hash
            arguments = arguments.sort.to_h
            arguments = { "name" => updated_name}.merge(arguments)
            arguments = { "description" => desc}.merge(arguments)
            $successes.append(arguments)
        else
            $failures.push([arguments,old_name,new_name])
        end
    end
end


def system6()
    heating_coil_types = ["Electric" , "Hot Water"]
    baseboard_types = ["Electric", "Hot Water"]
    chiller_types = ["Scroll","Centrifugal","RotaryScrew","Reciprocating"]
    fan_types = ["var_speed_drive"]
    # Generate all possible combinations of the above arrays
    heating_coil_types.product( baseboard_types, chiller_types, fan_types).each do |heating_coil_type, baseboard_type, chiller_type, fan_type|
            puts("heating_coil_type: #{heating_coil_type}  baseboard_type: #{baseboard_type}, chiller_type: #{chiller_type}, fan_type : #{fan_type}")
            arguments = Hash[
                "heating_coil_type", heating_coil_type, 
                "baseboard_type", baseboard_type, 
                "chiller_type", chiller_type, 
                "fan_type", fan_type, 
            ]
    
            #Create model
            model = create_model

            # Create hot water loop
            hw_loop = OpenStudio::Model::PlantLoop.new(model)

            # Create NECB2011 objects
            old_name,new_name,updated_name,desc = NECB2011.new.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
                    model:model,
                    zones:model.getThermalZones,
                    heating_coil_type: heating_coil_type,
                    baseboard_type: baseboard_type,
                    chiller_type: chiller_type,
                    fan_type: fan_type,
                    hw_loop: hw_loop
                    )

            if old_name == new_name
                arguments["system"] = "sys_6"
                arguments["description"] = desc
                # Make the "name" key the first key in the hash
                arguments = arguments.sort.to_h
                arguments = { "name" => updated_name}.merge(arguments)
                arguments = { "description" => desc}.merge(arguments)
                $successes.append(arguments)
            else
                $failures.push([arguments,old_name,new_name])
            end
        end
end

system1()
system2()
system3()
system4()
system5()
system6()

$successes.each do |hash|
    if hash.values.any? { |value| value == 'Hot Water' }
        hash['needs_boiler'] = true
    else
        hash['needs_boiler'] = false
    end
end


puts ("Successes: #{$successes}")
puts("Failures: #{$failures}")
#Save $failures hash to the csv file.
CSV.open('failures.csv', 'w') do |csv|
    csv << ["arguments","old_name","new_name"]
    $failures.each do |failure|
        csv << failure
    end
end
# Save Successes to a csv file
CSV.open('successes.csv', 'w') do |csv|
    csv << $successes[0].keys
    $successes.each do |hash|
        csv << hash.values
    end
end

# save  $successes array of hashes as a csv file.
# filter $successes array of hashes to only include hashes wehre the "system" key is "sys_1"
["sys_1","sys_2","sys_3","sys_4","sys_5","sys_6"].each do |system_type|
        system = $successes.select{|hash| hash["system"] == system_type}
        unless system.nil? or system.empty?
            filename = "#{system_type}.csv"
            CSV.open(filename, 'w') do |csv|
                csv << system[0].keys
                system.each do |hash|
                    csv << hash.values
            end
        end
    end
end

# save $successes array of hashes as a pretty yaml file.
File.open('successes.json', 'w') do |file|
    file.write(JSON.pretty_generate($successes))
end

cvslist = ["sys_1.csv","sys_2.csv","sys_3.csv","sys_4.csv","sys_5.csv","sys_6.csv"]
#load all csv files and create an excel file with each csv file as a sheet using RubyXL


# Create a new workbook
workbook = RubyXL::Workbook.new

cvslist.each do |csv|
  # Make sure the csv file exists
    unless File.exist?(csv)
        puts "File not found: #{csv}"
        next
    end 
  # Create a new worksheet with the name of the CSV file (without extension)
  sheet_name = File.basename(csv, File.extname(csv))
  worksheet = workbook.add_worksheet(sheet_name)

  # Read the CSV file and add each row to the worksheet
  CSV.foreach(csv).with_index do |row, row_index|
    row.each_with_index do |cell, col_index|
      worksheet.add_cell(row_index, col_index, cell)
    end
  end
end

# Remove the default worksheet created by RubyXL
workbook.worksheets.delete_at(0)

# Write the workbook to an Excel file
workbook.write('systems.xlsx')

# ---------------------------------------------
# Iterate over the $successes array of hashes


# $successes.each do |success|
    model = create_model()
    standard = Standard.build('NECB2011') 
    description = 'PSZ RTU ASHP with Gas and ASHP with Gas Supp. Heat Coils and Hot Water Baseboard'
    #description = success['description']
    puts("Creating HVAC system: #{description}")
    standard.create_hvac_by_name(model: model, hvac_system_name: description, zones: model.getThermalZones, hw_loop: nil)
# end





