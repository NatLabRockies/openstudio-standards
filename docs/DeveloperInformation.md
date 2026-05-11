# Developer Information

## Setup
1. Install the [latest version of OpenStudio](https://www.openstudio.net/downloads). We recommend a minimum version of OpenStudio 3.7.0.
2. Install the Ruby version that corresponds to your OpenStudio install. See the [OpenStudio SDK Version Compatibility Matrix](https://github.com/NREL/OpenStudio/wiki/OpenStudio-SDK-Version-Compatibility-Matrix) of the correct version. OpenStudio versions 3.2.0 through 3.7.0 use Ruby 2.7.2, OpenStudio 3.8.0 and above uses Ruby 3.2.2.
	-	**On Mac**: Install Ruby 2.7.2 using [rbenv](http://octopress.org/docs/setup/rbenv/)
	- **On Windows**: Install [Ruby+Devkit 2.7.2](https://rubyinstaller.org/downloads/archives)
	- **On Linux**: Use [rbenv](http://octopress.org/docs/setup/rbenv/) or your package manger to install ruby
	- **Using BTAP development Environment**: Do nothing.
	- Call `ruby -v` from command prompt to check installed version.
3. Connect Ruby to OpenStudio:
	-	**On Mac**:
		1. Create a file called `openstudio.rb`
		2. Contents: `require "/Applications/openstudio-3.7.0/Ruby/openstudio.rb"`. Modify `3.7.0` to the OpenStudio version you installed.
		3. Save it here: `/usr/lib/ruby/site_ruby/openstudio.rb`
	-	**On Windows**:
		1. Create a file called `openstudio.rb`
		2. Contents: `require "C:/openstudio-3.7.0/Ruby/openstudio.rb"`.  Modify `3.7.0` to the OpenStudio version you installed.
		3. Save it here: `C:/Ruby27-x64/lib/ruby/site_ruby/openstudio.rb`.  Modify `Ruby27-x64` to the Ruby version you installed.
		4. Start > right click Computer > Properties > Advanced system settings > Environment variables.  In the User variables section (top) add a new Variable with the name `GEM_PATH` and the Value `C:\Ruby27-x64\lib\ruby\gems\2.5.0`. Modify `Ruby27-x64` to the Ruby version you installed.
	- **On Linux**:
		1. Create a file called `openstudio.rb`
		2. Contents: `require "/usr/local/openstudio-3.7.0/Ruby/openstudio.rb"`. Modify `3.7.0` to the OpenStudio version you installed.
		3. Save it here: `/usr/local/lib/ruby/site_ruby/openstudio.rb`.
      - If you are having trouble locating the paths in your specific linux setup, you can find the ruby version with `gem environment` in command prompt and the location of openstudio with `which openstudio`.
	- **Using BTAP development Environment**:
		1. Do nothing.
4. Install [Git](https://git-scm.com/).
5. Install [GitHub desktop](https://desktop.github.com/) or another GUI that makes Git easier to use.
6. Clone the [source code](https://github.com/NREL/openstudio-standards.git) using GitHub desktop (easier) or Git (harder).
7. Install the `bundler` ruby gem. (`gem install bundler` from command prompt)
8. Run `bundle install` in command prompt from the top level `openstudio-standards` directory. This will install the correct ruby gem versions necessary for development.

## Development Process

### Summary
1. Modify the code
2. Test the code (new code plus old code to make sure you didn't break anything)
3. Document the code
5. Push branch to GitHub repository
6. Continuous automation runs tests
7. Pull request
8. Code review and merge

This project uses [Rake](http://rake.rubyforge.org/) to run tasks from the terminal.

`bundle exec rake -T`: List all available commands
- `bundle exec rake build`                    # Build openstudio-standards-X.X.XX.gem into the pkg directory
- `bundle exec rake clean`                    # Remove any temporary products
- `bundle exec rake clobber`                  # Remove any generated files
- `bundle exec rake data:update`              # Generate JSONs from OpenStudio_Standards spreadsheets locally downloaded to data/standards
- `bundle exec rake data:export:jsons`        # Export JSONs from OpenStudio_Standards to data library
- `bundle exec rake data:update:costing`      # Update RS-Means Database
- `bundle exec rake doc`                      # Generate the documentation
- `bundle exec rake doc:show`                 # Generate the documentation and show in a web browser
- `bundle exec rake install`                  # Build and install openstudio-standards-X.X.XX.gem into system gems
- `bundle exec rake install:local`            # Build and install openstudio-standards-X.X.XX.gem into system gems without network access
- `bundle exec rake library:export`           # Export libraries for the OpenStudio Application
- `bundle exec rake release[remote]`          # Create tag vX.X.XX and build and push openstudio-standards-X.X.XX.gem to Rubygems
- `bundle exec rake rubocop`                  # Check the code for style consistency
- `bundle exec rake rubocop:auto_correct`     # Auto-correct RuboCop offenses
- `bundle exec rake rubocop:show`             # Show the rubocop output in a web browser
- `bundle exec rake test:btap_json_test`      # Run tests for btap_json_test
- `bundle exec rake test:circ-90_1_general`   # Run tests for circ-90_1_general
- `bundle exec rake test:circ-90_1_prm`       # Run tests for circ-90_1_prm
- `bundle exec rake test:circ-all-tests`      # Run tests for circ-all-tests
- `bundle exec rake test:circ-doe_prototype`  # Run tests for circ-doe_prototype
- `bundle exec rake test:circ-necb`           # Run tests for circ-necb
- `bundle exec rake test:circ-necb_bldg`      # Run tests for circ-necb_bldg
- `bundle exec rake test:necb_local_bldgs_regression_tests`  # Run tests for necb_local_bld...`

### Modify the code
As you add to/modify the code, please follow the code architecture. See the {file:docs/RepositoryStructure.md Repository Structure page} to see how the code is organized.  If you don't understand something or want to discuss your plan before you get started, contact <mailto:matthew.dahlhausen@nrel.gov>.
1. Make a new branch for your changes.
2. Modify the code on your branch.

### Modify the data
1. 90.1 standards data is available in [this database](https://github.com/pnnl/building-energy-standards-data). All 90.1 changes happen on that database. Data for other standards or templates lives in the .json files in openstudio-standards.
2. If you have data, modify the .json files and run commands to update the database, as appropriate. Historically, openstudio-standards data used a series of google spreadsheets, and is still used for non-90.1-standards. See [OpenStudio_Standards Google Spreadsheet](https://drive.google.com/drive/folders/1x7yEU4jnKw-gskLBih8IopStwl0KAMEi?usp=sharing). Contact <mailto:matthew.dahlhausen@nrel.gov> for access.
3. You may edit the spreadsheet or modify a copy of the data, then download the spreadsheet to the `data/standards` directory, and run `bundle exec rake data:update:manual` to update the JSONs.

### Test the code
Tests prove that your code works as expected, but more importantly they help make sure that changes don't break other code. If your code doesn't have tests and someone else makes changes that break it, it's your own fault.
1. Create a new file called `test_XX.rb` in the `/test/subdirectory` directory.
2. Put tests into your file. See other test files for examples.
2. Call `ruby test/sub_directory/test_XX.rb` to run your new test file.
3. Fix your code and make sure your tests pass.

### Document the code
Good documentation is critical. Changes or additions without good documentation will not be accepted. This library uses [YARD](http://yardoc.org/) to generate documentation. You simply write the documentation inline as specially tagged comments. This [YARD cheat sheet](https://gist.github.com/chetan/1827484#methods) quickly shows you how to document things. You can also look at the other methods documented in the code.

1. Make sure your methods are documented.
2. `bundle exec rake doc` Generate the documentation and document any undocumented methods that are listed
3. `bundle exec rake doc:show` Inspect the documentation in a browser to make sure it looks right.

### Push branch to GitHub
1. Commit your changes to your branch.
2. Merge /Master into your branch and resolve any conflicts.
3. Push your branch to GitHub.

### Pull request
Once your code is done and the tests are passing locally on your branch with Master merged in, go to GitHub and create a Pull Request.  This tells the main developers that you have changes to bring into the main code. They will review and suggest edits or merge.

### Code Review & Merge
The main developers will review your changes and either approve the pull request or give you some comments.  If they approve the pull request, you are done and your changes are now part of the main code!

### Look at the continuous integration results
1. When a commit is made to any branch, the continuous integration machine will run all the tests.
2. For pull requests, the status of the tests will automatically be posted to GitHub.
3. Developers will need to be given access to the continuous integration system to see detailed results.

## Issues and New Features
  - Issues and feature requests are reported on the [GitHub Repository Issues Page](https://github.com/NREL/openstudio-standards/issues).
  - Issues should be labeled according to the [OpenStudio Issue Prioritization Guide](https://github.com/NREL/OpenStudio/wiki/Issue-Prioritization).
  - Failing tests do not need to be listed as issues; they should be fixed if they fail.