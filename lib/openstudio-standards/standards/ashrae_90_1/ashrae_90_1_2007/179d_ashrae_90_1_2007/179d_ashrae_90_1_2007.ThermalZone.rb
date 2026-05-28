class ACM179dASHRAE9012007

  # The v0.4-era `thermal_zone_add_exhaust` instance-method override that
  # used to live here is gone — openstudio-standards 0.8.x (commit e1509d3e,
  # "move thermal zone methods", 2024-03-15) removed `thermal_zone_add_exhaust`
  # from `Standard` and replaced it with the module function
  # `OpenstudioStandards::HVAC.create_exhaust_fan`, which doesn't dispatch
  # through inheritance. The 179D ACM exhaust-schedule logic now lives in
  # the `model_add_exhaust` override in 179d_ashrae_90_1_2007.Model.rb.

end
