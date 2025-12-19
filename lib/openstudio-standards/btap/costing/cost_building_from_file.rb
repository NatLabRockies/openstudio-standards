require 'fileutils'
require 'json'
require 'optparse'
require_relative './btap_costing.rb'

# This script is used to apply costs to a list of costing items produced by btap_costing.  Right now it can only be run
# from the btap_results resources folder because it uses btap_costing.rb.  It can be used elsewhere probably but then
# the require_relative statement has to be changed.  It takes in the following command line arguments:
# -c (string, required) Location of the json containing the list of items to be costed and the original costing City and
#    Province.
# -d (string, optional) Location of a custom costing database containing the costing information for the items that
#    need costing.  This is used only if you do not want to use the standard costing database.  It must have the same
#    structure as the 'costs' hash in the default costing database
# -t (string, optional) The city to use when finding localization factors (only if you do not want to use the city that
#    used in the original run).
# -p (string, optional) Same as -t only for Province.
# -o (string, optional) The location and name of the output file containing the costs.  If a name and path are not
#    provided then one called cost_list_output.json will be put in the same directory as this file.
#
# The output of this script is a json file containing the following cost summary:
#     {
#       envelope: (float) Building envelope costs (to 2 decimal places).
#       lighting: (float) Ligting costs (to 2 decimal places).
#       heating_and_cooling: (float) Heating and cooling costs (not related to ventilation) (to 2 decimal places).
#       shw: (float) Service hot water costs (to 2 decimal places).
#       ventilation: (float) Ventilation (including ventilation air heating and cooling) costs (to 2 decimal places).
#       grand_total: (float) Total costs (to 2 decimal places).
#     }
class BTAPCostFromFile
  def cost_file()
    # Get the commond line arguments
    args = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: example.rb [options]"
      opts.on("-c", "--costlist_location=NAME", "Costing List File Location") do |n|
        args['cost_file'] = n
      end

      opts.on("-d", "--custom_costing=NAME", "Custom Costing Database Location") do |n|
        args['custom_db_file'] = n
      end

      opts.on("-t", "--custom_city=NAME", "Custom Costing City") do |n|
        args['custom_city'] = n
      end

      opts.on("-p", "--custom_province=NAME", "Custom Costing Province") do |n|
        args['custom_province'] = n
      end

      opts.on("-o", "--output_name=NAME", "Output file name and location") do |n|
        args['output_loc'] = n
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end.parse!

    curr_folder = (File.dirname(__FILE__)).to_s + "/"

    # Get the output file location from the arguments
    outputLoc = args['output_loc']
    if outputLoc.nil?
      outputFile = "./cost_list_output.json"
    elsif outputLoc[0] == "."
      if outputLoc[1] == "."
        outputFile = curr_folder + outputLoc
      elsif outputLoc[1] == "/"
        outputFile = curr_folder + outputLoc[2..-1]
      else
        outputFile = curr_folder + outputLoc[1..-1]
      end
    elsif outputLoc[0] == "/"
      outputFile = outputLoc
    else
      outputFile = curr_folder + outputLoc
    end

    # Get the cost list location from the arguments
    costListLoc = args['cost_file']
    if costListLoc.nil?
      raise("No cost list location specified.  Please enter the location and name of the costed item list after the -c")
    elsif costListLoc[0] == "."
      if costListLoc[1] == "."
        cost_loc = curr_folder + costListLoc
      elsif costListLoc[1] == "/"
        cost_loc = curr_folder + costListLoc[2..-1]
      else
        cost_loc = curr_folder + costListLoc[1..-1]
      end
    elsif costListLoc[0] == "/"
      cost_loc = costListLoc
    else
      cost_loc = curr_folder + costListLoc
    end

    # Get the custom costing database location from the arguments
    custDB = args['custom_db_file']
    if custDB.nil?
      db_loc = nil
    else
      if custDB[0] == "."
        if custDB[1] == "."
          db_loc = curr_folder + custDB
        elsif custDB[1] == "/"
          db_loc = curr_folder + custDB[2..-1]
        else
          db_loc = curr_folder + custDB[1..-1]
        end
      elsif custDB[0] == "/"
        db_loc = custDB
      else
        db_loc = curr_folder + custDB
      end
    end

    # Set the custom costing city and province location if specified
    args['custom_city'].nil? ? customCity = nil : customCity = args['custom_city'].to_s
    args['custom_province'].nil? ? customProv = nil : customProv = args['custom_province'].to_s

    # Get the costed items list
    costList = JSON.parse(File.read(cost_loc))

    # Create a BTAPCosting object and pass the btap_items list, and optional costing database, costing City and costing
    # Province arguments.  Get the resulting costs and save them in a json (see the description of the -o inline
    # arguments above for more information).
    btapCosting = BTAPCosting.new()
    costResults = btapCosting.cost_list_items(btap_items: costList, custom_costing: custDB, custCity: customCity, custProvince: customProv)

    File.write(outputFile, JSON.pretty_generate(costResults))
  end
end
# Create a 'BTAPCostFromFile' object and call the 'cost_file' method to run the above script.
BTAPCostFromFile.new().cost_file()
