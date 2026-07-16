# This class holds methods that apply a version of ASHRAE 90.1-PRM-2019
# modified to suit 179D ACM 2019 needs.
# @ref [References::ASHRAE901PRM2019]
class ACM179dASHRAE901PRM2019 < ASHRAE901PRM2019
  register_standard '179D 2019'
  attr_reader :template

  def initialize
    super()
    @template = '179d-90.1-2019'
    load_standards_database
  end

  def load_standards_database(data_directories = [])
    super([__dir__] + data_directories)
  end
end
