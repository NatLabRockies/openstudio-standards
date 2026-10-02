class Standard
  # Holds the JSON data tables for a Standard and parses each table
  # the first time it is requested rather than when the Standard is built.
  #
  # Every JSON data file holds exactly one top-level table, named by the
  # last dot-separated part of the file name (for example
  # ashrae_90_1_2013.boilers.json holds the 'boilers' table). A few files use
  # an abbreviated suffix; those are mapped through SUFFIX_ALIASES.
  #
  # Data directories are searched in the order given. When several directories
  # provide the same table, the last directory wins, which lets a subclass
  # override the tables of its parent standard.
  #
  # The object answers the Hash methods the rest of the library uses on
  # standards data ([], []=, key?, keys, ...), so callers do not need to know
  # that the tables are parsed on demand.
  class LazyStandardsData
    include Enumerable

    # File name suffixes whose JSON table name differs from the suffix
    SUFFIX_ALIASES = {
      'spc_typ' => 'space_types',
      'ext_ltg' => 'exterior_lighting',
      'prm_ext_ltg' => 'prm_exterior_lighting',
      'ref_cases' => 'refrigerated_cases',
      'ref_lnup' => 'refrigeration_system_lineup'
    }.freeze

    # @param standard [Standard] the standard that owns the data; its template
    #   is written into every table object that carries a 'template' field
    # @param data_directories [Array<String>] directories whose data/*.json files
    #   supply the tables, from the most generic to the most specific
    # @param embedded [Boolean, nil] true when the files live inside the OpenStudio
    #   CLI's embedded file system; detected from this file's location when nil
    def initialize(standard, data_directories = [], embedded: nil)
      @standard = standard
      @embedded = embedded.nil? ? __dir__[0] == ':' : embedded
      @index = {}
      @loaded = {}
      data_directories.each { |data_dir| add_directory(data_dir) }
    end

    # The template written into each table's objects
    #
    # @return [String]
    def template
      @standard.template
    end

    # Registers every JSON file in a directory's data folder. Tables already
    # registered from an earlier directory are overridden.
    #
    # @param data_dir [String] directory containing a data folder of JSON files
    # @return [Array<String>] the table names supplied by the directory
    def add_directory(data_dir)
      files = @embedded ? embedded_json_files(data_dir) : local_json_files(data_dir)
      files.map do |file|
        table_name = self.class.table_name_for(file)
        if @index.key?(table_name)
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Overriding #{table_name} with #{File.basename(file)}")
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Adding #{table_name} from #{File.basename(file)}")
        end
        @index[table_name] = file
        @loaded.delete(table_name)
        table_name
      end
    end

    # The table name a data file supplies, derived from its file name
    #
    # @param file [String] path to a JSON data file
    # @return [String] table name
    def self.table_name_for(file)
      suffix = File.basename(file, '.json').split('.').last
      SUFFIX_ALIASES.fetch(suffix, suffix)
    end

    # Returns a table, parsing its file on first access.
    #
    # @param table_name [String]
    # @return [Array<Hash>, nil] the table, or nil when no file supplies it
    def [](table_name)
      return @loaded[table_name] if @loaded.key?(table_name)
      return nil unless @index.key?(table_name)

      @loaded[table_name] = parse_table(table_name, @index[table_name])
    end

    # Stores a table directly, replacing any file-backed table of the same name
    #
    # @param table_name [String]
    # @param objs [Array<Hash>]
    def []=(table_name, objs)
      @loaded[table_name] = objs
    end

    # @see Hash#fetch
    def fetch(table_name, *default, &block)
      return self[table_name] if key?(table_name)
      return block.call(table_name) if block
      return default.first unless default.empty?

      raise KeyError, "table not found: #{table_name}"
    end

    # @see Hash#dig
    def dig(table_name, *rest)
      table = self[table_name]
      return table if rest.empty? || table.nil?

      table.dig(*rest)
    end

    # @return [Boolean] true when a file supplies the table or it was stored directly
    def key?(table_name)
      @loaded.key?(table_name) || @index.key?(table_name)
    end
    alias has_key? key?
    alias include? key?
    alias member? key?

    # @return [Boolean] true when the table has already been parsed or stored
    def loaded?(table_name)
      @loaded.key?(table_name)
    end

    # @return [Array<String>] names of every available table
    def keys
      @index.keys | @loaded.keys
    end

    # @return [Array<String>] names of the tables that have been parsed or stored
    def loaded_tables
      @loaded.keys
    end

    # @return [String, nil] the file that supplies a table, or nil if it was stored directly
    def file_for(table_name)
      @index[table_name]
    end

    # @return [Boolean]
    def empty?
      keys.empty?
    end

    # @return [Integer] number of available tables
    def size
      keys.size
    end
    alias length size

    # Removes a table so that it is no longer available
    #
    # @return [Array<Hash>, nil] the removed table if it had been loaded
    def delete(table_name)
      @index.delete(table_name)
      @loaded.delete(table_name)
    end

    # Parses every table that has not been loaded yet
    #
    # @return [LazyStandardsData] self
    def load_all
      @index.each_key { |table_name| self[table_name] }
      self
    end

    # Yields every table, parsing any that are not loaded yet
    #
    # @yield [table_name, objs]
    def each_pair(&block)
      return enum_for(:each_pair) unless block

      keys.each { |table_name| block.call(table_name, self[table_name]) }
    end
    alias each each_pair

    # @return [Array<Array<Hash>>] every table, parsing any that are not loaded yet
    def values
      keys.map { |table_name| self[table_name] }
    end

    # @return [Hash] a plain hash of every table, parsing any that are not loaded yet
    def to_h
      keys.to_h { |table_name| [table_name, self[table_name]] }
    end

    # @return [String] a short description that does not dump the tables
    def inspect
      "#<#{self.class.name} template=#{template.inspect} tables=#{keys.size} loaded=#{@loaded.size}>"
    end

    private

    # @return [Array<String>] JSON files in the data folder of a local directory
    def local_json_files(data_dir)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Indexing JSON files from #{data_dir}")
      Dir.glob("#{data_dir}/data/*.json").select { |file| File.file?(file) }.sort
    end

    # @return [Array<String>] JSON files in the data folder of an OpenStudio CLI embedded directory
    def embedded_json_files(data_dir)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Indexing JSON files from OpenStudio CLI embedded directory #{data_dir}")
      EmbeddedScripting.allFileNamesAsString.split(';').select do |file|
        file.start_with?("#{data_dir}/data/") && file.end_with?('.json')
      end.sort
    end

    # @return [String] the contents of a data file
    def read_file(file)
      @embedded ? EmbeddedScripting.getFileAsString(file) : File.read(file)
    end

    # Parses a data file and returns the named table with its template fields
    # set to this standard's template
    #
    # @return [Array<Hash>]
    def parse_table(table_name, file)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Loading #{table_name} from #{File.basename(file)}")
      data = JSON.parse(read_file(file))
      objs = data[table_name]
      if objs.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.standard', "#{File.basename(file)} is expected to hold the '#{table_name}' table but holds #{data.keys.inspect}; rename the file to match its table.")
        objs = data.values.first
      elsif data.size > 1
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.standard', "#{File.basename(file)} holds #{data.keys.inspect}; only '#{table_name}' is used. Put each table in its own file.")
      end
      return objs unless objs.is_a?(Array)

      # Override the template in inherited files to match the instantiated template
      objs.each do |obj|
        obj['template'] = template if obj.is_a?(Hash) && obj.key?('template')
      end
      return objs
    end
  end
end
