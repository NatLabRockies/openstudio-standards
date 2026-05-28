# frozen_string_literal: true

# Restore the 0.4-era data-driven OpenstudioStandards::Space.space_residential?
# behavior for 179D models. Standards 0.8.x replaced the data lookup with a
# regex on the space type *name* (matching /\sApartment/, /GuestRoom/,
# /PatRoom/, /ResBedroom/, /ResLiving/), which mis-classifies SmallHotel
# WholeBuilding (and other building-level residential setups commonly used
# in 179D unit tests) as Nonresidential. The downstream effect is that
# model_create_prm_baseline_building picks the Nonresidential construction
# column from construction_properties.json, producing the wrong U-values
# (e.g. CZ 1 IEAD roof: U=0.063 nonres instead of U=0.048 res).
#
# This patch falls back to the original 0.4 logic — consult standards data
# for the space type's is_residential flag — when the upstream regex match
# fails. The standards data lookup honors the 179D data overlays
# (179d_ashrae_90_1_2007.spc_typ.json marks SmallHotel/WholeBuilding as
# is_residential=Yes).
#
# We only activate the fallback when the model's Building has
# standardsTemplate set to '179D 90.1-2007' so non-179D paths (other gem
# consumers) see no behavior change.
module OpenstudioStandards
  module Space
    class << self
      unless method_defined?(:space_residential_by_name?) || respond_to?(:space_residential_by_name?)
        alias_method :space_residential_by_name?, :space_residential?
      end

      def space_residential?(space)
        return true if space_residential_by_name?(space)

        building = space.model.getBuilding
        return false unless building.standardsTemplate.is_initialized
        return false unless building.standardsTemplate.get == '179D 90.1-2007'

        space_type = space.spaceType
        return false unless space_type.is_initialized
        space_type = space_type.get

        @std_179d_for_space_residential ||= ::Standard.build('179D 90.1-2007')
        props = @std_179d_for_space_residential.space_type_get_standards_data(space_type)
        return false if props.nil? || props.empty?

        props['is_residential'] == 'Yes'
      rescue StandardError => e
        OpenStudio.logFree(OpenStudio::Warn, '179d.standards.Space',
                           "space_residential? data fallback raised #{e.class}: #{e.message}; treating as nonresidential")
        false
      end
    end
  end
end
