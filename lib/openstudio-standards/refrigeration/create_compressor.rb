module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Create Refrigeration Compressor
    # Methods to add refrigeration system compressor

    # Adds a refrigeration system compressor to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] Technology or standards level, either 'old', 'new', or 'advanced'
    # @param operation_type [String] Temperature regime, either 'MT' Medium Temperature, or 'LT' Low Temperature
    # @return [OpenStudio::Model::RefrigerationCompressor] the refrigeration compressor
    def self.create_compressor(model,
                               template: 'new',
                               operation_type: 'MT')
      # load refrigeration compressor data
      compressors_csv = "#{File.dirname(__FILE__)}/data/refrigeration_compressors.csv"
      unless File.file?(compressors_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{compressors_csv}")
        return nil
      end
      compressors_tbl = CSV.table(compressors_csv, encoding: 'ISO8859-1:utf-8')
      compressors_hsh = compressors_tbl.map(&:to_hash)

      # get case properties
      compressor_properties = compressors_hsh.select { |r| (r[:template] == template) && (r[:operation_type] == operation_type) }

      if compressor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find compressor for template #{template} operation type #{operation_type}.")
        return nil
      end

      pc = compressor_properties.select { |r| r[:curve_type] == 'Power' }[0]
      cc = compressor_properties.select { |r| r[:curve_type] == 'Capacity' }[0]

      # create power curve
      power_coeffs = []
      power_coeffs << pc[:coefficient1]
      power_coeffs << pc[:coefficient2]
      power_coeffs << pc[:coefficient3]
      power_coeffs << pc[:coefficient4]
      power_coeffs << pc[:coefficient5]
      power_coeffs << pc[:coefficient6]
      power_coeffs << pc[:coefficient7]
      power_coeffs << pc[:coefficient8]
      power_coeffs << pc[:coefficient9]
      power_coeffs << pc[:coefficient10]
      power_curve = OpenstudioStandards::HVAC.create_curve_bicubic(model, power_coeffs, name: pc[:curve_name], min_x: pc[:min_val_x], max_x: pc[:max_val_x], min_y: pc[:min_val_y], max_y: pc[:max_val_y])

      # create capacity curve
      capacity_coeffs = []
      capacity_coeffs << cc[:coefficient1]
      capacity_coeffs << cc[:coefficient2]
      capacity_coeffs << cc[:coefficient3]
      capacity_coeffs << cc[:coefficient4]
      capacity_coeffs << cc[:coefficient5]
      capacity_coeffs << cc[:coefficient6]
      capacity_coeffs << cc[:coefficient7]
      capacity_coeffs << cc[:coefficient8]
      capacity_coeffs << cc[:coefficient9]
      capacity_coeffs << cc[:coefficient10]
      capacity_curve = OpenstudioStandards::HVAC.create_curve_bicubic(model, capacity_coeffs, name: cc[:curve_name], min_x: cc[:min_val_x], max_x: cc[:max_val_x], min_y: cc[:min_val_y], max_y: cc[:max_val_y])

      # Make the compressor
      compressor = OpenStudio::Model::RefrigerationCompressor.new(model)
      compressor.setName("#{template} #{operation_type} Refrigeration Compressor")
      compressor.setRefrigerationCompressorPowerCurve(power_curve)
      compressor.setRefrigerationCompressorCapacityCurve(capacity_curve)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Added refrigeration compressor #{compressor.name}.")

      return compressor
    end
  end
end
