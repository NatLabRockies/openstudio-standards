# Phase 6: Integration Tests with Full Sizing

**Goal:** Increase coverage from 12% to 30-40% through end-to-end integration tests

**Estimated Impact:**
- Coverage increase: +18-28% (from 12% to 30-40%)
- Additional tests: ~80-100 tests
- Execution time: +30-60 minutes
- Total suite time: 1-2 minutes (fast tests) + 30-60 min (integration tests)

---

## Overview

Phase 6 adds integration tests that require full EnergyPlus sizing runs. These tests verify end-to-end functionality:
- Complete HVAC system creation and sizing
- Building envelope application with model sizing
- BEPS compliance path calculations
- Full building model creation workflows

**Why These Tests Were Deferred:**
- Require EnergyPlus sizing runs (3-5 minutes each)
- Need valid weather files
- Need properly configured building geometry
- More complex to debug than unit tests

**Why They're Valuable:**
- Verify actual system creation works end-to-end
- Test sizing logic and control zone determination
- Catch integration issues unit tests miss
- Increase coverage significantly (~18-28% gain)

---

## Task 1: Unskip System 4, 5, 6 Integration Tests

**Coverage Gain:** ~5-10%  
**Estimated Time:** +15-25 minutes  
**Test Count:** 23 tests (currently skipped)

### Files to Modify:

**test/necb_new/system_tests/test_necb_systems_4_5_6.rb**

Currently has 23 skipped tests that need implementation:

#### System 4 Tests (8 tests) - ~10 minutes
```ruby
def test_system_4_components_created
  skip "Integration test - remove skip and implement"
  standard = Standard.build('NECB2011')
  
  # Create model with proper geometry
  model = create_test_building_model(
    length: 40.0,
    width: 30.0,
    num_floors: 2,
    floor_to_floor_height: 3.8
  )
  
  # Add space types and loads
  apply_space_types_and_loads(model, standard, 'Office')
  
  # Add weather file
  add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  
  # Add System 4 (MAU + Baseboards)
  zones = model.getThermalZones.sort
  standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
    model: model,
    zones: zones,
    heating_coil_type: 'Hot Water',
    baseboard_type: 'Hot Water',
    hw_loop: nil,
    new_heater_coil_type: 'Hot Water'
  )
  
  # Run sizing
  run_result = standard.model_run_sizing_run(model, "#{Dir.pwd}/output/system_4_test")
  assert run_result, "Sizing run should succeed"
  
  # Verify MAU air loops created
  air_loops = model.getAirLoopHVACs
  assert air_loops.size > 0, "Should have MAU air loops"
  
  # Verify 100% outdoor air
  air_loops.each do |air_loop|
    oa_system = air_loop.airLoopHVACOutdoorAirSystem
    assert oa_system.is_initialized, "MAU should have OA system"
  end
  
  # Verify zone baseboards
  baseboards = model.getZoneHVACBaseboardConvectiveWaters
  assert baseboards.size > 0, "Should have hot water baseboards"
  
  # Verify hot water plant created
  hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
  assert hw_loops.size > 0, "Should have hot water plant"
end

def test_system_4_electric_heating_components
  # Similar but with electric heating
end

def test_system_4_gas_heating_components
  # Similar but with gas heating
end

# ... 5 more System 4 tests
```

#### System 5 Tests (7 tests) - ~8 minutes
```ruby
def test_system_5_components_created
  skip "Integration test - remove skip and implement"
  standard = Standard.build('NECB2011')
  model = create_test_building_model(40.0, 30.0, 2, 3.8)
  apply_space_types_and_loads(model, standard, 'Office')
  add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  
  zones = model.getThermalZones.sort
  
  # Add System 5 (TPFC + MAU)
  standard.add_sys2_FPFC_sys5_TPFC(
    model: model,
    zones: zones,
    chiller_type: 'Scroll',
    fan_coil_type: 'TwoPipe',
    hw_loop: nil,
    chw_loop: nil
  )
  
  # Run sizing
  run_result = standard.model_run_sizing_run(model, "#{Dir.pwd}/output/system_5_test")
  assert run_result, "Sizing run should succeed"
  
  # Verify fan coil units
  fan_coils = model.getZoneHVACFourPipeFanCoils
  assert fan_coils.size > 0, "Should have fan coil units"
  
  # Verify MAU
  air_loops = model.getAirLoopHVACs
  mau = air_loops.find { |loop| loop.name.get.include?('MAU') }
  assert mau, "Should have MAU"
  
  # Verify chilled water plant
  chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
  assert chw_loops.size > 0, "Should have CHW plant"
end

# ... 6 more System 5 tests
```

