import { expandParametric, expandSlope } from '../api.js'
import { SET_EXPANDED_PROFILE, SET_EXPANDED_PROFILE_ERROR } from '../context.jsx'

// Pick the expander the way the Ruby does: explicit `expansion` field wins, else
// infer slope only when both slopes are present.
function expanderFor(scheduleData) {
  const expansion = scheduleData.expansion
    || (scheduleData.start_slope != null && scheduleData.end_slope != null ? 'slope' : 'control_points')
  return expansion === 'slope' ? expandSlope : expandParametric
}

export function createExpandDebounced(dispatch, delayMs = 150) {
  let timer = null
  let pending = []

  return function scheduleExpand(scheduleName, dayType, scheduleData, params) {
    // Collect calls; fire after delayMs of idle
    pending.push({ scheduleName, dayType, scheduleData, params })
    clearTimeout(timer)
    timer = setTimeout(async () => {
      const toProcess = [...pending]
      pending = []
      for (const { scheduleName: sn, dayType: dt, scheduleData: sd, params: p } of toProcess) {
        const profileKey = `${sn}|${dt}`
        try {
          const result = await expanderFor(sd)(sd, p)
          const paramsHash = JSON.stringify(p)
          dispatch({
            type: SET_EXPANDED_PROFILE,
            payload: { key: `${sn}|${dt}|${paramsHash}`, pairs: result.time_value_pairs, profileKey }
          })
        } catch (err) {
          dispatch({
            type: SET_EXPANDED_PROFILE_ERROR,
            payload: { profileKey, message: err.message }
          })
        }
      }
    }, delayMs)
  }
}
