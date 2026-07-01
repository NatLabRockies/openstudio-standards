import React from 'react'
import { useAppState, useAppDispatch } from '../context.jsx'
import { activeScheduleSet, patchScheduleSet } from '../utils/workingCopy.js'

// Schedule-set library-default timing offsets. These shift derived/direct load
// timing relative to occupancy (applied to direct-load previews here). Shown only
// when a space type (hence a schedule set) is selected.
export default function ScheduleSetOffsets({ onChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()

  const ss = activeScheduleSet(state)
  if (!ss) return null

  function update(field, value) {
    patchScheduleSet(state, dispatch, ss.schedule_set_name, { [field]: value })
    onChanged?.()
  }

  const inputStyle = { width: 70, padding: '2px 4px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3 }
  const row = { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }

  return (
    <div style={{ marginBottom: 12, padding: 8, background: '#f5f5f5', borderRadius: 4, border: '1px solid #ddd' }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: '#444', marginBottom: 6 }}>
        Load timing offsets — {ss.schedule_set_name}
      </div>
      <div style={row}>
        <label style={{ fontSize: 12, color: '#555' }}>Start offset (h)</label>
        <input type="number" step={0.25} style={inputStyle}
          value={ss.start_time_offset ?? 0}
          onChange={e => update('start_time_offset', parseFloat(e.target.value) || 0)} />
      </div>
      <div style={row}>
        <label style={{ fontSize: 12, color: '#555' }}>End offset (h)</label>
        <input type="number" step={0.25} style={inputStyle}
          value={ss.end_time_offset ?? 0}
          onChange={e => update('end_time_offset', parseFloat(e.target.value) || 0)} />
      </div>
      <div style={{ fontSize: 10, color: '#999' }}>Applied to direct-load previews.</div>
    </div>
  )
}
