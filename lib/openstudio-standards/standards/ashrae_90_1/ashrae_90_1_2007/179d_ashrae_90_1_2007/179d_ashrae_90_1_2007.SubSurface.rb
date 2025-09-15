# frozen_string_literal: true

class ACM179dASHRAE9012007
  def get_exterior_fenestration_value(sub_surface, column_name)
    known_columns = [
      'Construction',
      'Frame and Divider',
      'Glass Area',
      'Frame Area',
      'Divider Area',
      'Area of One Opening',
      'Area of Multiplied Openings',
      'Glass U-Factor',
      'Glass SHGC',
      'Glass Visible Transmittance',
      'Frame Conductance',
      'Divider Conductance',
      'NFRC Product Type',
      'Assembly U-Factor',
      'Assembly SHGC',
      'Assembly Visible Transmittance',
      'Shade Control',
      'Parent Surface',
      'Azimuth',
      'Tilt',
      'Cardinal Direction'
    ]
    raise "Unknown column '#{column_name}'. Available: #{known_columns}" unless known_columns.include?(column_name)

    sql_query = ''"
SELECT Value FROM TabularDataWithStrings
  WHERE ReportName='EnvelopeSummary'
    AND ReportForString='Entire Facility'
    AND TableName='Exterior Fenestration'
    AND RowName='#{sub_surface.nameString.upcase}'
    AND ColumnName='#{column_name}'
"''

    val_ = sub_surface.model.sqlFile.get.execAndReturnFirstDouble(sql_query)
    raise "Query failed: #{sql_query}" if val_.empty?

    return val_.get
  end

  def sub_surface_get_window_property(sub_surface)
    sql_file = sub_surface.model.sqlFile
    if !sql_file.is_initialized
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'Model has no sql file containing results, cannot lookup data.')
      return nil
    end
    sql_file = sql_file.get

    # get window type
    window_type = sub_surface.subSurfaceType
    unless ['window', 'skylight'].any? { |x| window_type.downcase.include?(x) }
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'SubSurface is a not a window or skylight.')
      return nil
    end

    sub_surface_name = sub_surface.name.to_s

    # OpenStudio SDK has only methods for querying the assembly values
    # (SubSurface::assemblySHGC / assemblyUFactor)
    # When you do not have a frame, these are empty (0.0) though!
    # Since we reimplement the get_exterior_fenestration_value, might as well
    # use it for everything for clarity and consistency
    if sub_surface.windowPropertyFrameAndDivider.is_initialized
      window_shgc = get_exterior_fenestration_value(sub_surface, 'Assembly SHGC')
      window_u_value = get_exterior_fenestration_value(sub_surface, 'Assembly U-Factor')
    else
      window_shgc = get_exterior_fenestration_value(sub_surface, 'Glass SHGC')
      window_u_value = get_exterior_fenestration_value(sub_surface, 'Glass U-Factor')
    end

    # get opening area, including the frame (width is added to the sub_surface vertices)
    window_area = get_exterior_fenestration_value(sub_surface, 'Area of Multiplied Openings')

    # get surface type
    surface_type = nil
    surface_ = sub_surface.surface
    if surface_.is_initialized
      surface_type = surface_.get.surfaceType
    end

    window_property = {
      'name' => sub_surface_name,
      'window_type' => window_type,
      'surface_type' => surface_type,
      'area_m2' => window_area,
      'shgc' => window_shgc,
      'u_value' => window_u_value
    }
    return window_property
  end
end
