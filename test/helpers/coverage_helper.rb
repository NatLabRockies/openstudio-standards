if ENV['ENABLE_SIMPLECOV']
  require 'simplecov'

  SimpleCov.start do
    command_name("#{File.basename($0)}:#{Process.pid}")
    add_filter '/data/'
    add_filter '/doc/'
    add_filter '/vendor/'
    add_filter '/test/'
    add_group 'NECB2011',           'lib/openstudio-standards/standards/necb/NECB2011'
    add_group 'NECB2015',           'lib/openstudio-standards/standards/necb/NECB2015'
    add_group 'NECB2017',           'lib/openstudio-standards/standards/necb/NECB2017'
    add_group 'NECB2020',           'lib/openstudio-standards/standards/necb/NECB2020'
    add_group 'NECB Common',        'lib/openstudio-standards/standards/necb/common'
    add_group 'NECB ECMS',          'lib/openstudio-standards/standards/necb/ECMS'
    add_group 'NECB BTAP1980-2010', 'lib/openstudio-standards/standards/necb/BTAP1980TO2010'
    add_group 'NECB BTAP Pre-1980', 'lib/openstudio-standards/standards/necb/BTAPPRE1980'
    add_group 'BTAP',               'lib/openstudio-standards/btap/'

    # Remove cached data after 12 hours.
    # NOTE: If you are re-running test suites within this threshold, remember to
    # remove cached results if you want to start fresh.
    merge_timeout 43200
  end
end

