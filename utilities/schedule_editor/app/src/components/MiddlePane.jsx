import React, { useEffect, useMemo } from 'react'
import { useAppState, useAppDispatch, SET_DAY_ASSIGNMENTS } from '../context.jsx'
import { assignDayTypes } from '../utils/dayAssignment.js'
import CalendarMap from './CalendarMap.jsx'
import DayTypePanel from './DayTypePanel.jsx'

export default function MiddlePane() {
  const state = useAppState()
  const dispatch = useAppDispatch()

  // Identify the occupancy schedule name for the current selection
  const occupancyScheduleName = useMemo(() => {
    if (!state.selectedSpaceType) {
      // Single schedule selected from ScheduleTab
      return state.selectedScheduleNames[0] || null
    }
    // Find via schedule set
    const spaceType = state.rawData.spaceTypes.find(
      st => st.space_type_name === state.selectedSpaceType
    )
    if (!spaceType) return state.selectedScheduleNames[0] || null
    const schedSet = (state.workingCopies.schedule_sets || state.rawData.scheduleSets)
      .find(s => s.schedule_set_name === spaceType.schedule_set_name)
    return schedSet?.occupancy_schedule || state.selectedScheduleNames[0] || null
  }, [state.selectedSpaceType, state.selectedScheduleNames, state.rawData, state.workingCopies])

  // Recompute day assignments when selection changes
  useEffect(() => {
    if (!occupancyScheduleName) return
    const allOccRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
    const schedObjects = allOccRecords.filter(o => o.name === occupancyScheduleName)
    if (schedObjects.length === 0) return
    const assignments = assignDayTypes(schedObjects, state.calendarYear)
    dispatch({ type: SET_DAY_ASSIGNMENTS, payload: { [occupancyScheduleName]: assignments } })
  }, [occupancyScheduleName, state.workingCopies.occupancy_schedules, state.calendarYear])

  const assignments = occupancyScheduleName
    ? (state.dayAssignments[occupancyScheduleName] || {})
    : {}

  if (state.selectedScheduleNames.length === 0) {
    return (
      <div style={{ padding: 24, color: '#888' }}>
        Select a space type or schedule from the left pane to begin.
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', overflow: 'hidden' }}>
      <div style={{ padding: '8px 12px', borderBottom: '1px solid #ddd', flexShrink: 0 }}>
        <CalendarMap assignments={assignments} year={state.calendarYear} />
      </div>
      <div style={{ flex: 1, overflow: 'auto' }}>
        <DayTypePanel
          occupancyScheduleName={occupancyScheduleName}
          assignments={assignments}
        />
      </div>
    </div>
  )
}
