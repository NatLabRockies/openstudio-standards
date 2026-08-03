class ACM179dACM2019 < Standard
  register_standard '179D ACM 2019'
  attr_reader :template

  ACM_TEMPLATE = '179d-ACM-2019'.freeze
  ACM_SCHEDULES_FILE = '179d_acm_2019.schedules.json'.freeze
  ACM_SPACE_TYPES_FILE = '179d_acm_2019.spc_typ.json'.freeze
  ACM_EXTEND_TABLES = ['schedules'].freeze

  def initialize
    super()
    @template = ACM_TEMPLATE
    load_standards_database
  end

  def load_standards_database(data_directories = [])
    @standards_data = {}
    ([__dir__] + data_directories).each do |data_dir|
      load_acm_json_file(File.join(data_dir, 'data', ACM_SCHEDULES_FILE))
      load_acm_json_file(File.join(data_dir, 'data', ACM_SPACE_TYPES_FILE))
    end
    @standards_data
  end

  def load_acm_json_file(file_path, required: true)
    unless File.file?(file_path)
      return unless required

      msg = "Missing 179D ACM data file '#{file_path}'."
      OpenStudio.logFree(OpenStudio::Error, '179d.acm.standard', msg)
      raise msg
    end

    JSON.parse(File.read(file_path)).each_pair do |key, rows|
      unless rows.is_a?(Array)
        msg = "179D ACM data file '#{file_path}' must contain array tables."
        OpenStudio.logFree(OpenStudio::Error, '179d.acm.standard', msg)
        raise msg
      end

      rows.each { |row| row['template'] = template if row.key?('template') }
      if @standards_data[key].nil?
        OpenStudio.logFree(OpenStudio::Debug, '179d.acm.standard', "Adding #{key} from #{File.basename(file_path)}")
        @standards_data[key] = rows
      elsif ACM_EXTEND_TABLES.include?(key)
        OpenStudio.logFree(OpenStudio::Debug, '179d.acm.standard', "Extending #{key} with #{File.basename(file_path)}")
        @standards_data[key] += rows
      else
        OpenStudio.logFree(OpenStudio::Debug, '179d.acm.standard', "Overriding #{key} with #{File.basename(file_path)}")
        @standards_data[key] = rows
      end
    end
  rescue JSON::ParserError => e
    msg = "179D ACM data file '#{file_path}' is not valid JSON: #{e.message}"
    OpenStudio.logFree(OpenStudio::Error, '179d.acm.standard', msg)
    raise msg
  end
end
