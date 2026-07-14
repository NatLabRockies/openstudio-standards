// Centralized resolution of the st/et/base/peak used to expand a control-point
// profile (occupancy or direct load). Shared by the expand effect, the chart
// render, and the derive lookup so their cache keys line up exactly.
//
// Precedence mirrors the library: building hours (when enabled) > per-profile
// slider edits (editorParams) > the record's *_std. Schedule-set offsets shift
// load timing and are passed in by the caller (direct loads only).

const WEEKEND_TOKENS = ['Wknd', 'Sat', 'Sun']
const NON_WEEKEND_TOKENS = ['Default', 'Wkdy']

// Weekend iff day_types ∩ {Wknd,Sat,Sun} and not {Default,Wkdy} (per impl notes).
export function isWeekendProfile(dayType) {
  return WEEKEND_TOKENS.includes(dayType) && !NON_WEEKEND_TOKENS.includes(dayType)
}

export function controlPointParams(state, record, profileId, { offsets } = {}) {
  const key = `${record.name}|${profileId}`
  const pp = state.editorParams.byProfile[key] || {}
  const bh = state.editorParams.buildingHours
  let st, et
  if (bh && bh.enabled) {
    // weekend determination uses the record's own day-type token, not the profile key
    if (isWeekendProfile(record.day_types)) { st = bh.wkndStart; et = bh.wkndStart + bh.wkndDuration }
    else { st = bh.wkdyStart; et = bh.wkdyStart + bh.wkdyDuration }
  } else {
    st = pp.st ?? record.st_std
    et = pp.et ?? record.et_std
  }
  if (offsets) { st += offsets.start || 0; et += offsets.end || 0 }
  return {
    base: pp.base ?? record.base_std,
    peak: pp.peak ?? record.peak_std,
    st,
    et,
    timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
  }
}

// Offsets for the schedule set linked to the current selection (direct/derived loads).
export function offsetsForActiveSet(state) {
  if (!state.selectedSpaceType) return null
  const st = state.rawData.spaceTypes.find(s => s.space_type_name === state.selectedSpaceType)
  if (!st) return null
  const sets = state.workingCopies.schedule_sets || state.rawData.scheduleSets
  const ss = sets.find(s => s.schedule_set_name === st.schedule_set_name)
  if (!ss) return null
  const start = ss.start_time_offset || 0
  const end = ss.end_time_offset || 0
  if (start === 0 && end === 0) return null
  return { start, end }
}
