# This class holds methods that apply ASHRAE 90.1-2013
# to a given model.
# @ref [References::ASHRAE9012013]
class ASHRAE901PRM2019 < ASHRAE901PRM
  register_standard '90.1-PRM-2019'
  attr_reader :template

  def initialize
    super()
    @template = '90.1-PRM-2019'
    load_standards_database
  end

  def load_standards_database(data_directories = [])
    super([__dir__] + data_directories)
  end
end
