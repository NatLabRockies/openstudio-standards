// Helpers for resolving schedules in the merged default_parametric_schedules.json
// file, which holds Occupancy, Lighting, Equipment, and Diurnal records keyed by
// name + category. A load slot on a schedule set may point either at a derived-load
// parameter object (default_*_parameters.json) or — when the name matches a
// parametric record of the load's category — at a "direct" parametric schedule that
// is expanded from its own control points instead of being derived from occupancy.

// editor category token -> the `category` value used in default_parametric_schedules.json
export const EDITOR_TO_PARAM_CATEGORY = {
  Occupancy: 'Occupancy',
  Lighting: 'Lighting',
  ElectricEquipment: 'Equipment',
  GasEquipment: 'Equipment',
  HotWater: 'Equipment',
  Diurnal: 'Diurnal',
}

// All day-type variant records that share a name.
export function recordsByName(name, parametricSchedules) {
  return (parametricSchedules || []).filter((r) => r.name === name)
}

// True when the named load is itself a parametric (control-point) schedule of the
// given editor category — i.e. a direct load expanded directly, not derived.
export function isDirectParametric(name, editorCategory, parametricSchedules) {
  const wantCat = EDITOR_TO_PARAM_CATEGORY[editorCategory]
  return (parametricSchedules || []).some(
    (r) => r.name === name && (r.category === wantCat || editorCategory === 'Occupancy')
  )
}

// Unique names of Diurnal-category schedules (usable as gate profiles).
export function diurnalScheduleNames(parametricSchedules) {
  return [...new Set(
    (parametricSchedules || []).filter(r => r.category === 'Diurnal').map(r => r.name)
  )].sort()
}

// Resolve a schedule's "kind" for rendering/editing:
//   'occupancy' — drives day assignments and is the derivation source
//   'direct'    — a parametric load schedule (own control points)
//   'derived'   — derived from occupancy via a *_parameters.json record
export function resolveKind(name, editorCategory, parametricSchedules) {
  if (editorCategory === 'Occupancy') return 'occupancy'
  return isDirectParametric(name, editorCategory, parametricSchedules) ? 'direct' : 'derived'
}
