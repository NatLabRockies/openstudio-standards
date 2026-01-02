require 'fileutils'
require 'erb'

# copied and modified from https://github.com/rubyworks/facets/blob/master/lib/core/facets/string/snakecase.rb
class String
  def snek
    #gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        tr('-', '_').
        gsub(/\s/, '_').
        gsub(/__+/, '_').
        gsub(/#+/, '').
        gsub(/\"/, '').
        downcase
  end
end

class GeneratorNECBRegressionTests
  # default loation ci_tests.txt file when run on

  def initialize()
    @file_out_dir = File.absolute_path(File.join(__dir__,'..','tests'))
    reset_folder(@file_out_dir)
  end


  def reset_folder(dirname)
    if File.directory?(dirname)
      puts "Removing directory : [#{dirname}]"
      FileUtils.rm_rf(dirname)
    end
    FileUtils.mkdir_p(dirname)
  end

  def generate_system_test_files()
    filenames = []
    filenames.concat( generate_hvac_system_1_test_files)
    filenames.concat(generate_hvac_system_2_and_5_test_files)
    filenames.concat(generate_hvac_system_3_test_files)
    filenames.concat(generate_hvac_system_4_test_files)
    filenames.concat(generate_hvac_system_6_test_files)
    puts filenames
  end

  # This method is used to generate NECB HVAC system 1 test
  def generate_hvac_system_1_test_files(verbose = true)
    necb_system_template = File.read("#{__dir__}/template_test_necb_system_1.rb")
    systems = [
        {
            name: 'system_1',
            boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
            mau_types: [true, false],
            mau_heating_coil_types: ["Hot Water", "Electric"],
            baseboard_types: ["Hot Water", "Electric"],
        }
    ]
    # iterate through variables
    filenames = []
    systems.each do |system|
      system[:boiler_fuel_types].each do |boiler_fueltype|
        system[:mau_types].each do |mau_type|
          system[:mau_heating_coil_types].each do |mau_heating_coil_type|
            system[:baseboard_types].each do |baseboard_type|
              # generate unique filename
              test_name = "test_necb_hvac_#{system[:name]}_#{boiler_fueltype.snek}_#{mau_type.to_s.snek}_#{mau_heating_coil_type.snek}_#{baseboard_type.snek}"
              filename = File.join(@file_out_dir, "#{test_name}.rb")
              file_string = ERB.new(necb_system_template).result(binding)
              # write file
              File.write(filename, file_string)
              filenames << filename
            end
          end
        end
      end
    end

  end


  # This method is used to generate NECB HVAC system 1 test
  def generate_hvac_system_2_and_5_test_files(verbose = true)
    necb_system_template = File.read("#{__dir__}/template_test_necb_system_2_and_5.rb")
    systems = [
        {
            name: 'system_2',
            boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
            chiller_types: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
            mua_cooling_types: ["Hydronic", "DX"],
            fan_coil_type: ['FPFC']
        }
        #System 5 not operational right now
        #,
        # {
        #     name: 'system_5',
        #     boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
        #     chiller_types: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
        #     mua_cooling_types: ["Hydronic", "DX"],
        #     fan_coil_type: ['TPFC']
        # }
    ]
    # iterate through variables
    filenames = []
    systems.each do |system|
      system[:boiler_fuel_types].each do |boiler_fueltype|
        system[:chiller_types].each do |chiller_type|
          system[:mua_cooling_types].each do |mua_cooling_type|
            system[:fan_coil_type].each do |fan_coil_type|
              # generate unique filename
              test_name = "test_necb_hvac_#{system[:name]}_#{boiler_fueltype.snek}_#{chiller_type.to_s.snek}_#{mua_cooling_type.snek}_#{fan_coil_type.snek}"
              filename = File.join(@file_out_dir, "#{test_name}.rb")
              file_string = ERB.new(necb_system_template).result(binding)
              # write file
              File.open(filename, 'w') {|file| file.write(file_string)}
              filenames << filename
            end
          end
        end
      end
    end
    return filenames
  end

  # This method is used to generate NECB HVAC system 3 test
  def generate_hvac_system_3_test_files(verbose = true)
    necb_system_template = File.read("#{__dir__}/template_test_necb_system_3.rb")
    systems = [
        {
            name: 'system_3',
            boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
            heating_coil_types_sys3: ["Electric", "Gas", "DX"],
            baseboard_types: ["Hot Water", "Electric"]
        }
    ]
    filenames = []
    # iterate through variables
    systems.each do |system|
      system[:boiler_fuel_types].each do |boiler_fueltype|
        system[:heating_coil_types_sys3].each do |heating_coil_type_sys3|
          system[:baseboard_types].each do |baseboard_type|
            # generate unique filename
            test_name = "test_necb_hvac_#{system[:name]}_#{boiler_fueltype.snek}_#{heating_coil_type_sys3.to_s.snek}_#{baseboard_type.snek}"
            filename = File.join(@file_out_dir, "#{test_name}.rb")
            file_string = ERB.new(necb_system_template).result(binding)
            # write file
            File.open(filename, 'w') {|file| file.write(file_string)}
            filenames << filename
          end
        end
      end
    end
    return filenames
  end


  # This method is used to generate NECB HVAC system 3 test
  def generate_hvac_system_4_test_files(verbose = true)
    necb_system_template = File.read("#{__dir__}/template_test_necb_system_4.rb")
    systems = [
        {
            name: 'system_4',
            boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
            baseboard_types: ["Hot Water", "Electric"],
            heating_coil_types_sys4: ["Electric", "Gas"],
        }
    ]
    # iterate through variables
     filenames = []
    systems.each do |system|
      system[:boiler_fuel_types].each do |boiler_fueltype|
        system[:heating_coil_types_sys4].each do |heating_coil_type_sys4|
          system[:baseboard_types].each do |baseboard_type|
            # generate unique filename
            test_name = "test_necb_hvac_#{system[:name]}_#{boiler_fueltype.snek}_#{heating_coil_type_sys4.to_s.snek}_#{baseboard_type.snek}"
            filename = File.join(@file_out_dir, "#{test_name}.rb")
            file_string = ERB.new(necb_system_template).result(binding)
            # write file
            File.open(filename, 'w') {|file| file.write(file_string)}
            filenames << filename
          end
        end
      end
    end
    return filenames
  end

  # This method is used to generate NECB HVAC system 3 test
  def generate_hvac_system_6_test_files(verbose = true)
    necb_system_template = File.read("#{__dir__}/template_test_necb_system_6.rb")
    systems = [
        {
            name: 'system_6',
            boiler_fuel_types: ["NaturalGas", "Electricity", "FuelOil#2"],
            baseboard_types: ["Hot Water", "Electric"],
            chiller_types: ["Scroll"], #,"Centrifugal","Rotary Screw","Reciprocating"] are not working.
            heating_coil_types_sys6: ["Electric", "Hot Water"],
            fan_types: ["AF_or_BI_rdg_fancurve", "AF_or_BI_inletvanes", "fc_inletvanes", "var_speed_drive"]
        }
    ]


    # iterate through variables
    filenames = []
    systems.each do |system|
      system[:boiler_fuel_types].each do |boiler_fueltype|
        system[:heating_coil_types_sys6].each do |heating_coil_type_sys6|
          system[:baseboard_types].each do |baseboard_type|
            system[:chiller_types].each do |chiller_type|
              system[:fan_types].each do |fan_type|
                # generate unique filename
                test_name = "test_necb_hvac_#{system[:name]}_#{boiler_fueltype.snek}_#{heating_coil_type_sys6.to_s.snek}_#{baseboard_type.snek}__#{chiller_type.snek}_#{fan_type.snek}"
                filename = File.join(@file_out_dir, "#{test_name}.rb")
                file_string = ERB.new(necb_system_template).result(binding)
                # write file
                File.open(filename, 'w') {|file| file.write(file_string)}
                filenames << filename
              end
            end
          end
        end
      end
    end
    return filenames
  end
end
GeneratorNECBRegressionTests.new.generate_system_test_files


