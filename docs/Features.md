# Features

openstudio-standards is intended for four main use-cases in mind:

1. Provide higher level methods to help BEM users and developers to create OpenStudio models from existing geometry, or programmatically generated geometry
2. Create typical building models in OpenStudio format
3. Create a code baseline model from a proposed model
4. Check a model against a code/standard

openstudio-standards previously supported making the DOE/PNNL prototype buildings in OpenStudio format. This has since been deprecated, as the DOE/PNNL prototypes are intended for specific code comparisons under the Energy Policy Act and are not intended to accurately represent typical existing or new buildings. While openstudio-standards still creates typical buildings, these are not the same as the highly specific DOE/PNNL prototypes that are used for code determination. Typical buildings may share the same geometry and some component level assumptions, but they strive to be more realistic and are updated regularly to reflect common practice.

The four main use-cases are all highly related, and share many common subtasks.  For example, typical buildings tend to follow minimally code-compliant DX coil efficiencies at the time of construction. Code baseline modeling also requires setting DX coil efficiencies. And checking a model against a code or standard also requires looking up DX coil efficiencies. These methods require access to the information about the minimum efficiencies, u-values, etc. that are defined in the `/data/standards` directory.

The code has been structured such that several higher level methods may all call the same lower level method. For example, both of the methods below eventually call `space_type_add_loads`.  Rather than having two copies of this code inside of the two top level methods, there is one method.

	model_create_prototype_building('Small Office, '90.1-2010', 'ASHRAE 169-2013-5A')
		model_add_schedules
			space_type_add_schedules
		model_apply_standard
			space_type_add_loads(people = true, lights = true, plug_loads = true)

	model_create_prm_baseline_building('Small Office', '90.1-2010', 'ASHRAE 169-2013-5A', 'Xcel Energy CO EDA', Dir.pwd, false)
		model_add_baseline_hvac_systems
		model_apply_standard
			space_type_add_loads(people = true, lights = true, plug_loads = false)

Where a method needs to operate **slightly differently** in two different situations, instead of duplicating the code, we make an input argument to tell that method what to do.  In the example above, `space_type_add_loads` is called with `plug_loads = true` when creating the prototype building, but `plug_loads = false` when creating the baseline model, since plug loads stay the same as the proposed model in Appendix G.

Where a method needs to operate **very differently** in two different situations, it should be broken out into a separate method.