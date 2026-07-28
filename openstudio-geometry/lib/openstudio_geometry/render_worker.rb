# frozen_string_literal: true

# Isolated glTF export worker — ALWAYS invoked as a child process
# (ruby render_worker.rb <model.osm> <out.gltf> [control.json]) because the
# C++ GltfForwardTranslator can HARD-CRASH (segfault) on un-triangulatable
# surfaces; an in-process rescue cannot catch that. Direct port of the campus
# repo's geometry_view.py worker (canmet-energy/campus,
# src/buildings/reports/geometry_view.py).
#
# control.json: {"remove_subsurfaces": bool,
#                "keep_surfaces": [handle,...] | null,
#                "drop_surfaces": [handle,...]}
# Exit codes: 0 ok, 1 translator returned false, 2 model unloadable,
#             3 nothing left to render.

require 'json'
require 'set'
require 'openstudio'

osm_path, out_path, ctrl_path = ARGV
control = ctrl_path ? JSON.parse(File.read(ctrl_path)) : {}

loaded = OpenStudio::Model::Model.load(OpenStudio::Path.new(osm_path))
exit(2) if loaded.empty?
model = loaded.get

model.getSubSurfaces.each(&:remove) if control['remove_subsurfaces']

keep = control['keep_surfaces']
drop = control['drop_surfaces'] || []
if !keep.nil?
  keep_set = keep.to_set { |h| h.to_s }
  model.getSurfaces.each { |s| s.remove unless keep_set.include?(s.handle.to_s) }
elsif drop.any?
  drop_set = drop.to_set { |h| h.to_s }
  model.getSurfaces.each { |s| s.remove if drop_set.include?(s.handle.to_s) }
end

exit(3) if model.getSurfaces.empty? && model.getShadingSurfaces.empty?

ok = OpenStudio::Gltf::GltfForwardTranslator.new.modelToGLTF(model, OpenStudio::Path.new(out_path))
exit(ok ? 0 : 1)