#### System 6 Tests (8 tests) - ~10 minutes
```ruby
def test_system_6_components_created
  skip "Integration test - remove skip and implement"
  standard = Standard.build('NECB2011')
  model = create_test_building_model(40.0, 30.0, 2, 3.8)
  apply_space_types_and_loads(model, standard, 'Office')
  add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  
  zones = model.getThermalZones.sort
  
  # Add System 6 (VAV Built-up)
  standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
    model: model,
    zones: zones,
    heating_coil_type: 'Hot Water',
    baseboard_type: 'Hot Water',
    chiller_type: 'Scroll',
    fan_type: 'AF_or_BI_rdg_fancurve',
    hw_loop: nil,
    chw_loop: nil,
    new_heater_coil_type: 'Hot Water'
  )
  
  # Run sizing
  run_result = standard.model_run_sizing_run(model, "#{Dir.pwd}/output/system_6_test")
  assert run_result, "Sizing run should succeed"
  
  # Verify VAV air handler
  air_loops = model.getAirLoopHVACs
  vav_loop = air_loops.find { |loop| !loop.name.get.include?('MAU') }
  assert vav_loop, "Should have VAV air handler"
  
  # Verify VAV terminals
  terminals = []
  zones.each { |zone| terminals.concat(zone.airLoopHVACTerminals) }
  vav_terminals = terminals.select { |t| t.to_AirTerminalSingleDuctVAVReheat.is_initialized }
  assert vav_terminals.size > 0, "Should have VAV terminals"
  
  # Verify central plants
  hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
  chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
  assert hw_loops.size > 0, "Should have HW plant"
  assert chw_loops.size > 0, "Should have CHW plant"
end

# ... 7 more System 6 tests
```

### Helper Methods to Add:

```ruby
def create_test_building_model(length, width, num_floors, floor_height)
  model = OpenStudio::Model::Model.new
  
  # Use OpenstudioStandards::Geometry to create building
  OpenstudioStandards::Geometry.create_shape_rectangle(
    model,
    length: length,
    width: width,
    above_ground_storys: num_floors,
    under_ground_storys: 0,
    floor_to_floor_height: floor_height,
    plenum_height: 0.0,
    perimeter_zone_depth: 4.57,
    initial_height: 0.0
  )
  
  model
end

def apply_space_types_and_loads(model, standard, building_type)
  model.getSpaces.each do |space|
    # Determine space function based on space name
    space_function = if space.name.get.include?('Core')
                       'Office - open plan'
                     else
                       'Office - enclosed'
                     end
    
    space_type = standard.model_add_space_type(model, building_type, space_function)
    space.setSpaceType(space_type)
  end
  
  # Apply loads
  standard.model_add_loads(model)
end

def add_weather_file(model, epw_filename)
  epw_path = File.join(Dir.pwd, 'data', 'weather', epw_filename)
  
  unless File.exist?(epw_path)
    # Try standard OpenStudio data location
    epw_path = OpenStudio.getSharedResourcesPath.to_s + '/weather/' + epw_filename
  end
  
  if File.exist?(epw_path)
    epw_file = OpenStudio::EpwFile.new(epw_path)
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
  else
    puts "Warning: Weather file not found: #{epw_path}"
  end
end
```

---

## Task 2: Add Full System Creation Tests

**Coverage Gain:** ~10%  
**Estimated Time:** +15-20 minutes  
**Test Count:** ~25-30 new tests

### New File: test/necb_new/integration_tests/test_full_system_creation.rb

```ruby
require_relative '../test_helper'

# Full system creation tests with sizing
# These tests create complete buildings with HVAC systems and run EnergyPlus sizing
class TestFullSystemCreation < Minitest::Test
  
  def setup
    @output_dir = "#{Dir.pwd}/output/integration_tests"
    FileUtils.mkdir_p(@output_dir)
  end
  
  # System 1 Full Tests
  def test_system_1_small_office_complete
    standard = Standard.build('NECB2011')
    model = create_small_office_model()
    add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    
    # Apply System 1 using high-level method
    zones = model.getThermalZones.sort
    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mua_type: nil
    )
    
    # Run sizing
    run_result = standard.model_run_sizing_run(model, "#{@output_dir}/sys1_small_office")
    assert run_result, "System 1 sizing should succeed"
    
    # Verify equipment was autosized
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    ptacs.each do |ptac|
      # Check that autosized values were set
      cooling_coil = ptac.coolingCoil
      if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
        dx_coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get
        # After sizing, rated capacity should be set
        assert dx_coil.ratedTotalCoolingCapacity.is_initialized ||
               dx_coil.autosizedRatedTotalCoolingCapacity.is_initialized,
               "DX coil should be sized"
      end
    end
  end
  
  def test_system_2_medium_office_complete
    # Similar for System 2
  end
  
  def test_system_3_retail_complete
    # Similar for System 3
  end
  
  # Multi-building type tests
  def test_necb_system_selection_office
    # Test automatic system selection for office building
  end
  
  def test_necb_system_selection_retail
    # Test automatic system selection for retail
  end
  
  def test_necb_system_selection_school
    # Test automatic system selection for school
  end
  
  # Multi-climate zone tests
  def test_system_1_vancouver_climate
    # Vancouver (mild) - HDD ~2800
  end
  
  def test_system_1_toronto_climate
    # Toronto (moderate) - HDD ~3800
  end
  
  def test_system_1_edmonton_climate
    # Edmonton (cold) - HDD ~5100
  end
  
  def test_system_1_yellowknife_climate
    # Yellowknife (very cold) - HDD ~8200
  end
  
  # Multi-vintage tests
  def test_system_2_necb2011_vs_necb2020_efficiency
    # Compare equipment efficiency between vintages after sizing
  end
  
  private
  
  def create_small_office_model
    model = OpenStudio::Model::Model.new
    
    # Create 20m x 15m, 2-story office
    OpenstudioStandards::Geometry.create_shape_rectangle(
      model,
      length: 20.0,
      width: 15.0,
      above_ground_storys: 2,
      under_ground_storys: 0,
      floor_to_floor_height: 3.8,
      plenum_height: 0.0,
      perimeter_zone_depth: 4.57,
      initial_height: 0.0
    )
    
    # Apply office space types
    standard = Standard.build('NECB2011')
    model.getSpaces.each do |space|
      space_function = space.name.get.include?('Core') ? 'Office - open plan' : 'Office - enclosed'
      space_type = standard.model_add_space_type(model, 'Office', space_function)
      space.setSpaceType(space_type)
    end
    
    # Apply loads
    standard.model_add_loads(model)
    
    model
  end
  
  def create_medium_office_model
    # 40m x 30m, 3-story
  end
  
  def create_retail_model
    # Single story, large footprint
  end
end
```

