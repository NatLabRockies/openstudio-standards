module OpenstudioStandards
  # The SqlFile module provides methods to get information from the EnergyPlus .sql file after a run
  module SqlFile
    # @!group Fenestration

    # Return the calculated fenestration U-Factor based on the glass, frame,
    # and divider performance and area from the EnergyPlus Envelope Summary report.
    #
    # @param construction [OpenStudio:Model:Construction] OpenStudio Construction object
    # @return [Double] the U-Factor in W/m^2*K
    def self.construction_calculated_fenestration_u_factor(construction)
      # check for sql file
      sql = construction.model.sqlFile
      unless sql.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SqlFile', 'Model has no sql file containing results, cannot lookup data.')
        return false
      end
      sql = sql.get

      u_factor_w_per_m2_k = nil
      construction_name = construction.name.get.to_s

      row_query = "SELECT RowName
                  FROM tabulardatawithstrings
                  WHERE ReportName='EnvelopeSummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Exterior Fenestration'
                  AND Value='#{construction_name.upcase}'"

      row_id = sql.execAndReturnFirstString(row_query)

      if row_id.is_initialized
        row_id = row_id.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SqlFile', "U-Factor row ID not found for construction: #{construction_name}.")
        row_id = 9999
      end

      # Glass U-Factor
      glass_u_factor_query = "SELECT Value
                  FROM tabulardatawithstrings
                  WHERE ReportName='EnvelopeSummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Exterior Fenestration'
                  AND ColumnName='Glass U-Factor'
                  AND RowName='#{row_id}'"

      glass_u_factor_w_per_m2_k = sql.execAndReturnFirstDouble(glass_u_factor_query)

      glass_u_factor_w_per_m2_k = glass_u_factor_w_per_m2_k.is_initialized ? glass_u_factor_w_per_m2_k.get : 0.0

      # Glass area
      glass_area_query = "SELECT Value
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND ColumnName='Glass Area'
                          AND RowName='#{row_id}'"

      glass_area_m2 = sql.execAndReturnFirstDouble(glass_area_query)

      glass_area_m2 = glass_area_m2.is_initialized ? glass_area_m2.get : 0.0

      # Frame conductance
      frame_conductance_query = "SELECT Value
                  FROM tabulardatawithstrings
                  WHERE ReportName='EnvelopeSummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Exterior Fenestration'
                  AND ColumnName='Frame Conductance'
                  AND RowName='#{row_id}'"

      frame_conductance_w_per_m2_k = sql.execAndReturnFirstDouble(frame_conductance_query)

      frame_conductance_w_per_m2_k = frame_conductance_w_per_m2_k.is_initialized ? frame_conductance_w_per_m2_k.get : 0.0

      # Frame area
      frame_area_query = "SELECT Value
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND ColumnName='Frame Area'
                          AND RowName='#{row_id}'"

      frame_area_m2 = sql.execAndReturnFirstDouble(frame_area_query)

      frame_area_m2 = frame_area_m2.is_initialized ? frame_area_m2.get : 0.0

      # Divider conductance
      divider_conductance_query = "SELECT Value
                  FROM tabulardatawithstrings
                  WHERE ReportName='EnvelopeSummary'
                  AND ReportForString='Entire Facility'
                  AND TableName='Exterior Fenestration'
                  AND ColumnName='Divider Conductance'
                  AND RowName='#{row_id}'"

      divider_conductance_w_per_m2_k = sql.execAndReturnFirstDouble(divider_conductance_query)

      divider_conductance_w_per_m2_k = divider_conductance_w_per_m2_k.is_initialized ? divider_conductance_w_per_m2_k.get : 0.0

      # Divider area
      divider_area_query = "SELECT Value
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND ColumnName='Divder Area'
                          AND RowName='#{row_id}'"

      divider_area_m2 = sql.execAndReturnFirstDouble(divider_area_query)

      divider_area_m2 = divider_area_m2.is_initialized ? divider_area_m2.get : 0.0

      u_factor_w_per_m2_k = ((glass_u_factor_w_per_m2_k * glass_area_m2) + (frame_conductance_w_per_m2_k * frame_area_m2) + (divider_conductance_w_per_m2_k * divider_area_m2)) / (glass_area_m2 + frame_area_m2 + divider_area_m2)

      return u_factor_w_per_m2_k
    end

    # @!endgroup Fenestration
  end
end
