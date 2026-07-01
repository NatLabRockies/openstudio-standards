import { getLoadParamArray } from './workingCopy.js'

export const DIURNAL_MODES = ['off_when_asleep', 'on_when_asleep']

// Build the diurnal portion of a /api/derive request body for a derived load.
// Returns {} when the load has no diurnal_profile set. The Diurnal schedule's
// Default-day record (from the working copy, so unsaved edits are reflected) is
// sent so the server can expand and gate it exactly as the library does.
export function diurnalDeriveBody(state, category, loadName) {
  const rec = getLoadParamArray(state, category).find(p => p.name === loadName)
  if (!rec || !rec.diurnal_profile) return {}
  const params = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules || []
  const dRec = params.find(o => o.name === rec.diurnal_profile && o.day_types === 'Default')
  if (!dRec) return {}
  return {
    diurnal_schedule_data: dRec,
    diurnal_mode: rec.diurnal_mode || 'off_when_asleep',
    diurnal_weight: rec.diurnal_weight ?? 1.0,
  }
}
