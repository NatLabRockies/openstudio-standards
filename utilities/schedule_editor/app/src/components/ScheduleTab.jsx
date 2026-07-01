import React, { useMemo, useState } from 'react'
import { useAppState, useAppDispatch, SET_SELECTED_SCHEDULE_NAMES } from '../context.jsx'

// The merged default_parametric_schedules.json holds multiple categories. Default
// to Occupancy (the original behavior) but let the user browse direct-load and
// diurnal schedules too.
const CATEGORIES = ['Occupancy', 'Lighting', 'Equipment', 'Diurnal', 'All']

export default function ScheduleTab() {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [filterCat, setFilterCat] = useState('Occupancy')

  const names = useMemo(() => {
    const seen = new Set()
    return state.rawData.parametricSchedules
      .filter(s => filterCat === 'All' || (s.category || 'Occupancy') === filterCat)
      .map(s => s.name)
      .filter(n => { if (seen.has(n)) return false; seen.add(n); return true })
      .sort()
  }, [state.rawData.parametricSchedules, filterCat])

  function select(name) {
    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: [name] })
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '6px 8px', borderBottom: '1px solid #eee' }}>
        <select value={filterCat} onChange={e => setFilterCat(e.target.value)}
          style={{ width: '100%', padding: '3px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3 }}>
          {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
      </div>
      <div style={{ overflowY: 'auto', flex: 1, padding: 8, fontSize: 13 }}>
        {names.map(name => (
          <div
            key={name}
            onClick={() => select(name)}
            style={{
              padding: '3px 6px', cursor: 'pointer', borderRadius: 3,
              background: state.selectedScheduleNames.length === 1 && state.selectedScheduleNames[0] === name
                ? '#e6f3ff' : 'transparent'
            }}
          >
            {name}
          </div>
        ))}
        {names.length === 0 && <div style={{ color: '#999', fontSize: 12, padding: 4 }}>No schedules in this category.</div>}
      </div>
    </div>
  )
}