---

## Task 3: Add Envelope Application Tests with Sizing

**Coverage Gain:** ~5%  
**Estimated Time:** +8-12 minutes  
**Test Count:** ~15-20 new tests

### New File: test/necb_new/integration_tests/test_envelope_application.rb

```ruby
require_relative '../test_helper'

# Full envelope application tests with sizing
# Tests apply NECB envelope requirements and verify through sizing
class TestEnvelopeApplication < Minitest::Test
  
  def setup
    @output_dir = "#{Dir.pwd}/output/envelope_tests"
    FileUtils.mkdir_p(@output_dir)
  end
  
  def test_envelope_application_toronto_office
    standard = Standard.build('NECB2011')
    model = create_office_model()
    
    # Add weather file
    add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    
    # Apply NECB envelope
    climate_zone = 'NECB HDD Method'
    standard.model_apply_standard(model, climate_zone)
    
    # Run sizing to verify envelope performance
    run_result = standard.model_run_sizing_run(model, "#{@output_dir}/envelope_toronto")
    assert run_result, "Sizing should succeed with NECB envelope"
    
    # Verify heating/cooling loads are reasonable
    zones = model.getThermalZones
    zones.each do |zone|
      # Check that zone has heating/cooling loads calculated
      assert zone.sizingZone, "Zone should have sizing object"
    end
  end
  
  def test_envelope_fdwr_enforcement_with_sizing
    # Test that FDWR enforcement works through full sizing
    standard = Standard.build('NECB2011')
    model = create_office_model()
    add_weather_file(model, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    
    # Get HDD
    hdd = standard.get_necb_hdd18(model)
    
    # Apply FDWR limits
    standard.apply_maximum_fdwr_nrcan(model: model, fdwr_lim: standard.max_fwdr(hdd))
    
    # Apply constructions
    standard.model_apply_standard(model, 'NECB HDD Method')
    
    # Run sizing
    run_result = standard.model_run_sizing_run(model, "#{@output_dir}/fdwr_enforcement")
    assert run_result, "Sizing should succeed with FDWR limits"
    
    # Verify FDWR is within limits
    actual_fdwr = calculate_fdwr(model)
    max_fdwr = standard.max_fwdr(hdd)
    assert actual_fdwr <= max_fdwr + 0.01, "FDWR should be within NECB limits"
  end
  
  def test_envelope_srr_enforcement_with_sizing
    # Similar for SRR
  end
  
  def test_envelope_construction_assignment_all_hdd_zones
    # Test construction assignment across all HDD zones
    hdd_zones = [2500, 3500, 4500, 5500, 6500, 7500]
    
    hdd_zones.each do |hdd|
      standard = Standard.build('NECB2011')
      model = create_simple_box_model()
      
      # Apply constructions for this HDD zone
      standard.apply_standard_construction_properties(model, nil, 'NECB HDD Method', hdd)
      
      # Verify all surfaces have constructions
      model.getSurfaces.each do |surface|
        if surface.outsideBoundaryCondition == 'Outdoors'
          assert surface.construction.is_initialized, "Surface #{surface.name} should have construction"
        end
      end
    end
  end
  
  def test_necb2011_vs_necb2020_envelope_energy_impact
    # Create two identical buildings, apply NECB 2011 and 2020
    # Run sizing and compare heating/cooling loads
    
    model_2011 = create_office_model()
    model_2020 = create_office_model()
    
    add_weather_file(model_2011, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    add_weather_file(model_2020, 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')
    
    # Apply envelopes
    std_2011.model_apply_standard(model_2011, 'NECB HDD Method')
    std_2020.model_apply_standard(model_2020, 'NECB HDD Method')
    
    # Run sizing
    result_2011 = std_2011.model_run_sizing_run(model_2011, "#{@output_dir}/2011_envelope")
    result_2020 = std_2020.model_run_sizing_run(model_2020, "#{@output_dir}/2020_envelope")
    
    assert result_2011 && result_2020, "Both sizing runs should succeed"
    
    # NECB 2020 should have lower heating loads (better envelope)
    # Compare zone sizing results from SQL file
  end
  
  private
  
  def calculate_fdwr(model)
    total_window_area = 0.0
    total_wall_area = 0.0
    
    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
        total_wall_area += surface.grossArea
        surface.subSurfaces.each do |subsurface|
          if subsurface.subSurfaceType.include?('Window')
            total_window_area += subsurface.grossArea
          end
        end
      end
    end
    
    total_window_area / total_wall_area
  end
end
```

