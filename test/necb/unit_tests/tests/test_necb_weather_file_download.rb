require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

# This test will check that the weather files are downloaded and exist in the specified directory.

class NECB_Download_Weather_Files_Test < Minitest::Test

  def test_weather_file_download
    template = 'NECB2020'
    standard = Standard.build(template)

    # File paths and extensions.
    weather_folder = File.absolute_path(File.join(__FILE__, '..', '..', '..', '..', '..', "data/weather"))
    weather_file_extensions = %w[clm ddy epw pvsyst rain stat wea zip]

    # Weather locations to test.
    weather_locations = [
      "CAN_ON_Wiarton-Keppel.Intl.AP.716330_CWEC2016",
      "CAN_SK_Yorkton.Muni.AP.712920_TMYx.2004-2018",
      "CAN_BC_Prince.Rupert.AP-Digby.Island.710220_NRCv12022_TMY_GW1.5",
      "CAN_QC_Cap.Tourmente.713840_NRCv12022_TRY_MaxTemp_1991-2021"
    ]

    # Download and verify weather files.
    weather_locations.each do |location|
      standard.get_weather_file_from_repo(epw_file: "#{location}.epw", btap_weather: true)
      weather_file_extensions.each do |ext|
        file = File.join(weather_folder, "#{location}.#{ext}")
        assert(File.exist?(file), "The file #{file} does not exist.")
      end
    end

    # Clean up downloaded files.
    weather_locations.each do |location|
      Dir.glob("#{weather_folder}/#{location}*.*").each do |file|
        File.delete(file)
      end
    end
  end
end


