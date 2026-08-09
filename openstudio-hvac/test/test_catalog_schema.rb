require_relative 'test_helper'

# Schema lint for data/systems.json — the catalog is a CLOSED, hand-maintained
# vocabulary, so a typo'd key ('heating_coil_typ') or an invented value ('gas')
# would otherwise sail through silently: builders read rows with `[]`/`fetch`
# defaults, so a misspelled key just means the default quietly wins.
#
# The allowlists below were DERIVED FROM THE DATA as it stands (every key that
# actually occurs in each family), then frozen. They are not aspirational — they
# describe today's rows exactly. Adding a key to a row must therefore be a
# CONSCIOUS act: add it here AND document it in lib/openstudio_hvac/data/README.md
# (with its row count). Same for a new value in any closed vocabulary.
class TestCatalogSchema < Minitest::Test
  ROWS = OpenStudioHVAC::Catalog.rows

  # family => every key any row of that family may carry (frozen from the data)
  FAMILY_KEYS = {
    'baseboards' => %w[baseboard_type boiler_fuel family hw_source name needs_boiler origin],
    'composite' => %w[comment family name needs_boiler origin parts],
    'doas' => %w[comment family heating_type name needs_boiler origin sizing],
    'doas_pthp' => %w[comment family name needs_boiler origin sizing supp_htg_fuel sys_abbr],
    'ecm_ashp_baseboard' => %w[air_eqpt baseboard_type comment family name needs_boiler origin sizing
                               supp_htg_fuel sys_abbr vent_type],
    'ecm_doas_vrf' => %w[air_eqpt comment family name needs_boiler origin sizing supp_htg_fuel sys_abbr],
    'ecm_hp_fancoils' => %w[air_eqpt boiler_fuel comment family name needs_boiler origin plant_type sizing
                            supp_htg_fuel sys_abbr],
    'evap_cooler' => %w[family name needs_boiler origin],
    'fan_coils' => %w[chiller_type comment family fan_coil_type mau_cooling_type mau_heating_coil_type name
                      needs_boiler needs_chiller sizing sys_abbr],
    'furnace' => %w[cooling family heating name needs_boiler origin ventilation],
    'mau_ptac' => %w[baseboard_type comment family mau_heating_coil_type name needs_boiler origin reference_hp
                     sizing supp_htg_fuel sys_abbr],
    # 'heat_source' is the reference-ASHP marker (was: heating_coil_type 'DX').
    'psz' => %w[baseboard_type boiler_fuel comment family heat_source heating_coil_type name needs_boiler
                origin per_zone sizing supp_htg_fuel sys_abbr],
    'unit_heaters' => %w[family heating_type name needs_boiler origin],
    'vav_reheat' => %w[baseboard_type boiler_fuel chiller_type comment cooling_type family heating_coil_type
                       name needs_boiler needs_chiller origin sizing sys_abbr],
    'vrf' => %w[comment family name needs_boiler origin zone_ventilation],
    'wshp' => %w[boiler_fuel comment family name needs_boiler origin sizing ventilation],
    'zone_ervs' => %w[comment family name needs_boiler origin],
    'zone_terminal' => %w[baseboard_type boiler_fuel comment family heating_type name needs_boiler origin
                          unit_type]
  }.freeze

  # Closed value vocabularies. Exact-match strings — case included (the dialects
  # differ by source vocabulary: 'Gas' vs 'dx' vs 'ashp'; see data/README.md).
  ENUMS = {
    'family' => FAMILY_KEYS.keys,
    'heating_coil_type' => ['Gas', 'Electric', 'Hot Water'], # 'DX' RETIRED -> heat_source
    'heat_source' => ['ashp'],
    'baseboard_type' => ['Hot Water', 'Electric', 'None'],
    'chiller_type' => ['Scroll', 'Centrifugal', 'Rotary Screw', 'Reciprocating'],
    'mau_cooling_type' => %w[DX Hydronic], # DX IS a real coil type here — cooling
    'unit_type' => %w[ptac pthp window_ac],
    'origin' => %w[cbecs generic necb_ecm necb_reference_hp]
  }.freeze

  def test_every_family_has_an_allowlist
    families = ROWS.map { |r| r['family'] }.uniq.sort
    assert_equal FAMILY_KEYS.keys.sort, families,
                 'a family appeared/disappeared in systems.json — add or remove its key allowlist here'
  end

  def test_row_keys_are_allowlisted
    ROWS.each do |row|
      allowed = FAMILY_KEYS.fetch(row['family'])
      unknown = row.keys - allowed
      assert_empty unknown,
                   "'#{row['name']}' (#{row['family']}) carries unknown key(s) #{unknown.inspect}. " \
                   'If deliberate: add them to FAMILY_KEYS here and to data/README.md.'
    end
  end

  def test_every_row_has_the_universal_keys
    ROWS.each do |row|
      %w[name family needs_boiler].each do |key|
        assert row.key?(key), "'#{row['name'] || row.inspect}' is missing required key '#{key}'"
      end
      assert_kind_of String, row['name']
      assert_includes [true, false], row['needs_boiler'], "'#{row['name']}': needs_boiler must be a boolean"
    end
  end

  def test_names_are_unique
    names = ROWS.map { |r| r['name'] }
    duplicates = names.tally.select { |_, n| n > 1 }.keys
    assert_empty duplicates, "duplicate catalog names: #{duplicates.inspect}"
  end

  def test_closed_vocabularies
    ROWS.each do |row|
      ENUMS.each do |key, allowed|
        next unless row.key?(key)

        assert_includes allowed, row[key],
                        "'#{row['name']}': #{key} = #{row[key].inspect} is outside the closed vocabulary " \
                        "#{allowed.inspect}"
      end
    end
  end

  def test_sizing_blocks_resolve
    blocks = OpenStudioHVAC::Catalog.sizing_blocks
    ROWS.each do |row|
      next unless row.key?('sizing')

      assert blocks.key?(row['sizing']),
             "'#{row['name']}': sizing block '#{row['sizing']}' is not in sizing.json"
    end
  end

  # ---- the heat_source rename (the reference-ASHP marker) ----

  def test_reference_ashp_rows_carry_heat_source
    ashp = ROWS.select { |r| r['heat_source'] == 'ashp' }
    assert_equal 8, ashp.size, 'expected the 8 psz sys3/sys4 reference-ASHP rows'
    ashp.each do |row|
      assert_equal 'psz', row['family'], "'#{row['name']}': heat_source is a psz-family key"
      assert_equal 'necb_reference_hp', row['origin'], "'#{row['name']}': heat_source rows are reference-HP rows"
      refute row.key?('heating_coil_type'),
             "'#{row['name']}': heat_source rows must NOT also carry heating_coil_type"
      assert_includes %w[Gas Electric], row['supp_htg_fuel'],
                      "'#{row['name']}': an ASHP build needs a supplemental coil fuel"
    end
    assert_equal %w[sys_3 sys_4], ashp.map { |r| r['sys_abbr'] }.uniq.sort
  end

  def test_no_row_uses_dx_as_a_heating_coil_type
    offenders = ROWS.select { |r| r['heating_coil_type'] == 'DX' }.map { |r| r['name'] }
    assert_empty offenders,
                 "'DX' is not a heating coil type — it was the old spelling of the reference-ASHP marker. " \
                 "Use heat_source: 'ashp'. Offending rows: #{offenders.inspect}"
  end

  # mau_ptac keeps its own older marker by ruling — pinned so it neither spreads
  # to other families nor silently disappears.
  def test_reference_hp_flag_is_confined_to_mau_ptac
    flagged = ROWS.select { |r| r.key?('reference_hp') }
    assert_equal 4, flagged.size
    assert(flagged.all? { |r| r['family'] == 'mau_ptac' && r['reference_hp'] == true })
  end
end