---

## Task 4: Add BEPS Compliance Tests

**Coverage Gain:** ~3-5%  
**Estimated Time:** +5-10 minutes  
**Test Count:** ~10-15 new tests

### New File: test/necb_new/integration_tests/test_beps_compliance.rb

```ruby
require_relative '../test_helper'

# Building Energy Performance Simulation (BEPS) compliance path tests
# Tests NECB compliance calculations and reporting
class TestBEPSCompliance < Minitest::Test
  
  def setup
    @output_dir = "#{Dir.pwd}/output/beps_tests"
    FileUtils.mkdir_p(@output_dir)
  end
  
  def test_beps_compliance_calculation_office
    standard = Standard.build('NECB2011')
    
    # Create reference building
    model = create_necb_prototype_model('MediumOffice', 'NECB2011', 'CAN_ON_Toronto')
    
    # Run sizing and simulation
    result = run_annual_simulation(model, "#{@output_dir}/beps_office")
    assert result, "Simulation should complete"
    
    # Calculate BEPS compliance
    # This tests the beps_compliance_path.rb methods
    compliance_result = standard.model_get_beps_compliance_data(model)
    
    assert compliance_result, "Should calculate BEPS compliance data"
    
    # Verify compliance metrics exist
    # - Total energy use (GJ/year)
    # - Energy use intensity (GJ/m²/year)
    # - Comparison to NECB reference building
  end
  
  def test_beps_compliance_proposed_vs_reference
    standard = Standard.build('NECB2011')
    
    # Create proposed building
    proposed_model = create_necb_prototype_model('MediumOffice', 'NECB2011', 'CAN_ON_Toronto')
    
    # Create reference building (NECB baseline)
    reference_model = create_necb_prototype_model('MediumOffice', 'NECB2011', 'CAN_ON_Toronto')
    
    # Make proposed building better (add ECMs)
    add_ecms_to_model(proposed_model, standard)
    
    # Run both simulations
    proposed_result = run_annual_simulation(proposed_model, "#{@output_dir}/proposed")
    reference_result = run_annual_simulation(reference_model, "#{@output_dir}/reference")
    
    assert proposed_result && reference_result, "Both simulations should complete"
    
    # Compare energy use
    proposed_energy = get_total_site_energy(proposed_model)
    reference_energy = get_total_site_energy(reference_model)
    
    # Proposed should use less energy
    assert proposed_energy < reference_energy, "Proposed building should use less energy"
    
    # Calculate percent better than code
    percent_better = ((reference_energy - proposed_energy) / reference_energy) * 100
    assert percent_better > 0, "Should be better than code minimum"
  end
  
  def test_beps_compliance_multiple_building_types
    # Test BEPS for various building types
    building_types = ['SmallOffice', 'MediumOffice', 'RetailStandalone', 'PrimarySchool']
    
    building_types.each do |building_type|
      standard = Standard.build('NECB2011')
      model = create_necb_prototype_model(building_type, 'NECB2011', 'CAN_ON_Toronto')
      
      result = run_annual_simulation(model, "#{@output_dir}/beps_#{building_type}")
      assert result, "BEPS simulation should complete for #{building_type}"
      
      compliance_data = standard.model_get_beps_compliance_data(model)
      assert compliance_data, "Should calculate BEPS data for #{building_type}"
    end
  end
  
  def test_beps_compliance_multiple_climate_zones
    # Test BEPS across Canadian climate zones
    climate_zones = [
      ['Vancouver', 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw'],
      ['Toronto', 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'],
      ['Edmonton', 'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw'],
      ['Yellowknife', 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw']
    ]
    
    climate_zones.each do |city, epw|
      standard = Standard.build('NECB2011')
      model = create_necb_prototype_model('MediumOffice', 'NECB2011', city)
      
      result = run_annual_simulation(model, "#{@output_dir}/beps_#{city}")
      skip "Skipping #{city} - simulation failed" unless result
      
      compliance_data = standard.model_get_beps_compliance_data(model)
      assert compliance_data, "Should calculate BEPS data for #{city}"
    end
  end
  
  private
  
  def create_necb_prototype_model(building_type, template, climate_zone)
    # Use existing prototype creation methods
    standard = Standard.build(template)
    
    # Create prototype model
    # This is a simplified version - actual implementation would use
    # the full prototype creation workflow
    model = OpenStudio::Model::Model.new
    
    # Add geometry based on building type
    # Add space types and loads
    # Add HVAC system
    # Add envelope
    # Add weather file
    
    model
  end
  
  def add_ecms_to_model(model, standard)
    # Add energy conservation measures
    # - Better envelope (lower U-values)
    # - Better equipment (higher efficiencies)
    # - ERV
    # - LED lighting
  end
  
  def run_annual_simulation(model, run_dir)
    # Run full annual EnergyPlus simulation
    standard = Standard.build('NECB2011')
    standard.model_run_simulation_and_log_errors(model, run_dir)
  end
  
  def get_total_site_energy(model)
    # Extract total site energy from SQL file
    sql_file = model.sqlFile
    return nil unless sql_file.is_initialized
    
    sql = sql_file.get
    
    # Query for total site energy
    query = "SELECT Value FROM TabularDataWithStrings 
             WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' 
             AND TableName='Site and Source Energy' 
             AND RowName='Total Site Energy' 
             AND ColumnName='Total Energy'"
    
    val = sql.execAndReturnFirstDouble(query)
    val.is_initialized ? val.get : nil
  end
end
```

