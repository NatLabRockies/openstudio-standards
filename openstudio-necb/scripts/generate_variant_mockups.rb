#!/usr/bin/env ruby
# frozen_string_literal: true

# Variant mockup set (D-33): minimal synthetic buildings, one per reference-
# system route the archetype fleet never exercises. The whole-building sweeps
# only ever select/build Systems 1/3/4/6 (see the sweep audits); Systems 2/5,
# the hp override, the residential copy/through-the-wall branches, the
# kitchen-hood route and the 8.4.4.6 purchased-energy representations exist
# only as gem-level topology tests — none had ever been through the umbrella
# pipeline (sizing runs, post-sizing efficiencies, ERV determination).
#
# Each mockup = shared 5ZoneNoHVAC geometry + NECB catalog space types +
# catalog loads/schedules/thermostats (self-contained OSM) + a proposed HVAC
# chosen to trigger the route. Conditions the OSM cannot express
# (kitchen hood, refrigerated space, storey override) live in manifest.json
# as `building:` overrides — the same mechanism a real modeller uses.
#
# Regenerate with:  ruby openstudio-necb/scripts/generate_variant_mockups.rb
# Consumed by:      openstudio-necb/test/test_variant_mockups.rb

require 'fileutils'
require 'json'
require 'openstudio'

ROOT = File.expand_path('../..', __dir__)
require File.join(ROOT, 'openstudio-necb', 'lib', 'openstudio_necb')

OUT = File.join(ROOT, 'openstudio-necb', 'test', 'fixtures', 'variant_mockups')
FIXTURE = File.join(ROOT, 'openstudio-hvac', 'test', 'fixtures', '5ZoneNoHVAC.osm')
FileUtils.mkdir_p(OUT)

def base_model(space_type)
  model = OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  # strip the fixture's untagged space types; tag every space with ONE real
  # NECB catalog type and bake the catalog loads/schedules/thermostats in.
  map = model.getSpaces.to_h { |s| [s.nameString, ['Space Function', space_type]] }
  OpenStudioLoads.assign_space_types(model, map, vintage: '2020')
  OpenStudioLoads::NECB::Apply.apply_loads(model, vintage: '2020')
  model
end

def with_proposed(model, catalog_name)
  zones = model.getThermalZones.sort_by(&:nameString)
  OpenStudioHVAC.build_system(model, catalog_name, zones)
  model
end

# 8.4.4.6: swap the proposed's boiler/chiller for district (purchased) energy.
def districtify!(model)
  model.getBoilerHotWaters.each do |boiler|
    loop_ = boiler.plantLoop
    next if loop_.empty?

    district = OpenStudio::Model.const_defined?(:DistrictHeatingWater) ? OpenStudio::Model::DistrictHeatingWater.new(model) : OpenStudio::Model::DistrictHeating.new(model)
    loop_.get.addSupplyBranchForComponent(district)
    boiler.remove
  end
  model.getChillerElectricEIRs.each do |chiller|
    loop_ = chiller.plantLoop
    next if loop_.empty?

    district = OpenStudio::Model::DistrictCooling.new(model)
    loop_.get.addSupplyBranchForComponent(district)
    chiller.remove
  end
  model
end

MOCKUPS = {
  'sys2_museum' => {
    space_type: 'Museum restoration room',
    proposed: 'Baseboard electric',
    note: 'Historical Collections Area -> System 2 (unconditional row). NOTE: "Museum general exhibition area" instead lands in Assembly Area via the "exhibit" keyword — ambiguous vs the printed table; the chosen type avoids the collision',
    building: nil,
    expect: { selected: "System 2 -> 'FPFC MAU Chilled Water Coils with Scroll Chiller'",
              built: 'FPFC MAU Chilled Water Coils with Scroll Chiller' }
  },
  'sys5_refrigerated' => {
    space_type: 'Warehouse storage area medium to bulky palletized items',
    proposed: 'Baseboard electric',
    note: 'Warehouse Area + refrigerated condition -> System 5 (first-ever build of TPFC reference; A4 "System 5 heating" adjudication pending)',
    building: { refrigerated_zones: :all_zones },
    expect: { selected: "System 5 -> 'TPFC MAU Chilled Water Coils with Scroll Chiller'",
              built: 'TPFC MAU Chilled Water Coils with Scroll Chiller',
              article: 'refrigerated space -> System 5' }
  },
  'hp_office' => {
    space_type: 'Office enclosed <= 25 m2',
    proposed: 'PTHP',
    note: 'proposed heat pump -> Table 8.4.4.13 ASHP reference override',
    building: nil,
    expect: { selected: "System hp -> 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard'",
              built: 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard' }
  },
  'res_copy' => {
    space_type: 'Dwelling units general',
    proposed: 'PTHP',
    note: 'residential + compatible cooling -> reference identical to proposed (copy rule) through the full pipeline',
    building: nil,
    expect: { decision: 'residential with compatible cooling -> reference identical to proposed' }
  },
  'res_ttw' => {
    space_type: 'Dwelling units general',
    proposed: 'MZ BU RTU Electric Heating Coil Scroll Chiller and Electric Baseboard',
    note: 'residential + INCOMPATIBLE (central chilled-water) cooling -> through-the-wall systems',
    building: nil,
    expect: { decision: 'residential otherwise -> through-the-wall systems' }
  },
  'kitchen_hood' => {
    space_type: 'Food preparation area',
    proposed: 'Baseboard electric',
    note: 'Supermarket/Food Service + kitchen-hood condition -> System 4 (the hood ROUTE; sys 4 itself is fleet-covered)',
    building: { kitchen_hood_zones: :all_zones },
    expect: { selected: "System 4 -> 'PSZ RTU with exhaust Electric and DX Coils and Electric Baseboard'",
              article: 'food preparation with kitchen hood' }
  },
  'purchased_energy' => {
    space_type: 'Office open plan',
    proposed: 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard',
    districtify: true,
    note: '8.4.4.6 purchased heating/cooling -> gas-boiler + air-cooled-chiller representations (storeys override -> sys 6 so the chiller representation is exercised)',
    building: { storeys: 3 },
    expect: { decision: 'purchased heating energy -> represented by gas-fired modulating boiler',
              decision2: 'purchased cooling energy -> represented by air-cooled electric chiller',
              selected: "System 6 -> 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard'" }
  }
}.freeze

manifest = {}
MOCKUPS.each do |name, spec|
  model = with_proposed(base_model(spec[:space_type]), spec[:proposed])
  districtify!(model) if spec[:districtify]
  osm = File.join(OUT, "#{name}.osm")
  model.save(OpenStudio::Path.new(osm), true)

  building = spec[:building]&.transform_values do |v|
    v == :all_zones ? model.getThermalZones.map(&:nameString).sort : v
  end
  manifest[name] = { 'osm' => File.basename(osm), 'space_type' => spec[:space_type],
                     'proposed' => spec[:proposed], 'note' => spec[:note],
                     'building' => building, 'expect' => spec[:expect].transform_keys(&:to_s) }
  puts format('%-18s %-55s zones=%d', name, spec[:proposed], model.getThermalZones.size)
end

File.write(File.join(OUT, 'manifest.json'), JSON.pretty_generate(manifest))
puts "wrote #{MOCKUPS.size} mockups + manifest.json to #{OUT}"
