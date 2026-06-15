class NECB2020

  # Set all external subsurfaces (doors, windows, skylights) to NECB values.
  # @author phylroy.lopez@nrcan.gc.ca
  # @param subsurface [String]
  # @param hdd [Float]
  def set_necb_external_subsurface_conductance(subsurface, hdd)
    conductance_value = 0

    if subsurface.outsideBoundaryCondition.downcase.match('outdoors')
      case subsurface.subSurfaceType.downcase
      when /window/
        conductance_value = @standards_data['conductances']['Window'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      when /skylight/
        conductance_value = @standards_data['conductances']['Skylight'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      when /door/
        conductance_value = @standards_data['conductances']['Door'].find { |i| i['hdd'] > hdd }['thermal_transmittance'] * scaling_factor
      end
      subsurface.setRSI(1 / conductance_value)
    end
  end
end