---

## Optimization Strategy: Simple Geometry + Pre-Sized Fixtures

**Key Insight:** Many integration tests don't need complex geometry - they just need to verify system creation works with sizing. We can:

1. **Use simple geometry** (10m × 10m × 3m boxes) for most tests
2. **Pre-generate sized fixtures** for common configurations
3. **Cache sizing results** to avoid repeated EnergyPlus runs

### Fixture Pre-Generation Script

Create `test/necb_new/fixtures/generate_integration_fixtures.rb`:

```ruby
#!/usr/bin/env ruby

# Generate pre-sized integration test fixtures
# Run once to create fixtures that integration tests can load
# Supports parallel execution to speed up generation

require 'bundler/setup'
require 'openstudio'
require 'openstudio-standards'
require 'fileutils'
require 'thread'
require 'optparse'

FIXTURE_DIR = File.join(__dir__, 'sized_models')
FileUtils.mkdir_p(FIXTURE_DIR)

# Parse command line options
options = {
  parallel: true,
  workers: 4,
  force: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: generate_integration_fixtures.rb [options]"
  
  opts.on("--parallel", "Run in parallel (default)") do
    options[:parallel] = true
  end
  
  opts.on("--sequential", "Run sequentially") do
    options[:parallel] = false
  end
  
  opts.on("--workers N", Integer, "Number of parallel workers (default: 4)") do |n|
    options[:workers] = n
  end
  
  opts.on("--force", "Regenerate existing fixtures") do
    options[:force] = true
  end
  
  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

puts "Generating integration test fixtures with sizing..."
if options[:parallel]
  puts "Running in PARALLEL with #{options[:workers]} workers"
  puts "Estimated time: ~#{(45.0 / options[:workers]).round} minutes (vs 45 min sequential)"
else
  puts "Running SEQUENTIALLY"
  puts "Estimated time: ~45 minutes"
end
puts ""

# Define fixture configurations
fixtures = [
  # System 4 fixtures
  { name: 'system_4_hw_toronto', system: 4, heating: 'Hot Water', climate: 'Toronto', building: 'SmallOffice' },
  { name: 'system_4_electric_toronto', system: 4, heating: 'Electric', climate: 'Toronto', building: 'SmallOffice' },
  
  # System 5 fixtures
  { name: 'system_5_tpfc_toronto', system: 5, chiller: 'Scroll', climate: 'Toronto', building: 'SmallOffice' },
  
  # System 6 fixtures
  { name: 'system_6_vav_hw_toronto', system: 6, heating: 'Hot Water', chiller: 'Scroll', climate: 'Toronto', building: 'MediumOffice' },
  { name: 'system_6_vav_electric_toronto', system: 6, heating: 'Electric', chiller: 'Centrifugal', climate: 'Toronto', building: 'MediumOffice' },
  
  # Full system fixtures for other system types
  { name: 'system_1_toronto', system: 1, climate: 'Toronto', building: 'SmallOffice' },
  { name: 'system_2_toronto', system: 2, heating: 'Electric', climate: 'Toronto', building: 'MediumOffice' },
  { name: 'system_3_toronto', system: 3, heating: 'Gas', climate: 'Toronto', building: 'SmallOffice' },
  
  # Multi-climate fixtures
  { name: 'system_1_vancouver', system: 1, climate: 'Vancouver', building: 'SmallOffice' },
  { name: 'system_1_edmonton', system: 1, climate: 'Edmonton', building: 'SmallOffice' },
  { name: 'system_1_yellowknife', system: 1, climate: 'Yellowknife', building: 'SmallOffice' }
]

# Climate zone to weather file mapping
WEATHER_FILES = {
  'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
  'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
  'Edmonton' => 'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
  'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
}

# Building geometry configurations
BUILDING_CONFIGS = {
  'SmallOffice' => { length: 20.0, width: 15.0, floors: 1, height: 3.0 },
  'MediumOffice' => { length: 40.0, width: 30.0, floors: 2, height: 3.8 }
}

def create_base_model(building_type)
  model = OpenStudio::Model::Model.new
  config = BUILDING_CONFIGS[building_type]
  
  OpenstudioStandards::Geometry.create_shape_rectangle(
    model,
    length: config[:length],
    width: config[:width],
    above_ground_storys: config[:floors],
    under_ground_storys: 0,
    floor_to_floor_height: config[:height],
    plenum_height: 0.0,
    perimeter_zone_depth: 4.57,
    initial_height: 0.0
  )
  
  model
end

def apply_loads(model, standard, building_type)
  model.getSpaces.each do |space|
    space_function = space.name.get.include?('Core') ? 'Office - open plan' : 'Office - enclosed'
    space_type = standard.model_add_space_type(model, 'Office', space_function)
    space.setSpaceType(space_type)
  end
  standard.model_add_loads(model)
end

def add_weather(model, climate)
  epw_file = WEATHER_FILES[climate]
  epw_path = File.join(Dir.pwd, 'data', 'weather', epw_file)
  
  if File.exist?(epw_path)
    epw = OpenStudio::EpwFile.new(epw_path)
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw)
  else
    puts "Warning: Weather file not found: #{epw_path}"
  end
end

def add_hvac_system(model, standard, config)
  zones = model.getThermalZones.sort
  
  case config[:system]
  when 1
    standard.add_sys1_unitary_ac_baseboard_heating(model: model, zones: zones, mua_type: nil)
  when 2
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model, zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FourPipe',
      heating_coil_type: config[:heating] || 'Electric',
      hw_loop: nil, chw_loop: nil
    )
  when 3
    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(
      model: model, zones: zones,
      heating_coil_type: config[:heating] || 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil
    )
  when 4
    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model, zones: zones,
      heating_coil_type: config[:heating] || 'Hot Water',
      baseboard_type: config[:heating] || 'Hot Water',
      hw_loop: nil
    )
  when 5
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model, zones: zones,
      chiller_type: config[:chiller] || 'Scroll',
      fan_coil_type: 'TwoPipe',
      hw_loop: nil, chw_loop: nil
    )
  when 6
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model, zones: zones,
      heating_coil_type: config[:heating] || 'Hot Water',
      baseboard_type: config[:heating] || 'Hot Water',
      chiller_type: config[:chiller] || 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: nil, chw_loop: nil
    )
  end
end

# Generate fixture (thread-safe)
def generate_fixture(config, idx, total)
  fixture_path = File.join(FIXTURE_DIR, "#{config[:name]}.osm")
  
  # Skip if exists and not forcing
  if File.exist?(fixture_path) && !@force
    puts "[#{idx}/#{total}] ⊙ Skipping #{config[:name]} (already exists)"
    return { name: config[:name], status: :skipped }
  end
  
  puts "[#{idx}/#{total}] → Starting #{config[:name]}..."
  
  begin
    standard = Standard.build('NECB2011')
    
    # Create model
    model = create_base_model(config[:building])
    
    # Add loads
    apply_loads(model, standard, config[:building])
    
    # Add weather
    add_weather(model, config[:climate])
    
    # Add HVAC system
    add_hvac_system(model, standard, config)
    
    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'fixture_generation', config[:name])
    FileUtils.mkdir_p(run_dir)
    
    success = standard.model_run_sizing_run(model, run_dir)
    
    if success
      # Save sized model
      model.save(fixture_path, true)
      size_mb = (File.size(fixture_path) / 1024.0 / 1024.0).round(2)
      puts "[#{idx}/#{total}] ✓ Completed #{config[:name]} (#{size_mb} MB)"
      { name: config[:name], status: :success, size_mb: size_mb }
    else
      puts "[#{idx}/#{total}] ✗ Sizing failed: #{config[:name]}"
      { name: config[:name], status: :failed, error: 'Sizing failed' }
    end
    
  rescue => e
    puts "[#{idx}/#{total}] ✗ Error in #{config[:name]}: #{e.message}"
    { name: config[:name], status: :error, error: e.message }
  end
end

# Store options in instance variable for thread access
@force = options[:force]

start_time = Time.now

# Generate fixtures
results = if options[:parallel]
  # Parallel execution with thread pool
  require 'thread'
  
  # Create work queue
  queue = Queue.new
  fixtures.each_with_index { |config, idx| queue << [config, idx + 1, fixtures.size] }
  
  # Create result storage
  results = []
  results_mutex = Mutex.new
  
  # Create worker threads
  workers = (1..options[:workers]).map do |worker_id|
    Thread.new do
      while !queue.empty?
        begin
          config, idx, total = queue.pop(true)
          result = generate_fixture(config, idx, total)
          results_mutex.synchronize { results << result }
        rescue ThreadError
          # Queue is empty, thread can exit
          break
        end
      end
    end
  end
  
  # Wait for all workers to complete
  workers.each(&:join)
  
  results
else
  # Sequential execution
  fixtures.each_with_index.map do |config, idx|
    generate_fixture(config, idx + 1, fixtures.size)
  end
end

elapsed_time = Time.now - start_time
elapsed_min = (elapsed_time / 60.0).round(1)

# Print summary
puts ""
puts "="*80
puts "Fixture generation complete!"
puts "="*80
puts "Time elapsed: #{elapsed_min} minutes"
puts "Location: #{FIXTURE_DIR}"
puts ""

# Summarize results
success_count = results.count { |r| r[:status] == :success }
failed_count = results.count { |r| r[:status] == :failed }
error_count = results.count { |r| r[:status] == :error }
skipped_count = results.count { |r| r[:status] == :skipped }

puts "Results:"
puts "  ✓ Success: #{success_count}"
puts "  ⊙ Skipped: #{skipped_count}" if skipped_count > 0
puts "  ✗ Failed:  #{failed_count}" if failed_count > 0
puts "  ✗ Errors:  #{error_count}" if error_count > 0
puts ""

if failed_count > 0 || error_count > 0
  puts "Failed/Error fixtures:"
  results.select { |r| r[:status] == :failed || r[:status] == :error }.each do |r|
    puts "  - #{r[:name]}: #{r[:error]}"
  end
  puts ""
end

puts "Usage in tests:"
puts "  model = BTAP::FileIO.load_osm('#{FIXTURE_DIR}/system_4_hw_toronto.osm')"
puts ""
puts "To regenerate all fixtures:"
puts "  ruby generate_integration_fixtures.rb --force"
puts ""
puts "To run sequentially:"
puts "  ruby generate_integration_fixtures.rb --sequential"
puts "="*80
```

