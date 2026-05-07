import React, { useMemo } from 'react'
import { useAppState, useAppDispatch, SET_SELECTED_SCHEDULE_NAMES } from '../context.jsx'

export default function ScheduleTab() {
  const state = useAppState()
  const dispatch = useAppDispatch()

  const names = useMemo(() => {
    const seen = new Set()
    return state.rawData.occupancySchedules
      .map(s => s.name)
      .filter(n => { if (seen.has(n)) return false; seen.add(n); return true })
      .sort()
  }, [state.rawData.occupancySchedules])

  function select(name) {
    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: [name] })
  }

  return (
    <div style={{ overflowY: 'auto', height: '100%', padding: 8, fontSize: 13 }}>
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
    </div>
  )
}
