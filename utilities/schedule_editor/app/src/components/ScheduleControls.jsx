import React from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'
import SliderWithInput from './SliderWithInput.jsx'

export default function ScheduleControls({ scheduleName, onParamsChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const dayType = state.activeDayType

  const allOccRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
  const schedObj = allOccRecords.find(o => o.name === scheduleName && o.day_types === dayType)
                || allOccRecords.find(o => o.name === scheduleName && o.day_types === 'Default')

  const profileKey = `${scheduleName}|${dayType}`
  const savedParams = state.editorParams.byProfile[profileKey] || {}

  const params = {
    st:   savedParams.st   ?? schedObj?.st_std   ?? 8,
    et:   savedParams.et   ?? schedObj?.et_std   ?? 18,
    base: savedParams.base ?? schedObj?.base_std ?? 0,
    peak: savedParams.peak ?? schedObj?.peak_std ?? 1,
  }

  function update(field, value) {
    const newParams = { ...params, [field]: value }
    dispatch({ type: SET_EDITOR_PARAMS, payload: { scheduleName, dayType, params: newParams } })
    onParamsChanged?.()
  }

  if (!schedObj) return <div style={{ color: '#999', fontSize: 12 }}>No parametric data found for {scheduleName}</div>

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6, color: '#333' }}>
        Occupancy — {scheduleName}
      </div>
      <SliderWithInput label="Start time (h)" value={params.st} min={0} max={32} step={0.25}
        stdValue={schedObj.st_std} onChange={v => update('st', v)} />
      <SliderWithInput label="End time (h)" value={params.et} min={0} max={32} step={0.25}
        stdValue={schedObj.et_std} onChange={v => update('et', v)} />
      <SliderWithInput label="Base fraction" value={params.base} min={0} max={1} step={0.05}
        stdValue={schedObj.base_std} onChange={v => update('base', v)} />
      <SliderWithInput label="Peak fraction" value={params.peak} min={0} max={1} step={0.05}
        stdValue={schedObj.peak_std} onChange={v => update('peak', v)} />
    </div>
  )
}
