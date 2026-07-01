import React from 'react'
import { useAppState, useAppDispatch } from '../context.jsx'
import { findRecord, patchParametricRecord } from '../utils/workingCopy.js'
import SliderWithInput from './SliderWithInput.jsx'

// Controls for the expansion mechanics added in the parametric refactor:
//   - expansion:       control_points | slope  (which expander runs)
//   - adjustment_mode: stretch | truncate  (control-point expander only)
//   - start_slope/end_slope (slope expander only)
// These persist directly onto the parametric_schedules record (per day-type), so
// they flow into the posted schedule_data and are honored by the Ruby methods.
export default function ExpansionControls({ scheduleName, onChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const dayType = state.activeDayType

  const record = findRecord(state, scheduleName, dayType)
  if (!record) return null

  // Inferred default: slope iff both slopes present and no explicit expansion.
  const inferred = record.start_slope != null && record.end_slope != null ? 'slope' : 'control_points'
  const expansion = record.expansion || inferred
  // 'static' was a legacy alias for 'truncate'; normalize it for display.
  const adjustmentMode = record.adjustment_mode === 'static' ? 'truncate' : (record.adjustment_mode || 'stretch')

  function patch(p) {
    patchParametricRecord(state, dispatch, scheduleName, dayType, p)
    onChanged?.()
  }

  const labelStyle = { fontSize: 11, fontWeight: 600, color: '#555', display: 'block', marginBottom: 2 }
  const selectStyle = { width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, marginBottom: 8 }

  return (
    <div style={{ marginBottom: 10, padding: 8, background: '#f7f9fb', borderRadius: 4, border: '1px solid #e3e8ee' }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: '#444', marginBottom: 6 }}>Expansion</div>

      <label style={labelStyle}>Expander</label>
      <select style={selectStyle} value={expansion} onChange={e => patch({ expansion: e.target.value })}>
        <option value="control_points">control points</option>
        <option value="slope">slope</option>
      </select>

      {expansion === 'control_points' ? (
        <>
          <label style={labelStyle} title="truncate anchors humps at absolute st_std/et_std then clips to the [st,et] window">
            Adjustment mode
          </label>
          <select style={selectStyle} value={adjustmentMode} onChange={e => patch({ adjustment_mode: e.target.value })}>
            <option value="stretch">stretch (scale to st/et)</option>
            <option value="truncate">truncate (absolute, clipped)</option>
          </select>
        </>
      ) : (
        <>
          <SliderWithInput label="Start slope" value={record.start_slope ?? 0.2} min={0} max={2} step={0.05}
            onChange={v => patch({ start_slope: v })} />
          <SliderWithInput label="End slope" value={record.end_slope ?? 0.2} min={0} max={2} step={0.05}
            onChange={v => patch({ end_slope: v })} />
        </>
      )}
    </div>
  )
}
