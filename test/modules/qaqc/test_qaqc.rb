require_relative '../../helpers/minitest_helper'

class TestQAQC < Minitest::Test
  def setup
    @qaqc = OpenstudioStandards::QAQC
    @create = OpenstudioStandards::CreateTypical

    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # request additional output variables for QAQC
    vars = []

    # Request output variables for air loop and plant loop supply outlet nodes
    # request all because loops aren't built yet
    vars << ['System Node Temperature', 'Timestep']
    vars << ['System Node Standard Density Volume Flow Rate', 'Timestep']

    # Request equipment part load ratios
    vars << ['Boiler Part Load Ratio', 'Hourly']
    vars << ['Chiller Part Load Ratio', 'Hourly']
    vars << ['Cooling Tower Fan Electric Power', 'Hourly']
    vars << ['Cooling Coil Total Cooling Rate', 'Hourly']
    vars << ['Heating Coil Heating Rate', 'Hourly']
    vars << ['Heating Coil Air Heating Rate', 'Hourly']

    # Zone Air Terminal Sensible Heating Rate
    vars << ['Zone Air Terminal Sensible Cooling Rate', 'Hourly']

    # Ventilation flow rates
    vars << ['Zone Mechanical Ventilation Standard Density Volume Flow Rate', 'Hourly']

    # Request the day type to use in the peak demand window checks
    vars << ['Site Day Type Index', 'Timestep']

    vars.each do |var, freq|
      output_var = OpenStudio::Model::OutputVariable.new(var, model)
      output_var.setReportingFrequency(freq)
    end

    @create.create_typical_building_from_model(model, template, climate_zone: climate_zone)
    std.model_run_simulation_and_log_errors(model, "#{__dir__}/annual_run")
  end

  def test_qaqc_checks
    target_standard = '90.1-2013'
    std = Standard.build(target_standard)
    @model = std.safe_load_model("#{__dir__}/annual_run/run/in.osm")
    sql_path = OpenStudio::Path.new("#{__dir__}/annual_run/run/eplusout.sql")
    @sql = OpenStudio::SqlFile.new(sql_path)
    assert(@sql.connectionOpen)
    @model.setSqlFile(@sql)

    # check that the annual run completed and is accessible
    ann_env_pd = nil
    @sql = @model.sqlFile.get
    @sql.availableEnvPeriods.each do |env_pd|
      env_type = @sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
          break
        end
      end
    end
    assert(ann_env_pd)

    # collect attributes
    check_elems = OpenStudio::AttributeVector.new

    # eui checks
    check_elems << @qaqc.check_eui('General', target_standard)
    check_elems << @qaqc.check_eui_by_end_use('General', target_standard)

    # envelope checks
    check_elems << @qaqc.check_envelope_conductance('Baseline', target_standard)

    # internal load checks
    check_elems << @qaqc.check_internal_loads('Baseline', target_standard)
    check_elems << @qaqc.check_internal_loads_schedules('Baseline', target_standard)

    # schedules
    check_elems << @qaqc.check_schedule_coordination('General', target_standard)

    # zone conditions
    check_elems << @qaqc.check_plenum_loads('General', target_standard)
    check_elems << @qaqc.check_supply_air_and_thermostat_temperature_difference('Baseline', target_standard)
    check_elems << @qaqc.check_occupied_zones_conditioned('General', target_standard)

    # service water heating
    check_elems << @qaqc.check_service_hot_water('General', target_standard)

    # hvac system checks
    check_elems << @qaqc.check_air_loop_temperatures('General')
    check_elems << @qaqc.check_air_loop_fan_power('General', target_standard)
    check_elems << @qaqc.check_hvac_system_type('General', target_standard)
    check_elems << @qaqc.check_hvac_capacity('General', target_standard)
    check_elems << @qaqc.check_hvac_efficiency('Baseline', target_standard)
    check_elems << @qaqc.check_hvac_part_load_efficiency('General', target_standard)
    check_elems << @qaqc.check_plant_loop_capacity('General', target_standard)
    check_elems << @qaqc.check_plant_loop_temperatures('General')
    check_elems << @qaqc.check_pump_power('General', target_standard)
    check_elems << @qaqc.check_simultaneous_heating_and_cooling('General')
    check_elems << @qaqc.check_hvac_equipment_part_load_ratios('General')

    # unmet hours
    check_elems << @qaqc.check_unmet_hours('General', target_standard)

    # add checks to report_elems
    report_elems = OpenStudio::AttributeVector.new
    report_elems << OpenStudio::Attribute.new('checks', check_elems)

    # create an extra layer of report.  the first level gets thrown away.
    top_level_elems = OpenStudio::AttributeVector.new
    top_level_elems << OpenStudio::Attribute.new('report', report_elems)

    # create the report
    result = OpenStudio::Attribute.new('summary_report', top_level_elems)
    result.saveToXml(OpenStudio::Path.new('report.xml'))

    # closing the sql file
    @sql.close
  end
end