require_relative '../helpers/minitest_helper'


class TestRPDModelPreparation < Minitest::Test
  def setup
    # add needed class variables
    @rpd = OpenStudioStandards::RulesetChecking
  end

  def test_export_json_output_default_model
    model = OpenStudio::Model::Model.new
    @rpd.export_json_output(model)
    output_json = model.getOutputJSON
    assert(output_json.optionType == 'TimeSeriesAndTabular', "Output type shall be set to TimeSeriesAndTabular, got #{output_json.optionType} instead.")
    assert(output_json.outputJSON, "Output JSON shall be true, got 'false' instead.")
    assert(!output_json.outputCBOR, "Output CBOR shall be false, got 'true' instead.")
    assert(!output_json.outputMessagePack, "Output Message Pack shall be false, got 'true' instead.")

    output_schedules = model.getOutputSchedules
    assert(output_schedules.keyField == 'Hourly', "OutputSchedule keyField shall be Hourly, got #{output_schedules.keyField} instead")

    output_variables = model.getOutputVariables
    assert(output_variables.length == 1, "There should be one and only one output variable in the model for RPD export.")
    output_var = output_variables[0]
    assert(output_var.variableName == 'Schedule Value', "Output variable Name shall be Schedule Value, got #{output_var.variableName} instead.")
    assert(output_var.reportingFrequency == 'hourly', "Output variable reporting frequency shall be hourly, got #{output_var.reportingFrequency} instead.")
    assert(output_var.keyValue == '*', "Output variable key value shall be *, got #{output_var.keyValue} instead.")

    # assert output control table style
    outputcontrol_table_style = model.getOutputControlTableStyle
    assert(outputcontrol_table_style.columnSeparator == 'HTML', "Output control table style column separator shall set to HTML, got #{outputcontrol_table_style.columnSeparator} instead.")
    assert(outputcontrol_table_style.unitConversion == 'None', "Output control table style column separator shall set to None, got #{outputcontrol_table_style.unitConversion} instead.")

    # assert output table summary reports
    output_table_summaryreports = model.getOutputTableSummaryReports
    summary_reports = output_table_summaryreports.summaryReports
    assert(summary_reports.length == 1, "Only one summary report allowed for the output table summary report.")
    assert(summary_reports[0] == 'AllSummaryAndMonthly', "Output table summary report shall be AllSummaryAndMonthly, got #{summary_reports[0]} instead.")
  end

  def test_export_json_output_multiple_variables_model
    model = OpenStudio::Model::Model.new

    node_list = ['hypothentical node 1', 'hypothentical node 2']
    var_name = 'System Node Standard Density Volume Flow Rate'
    frequency = 'hourly'
    node_list.each do |node|
      output = OpenStudio::Model::OutputVariable.new(var_name, model)
      output.setKeyValue(node)
      output.setReportingFrequency(frequency)
    end

    @rpd.export_json_output(model)
    output_variables = model.getOutputVariables
    assert(output_variables.length == 1, "There should be one and only one output variable in the model for RPD export.")
    output_var = output_variables[0]
    assert(output_var.variableName == 'Schedule Value', "Output variable Name shall be Schedule Value, got #{output_var.variableName} instead.")
    assert(output_var.reportingFrequency == 'hourly', "Output variable reporting frequency shall be hourly, got #{output_var.reportingFrequency} instead.")
    assert(output_var.keyValue == '*', "Output variable key value shall be *, got #{output_var.keyValue} instead.")
  end
end