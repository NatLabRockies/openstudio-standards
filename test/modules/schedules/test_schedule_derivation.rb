require_relative '../../helpers/minitest_helper'

class TestSchedulesDerivation < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def test_schedule_derivation
    # load schedules data
    schedule_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/test_schedules_data.json"), symbolize_names: true)

    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # test a range of derivation params
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, schedule_data, 'conference occupancy', {})
    [0.5, 0.75, 1.0].each do |peak|
      [0.5, 1.0, 5.0].each do |response|
        params = {
          "name": "conference equipment",
          "category": "Equipment",
          "derivation_type": "linear",
          "base": 0.3,
          "peak": peak,
          "response": response,
          "winter_design_day_base": 0.0,
          "winter_design_day_peak": 0.0,
          "winter_design_day_response": 0.0,
          "summer_design_day_base": 1.0,
          "summer_design_day_peak": 1.0,
          "summer_design_day_response": 1.0
        }
        equip_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)
        equip_sch.setName("equipment_peak:#{peak}_resp:#{response}")
      end
    end

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation.osm', true)
  end

  def test_derivation_school
    # load schedules data
    schedule_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/test_schedules_data.json"), symbolize_names: true)

    # create a new model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    # test derivation for school classroom occupancy
    occ_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, schedule_data, 'school classroom occupancy', {})
    params = {
      "name": "school classroom lighting",
      "category": "Lighting",
      "derivation_type": "exponential",
      "base": 0.05,
      "peak": 0.9,
      "response": 0.5,
      "winter_design_day_base": 0.0,
      "winter_design_day_peak": 0.0,
      "winter_design_day_response": 0.0,
      "summer_design_day_base": 1.0,
      "summer_design_day_peak": 1.0,
      "summer_design_day_response": 1.0
    }
    light_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occ_sch, params)

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation_school.osm', true)
  end
end
