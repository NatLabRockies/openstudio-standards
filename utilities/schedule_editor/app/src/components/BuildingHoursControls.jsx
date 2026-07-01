import React from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'
import SliderWithInput from './SliderWithInput.jsx'

const DEFAULTS = { enabled: false, wkdyStart: 8, wkdyDuration: 10, wkndStart: 8, wkndDuration: 6 }

// Optional building-hours override. When enabled, weekday profiles expand at the
// wkdy window and weekend profiles (Wknd/Sat/Sun) at the wknd window — mirroring the
// library's weekday/weekend split. Disabled by default so standalone expansion is
// unchanged (the per-profile st/et sliders drive expansion as before).
export default function BuildingHoursControls({ onChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const bh = { ...DEFAULTS, ...(state.editorParams.buildingHours || {}) }

  function update(patch) {
    dispatch({ type: SET_EDITOR_PARAMS, payload: { params: { buildingHours: { ...bh, ...patch } } } })
    onChanged?.()
  }

  return (
    <div style={{ marginBottom: 12, padding: 8, background: '#f5f5f5', borderRadius: 4, border: '1px solid #ddd' }}>
      <label style={{ fontSize: 11, fontWeight: 700, color: '#444', display: 'flex', alignItems: 'center', gap: 6 }}>
        <input type="checkbox" checked={bh.enabled} onChange={e => update({ enabled: e.target.checked })} />
        Building hours override
      </label>
      {bh.enabled && (
        <div style={{ marginTop: 8 }}>
          <div style={{ fontSize: 11, fontWeight: 600, color: '#666', marginBottom: 2 }}>Weekday (Default / Wkdy)</div>
          <SliderWithInput label="Start (h)" value={bh.wkdyStart} min={0} max={24} step={0.25}
            onChange={v => update({ wkdyStart: v })} />
          <SliderWithInput label="Duration (h)" value={bh.wkdyDuration} min={0} max={24} step={0.25}
            onChange={v => update({ wkdyDuration: v })} />
          <div style={{ fontSize: 11, fontWeight: 600, color: '#666', margin: '6px 0 2px' }}>Weekend (Wknd / Sat / Sun)</div>
          <SliderWithInput label="Start (h)" value={bh.wkndStart} min={0} max={24} step={0.25}
            onChange={v => update({ wkndStart: v })} />
          <SliderWithInput label="Duration (h)" value={bh.wkndDuration} min={0} max={24} step={0.25}
            onChange={v => update({ wkndDuration: v })} />
          <div style={{ fontSize: 10, color: '#999' }}>
            Overrides the per-schedule start/end-time sliders while enabled.
          </div>
        </div>
      )}
    </div>
  )
}