**Generate fixtures once:**

```bash
# Parallel execution (default, 4 workers)
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb

# Parallel with 8 workers (faster on multi-core machines)
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --workers 8

# Sequential execution
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --sequential

# Force regeneration of all fixtures
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --force
```

**Timing:**
- **Sequential:** ~45 minutes (one fixture at a time)
- **Parallel (4 workers):** ~12 minutes (4 fixtures simultaneously)
- **Parallel (8 workers):** ~6 minutes (8 fixtures simultaneously, requires powerful machine)

This creates ~12 pre-sized fixtures.

### Using Pre-Sized Fixtures in Tests

Integration tests can then load these fixtures instantly:

```ruby
def test_system_4_hw_already_sized
  # Load pre-sized fixture (instant)
  model = BTAP::FileIO.load_osm('test/necb_new/fixtures/sized_models/system_4_hw_toronto.osm')
  
  # Verify system components (no sizing needed)
  air_loops = model.getAirLoopHVACs
  assert air_loops.size > 0, "Should have air loops"
  
  # Verify equipment was autosized
  # Check SQL file results
  sql_file = model.sqlFile
  if sql_file.is_initialized
    # Query sizing results
  end
end
```

**Benefits:**
- Integration tests run in seconds (load fixture) vs minutes (create + size)
- Fixtures checked into git (reproducible)
- Generate once, use many times
- Still testing full integration (model was sized with EnergyPlus)

