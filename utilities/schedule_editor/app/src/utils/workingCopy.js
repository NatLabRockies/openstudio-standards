import { SET_WORKING_COPY } from '../context.jsx'

// Active parametric_schedules array (working copy if present, else the raw array).
export function getParametricArray(state) {
  return state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
}

// Find the record for name + dayType, falling back to the Default day-type record.
export function findRecord(state, name, dayType) {
  const arr = getParametricArray(state)
  return (
    arr.find(o => o.name === name && o.day_types === dayType) ||
    arr.find(o => o.name === name && o.day_types === 'Default') ||
    null
  )
}

// Merge `patch` into the record matching name + dayType (Default fallback) and
// dispatch the updated parametric_schedules working copy.
export function patchParametricRecord(state, dispatch, name, dayType, patch) {
  const arr = getParametricArray(state)
  let idx = arr.findIndex(o => o.name === name && o.day_types === dayType)
  if (idx === -1) idx = arr.findIndex(o => o.name === name && o.day_types === 'Default')
  if (idx === -1) return
  const next = arr.map((o, i) => (i === idx ? { ...o, ...patch } : o))
  dispatch({ type: SET_WORKING_COPY, payload: { target: 'parametric_schedules', data: next } })
}

// Active schedule_sets array (working copy if present, else the raw array).
export function getScheduleSetsArray(state) {
  return state.workingCopies.schedule_sets || state.rawData.scheduleSets
}

// Merge `patch` into the schedule set matching scheduleSetName and dispatch.
export function patchScheduleSet(state, dispatch, scheduleSetName, patch) {
  const arr = getScheduleSetsArray(state).map(s => ({ ...s }))
  const idx = arr.findIndex(s => s.schedule_set_name === scheduleSetName)
  if (idx === -1) return
  arr[idx] = { ...arr[idx], ...patch }
  dispatch({ type: SET_WORKING_COPY, payload: { target: 'schedule_sets', data: arr } })
}

// Derived-load parameter files keyed by editor category: [working-copy target, rawData key].
const LOAD_PARAM_TARGET = {
  Lighting: ['lighting_params', 'lightingParams'],
  ElectricEquipment: ['elec_equip_params', 'elecEquipParams'],
  GasEquipment: ['gas_equip_params', 'gasEquipParams'],
  HotWater: ['hot_water_params', 'hotWaterParams'],
}

// Active derived-load parameter array for a category (working copy if present).
export function getLoadParamArray(state, category) {
  const entry = LOAD_PARAM_TARGET[category]
  if (!entry) return []
  return state.workingCopies[entry[0]] || state.rawData[entry[1]] || []
}

// Merge `patch` into the derived-load parameter record matching name and dispatch the
// updated working copy (so the change is saved to the *_parameters.json file).
export function patchLoadParamRecord(state, dispatch, category, name, patch) {
  const entry = LOAD_PARAM_TARGET[category]
  if (!entry) return
  const arr = state.workingCopies[entry[0]] || state.rawData[entry[1]] || []
  const idx = arr.findIndex(p => p.name === name)
  if (idx === -1) return
  const next = arr.map((p, i) => (i === idx ? { ...p, ...patch } : p))
  dispatch({ type: SET_WORKING_COPY, payload: { target: entry[0], data: next } })
}

// The schedule set linked to the currently selected space type, if any.
export function activeScheduleSet(state) {
  if (!state.selectedSpaceType) return null
  const st = state.rawData.spaceTypes.find(s => s.space_type_name === state.selectedSpaceType)
  if (!st) return null
  return getScheduleSetsArray(state).find(s => s.schedule_set_name === st.schedule_set_name) || null
}
