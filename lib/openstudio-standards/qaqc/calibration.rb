# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Calibration

    # Check the calibration against utility bills
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_nmbe [Double] maximum allowable normalized mean bias error (NMBE), default 5.0%
    # @param max_cvrmse [Double] maximum allowable coefficient of variation of the root mean square error (CVRMSE), default 15.0%
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_calibration(category, target_standard, max_nmbe: 5.0, max_cvrmse: 15.0, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Calibration')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that the model is calibrated to the utility bills.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        results = check_elems.map(&:valueAsString)
        return results
      end

      std = Standard.build(target_standard)

      begin
        # Check that there are utility bills in the model
        if @model.getUtilityBills.empty?
          check_elems << OpenStudio::Attribute.new('flag', 'Model contains no utility bills, cannot check calibration.')
        end

        # Check the calibration for each utility bill
        @model.getUtilityBills.each do |bill|
          bill_name = bill.name.get
          fuel = bill.fuelType.valueDescription

          # Consumption

          # NMBE
          if bill.NMBE.is_initialized
            nmbe = bill.NMBE.get
            if nmbe > max_nmbe || nmbe < -1.0 * max_nmbe
              check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the consumption NMBE of #{nmbe.round(1)}% is outside the limit of +/- #{max_nmbe}%, so the model is not calibrated.")
            end
          end

          # CVRMSE
          if bill.CVRMSE.is_initialized
            cvrmse = bill.CVRMSE.get
            if cvrmse > max_cvrmse
              check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the consumption CVRMSE of #{cvrmse.round(1)}% is above the limit of #{max_cvrmse}%, so the model is not calibrated.")
            end
          end

          # Peak Demand (for some fuels)
          if bill.peakDemandUnitConversionFactor.is_initialized
            peak_conversion = bill.peakDemandUnitConversionFactor.get

            # Get modeled and actual values
            actual_vals = []
            modeled_vals = []
            bill.billingPeriods.each do |billing_period|
              actual_peak = billing_period.peakDemand
              if actual_peak.is_initialized
                actual_vals << actual_peak.get
              end

              modeled_peak = billing_period.modelPeakDemand
              if modeled_peak.is_initialized
                modeled_vals << modeled_peak.get
              end
            end

            # Check that both arrays are the same size
            unless actual_vals.size == modeled_vals.size
              check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, cannot get the same number of modeled and actual peak demand values, cannot check peak demand calibration.")
            end

            # NMBE and CMRMSE
            ysum = 0
            sum_err = 0
            squared_err = 0
            n = actual_vals.size

            actual_vals.each_with_index do |actual, i|
              modeled = modeled_vals[i]
              actual *= peak_conversion # Convert actual demand to model units
              ysum += actual
              sum_err += (actual - modeled)
              squared_err += (actual - modeled)**2
            end

            if n > 1
              ybar = ysum / n

              # NMBE
              demand_nmbe = 100.0 * (sum_err / (n - 1)) / ybar
              if demand_nmbe > max_nmbe || demand_nmbe < -1.0 * max_nmbe
                check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the peak demand NMBE of #{demand_nmbe.round(1)}% is outside the limit of +/- #{max_nmbe}%, so the model is not calibrated.")
              end

              # CVRMSE
              demand_cvrmse = 100.0 * ((squared_err / (n - 1))**0.5) / ybar
              if demand_cvrmse > max_cvrmse
                check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the peak demand CVRMSE of #{demand_cvrmse.round(1)}% is above the limit of #{max_cvrmse}%, so the model is not calibrated.")
              end
            end

          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end
  end
end