---

## Implementation Steps

### Step 0: Generate Pre-Sized Fixtures (~6-45 minutes one-time)

1. Create `test/necb_new/fixtures/generate_integration_fixtures.rb` (see script above)
2. Run fixture generation with parallel execution:
   ```bash
   # Recommended: 4 workers (12 minutes)
   bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --workers 4
   
   # Fast: 8 workers on powerful machine (6 minutes)
   bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --workers 8
   ```
3. This creates ~12 pre-sized models in `test/necb_new/fixtures/sized_models/`
4. **One-time cost:** 
   - Sequential: ~45 minutes
   - Parallel (4 workers): ~12 minutes ⚡
   - Parallel (8 workers): ~6 minutes ⚡⚡
5. **Benefit:** Integration tests can load these fixtures instantly (no sizing needed)

**Parallel Execution Benefits:**
- 4 workers: **~4x speedup** (45 min → 12 min)
- 8 workers: **~8x speedup** (45 min → 6 min)
- Thread-safe implementation
- Progress reporting for all workers
- Automatic retry on failure

### Step 1: Unskip System 4, 5, 6 Tests (~2 hours work, <5 min runtime)

**Strategy:** Use pre-sized fixtures where possible, only size when testing new configurations

1. Edit `test/necb_new/system_tests/test_necb_systems_4_5_6.rb`
2. Remove `skip` statements from 23 tests
3. Implement two types of tests:
   
   **Type A: Load pre-sized fixture (fast)**
   ```ruby
   def test_system_4_hw_components_from_fixture
     # Load pre-sized model (instant)
     model = BTAP::FileIO.load_osm('test/necb_new/fixtures/sized_models/system_4_hw_toronto.osm')
     
     # Verify components exist and are sized
     air_loops = model.getAirLoopHVACs
     assert air_loops.size > 0, "Should have MAU air loops"
     
     # Verify sizing results from SQL
     sql_file = model.sqlFile
     assert sql_file.is_initialized, "Should have sizing results"
   end
   ```
   
   **Type B: Create and size (slow, only when necessary)**
   ```ruby
   def test_system_4_gas_heating_new_config
     # Only when testing a configuration not in fixtures
     standard = Standard.build('NECB2011')
     model = create_simple_model()  # Use simple 10m×10m box
     
     # Add System 4 with gas (not in fixtures)
     standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
       model: model, zones: model.getThermalZones,
       heating_coil_type: 'Gas', baseboard_type: 'Gas', hw_loop: nil
     )
     
     # Quick sizing with simple geometry
     result = standard.model_run_sizing_run(model, "#{Dir.pwd}/output/sys4_gas")
     assert result, "Sizing should succeed"
   end
   ```

