# This class holds methods that apply NECB2011 rules.
# @ref [References::NECB2011]
class BTAPPRE1980 < NECB2011
  @template = new.class.name
  register_standard(@template)

  def initialize
    super()
    @template = self.class.name
    @standards_data = load_standards_database_new
    corrupt_standards_database
    @tbd = nil
    @activity = nil
    @structure = nil
    @osut = {gra0: 0, graX: 0, status: 0, logs: []} # "gra": "gross roof area"
  end

  def load_standards_database_new
    # load NECB2011 data
    super()

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['constants'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select { |e| File.file? e }
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['formulas'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    end
    # Write database to file.
    # File.open(File.join(File.dirname(__FILE__), '..', 'NECB2017.json'), 'w') {|f| f.write(JSON.pretty_generate(@standards_data))}

    return @standards_data
  end

  # Thermal zones need to be set to determine conditioned spaces when applying fdwr and srr limits.
  #
  # fdwr_set/srr_set settings:
  #   0-1:  Remove all windows/skylights and add windows/skylights to match this fdwr/srr
  #    -1:  Remove all windows/skylights and add windows/skylights to match max fdwr/srr from NECB
  #    -2:  Do not apply any fdwr/srr changes, leave windows/skylights alone (also works for fdwr/srr > 1)
  #    -3:  Use old method which reduces existing window/skylight size (if necessary) to meet maximum NECB fdwr/srr limit
  # <-3.1:  Remove all the windows/skylights
  #   > 1:  Do nothing
  #
  # By default, :srr_opt is an empty string (" "). If set to "osut", SRR is
  # instead met using OSut's 'addSkylights' (:srr_set numeric values may apply).
  def apply_fdwr_srr_daylighting(model:, fdwr_set: -1.0, srr_set: -1.0, necb_hdd: true, srr_opt: '')
    fdwr_set = -2.0 if (fdwr_set == 'NECB_default') || fdwr_set.nil? || (fdwr_set.to_f.round(0) == -1.0)
    srr_set = -2.0 if (srr_set == 'NECB_default') || srr_set.nil? || (srr_set.to_f.round(0) == -1.0)
    fdwr_set = fdwr_set.to_f
    srr_set = srr_set.to_f
    apply_standard_window_to_wall_ratio(model: model, fdwr_set: fdwr_set, necb_hdd: true)
    # apply_standard_skylight_to_roof_ratio(model: model, srr_set: srr_set)
    apply_standard_skylight_to_roof_ratio(model: model, srr_set: srr_set, srr_opt: srr_opt)
    # model_add_daylighting_controls(model) # to be removed after refactor.
  end

  def apply_standard_efficiencies(model:, sizing_run_dir:, dcv_type: 'NECB_Default', necb_reference_hp:false)
    # Do a sizing run
    try_sizing_run(model: model, sizing_run_dir: sizing_run_dir, sizing_run_subdir: 'plant_loops')

    climate_zone = 'NECB HDD Method'

    # This is needed for NECB2011 as a workaround for sizing the reheat boxes
    model.getAirTerminalSingleDuctVAVReheats.each { |iobj| air_terminal_single_duct_vav_reheat_set_heating_cap(iobj) }
    # Apply the prototype HVAC assumptions
    model_apply_prototype_hvac_assumptions(model, nil, climate_zone)
    # Apply the HVAC efficiency standard
    sql_db_vars_map = {}
    model_apply_hvac_efficiency_standard(model, climate_zone, sql_db_vars_map: sql_db_vars_map)
    model_enable_demand_controlled_ventilation(model, dcv_type)
    model_apply_existing_building_fan_performance(model: model)
    return sql_db_vars_map
  end

  # occupancy sensor control applied using lighting schedule, see apply_lighting_schedule method
  def set_occ_sensor_spacetypes(model, space_type_map)
    return true
  end

end
