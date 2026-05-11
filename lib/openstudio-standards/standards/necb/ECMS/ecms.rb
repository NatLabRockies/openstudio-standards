class ECMS < NECB2011
  @template = new.class.name
  register_standard(@template)

  # Combine the data from the JSON files into a single hash
  # Load JSON files differently depending on whether loading from
  # the OpenStudio CLI embedded filesystem or from typical gem installation
  def load_standards_database_new
    @standards_data = {}
    @standards_data['tables'] = {}

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil? && data['tables'].first['data_type'] == 'table'
          @standards_data['tables'] << data['tables'].first
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select { |e| File.file? e }
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    end

    return @standards_data
  end

  def initialize
    super()
    @standards_data = load_standards_database_new
    @standards_data['curves'] = standards_data['tables']['curves']['table']
  end

  def apply_system_ecm(model:,
                       ecm_system_name: nil,
                       template_standard:,
                       runner: nil,
                       ecm_system_zones_map_option: 'NECB_Default')
    # Do nothing if nil or other usual suspects.. covering all bases for now.
    return if ecm_system_name.nil? || ecm_system_name == 'none' || ecm_system_name == 'NECB_Default'
    # Verify the heating fuel
    primary_heating_fuel = template_standard.fuel_type_set.ecm_fueltype
    raise("Heating fuel for ECM #{ecm_system_name} is neither Electricity nor NaturalGas") if ((primary_heating_fuel != 'Electricity') && (primary_heating_fuel != 'NaturalGas'))
    ecm_system_zones_map_option = 'NECB_Default' if ecm_system_zones_map_option.nil? || ecm_system_zones_map_option == 'none'

    ecm_std = Standard.build('ECMS')
    systems = model.getAirLoopHVACs
    map_system_to_zones, system_doas_flags = ecm_std.get_map_systems_to_zones(systems)
    ecm_add_method_name = "add_ecm_#{ecm_system_name.downcase}"

    raise("the method #{ecm_add_method_name} does not exist in the ECM class. Please verify that this should be called.") unless ecm_std.respond_to? ecm_add_method_name

    # when the ecm is associated with adding a new HVAC system, then remove existing system components and loops
    ecm_std.remove_all_zone_eqpt(systems)
    OpenstudioStandards::HVAC.remove_air_loops(model)
    ecm_std.remove_hw_loops(model)
    ecm_std.remove_chw_loops(model)
    ecm_std.remove_cw_loops(model)

    ecm_std.send(ecm_add_method_name,
                 model: model,
                 system_zones_map: map_system_to_zones,
                 system_doas_flags: system_doas_flags,
                 ecm_system_zones_map_option: ecm_system_zones_map_option,
                 standard: template_standard)
  end

  def apply_system_efficiencies_ecm(model:, ecm_system_name: nil, template_standard:)
    # Do nothing if nil.
    return if ecm_system_name.nil? || ecm_system_name == 'none' || ecm_system_name == 'NECB_Default' || ecm_system_name.to_s.downcase == 'remove_airloops_add_zone_baseboards'

    ecm_std = Standard.build('ECMS')
    # Get method name that should be present in the ECM class.
    ecm_apply_eff_method_name = "apply_efficiency_ecm_#{ecm_system_name.downcase}"
    # Raise exception if method does not exists.
    raise("the method #{ecm_apply_eff_method_name} does not exist in the ECM class. Please verify that this should be called.") unless ecm_std.respond_to?(ecm_apply_eff_method_name)

    # apply system eff method.
    ecm_std.send(ecm_apply_eff_method_name, model, template_standard)
  end
end
