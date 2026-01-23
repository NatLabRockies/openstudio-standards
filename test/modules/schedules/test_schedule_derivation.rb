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

    # default params
    occ_sch = OpenstudioStandards::Schedules.model_add_parametric_schedule_full(model, schedule_data, 'conference_meeting_multipurpose_occupancy', {})
    # puts occ_sch.defaultDaySchedule

    [0.5, 0.75, 1.0].each do |peak|
      [0.5, 1, 10].each do |response|
        equip_sch = OpenstudioStandards::Schedules.model_derive_equipment_schedule(model, occ_sch, schedule_data, 'conference_meeting_multipurpose_equipment', { base: 0.1, peak: peak, response: response })
        equip_sch.setName("equipment_peak:#{peak}_resp:#{response}")
      end
    end

    model.save(File.dirname(__FILE__) + '/output/test_schedule_derivation.osm', true)
  end
end
