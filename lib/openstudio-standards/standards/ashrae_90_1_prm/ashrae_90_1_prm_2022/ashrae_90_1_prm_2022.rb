# This class holds methods that apply the ASHRAE 90.1-2022 Appendix G
# Performance Rating Method (PRM) to a given model.
# It started as a copy of ASHRAE901PRM2019 (methods and data) and is
# modified as the 2022 requirements are implemented.
# @ref [References::ASHRAE901PRM2022]
class ASHRAE901PRM2022 < ASHRAE901PRM
  register_standard '90.1-PRM-2022'
  attr_reader :template

  def initialize
    super()
    @template = '90.1-PRM-2022'
    load_standards_database
  end

  # Loads the openstudio standards dataset for this standard.
  #
  # @param data_directories [Array<String>] array of file paths that contain standards data
  # @return [Hash] a hash of standards data
  def load_standards_database(data_directories = [])
    super([__dir__] + data_directories)
  end
end
