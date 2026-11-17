class ASHRAE9012022 < ASHRAE901
  # Get applicable performance curve for capacity as a function of temperature
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_cap_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    case cooling_type
    when 'AirCooled'
      return 'AirCooled_Chiller_2010_PathA_CAPFT'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal'
        if compliance_path == 'Path A'
          return 'WaterCooled_Centrifugal_Chiller_2010_PathA_CAPFT'
        elsif compliance_path == 'Path B'
          return 'WaterCooled_Centrifugal_Chiller_2010_PathB_CAPFT'
        else
          return nil
        end
      when 'Reciprocating', 'Rotary Screw', 'Scroll'
        return 'ChlrWtrPosDispPathAAllQRatio_fTchwsTcwsSI'
      else
        return nil
      end
    else
      return nil
    end
  end

  # Get applicable performance curve for EIR as a function of temperature
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_eir_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    case cooling_type
    when 'AirCooled'
      return 'AirCooled_Chiller_2010_PathA_EIRFT'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal'
        if compliance_path == 'Path A'
          return 'WaterCooled_Centrifugal_Chiller_2010_PathA_EIRFT'
        elsif compliance_path == 'Path B'
          return 'WaterCooled_Centrifugal_Chiller_2010_PathB_EIRFT'
        else
          return nil
        end
      when 'Reciprocating', 'Rotary Screw', 'Scroll'
        return 'ChlrWtrPosDispPathAAllEIRRatio_fTchwsTcwsSI'
      else
        return nil
      end
    else
      return nil
    end
  end

  # Get applicable performance curve for EIR as a function of part load ratio
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_eir_f_plr_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    case cooling_type
    when 'AirCooled'
      return 'AirCooled_Chiller_AllCapacities_2004_2010_EIRFPLR'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal'
        return 'ChlrWtrCentPathAAllEIRRatio_fQRatio'
      when 'Reciprocating', 'Rotary Screw', 'Scroll'
        return 'ChlrWtrPosDispPathAAllEIRRatio_fQRatio'
      else
        return nil
      end
    else
      return nil
    end
  end
end

