# This abstract class holds generic methods that many energy standards would commonly use.
# Many of the methods in this class apply efficiency values from the
# OpenStudio-Standards spreadsheet.  If a method in this class is redefined
# by a subclass, the implementation in the subclass is used.
# @abstract
class Standard
  attr_reader :standards_data
  attr_reader :template

  # The code below is required for the factory method. For an explanation see
  # https://stackoverflow.com/questions/1515577/factory-methods-in-ruby and clakes post. Which I think is the cleanest
  # implementation.
  # This creates a constant HASH to be set  during class instantiation.
  # When adding standards you must register the class by invoking 'register_standard ('NECB2011')' for example for
  # NECB2011.

  # A list of available Standards subclasses that can
  # be created using the Standard.build() method.
  STANDARDS_LIST = {} # rubocop:disable Style/MutableConstant

  # Add the standard to the STANDARDS_LIST.
  def self.register_standard(name)
    STANDARDS_LIST[name] = self
  end

  # Create an instance of a Standard by passing it's name
  #
  # @param name [String] the name of the Standard to build.
  #   valid choices are: DOE Pre-1980, DOE 1980-2004, 90.1-2004,
  #   90.1-2007, 90.1-2010, 90.1-2013, 90.1-2016, 90.1-2019,
  #   NREL ZNE Ready 2017, NECB2011
  # @example Create a new Standard object by name
  #   standard = Standard.build('NECB2011')
  def self.build(name)
    if STANDARDS_LIST[name].nil?
      raise "ERROR: Did not find a class called '#{name}' to create in #{JSON.pretty_generate(STANDARDS_LIST)}"
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.standard', "Using OpenStudio Standards version #{OpenstudioStandards::VERSION} with template #{name}.")
    return STANDARDS_LIST[name].new
  end

  # set up template class variable.
  def initialize
    super()
  end

  # Get the name of the building type used in lookups
  #
  # @param building_type [String] the building type
  # @return [String] returns the lookup name as a string
  # @todo Unify the lookup names and eliminate this method
  def model_get_lookup_name(building_type)
    lookup_name = building_type
    case building_type
    when 'SmallOffice', 'SmallOfficeDetailed', 'MediumOffice', 'MediumOfficeDetailed', 'LargeOffice', 'LargeOfficeDetailed', 'Office'
      lookup_name = 'Office'
    when 'RetailStandalone'
      lookup_name = 'Retail'
    when 'RetailStripmall'
      lookup_name = 'StripMall'
    end
    return lookup_name
  end

  # Loads the openstudio standards dataset for this standard.
  # For standards subclassed from other standards, the lowest-level
  # data will override data supplied at a higher level.
  # For example, data from ASHRAE 90.1-2004 will be overridden by
  # data from ComStock ASHRAE 90.1-2004.
  #
  # Only the list of available tables is built here. Each table's JSON file
  # is parsed the first time the table is requested from standards_data.
  #
  # @param data_directories [Array<String>] array of file paths that contain standards data
  # @return [Standard::LazyStandardsData] the standards data tables, indexed by table name
  def load_standards_database(data_directories = [])
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.standard', "Loading OpenStudio Standards data for #{template}")
    @standards_data = LazyStandardsData.new(self, data_directories)

    # Check that standards data files were found
    if @standards_data.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.standard', "OpenStudio Standards JSON data was not loaded correctly for #{template}.")
    end
    return @standards_data
  end
end
