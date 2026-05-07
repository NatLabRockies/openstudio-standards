import React, { useState } from 'react'
import { useAppState, useAppDispatch, SET_WORKING_COPY } from '../context.jsx'
import NewScheduleDialog from './NewScheduleDialog.jsx'

export default function ScheduleActionBar() {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [dialog, setDialog] = useState(null) // null | { mode: 'new'|'duplicate', prefill }

  const singleChildSelected = state.selectedScheduleNames.length === 1
  const spaceTypeSelected = !!state.selectedSpaceType
  const hasSelection = state.selectedScheduleNames.length > 0

  function handleUnassign() {
    if (!singleChildSelected || !state.selectedSpaceType) return
    const scheduleName = state.selectedScheduleNames[0]
    const { scheduleSets } = state.rawData
    // Get current schedule_sets (working copy or raw)
    const currentSets = state.workingCopies.schedule_sets
      ? [...state.workingCopies.schedule_sets]
      : scheduleSets.map(s => ({ ...s }))

    // Find the schedule set for this space type
    const { spaceTypes } = state.rawData
    const spaceType = spaceTypes.find(st => st.space_type_name === state.selectedSpaceType)
    if (!spaceType) return
    const setIdx = currentSets.findIndex(s => s.schedule_set_name === spaceType.schedule_set_name)
    if (setIdx === -1) return

    // Null out the field that references this schedule name
    const keys = ['occupancy_schedule','derived_interior_lighting_parameters',
                  'derived_electric_equipment_parameters','derived_gas_equipment_parameters',
                  'derived_hot_water_equipment_parameters']
    const updated = { ...currentSets[setIdx] }
    for (const k of keys) {
      if (updated[k] === scheduleName) updated[k] = null
    }
    currentSets[setIdx] = updated
    dispatch({ type: SET_WORKING_COPY, payload: { target: 'schedule_sets', data: currentSets } })
    dispatch({ type: 'SET_SELECTED_SCHEDULE_NAMES', payload: [] })
  }

  const btnStyle = (disabled) => ({
    padding: '4px 10px', fontSize: 12, cursor: disabled ? 'not-allowed' : 'pointer',
    opacity: disabled ? 0.4 : 1, marginRight: 6, borderRadius: 3, border: '1px solid #aaa',
    background: '#f5f5f5'
  })

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      <button style={btnStyle(!singleChildSelected)} disabled={!singleChildSelected} onClick={handleUnassign}>
        ✕ Un-assign
      </button>
      <button style={btnStyle(!hasSelection)} disabled={!hasSelection}
        onClick={() => {
          const prefill = { scheduleName: state.selectedScheduleNames[0] + ' copy' }
          setDialog({ mode: 'duplicate', prefill })
        }}>
        ⧉ Duplicate
      </button>
      <button style={btnStyle(!spaceTypeSelected)} disabled={!spaceTypeSelected}
        onClick={() => setDialog({ mode: 'new', prefill: {} })}>
        + Add New
      </button>
      {dialog && (
        <NewScheduleDialog
          mode={dialog.mode}
          prefill={dialog.prefill}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  )
}
