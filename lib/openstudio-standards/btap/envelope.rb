# *********************************************************************
# *  Copyright (c) 2008-2015, Natural Resources Canada
# *  All rights reserved.
# *
# *  This library is free software; you can redistribute it and/or
# *  modify it under the terms of the GNU Lesser General Public
# *  License as published by the Free Software Foundation; either
# *  version 2.1 of the License, or (at your option) any later version.
# *
# *  This library is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *  Lesser General Public License for more details.
# *
# *  You should have received a copy of the GNU Lesser General Public
# *  License along with this library; if not, write to the Free Software
# *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# **********************************************************************/

require "#{File.dirname(__FILE__)}/btap"

module BTAP
  module Resources #Resources
    # This module contains methods that relate to Materials, Constructions and Construction Sets
    module Envelope #Resources::Envelope
      #This method assignes interior surface construction to adiabatic surfaces from model.
      #@author phylroy.lopez@nrcan.gc.ca
      #@param model [OpenStudio::Model::Model] A model object
      def self.assign_interior_surface_construction_to_adiabatic_surfaces(model, runner = nil)
        BTAP::runner_register("Info", "assign_interior_surface_construction_to_adiabatic_surfaces", runner)
        unless model.building.get.defaultConstructionSet.empty? or model.building.get.defaultConstructionSet.get.defaultInteriorSurfaceConstructions.empty? or model.building.get.defaultConstructionSet.get.defaultInteriorSurfaceConstructions.get.wallConstruction.empty?
          #Give adiabatic surfaces a construction. Does not matter what. This is a bug in OpenStudio that leave these surfaces unassigned by the default construction set.

          all_adiabatic_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces, "Adiabatic")

          unless all_adiabatic_surfaces.empty?
            wall_construction = model.building.get.defaultConstructionSet.get.defaultInteriorSurfaceConstructions.get.wallConstruction.get
            all_adiabatic_surfaces.each { |surface| surface.setConstruction(wall_construction) }
            names = ""
            all_adiabatic_surfaces.each { |surface| name = "#{names} , #{surface.name.to_s} " }
            BTAP::runner_register("Warning", "The following adiabatic surfaces have been assigned the construction #{wall_construction.name} : #{name}", runner)
          end
        else
          BTAP::runner_register("Error", "default constructruction not defined", runner)
          return false
        end
        return true
      end

      #This method removes all envelope information from model.
      #@author phylroy.lopez@nrcan.gc.ca
      #@param model [OpenStudio::Model::Model] A model object
      def self.remove_all_envelope_information(model)
        model.getDefaultConstructionSets.each(&:remove)
        model.building.get.resetDefaultConstructionSet
        model.getDefaultSubSurfaceConstructionss.each(&:remove)
        model.getDefaultSurfaceConstructionss.each(&:remove)
        model.getPlanarSurfaces.sort.each { |item| item.resetConstruction }
        model.getConstructionBases.each(&:remove)
        model.getMaterials.each(&:remove)
        model.getInternalMassDefinitions(&:remove)
        model.getInternalMasss(&:remove)
      end

      #This module contains methods dealing with the creation and modification of constructions.
      module Constructions #Resources::Envelope::Constructions

        # TODO: These are temporary values for uMIN and uMAX that reflect the
        # current maximum and minimum assemblies for the construction database
        # from `nrcan_476`.
        @uMIN = 0.08
        @uMAX = 2.69
        class << self
          attr_reader :uMIN
          attr_reader :uMAX
        end

        #Test Constructions Module
        if __FILE__ == $0
          require 'test/unit'
          class ConstructionsTests < Test::Unit::TestCase

            #This method sets up the model.
            #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
            def setup
              @model = OpenStudio::Model::Model.new()
              #Create opaque layers from defaults
              @insulation = OpenStudio::Model::StandardOpaqueMaterial.new(@model, 'Smooth', 0.1, 0.001, 0.1, 0.1)
              @opaque = OpenStudio::Model::StandardOpaqueMaterial.new(@model, 'Smooth', 0.1, 0.1, 0.1, 100)
              @massless = OpenStudio::Model::MasslessOpaqueMaterial.new(@model, 'Smooth', 0.1)
              #Create fenestration layer from defaults.
              @simple = OpenStudio::Model::SimpleGlazing.new(@model, 0.1, 0.1)
              @simple.setThickness(0.005)
              @simple.setVisibleTransmittance(0.8)
              @standard = OpenStudio::Model::StandardGlazing.new(@model, 'SpectralAverage', 0.003)
              @opaque_construction = BTAP::Resources::Envelope::Constructions::create_construction(@model, "test construction", [@opaque, @insulation, @massless, @opaque], @insulation)
              @fenestration_construction = BTAP::Resources::Envelope::Constructions::create_construction(@model, "test construction", [@simple, @standard])

              array = [@opaque, "insulation"]
              BTAP::Common::validate_array(@model, array, "Material")
            end

            #This method will create a test opaque construction.
            #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
            def test_create_opaque_construction()
              construction = BTAP::Resources::Envelope::Constructions::create_construction(@model, "test construction", [@opaque, @insulation, @massless, @opaque], @insulation)
              #Check that the construction was created
              assert(!(construction.to_Construction.empty?))
              #check that all layers were entered
              assert_equal(5, construction.layers.size)
              #check insulation was set.
              assert(construction.insulation().get == @insulation)
            end

            #This method will test creation of fenestration construction.
            #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
            def test_create_fenestration_construction()
              construction = BTAP::Resources::Envelope::Constructions::create_construction(@model, "test construction", [@simple, @standard])
              assert_equal(6, construction.layers.size)
              assert(!(construction.to_Construction.empty?))
            end

            #This method will create new construction based on exisiting.
            #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
            def test_create_new_construction_based_on_exisiting()
              #              opaque
              new_construction = BTAP::Resources::Envelope::Constructions::customize_opaque_construction(@model, @opaque_construction, 0.05)
              assert_in_delta(0.05, new_construction.thermalConductance.to_f, 0.00001)
              #              fenestration
              new_construction = BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(@model, @fenestration_construction, 0.5, nil, nil, 0.0)
              assert_in_delta(0.5, OpenstudioStandards::Constructions.construction_get_conductance(new_construction).to_f, 0.00001)
            end
          end
        end # End Test Constructions

        #This method will create a new construction based on self and a new conductance value.
        #It will check to see if a similar construction has already been created by this method
        #if so it will return the existing construction. If you wish to keep some of the properties, enter the
        #string "default" instead of a numerical value.
        #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
        #@param model [OpenStudio::Model::Model]
        #@param construction <String>
        #@param conductance [Fixnum]
        #@return [<String]OpenStudio::Model::getConstructionByName] new_construction
        def self.customize_opaque_construction(model, construction, conductance)
          #Will convert from a string identifier to an object if required.
          construction = BTAP::Common::validate_array(model, construction, "Construction").first
          #If it is Opaque
          raise ("This construction is not opaque :#{construction.name}") unless (construction.isOpaque)
          minimum_resistance = 0
          base_cons_name = construction.name.to_s
          if match = construction.name.to_s.match(/(.*)?:(.*)?/)
            base_cons_name = match.captures[0]
          end
          name_prefix = "#{base_cons_name}:U-#{conductance}"

          #Check to see if we already made one like this.
          existing_construction = OpenStudio::Model::getConstructionByName(construction.model, name_prefix)
          if not existing_construction.empty?
            # if so, return existing construction
            return existing_construction.get
          end

          #create a copy
          new_construction = OpenstudioStandards::Constructions.construction_deep_copy(construction)

          #Change Construction name in clone
          new_construction.setName(name_prefix)

          if conductance.kind_of?(Float)
            #re-find insulation layer
            OpenstudioStandards::Constructions.construction_find_and_set_insulation_layer(new_construction)

            #Determine how low the resistance can be set. Subtract exisiting insulation
            #Values from the total resistance to see how low we can go.
            minimum_resistance = (1 / new_construction.thermalConductance.to_f) - (1.0 / new_construction.insulation.get.thermalConductance.to_f)

            #Check if the requested resistance is smaller than the minimum
            # resistance. If so, revise the construction layers.
            if minimum_resistance > (1 / conductance)
              # Changing the insulation layer will not be enough so either start removing layers or modify them to get
              # to the required conductance.
              new_construction = adjust_opaque_construction(construction: new_construction, req_conductance: conductance.to_f)
            else
              unless new_construction.setConductance(conductance)
                raise("could not set conductance of construction #{new_construction.name.to_s}")
              end
            end
          end
          return new_construction
        end

        # This removes construction layers if the required conductance for a construction is higher than the maximum
        # conductance that construction can have.  Otherwise it modifies existing layers to set their thickness or
        # resistance values (depending on what is in the layer) to achieve the required conductance.
        # @author Chris Kirney <chris.kirney@canada.ca>
        # @param construction <String> the construction we are modifying
        # @param req_conductance [Fixnum] the conductance we are trying to reach
        # @return [<String]OpenStudio::Model::getConstructionByName] the final construction after modification
        def self.adjust_opaque_construction(construction:, req_conductance:)
          layer_comp = []
          # Extract the thickness, conductivity, resistance of each layer of the construction.  If the material is
          # "No Mass", or "Air gap" set the conductivity (how well the material conducts heat) and conductance (how well
          # the material with a given thickness conducts heat) to the inverse of the resistance.  This is because
          # No Mass and Air gap materials do not have a thickness value.  Also, include which layer index the material
          # has and the material object itself.
          construction.layers.each_with_index do |layer, layer_index|
            mat_type = layer.iddObjectType.valueName.to_s
            case mat_type
            when "OS_Material"
              mat_layer = layer.to_StandardOpaqueMaterial.get
              layer_comp << {
                  thickness_m: mat_layer.thickness.to_f,
                  conductivity_SI: mat_layer.conductivity.to_f,
                  conductance_SI: (mat_layer.conductivity.to_f / mat_layer.thickness.to_f),
                  resistance_SI: (mat_layer.thickness.to_f / mat_layer.conductivity.to_f),
                  construction_index: layer_index,
                  layer_object: mat_layer
              }
            when "OS_Material_NoMass"
              mat_layer = layer.to_MasslessOpaqueMaterial.get
              layer_comp << {
                  thickness_m: 0,
                  conductivity_SI: 1.0 / mat_layer.thermalResistance.to_f,
                  conductance_SI: 1.0 / mat_layer.thermalResistance.to_f,
                  resistance_SI: mat_layer.thermalResistance.to_f,
                  construction_index: layer_index,
                  layer_object: mat_layer
              }
            when "OS_Material_AirGap"
              mat_layer = layer.to_AirGap.get
              layer_comp << {
                  thickness_m: 0,
                  conductivity_SI: 1.0 / mat_layer.thermalResistance.to_f,
                  conductance_SI: 1.0 / mat_layer.thermalResistance.to_f,
                  resistance_SI: mat_layer.thermalResistance.to_f,
                  construction_index: layer_index,
                  layer_object: mat_layer
              }
            end
          end
          # Sort the above layers by the conductivity of the layers.  The lowest conductivity layers first followed by
          # layers with progressively higher conductivities.
          sorted_layers = layer_comp.sort { |a, b| b[:conductivity_SI] <=> a[:conductivity_SI] }
          index = 0
          total_conductance = construction.thermalConductance.to_f
          # The following loop steps through the array of layers, sorted form highest conductivity to lowest.  It
          # deletes a layer in the construction if the conductance for the layer is not enough to reach the total
          # conductance for the construction that we are trying to reach.  If modifies the thickness or resistance
          # (depending on the layer material type) of a layer if doing so will reach the overall construction
          # conductance target. The total conductance of the construction is rounded because the conductance never seems
          # to be set precisely enough.

          while total_conductance.round(4) < req_conductance
            # There are too indicies that are tracked:
            # index:  The index of the element in the sorted array of layers that we are currently considering
            # const_index:  The index of the layer we are currently considering in the construction
            # Note that both the construction array and sorted array contain the same elements.  However these elements
            # may be in a different order.  Thus, the index and const_index may be different.  They will both indicate
            # the same layer.  However, they may differ because the sorted array is sorted by conductivity while the
            # construction array is ordered with the first layer outside (a given space) and the final layer inside (a
            # given space).
            const_index = sorted_layers[index][:construction_index]
            # Check if modifying the resistance of the currently layer will be enough to reach our total construction
            # conductance goal.  If it will, modify the layer.  If it will not, delete the layer.
            if sorted_layers[index][:resistance_SI] > ((1.0 / total_conductance) - (1.0 / req_conductance))
              # If the current layer is a NoMass or AirGap material its thickness is zero so we set the resistance.
              if sorted_layers[index][:thickness_m] == 0
                # Determine the resistance we want to set the layer to.
                res_mod = sorted_layers[index][:resistance_SI] - ((1.0 / total_conductance) - (1.0 / req_conductance))
                # Find out if the layer is an AirGap or NoMass and set the resistance for the layer with the right
                # command systax.
                mat_type = construction.layers[const_index].iddObjectType.valueName.to_s
                case mat_type
                when "OS_Material_NoMass"
                  construction.layers[const_index].to_MasslessOpaqueMaterial.get.setThermalResistance(res_mod)
                when "OS_Material_AirGap"
                  construction.layers[const_index].to_AirGap.get.setThermalResistance(res_mod)
                end
              else
                # The the current layer is a regular opaque material it has a thickness so we set that to reach the
                # desired resistance for that layer.
                # Determine the thickness we want to set the layer.
                thick_mod = (sorted_layers[index][:resistance_SI] - ((1.0 / total_conductance) - (1.0 / req_conductance))) * (sorted_layers[index][:conductivity_SI])
                # Set the thickness of the layer.
                construction.layers[const_index].to_StandardOpaqueMaterial.get.setThickness(thick_mod)
              end
              # Step the index of the sorted array forward by 1.  We should be able to leave the loop now because the
              # construction should have the conductance we want now.  But you never know.
              index += 1
            else
              # There the layer could not be adjusted to reach the desired conductance for the construction so get rid
              # of the layer.
              # If this is the only layer then we cannot get rid of it so throw an error.  This should never happen but
              # you never know.
              if sorted_layers.size == 1
                raise ("Could not set conductance of construction #{construction.name.to_s} to #{req_conductance} because existing layers make this impossible. Could not automatically change the constructions. Change the construction to allow for this conductance to be set.")
                return construction
              end
              # Delete the layer from the construction.
              construction.eraseLayer(const_index)
              # Delete the layer from the sorted set of layers (so that both the construction array and sorted array
              # continue to contain the same layers).
              sorted_layers.delete_at(index)
              # Go through the sorted array and change the construction indicies so that they continue to point to the
              # correct layers of the construction array. Note that index is not increased.  This is because the element
              # we were looking at just got removed so its index will be the same as that of what would have been the
              # next element.
              sorted_layers.each do |sorted_layer|
                if sorted_layer[:construction_index] > (const_index - 1)
                  sorted_layer[:construction_index] -= 1
                end
              end
            end
            # Get the revised conductance for the construction now that it has been modified (by either removing or
            # modifying layers).
            total_conductance = construction.thermalConductance.to_f
            # Check if we have anything left to modify.  If yes, then keep going.  If not, then if we have done enough
            # we can stop and return the revised construction, otherwise throw an error.
            if construction.layers.size < index + 1
              if total_conductance.round(4) >= req_conductance
                return construction
              else
                raise ("Could not set conductance of construction #{construction.name.to_s} from the current conductance of #{total_conductance} to #{req_conductance} because existing layers make this impossible. Change the construction to allow for this conductance to be set.")
                return construction
              end
            end
          end
          # We have achieved our goal, return the revised construction.
          return construction
        end

        # This checks if the construction layer can be modified to set thermal resistance of the whole construction to
        # be less than the required resistance
        # @author Chris Kirney <chris.kirney@canada.ca>
        # @param mat_resistance <Fixnum>
        # @param total_conductance <Fixnum>
        # @param req_conductance <Fixnum>
        # @return [<Fixnum>] layer resistance needed to meet construction material resistance, -999 if this is not enough
        def self.should_modify_layer(mat_resistance:, total_conductance:, req_conductance:)
          # Determine if the amount of resistance you can modify in this layer is greater than the amount of resistance
          # you have to change.
          if mat_resistance > ((1.0 / total_conductance) - (1.0 / req_conductance))
            # If yes, determine what the resistance for this layer should be to meet the required resistance of the
            # entire assembly.  Then return the new resistance value.
            target_res = mat_resistance - ((1.0 / total_conductance) - (1.0 / req_conductance))
            return target_res
          else
            # If no, then return an unambiguous no.
            return -999
          end
        end

        #This will create construction model
        #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
        #@param model [OpenStudio::Model::Model]
        #@param name <String>
        #@param materials <Material>
        #@param insulationLayer = nil
        #@return [String] construction
        def self.create_construction(model, name, materials, insulationLayer = nil)
          construction = OpenStudio::Model::Construction.new(model)
          construction.setName(name)
          #check to see if they are all Fenestation or Opaque. Can't mix and match.
          is_fenestration = false
          is_opaque = false
          #check to see if materials are all the same type.
          materials.each do |material|
            is_fenestration = true unless material.to_FenestrationMaterial.empty?
            is_opaque = true unless material.to_OpaqueMaterial.empty?
          end
          raise ("Materials Passed are not valid. Either they are mixed Opaque/Fenestration or invalid materials") if (is_fenestration and is_opaque) or (not is_fenestration and not is_opaque)
          construction.setLayers(materials)
          construction.setInsulation(insulationLayer) unless nil == insulationLayer or is_fenestration
          return construction
        end

        #This will customize fenestration construction
        #@author Phylroy A. Lopez <plopez@nrcan.gc.ca>
        #@param model [OpenStudio::Model::Model]
        #@param construction <String>
        #@param conductance <String> = nil
        #@param solarTransmittanceatNormalIncidence [Float] = nil
        #@param visibleTransmittance [Float] = nil
        #@param at_temperature_c [Float] = 0.0
        #@return [String] create_construction
        def self.customize_fenestration_construction(
            model,
            construction,
            conductance = nil,
            solarTransmittanceatNormalIncidence = nil,
            visibleTransmittance = nil,
            at_temperature_c = 0.0)
          construction = OpenStudio::Model::getConstructionByName(model, construction.name.to_s).get
          raise ("This is not a fenestration!") unless construction.isFenestration
          #get equivilant values for tsol, tvis, and conductances.
          #TSol in this case is SHGC
          solarTransmittanceatNormalIncidence = OpenstudioStandards::Constructions.construction_get_solar_transmittance(construction) if solarTransmittanceatNormalIncidence.nil?
          visibleTransmittance = OpenstudioStandards::Constructions.construction_get_visible_transmittance(construction) if visibleTransmittance.nil?
          conductance = OpenstudioStandards::Constructions.construction_get_conductance(construction) if conductance.nil?
          frontSideSolarReflectanceatNormalIncidence = 1.0 - solarTransmittanceatNormalIncidence
          backSideSolarReflectanceatNormalIncidence = 1.0 - solarTransmittanceatNormalIncidence
          frontSideVisibleReflectanceatNormalIncidence = 0.081000
          backSideVisibleReflectanceatNormalIncidence = 0.081000
          infraredTransmittanceatNormalIncidence = 0.0
          frontSideInfraredHemisphericalEmissivity = 0.84
          backSideInfraredHemisphericalEmissivity = 0.84
          #store part of fenestation in array bins.
          glazing_array = Array.new()
          shading_material_array = Array.new()
          gas_array = Array.new()
          construction.layers.each do |material|
            glazing_array << material unless material.to_Glazing.empty?
            shading_material_array << material unless material.to_ShadingMaterial.empty?
            gas_array << material unless material.to_GasLayer.empty?
          end

          #set value of fictious glazing based on the fenestrations front and back if available
          unless glazing_array.first.to_StandardGlazing.empty?
            frontSideSolarReflectanceatNormalIncidence = glazing_array.first.to_StandardGlazing.get.frontSideSolarReflectanceatNormalIncidence
            frontSideVisibleReflectanceatNormalIncidence = glazing_array.first.to_StandardGlazing.get.frontSideVisibleReflectanceatNormalIncidence
            frontSideInfraredHemisphericalEmissivity = glazing_array.first.to_StandardGlazing.get.frontSideInfraredHemisphericalEmissivity
          end

          unless glazing_array.last.to_StandardGlazing.empty?
            backSideSolarReflectanceatNormalIncidence = glazing_array.last.to_StandardGlazing.get.backSideSolarReflectanceatNormalIncidence
            backSideVisibleReflectanceatNormalIncidence = glazing_array.last.to_StandardGlazing.get.backSideVisibleReflectanceatNormalIncidence
            backSideInfraredHemisphericalEmissivity = glazing_array.last.to_StandardGlazing.get.backSideInfraredHemisphericalEmissivity
          end
          #create fictious glazing.
          #assume a thickness of 0.10m
          thickness = 0.10
          #calculate conductivity
          conductivity = conductance * thickness
          data_name_suffix = "U=#{("%.3f" % conductivity).to_s} SHGC=#{("%.3f" % solarTransmittanceatNormalIncidence).to_s}"
          base_cons_name = construction.name.to_s
          if match = construction.name.to_s.match(/(.*)?:(.*)?/)
            base_cons_name = match.captures[0]
          end
          cons_name = "#{base_cons_name}:" + data_name_suffix
          glazing_name = "SimpleGlazing:" + data_name_suffix
          #Search to prevent the massive duplication that may ensue.
          return model.getConstructionByName(cons_name).get unless model.getConstructionByName(cons_name).empty?

          #fix for Simple glazing
          glazing_name = "SimpleGlazing:" + data_name_suffix
          glazing = nil
          if model.getSimpleGlazingByName(glazing_name).empty?
            glazing_name = "SimpleGlazing:" + data_name_suffix
            glazing = OpenStudio::Model::SimpleGlazing.new(construction.model)
            glazing.setSolarHeatGainCoefficient(solarTransmittanceatNormalIncidence)
            glazing.setUFactor(conductance)
            glazing.setThickness(0.21)
            glazing.setVisibleTransmittance(visibleTransmittance)
            glazing.setName(glazing_name)
          else
            glazing = model.getSimpleGlazingByName(glazing_name).get
          end

          #add the glazing and any shading materials to the array and create construction based on this.
          new_materials_array = Array.new()
          new_materials_array << glazing
          new_materials_array.concat(shading_material_array) unless shading_material_array.empty?
          #puts new_materials_array.size
          return self.create_construction(construction.model, cons_name, new_materials_array)
        end
      end #module Constructions

      #This module contains methods for creating ConstructionSets.
      module ConstructionSets #Resources::Envelope::ConstructionSets

        #Test Constructions Module
        if __FILE__ == $0
          require 'test/unit'
          class ConstructionsSetTests < Test::Unit::TestCase

            #This method creates default surface constructions
            #@author phylroy.lopez@nrcan.gc.ca
            def test_create_default_surface_constructions()
              model = OpenStudio::Model::Model.new()
              #Create layers from defaults
              insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.1, 0.001, 0.1, 0.1)
              opaque = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.1, 0.1, 0.1, 100)
              massless = OpenStudio::Model::MasslessOpaqueMaterial.new(model, 'Smooth', 0.1)
              construction = BTAP::Resources::Envelope::Constructions::create_construction(model, "test construction", [opaque, insulation, massless, opaque], insulation)
              walls_cons = floor_cons = roof_cons = construction
              construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_surface_constructions(model, "test construction set", walls_cons, floor_cons, roof_cons)
              #Check that the construction was created
              assert(!(construction_set.to_DefaultSurfaceConstructions.empty?))
            end

            #This method creates default subsurface constructions
            #@author phylroy.lopez@nrcan.gc.ca
            def test_create_default_subsurface_constructions()
              model = OpenStudio::Model::Model.new()
              #Create layers from defaults
              simple = OpenStudio::Model::SimpleGlazing.new(model, 0.1, 0.1)
              simple.setThickness(0.005)
              simple.setVisibleTransmittance(0.8)
              standard = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
              fixedWindowConstruction = BTAP::Resources::Envelope::Constructions::create_construction(model, "test construction", [simple, standard])
              operableWindowConstruction = setDoorConstruction = setGlassDoorConstruction = overheadDoorConstruction = skylightConstruction = tubularDaylightDomeConstruction = tubularDaylightDiffuserConstruction = fixedWindowConstruction
              default_subsurface_constructions = BTAP::Resources::Envelope::ConstructionSets::create_subsurface_construction_set(
                  model,
                  fixedWindowConstruction,
                  operableWindowConstruction,
                  setDoorConstruction,
                  setGlassDoorConstruction,
                  overheadDoorConstruction,
                  skylightConstruction,
                  tubularDaylightDomeConstruction,
                  tubularDaylightDiffuserConstruction)
              assert(!(default_subsurface_constructions.to_DefaultSubSurfaceConstructions.empty?))
            end

            #This method creates default constructions
            #@author phylroy.lopez@nrcan.gc.ca
            def test_create_default_construction_set()
              model = OpenStudio::Model::Model.new()
              #Create layers from defaults
              insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.1, 0.001, 0.1, 0.1)
              opaque = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.1, 0.1, 0.1, 100)
              massless = OpenStudio::Model::MasslessOpaqueMaterial.new(model, 'Smooth', 0.1)
              construction = BTAP::Resources::Envelope::Constructions::create_construction(model, "test construction", [opaque, insulation, massless, opaque], insulation)
              walls_cons = floor_cons = roof_cons = construction
              exterior_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_surface_constructions(model, "test construction set", walls_cons, floor_cons, roof_cons)
              interior_construction_set = ground_construction_set = exterior_construction_set

              #Create layers from defaults
              simple = OpenStudio::Model::SimpleGlazing.new(model, 0.1, 0.1)
              simple.setThickness(0.005)
              simple.setVisibleTransmittance(0.8)
              standard = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
              fixedWindowConstruction = BTAP::Resources::Envelope::Constructions::create_construction(model, "test construction", [simple, standard])
              operableWindowConstruction = setDoorConstruction = setGlassDoorConstruction = overheadDoorConstruction = skylightConstruction = tubularDaylightDomeConstruction = tubularDaylightDiffuserConstruction = fixedWindowConstruction
              ext_subsurface_constructions = BTAP::Resources::Envelope::ConstructionSets::create_subsurface_construction_set(
                  model,
                  fixedWindowConstruction,
                  operableWindowConstruction,
                  setDoorConstruction,
                  setGlassDoorConstruction,
                  overheadDoorConstruction,
                  skylightConstruction,
                  tubularDaylightDomeConstruction,
                  tubularDaylightDiffuserConstruction)

              int_subsurface_constructions = ext_subsurface_constructions

              construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_construction_set(
                  model,
                  "default construction set test",
                  exterior_construction_set,
                  interior_construction_set,
                  ground_construction_set,
                  ext_subsurface_constructions,
                  int_subsurface_constructions)

              #Check that the construction was created
              assert(!(construction_set.to_DefaultConstructionSet.empty?))
            end
          end
        end

        #This method set the default construction set from an OSM library file and the construction set name.
        #params construction_library_file [String] Path to osm file that contains the contruction set to be used.
        #params construction_set_name [String] Name of the construction set to be used.
        def self.set_construction_set_by_file(model, construction_library_file, construction_set_name, runner = nil)
          BTAP::runner_register("Info", "set_construction_set_by_file(#{construction_library_file}, #{construction_set_name})")
          #check if file exists
          unless File.exist?(construction_library_file) == true
            BTAP::runner_register("Error", "Could not find #{construction_library_file}", runner)
            return false
          end
          construction_set = BTAP::Resources::Envelope::ConstructionSets::get_construction_set_from_library(construction_library_file, construction_set_name)
          #check if construction set name exists and can apply to the model.
          unless model.building.get.setDefaultConstructionSet(construction_set.clone(model).to_DefaultConstructionSet.get)
            BTAP::runner_register("Error", "Could not use default construction set #{construction_set_name} from #{construction_library_file} ", runner)
            return false
          end
          #sets all surfaces to use default constructions except adiabatic, where it does a hard assignment of the interior wall construction type.
          model.getPlanarSurfaces.sort.each { |item| item.resetConstruction }
          #if the default construction set is defined..try to assign the interior wall to the adiabatic surfaces
          BTAP::Resources::Envelope::assign_interior_surface_construction_to_adiabatic_surfaces(model, runner)
          BTAP::runner_register("Info", "set_construction_set_by_file(#{construction_library_file}, #{construction_set_name}) Completed Sucessfully.")
          return true
        end

        #This method customizes default surface construction and sets conductance
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param name [String]
        #@param default_surface_construction_set <String>
        #@param ext_wall_cond [Float] = nil
        #@param ext_floor_cond [Float] = nil
        #@param ext_roof_cond [Float] = nil
        #@param ground_wall_cond [Float] = nil
        #@param ground_floor_cond [Float] = nil
        #@param ground_roof_cond [Float] = nil
        #@param fixed_window_cond [Float] = nil
        #@param fixed_wind_solar_trans [Float] = nil
        #@param fixed_wind_vis_trans [Float] = nil
        #@param operable_window_cond [Float] = nil
        #@param operable_wind_solar_trans [Float] = nil
        #@param operable_wind_vis_trans [Float] = nil
        #@param door_construction_cond [Float] = nil
        #@param glass_door_cond [Float] = nil
        #@param glass_door_solar_trans [Float] = nil
        #@param glass_door_vis_trans [Float] = nil
        #@param overhead_door_cond [Float] = nil
        #@param skylight_cond [Float] = nil
        #@param skylight_solar_trans [Float] = nil
        #@param skylight_vis_trans [Float] = nil,
        #@param tubular_daylight_dome_cond [Float] = nil
        #@param tubular_daylight_dome_solar_trans [Float] = nil
        #@param tubular_daylight_dome_vis_trans [Float] = nil,
        #@param tubular_daylight_diffuser_cond [Float] = nil
        #@param tubular_daylight_diffuser_solar_trans [Float] = nil
        #@param tubular_daylight_diffuser_vis_trans [Float] = nil
        def self.customize_default_surface_construction_set!(model:,
                                                             name:,
                                                             default_surface_construction_set:,
                                                             # ext surfaces
                                                             ext_wall_cond: nil,
                                                             ext_floor_cond: nil,
                                                             ext_roof_cond: nil,
                                                             # ground surfaces
                                                             ground_wall_cond: nil,
                                                             ground_floor_cond: nil,
                                                             ground_roof_cond: nil,
                                                             # fixed Windows
                                                             fixed_window_cond: nil,
                                                             fixed_wind_solar_trans: nil,
                                                             fixed_wind_vis_trans: nil,
                                                             # operable windows
                                                             operable_wind_solar_trans: nil,
                                                             operable_window_cond: nil,
                                                             operable_wind_vis_trans: nil,
                                                             # glass doors
                                                             glass_door_cond: nil,
                                                             glass_door_solar_trans: nil,
                                                             glass_door_vis_trans: nil,
                                                             # opaque doors
                                                             door_construction_cond: nil,
                                                             overhead_door_cond: nil,
                                                             # skylights
                                                             skylight_cond: nil,
                                                             skylight_solar_trans: nil,
                                                             skylight_vis_trans: nil,
                                                             # tubular daylight dome
                                                             tubular_daylight_dome_cond: nil,
                                                             tubular_daylight_dome_solar_trans: nil,
                                                             tubular_daylight_dome_vis_trans: nil,
                                                             # tubular daylight diffuser
                                                             tubular_daylight_diffuser_cond: nil,
                                                             tubular_daylight_diffuser_solar_trans: nil,
                                                             tubular_daylight_diffuser_vis_trans: nil
        )

          #Change name if required.
          default_surface_construction_set.setName(name) unless name.nil?
          ext_surface_set = default_surface_construction_set.defaultExteriorSurfaceConstructions.get
          new_ext_surface_set = self.customize_default_surface_constructions_conductance(model, name, ext_surface_set, ext_wall_cond, ext_floor_cond, ext_roof_cond)
          raise ("Could not customized exterior constructionset") unless default_surface_construction_set.setDefaultExteriorSurfaceConstructions(new_ext_surface_set)

          ground_surface_set = default_surface_construction_set.defaultGroundContactSurfaceConstructions.get

          new_ground_surface_set = self.customize_default_surface_constructions_conductance(model, name, ground_surface_set, ground_wall_cond, ground_floor_cond, ground_roof_cond)
          raise ("Could not customized ground constructionset") unless default_surface_construction_set.setDefaultGroundContactSurfaceConstructions(new_ground_surface_set)

          ext_subsurface_set = default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get

          new_ext_subsurface_set = self.customize_default_sub_surface_constructions_conductance(
              model: model,
              name: name,
              subsurface_set: ext_subsurface_set,
              fixed_window_conductance: fixed_window_cond,
              fixed_wind_vis_trans: fixed_wind_vis_trans,
              fixed_wind_solar_trans: fixed_wind_solar_trans,
              operable_window_conductance: operable_window_cond,
              operable_wind_solar_trans: operable_wind_solar_trans,
              operable_wind_vis_trans: operable_wind_vis_trans,
              glass_door_conductance: glass_door_cond,
              glass_door_solar_trans: glass_door_solar_trans,
              glass_door_vis_trans: glass_door_vis_trans,
              skylight_conductance: skylight_cond,
              skylight_solar_trans: skylight_solar_trans,
              skylight_vis_trans: skylight_vis_trans,
              tubular_daylight_dome_conductance: tubular_daylight_dome_cond,
              tubular_daylight_dome_solar_trans: tubular_daylight_dome_solar_trans,
              tubular_daylight_dome_vis_trans: tubular_daylight_dome_vis_trans,
              tubular_daylight_diffuser_conductance: tubular_daylight_diffuser_cond,
              tubular_daylight_diffuser_solar_trans: tubular_daylight_diffuser_solar_trans,
              tubular_daylight_diffuser_vis_trans: tubular_daylight_diffuser_vis_trans,
              door_construction_conductance: door_construction_cond,
              overhead_door_conductance: overhead_door_cond,
          )
          raise ("Could not customize subsurface constructionset") unless default_surface_construction_set.setDefaultExteriorSubSurfaceConstructions(new_ext_subsurface_set)

        end

        #This will remove all associated construction costs for each construction
        #type associated with the construction set. Unless the value is set to nil, in which case it will do nothing.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param default_surface_construction_set <String>
        #@param ext_wall_cost [Float] = nil
        #@param ext_floor_cost [Float] = nil
        #@param ext_roof_cost [Float] = nil
        #@param ground_wall_cost [Float] = nil
        #@param ground_floor_cost [Float] = nil
        #@param ground_roof_cost [Float] = nil
        #@param fixed_window_cost [Float] = nil
        #@param operable_window_cost [Float] = nil
        #@param door_construction_cost [Float] = nil
        #@param glass_door_cost [Float] = nil
        #@param overhead_door_cost [Float] = nil
        #@param skylight_cost [Float] = nil
        #@param tubular_daylight_dome_cost [Float] = nil
        #@param tubular_daylight_diffuser_cost [Float] = nil
        #@param total_building_construction_set_cost [Float] = nil
        def self.customize_default_surface_construction_set_costs(default_surface_construction_set,
                                                                  ext_wall_cost = nil,
                                                                  ext_floor_cost = nil,
                                                                  ext_roof_cost = nil,
                                                                  ground_wall_cost = nil,
                                                                  ground_floor_cost = nil,
                                                                  ground_roof_cost = nil,
                                                                  fixed_window_cost = nil,
                                                                  operable_window_cost = nil,
                                                                  door_construction_cost = nil,
                                                                  glass_door_cost = nil,
                                                                  overhead_door_cost = nil,
                                                                  skylight_cost = nil,
                                                                  tubular_daylight_dome_cost = nil,
                                                                  tubular_daylight_diffuser_cost = nil,
                                                                  total_building_construction_set_cost = nil
        )

          constructions_and_cost = [
              ["ext_wall_cost_m3", ext_wall_cost, default_surface_construction_set.defaultExteriorSurfaceConstructions.get.wallConstruction.get],
              ["ext_floor_cost_m3", ext_floor_cost, default_surface_construction_set.defaultExteriorSurfaceConstructions.get.floorConstruction.get],
              ["ext_roof_cost_m3", ext_roof_cost, default_surface_construction_set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get],
              ["ground_wall_cost_m3", ground_wall_cost, default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.wallConstruction.get],
              ["ground_floor_cost_m3", ground_floor_cost, default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.floorConstruction.get],
              ["ground_roof_cost_m3", ground_roof_cost, default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.roofCeilingConstruction.get],
              ["fixed_window_cost_m3", fixed_window_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get],
              ["operable_window_cost_m3", operable_window_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.operableWindowConstruction.get],
              ["door_construction_cost_m3", door_construction_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.doorConstruction.get],
              ["glass_door_cost_m3", glass_door_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.glassDoorConstruction.get],
              ["overhead_door_cost_m3", overhead_door_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.overheadDoorConstruction.get],
              ["skylight_cost_m3", skylight_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.skylightConstruction.get],
              ["tubular_daylight_dome_cost_m3", tubular_daylight_dome_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDomeConstruction.get],
              ["tubular_daylight_diffuser_cost_m3", tubular_daylight_diffuser_cost, default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDiffuserConstruction.get]
          ]

          #Assign cost to each construction.
          constructions_and_cost.each do |item|
            unless item[1].nil?
              item[2].removeLifeCycleCosts()
              raise("Could not remove LCC info from construction #{item[2]}") unless item[2].lifeCycleCosts.size == 0
              construction_cost_object = OpenStudio::Model::LifeCycleCost.new(item[2])
              construction_cost_object.setName(item[0])
              construction_cost_object.setCost(item[1])
              construction_cost_object.setCostUnits("CostPerArea")
            end
          end
          #create building total construction cost if needed.
          building = default_surface_construction_set.model.building.get
          BTAP::Resources::Economics::object_cost(building, "Builing Contruction Set Whole Building Capital Cost", total_building_construction_set_cost, "CostPerEach")
        end

        #This will customize default subsurface construction conductances.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param name [String]
        #@param subsurface_set [Array]
        #@param fixed_window_conductance [Float] = nil
        #@param fixed_wind_solar_trans [Float] = nil
        #@param fixed_wind_vis_trans [Float] = nil
        #@param operable_window_conductance [Float] = nil
        #@param operable_wind_solar_trans [Float] = nil
        #@param operable_wind_vis_trans [Float] = nil
        #@param door_construction_conductance [Float] = nil
        #@param glass_door_conductance [Float] = nil
        #@param glass_door_solar_trans [Float] = nil
        #@param glass_door_vis_trans [Float] = nil
        #@param overhead_door_conductance [Float] = nil
        #@param skylight_conductance [Float] = nil
        #@param skylight_solar_trans [Float] = nil
        #@param skylight_vis_trans [Float] = nil
        #@param tubular_daylight_dome_conductance [Float] = nil
        #@param tubular_daylight_dome_solar_trans [Float] = nil
        #@param tubular_daylight_dome_vis_trans [Float] = nil
        #@param tubular_daylight_diffuser_conductance [Float] = nil
        #@param tubular_daylight_diffuser_solar_trans [Float] = nil
        #@param tubular_daylight_diffuser_vis_trans [Float] = nil
        #@return [Object] set
        def self.customize_default_sub_surface_constructions_conductance(
            model:,
            name:,
            subsurface_set:,
            fixed_window_conductance: nil,
            fixed_wind_solar_trans: nil,
            fixed_wind_vis_trans: nil,
            operable_window_conductance: nil,
            operable_wind_solar_trans: nil,
            operable_wind_vis_trans: nil,
            door_construction_conductance: nil,
            glass_door_conductance: nil,
            glass_door_solar_trans: nil,
            glass_door_vis_trans: nil,
            overhead_door_conductance: nil,
            skylight_conductance: nil,
            skylight_solar_trans: nil,
            skylight_vis_trans: nil,
            tubular_daylight_dome_conductance: nil,
            tubular_daylight_dome_solar_trans: nil,
            tubular_daylight_dome_vis_trans: nil,
            tubular_daylight_diffuser_conductance: nil,
            tubular_daylight_diffuser_solar_trans: nil, tubular_daylight_diffuser_vis_trans: nil
        )
          set = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
          set.setName(name)
          set.setFixedWindowConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.fixedWindowConstruction.get, fixed_window_conductance, fixed_wind_solar_trans, fixed_wind_vis_trans))
          set.setOperableWindowConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.operableWindowConstruction.get, operable_window_conductance, operable_wind_solar_trans, operable_wind_vis_trans))
          set.setDoorConstruction(BTAP::Resources::Envelope::Constructions::customize_opaque_construction(model, subsurface_set.doorConstruction.get, door_construction_conductance))
          set.setGlassDoorConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.glassDoorConstruction.get, glass_door_conductance, glass_door_solar_trans, glass_door_vis_trans))
          set.setOverheadDoorConstruction(BTAP::Resources::Envelope::Constructions::customize_opaque_construction(model, subsurface_set.overheadDoorConstruction.get, overhead_door_conductance))
          set.setSkylightConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.skylightConstruction.get, skylight_conductance, skylight_solar_trans, skylight_vis_trans))
          set.setTubularDaylightDomeConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.tubularDaylightDomeConstruction.get, tubular_daylight_dome_conductance, tubular_daylight_dome_solar_trans, tubular_daylight_dome_vis_trans))
          set.setTubularDaylightDiffuserConstruction(BTAP::Resources::Envelope::Constructions::customize_fenestration_construction(model, subsurface_set.tubularDaylightDiffuserConstruction.get, tubular_daylight_diffuser_conductance, tubular_daylight_diffuser_solar_trans, tubular_daylight_diffuser_vis_trans))
          return set
        end

        #This will customize default surface construction conductance.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param name [String] = nil
        #@param default_surface_constructions [Float] = nil
        #@param wall_conductance [Float] = nil
        #@param floor_conductance [Float] = nil
        #@param roof_conductance [Float] = nil
        #@return [Object] set
        def self.customize_default_surface_constructions_conductance(model, name, default_surface_constructions, wall_conductance = nil, floor_conductance = nil, roof_conductance = nil)

          set = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
          set.setName(name)
          set.setFloorConstruction(Resources::Envelope::Constructions::customize_opaque_construction(model, default_surface_constructions.floorConstruction.get, floor_conductance)) unless floor_conductance.nil?
          set.setWallConstruction(Resources::Envelope::Constructions::customize_opaque_construction(model, default_surface_constructions.wallConstruction.get, wall_conductance)) unless wall_conductance.nil?
          set.setRoofCeilingConstruction(Resources::Envelope::Constructions::customize_opaque_construction(model, default_surface_constructions.roofCeilingConstruction.get, roof_conductance)) unless roof_conductance.nil?
          return set
        end

        #This creates a new construction set of wall, floor and roof/ceiling objects.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param name [String] = nil
        #@param wall [Float] = nil
        #@param floor [Float] = nil
        #@param roof [Float] = nil
        #@return [Object] set
        def self.create_default_surface_constructions(model, name, wall, floor, roof)
          wall = BTAP::Common::validate_array(model, wall, "Construction").first
          floor = BTAP::Common::validate_array(model, floor, "Construction").first
          roof = BTAP::Common::validate_array(model, roof, "Construction").first
          set = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
          set.setFloorConstruction(floor)
          set.setWallConstruction(wall)
          set.setRoofCeilingConstruction(roof)
          set.setName(name)
          return set
        end

        #This method creates a subsurface construction set (windows, doors, skylights, etc)
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param fixedWindowConstruction <String>
        #@param operableWindowConstruction <String>
        #@param setDoorConstruction <String>
        #@param setGlassDoorConstruction <String>
        #@param overheadDoorConstruction <String>
        #@param skylightConstruction <String>
        #@param tubularDaylightDomeConstruction <String>
        #@param tubularDaylightDiffuserConstruction <String>
        #@return [Object] set
        def self.create_subsurface_construction_set(
            model,
            fixedWindowConstruction,
            operableWindowConstruction,
            setDoorConstruction,
            setGlassDoorConstruction,
            overheadDoorConstruction,
            skylightConstruction,
            tubularDaylightDomeConstruction,
            tubularDaylightDiffuserConstruction)
          fixedWindowConstruction = BTAP::Common::validate_array(model, fixedWindowConstruction, "Construction").first
          operableWindowConstruction = BTAP::Common::validate_array(model, operableWindowConstruction, "Construction").first
          setDoorConstruction = BTAP::Common::validate_array(model, setDoorConstruction, "Construction").first
          setGlassDoorConstruction = BTAP::Common::validate_array(model, setGlassDoorConstruction, "Construction").first
          overheadDoorConstruction = BTAP::Common::validate_array(model, overheadDoorConstruction, "Construction").first
          skylightConstruction = BTAP::Common::validate_array(model, skylightConstruction, "Construction").first
          tubularDaylightDomeConstruction = BTAP::Common::validate_array(model, tubularDaylightDomeConstruction, "Construction").first
          tubularDaylightDiffuserConstruction = BTAP::Common::validate_array(model, tubularDaylightDiffuserConstruction, "Construction").first

          set = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
          set.setFixedWindowConstruction(fixedWindowConstruction) unless fixedWindowConstruction.nil?
          set.setOperableWindowConstruction(operableWindowConstruction) unless operableWindowConstruction.nil?
          set.setDoorConstruction(setDoorConstruction) unless setDoorConstruction.nil?
          set.setGlassDoorConstruction(setGlassDoorConstruction) unless setGlassDoorConstruction.nil?
          set.setOverheadDoorConstruction(overheadDoorConstruction) unless overheadDoorConstruction.nil?
          set.setSkylightConstruction(skylightConstruction) unless skylightConstruction.nil?
          set.setTubularDaylightDomeConstruction(tubularDaylightDomeConstruction) unless tubularDaylightDomeConstruction.nil?
          set.setTubularDaylightDiffuserConstruction(tubularDaylightDiffuserConstruction) unless tubularDaylightDiffuserConstruction.nil?
          return set
        end

        #This method gets construction set object from external library
        #@author phylroy.lopez@nrcan.gc.ca
        #@param construction_library_file [String]
        #@param construction_set_name [String]
        #@return [Boolean] optional_construction_set
        def self.get_construction_set_from_library(construction_library_file, construction_set_name)
          #Load Contruction osm library.
          if File.exist?(construction_library_file)
            construction_lib = BTAP::FileIO::load_osm(construction_library_file)
            #Get construction set..
            optional_construction_set = construction_lib.getDefaultConstructionSetByName(construction_set_name)
            if optional_construction_set.empty?
              raise("#{construction_set_name} does not exist in #{construction_library_file} library ")
            else
              return optional_construction_set.get
            end
          else
            raise("Error : Construction Lib #{construction_library_file} does not exist!")
          end
          return false
        end

        #This method creates a default construction set. A construction set for
        #exterior, interior,ground and subsurface must be created prior to populate
        #this object.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param model [OpenStudio::Model::Model]
        #@param name [String]
        #@param exterior_construction_set
        #@param interior_construction_set
        #@param ground_construction_set
        #@param subsurface_exterior_construction_set
        #@param subsurface_interior_construction_set
        #@return [Object] set
        def self.create_default_construction_set(
            model,
            name,
            exterior_construction_set,
            interior_construction_set,
            ground_construction_set,
            subsurface_exterior_construction_set,
            subsurface_interior_construction_set)
          exterior_construction_set = BTAP::Common::validate_array(model, exterior_construction_set, "DefaultSurfaceConstructions").first
          interior_construction_set = BTAP::Common::validate_array(model, interior_construction_set, "DefaultSurfaceConstructions").first
          ground_construction_set = BTAP::Common::validate_array(model, ground_construction_set, "DefaultSurfaceConstructions").first
          subsurface_exterior_construction_set = BTAP::Common::validate_array(model, subsurface_exterior_construction_set, "DefaultSubSurfaceConstructions").first
          subsurface_interior_construction_set = BTAP::Common::validate_array(model, subsurface_interior_construction_set, "DefaultSubSurfaceConstructions").first


          set = OpenStudio::Model::DefaultConstructionSet.new(model)
          set.setDefaultExteriorSurfaceConstructions(exterior_construction_set) unless exterior_construction_set.nil?
          set.setDefaultGroundContactSurfaceConstructions(ground_construction_set) unless ground_construction_set.nil?
          set.setDefaultInteriorSurfaceConstructions(interior_construction_set) unless interior_construction_set.nil?
          set.setDefaultExteriorSubSurfaceConstructions(subsurface_exterior_construction_set) unless subsurface_exterior_construction_set.nil?
          set.setDefaultInteriorSubSurfaceConstructions(subsurface_interior_construction_set) unless subsurface_interior_construction_set.nil?
          set.setName(name)
          return set
        end

        #This method creates a default construction set. A construction set for
        #exterior, interior,ground and subsurface must be created prior to populate
        #this object.
        #@author phylroy.lopez@nrcan.gc.ca
        #@param default_surface_construction_set [Object]
        #@return [String] table
        def self.get_construction_set_info(default_surface_construction_set)
          #######################
          constructions_and_cost = [
              ["ext_wall", default_surface_construction_set.defaultExteriorSurfaceConstructions.get.wallConstruction.get],
              ["ext_floor", default_surface_construction_set.defaultExteriorSurfaceConstructions.get.floorConstruction.get],
              ["ext_roof", default_surface_construction_set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get],
              ["ground_wall", default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.wallConstruction.get],
              ["ground_floor", default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.floorConstruction.get],
              ["ground_roof", default_surface_construction_set.defaultGroundContactSurfaceConstructions.get.roofCeilingConstruction.get],
              ["fixed_window", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get],
              ["operable_window", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.operableWindowConstruction.get],
              ["door_construction", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.doorConstruction.get],
              ["glass_door", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.glassDoorConstruction.get],
              ["overhead_door", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.overheadDoorConstruction.get],
              ["skylight", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.skylightConstruction.get],
              ["tubular_daylight_dome", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDomeConstruction.get],
              ["tubular_daylight_diffuser", default_surface_construction_set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDiffuserConstruction.get]
          ]
          default_surface_construction_set.name
          table = "construction,rsi,cost_m3\n"
          constructions_and_cost.each do |item|
            cost_item = OpenStudio::Model::getLifeCycleCostByName(default_surface_construction_set.model, "#{item[0]}_cost_m3")
            #ensure it exists
            cost = "NA"
            cost = cost_item.cost unless cost_item.empty?
            rsi = 1.0 / OpenstudioStandards::Constructions.construction_get_conductance(item[1])
            table << "#{item[0]},#{rsi},#{cost}\n"
          end
          return table
        end
      end #module ConstructionSet
    end #Envelope
  end #module Resources
end