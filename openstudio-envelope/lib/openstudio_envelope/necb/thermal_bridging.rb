module OpenStudioEnvelope
  module NECB
    # NECB 3.1.1.7: the Table 3.2.2.x values are EFFECTIVE overall thermal
    # transmittance — Ut = Uo + (Σψ·L)/A + (Σχ·n)/A — so clear-field U-values alone
    # under-insulate relative to code intent. This module integrates the TBD gem
    # (rd2/tbd: linear/point thermal-bridge derating with BETBG PSI sets) to UPRATE
    # each opaque assembly so its DERATED effective transmittance meets the
    # prescriptive target.
    #
    # tbd is lazily required. When unavailable the gem still works — but this module
    # returns false and writes a LOUD audit warning that 3.1.1.7 is not accounted.
    # Never a silent clear-field result.
    module ThermalBridging
      module_function

      # TBD built-in PSI sets (BETBG-derived); a Hash of detail=>psi may be given
      # instead for custom sets (kept vocabulary-compatible with btap/bridging.rb
      # detail types for the future thermal-bridging costing linkage).
      BUILT_IN_PSI_SETS = ['poor (BETBG)', 'regular (BETBG)', 'efficient (BETBG)',
                           'spandrel (BETBG)', 'spandrel HP (BETBG)',
                           'code (Quebec)', 'uncompliant (Quebec)', '(non thermal bridging)'].freeze

      def available?
        return false if ENV['OPENSTUDIO_ENVELOPE_DISABLE_TBD'] == '1'
        return @available unless @available.nil?

        @available = begin
          require 'tbd'
          true
        rescue LoadError
          false
        end
      end

      # Uprate walls/roofs/exposed floors so the TBD-derated effective Ut meets the
      # NECB maximum U at this HDD, using the given PSI set.
      # @param psi_set [String, Hash] a TBD built-in set name or {detail => psi W/(m.K)}
      # @return [Hash, false] the TBD result hash (:io, :surfaces), or false when
      #   tbd is unavailable (audited)
      def apply(model, vintage:, hdd: nil, psi_set: 'regular (BETBG)', audit: nil)
        audit ||= AuditLog.new
        unless available?
          audit.warn(:thermal_bridging,
                     "NECB 3.1.1.7 EFFECTIVE transmittance NOT accounted: the 'tbd' gem is not " \
                     'available, so applied U-values remain clear-field (Uo). Install tbd to ' \
                     'uprate/derate for thermal bridging.',
                     article: '3.1.1.7.')
          return false
        end

        hdd = Climate.hdd18(model, hdd: hdd, audit: audit)
        raise(ArgumentError, 'HDD unresolvable: pass hdd: explicitly or set a weather file') if hdd.nil?

        targets = {
          wall_ut: NECB.max_u(vintage: vintage, surface: 'wall', boundary: 'outdoors', hdd: hdd),
          roof_ut: NECB.max_u(vintage: vintage, surface: 'roofceiling', boundary: 'outdoors', hdd: hdd),
          floor_ut: NECB.max_u(vintage: vintage, surface: 'floor', boundary: 'outdoors', hdd: hdd)
        }

        TBD.clean!
        argh = {
          uprate_walls: true, uprate_roofs: true, uprate_floors: true,
          wall_option: 'all wall constructions',
          roof_option: 'all roof constructions',
          floor_option: 'all floor constructions'
        }.merge(targets)
        if psi_set.is_a?(Hash)
          argh[:option] = '(non thermal bridging)'
          argh[:io_path] = { psis: [{ id: 'custom', building: psi_set }], building: { psi: 'custom' } }
        else
          argh[:option] = psi_set
        end

        result = TBD.process(model, argh)
        surfaces = result[:surfaces] || {}
        derated = surfaces.select { |_, s| s[:deratable] && s[:heatloss].to_f.abs > 1e-9 }

        # Forward every TBD warning+ into the audit — 'Unable to uprate X' means the
        # geometry's edge losses alone exceed the effective target with this PSI set
        # (physically infeasible), which must be visible, never swallowed.
        TBD.logs.select { |l| l[:level].to_i >= 3 }.each do |l|
          audit.warn(:thermal_bridging, "TBD: #{l[:message]}", article: '3.1.1.7.')
        end

        audit.decision(:thermal_bridging,
                       'assemblies uprated so the TBD-derated effective Ut meets the prescriptive targets',
                       inputs: { psi_set: psi_set.is_a?(Hash) ? 'custom' : psi_set, hdd: hdd,
                                 wall_ut: targets[:wall_ut], roof_ut: targets[:roof_ut],
                                 floor_ut: targets[:floor_ut], surfaces_derated: derated.size },
                       value: "total edge heat loss #{derated.values.sum { |s| s[:heatloss].to_f }.round(1)} W/K over #{derated.size} surfaces",
                       article: '3.1.1.7. (Ut = Uo + Σψ·L/A + Σχ·n/A; PSI per BETBG)')
        derated.sort_by { |name, _| name.to_s }.first(50).each do |name, s|
          audit.info(:thermal_bridging, 'surface derated for linear thermal bridging',
                     target: name.to_s,
                     inputs: { heatloss_w_per_k: s[:heatloss].to_f.round(3) },
                     article: '3.1.1.7.')
        end
        result
      end
    end
  end
end