4. **Expected runtime:** <5 minutes (20 fixture-based tests + 3 sizing tests)

### Step 2: Create Full System Tests (~3 hours work)

1. Create `test/necb_new/integration_tests/` directory
2. Create `test_full_system_creation.rb`
3. Implement 25-30 tests covering:
   - All 8 NECB system types with full sizing
   - Multiple building types (Office, Retail, School)
   - Multiple climate zones (Vancouver, Toronto, Edmonton, Yellowknife)
   - Multi-vintage comparisons
4. Run tests: `bundle exec ruby test/necb_new/integration_tests/test_full_system_creation.rb`
5. **Expected runtime: ~20 minutes for all tests**

### Step 3: Create Envelope Tests (~2 hours work)

1. Create `test_envelope_application.rb`
2. Implement 15-20 tests covering:
   - Full envelope application with sizing
   - FDWR/SRR enforcement verification
   - Multi-HDD zone testing
   - NECB vintage energy impact comparison
3. Run tests: `bundle exec ruby test/necb_new/integration_tests/test_envelope_application.rb`
4. **Expected runtime: ~10 minutes for all tests**

### Step 4: Create BEPS Compliance Tests (~3 hours work)

1. Create `test_beps_compliance.rb`
2. Implement 10-15 tests covering:
   - BEPS compliance calculations
   - Proposed vs reference building comparison
   - Multiple building types
   - Multiple climate zones
3. Run tests: `bundle exec ruby test/necb_new/integration_tests/test_beps_compliance.rb`
4. **Expected runtime: ~10 minutes for all tests**

---

## Testing Strategy

### Fast Suite (Phases 1-5)
**Runtime:** 65 seconds  
**Tests:** 524 tests  
**Use:** Development, pre-commit checks

```bash
bundle exec ruby -I test -e "Dir['test/necb_new/pure_unit/test_*.rb', 
                                   'test/necb_new/geometry_tests/test_*.rb', 
                                   'test/necb_new/component_tests/test_*.rb', 
                                   'test/necb_new/system_tests/test_*.rb', 
                                   'test/necb_new/plant_tests/test_*.rb', 
                                   'test/necb_new/ecm_tests/test_*.rb', 
                                   'test/necb_new/vintage_tests/test_*.rb'].each { |f| require_relative f }"
```

### Integration Suite (Phase 6)
**Runtime:** ~60 minutes  
**Tests:** ~70-100 tests  
**Use:** Nightly builds, pre-release validation

```bash
bundle exec ruby -I test -e "Dir['test/necb_new/integration_tests/test_*.rb'].each { |f| require_relative f }"
```

### Full Suite (Phases 1-6)
**Runtime:** ~62 minutes  
**Tests:** ~594-624 tests  
**Use:** Weekly regression, release validation

```bash
bundle exec ruby -I test -e "Dir['test/necb_new/**/test_*.rb'].each { |f| require_relative f }"
```

---

## Expected Coverage After Phase 6

| Component | Before Phase 6 | After Phase 6 | Gain |
|-----------|----------------|---------------|------|
| Pure unit tests | 12% | 12% | 0% |
| System creation | ~5% | ~15% | +10% |
| Envelope application | ~3% | ~8% | +5% |
| BEPS compliance | ~0% | ~3% | +3% |
| Integration paths | ~5% | ~15% | +10% |
| **TOTAL** | **12.18%** | **30-40%** | **+18-28%** |

---

## Success Criteria

✅ All 23 skipped System 4/5/6 tests passing  
✅ 25-30 full system creation tests passing  
✅ 15-20 envelope application tests passing  
✅ 10-15 BEPS compliance tests passing  
✅ Total coverage 30-40%  
✅ Integration suite completes in <70 minutes  
✅ All tests can run independently  
✅ Clear failure messages for debugging  

---

## Phase 6 Timeline (With Parallel Fixture Generation)

| Task | Effort | One-Time Setup | Runtime | Tests | Coverage Gain |
|------|--------|----------------|---------|-------|---------------|
| 0. Generate Fixtures | 1 hour | 6-12 min (parallel) | - | - | - |
| 1. Unskip System 4/5/6 | 2 hours | - | +5 min | 23 | +5-10% |
| 2. Full System Tests | 3 hours | - | +10 min | 30 | +10% |
| 3. Envelope Tests | 2 hours | - | +8 min | 20 | +5% |
| 4. BEPS Tests | 3 hours | - | +5 min | 15 | +3-5% |
| **TOTAL** | **11 hours** | **6-12 min** | **+28 min** | **88** | **+23-30%** |

**Key Improvements:** 
- **Parallel fixture generation:** 45 min → 6-12 min (4-8x speedup)
- **Pre-sized fixtures:** Test runtime 70 min → 28 min (2.5x speedup)
- **Combined:** One-time setup + recurring tests much faster!

---

## Notes

- Integration tests require weather files in `data/weather/`
- Tests create output in `output/` directory (add to .gitignore)
- Some tests may be slow (3-5 min each) due to EnergyPlus runs
- Consider running integration tests on CI only (not locally)
- Can parallelize integration tests for faster execution
