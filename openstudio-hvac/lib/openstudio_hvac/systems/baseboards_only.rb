module OpenStudioHVAC
  module Systems
    # Zone baseboards with no air system (CBECS 'Baseboard electric' / 'Baseboard gas
    # boiler'): electric convective baseboards, or hot-water baseboards served by the
    # (gas) boiler loop. Heating-only; builds no air loops.
    class BaseboardsOnly < BaseSystem
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] empty (no air system)
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        baseboard_type = config['baseboard_type']
        zones.each do |zone|
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
        end
        []
      end
    end
  end
end
