import React, { useState } from 'react'
import { useAppState, useAppDispatch, SET_SELECTED_SPACE_TYPE, SET_SELECTED_SCHEDULE_NAMES } from '../context.jsx'

function getChildNames(scheduleSet) {
  if (!scheduleSet) return []
  return [
    scheduleSet.occupancy_schedule,
    scheduleSet.derived_interior_lighting_parameters,
    scheduleSet.derived_electric_equipment_parameters,
    scheduleSet.derived_gas_equipment_parameters,
    scheduleSet.derived_hot_water_equipment_parameters,
  ].filter(Boolean)
}

export default function SpaceTypeTree() {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [expanded, setExpanded] = useState({})

  const { spaceTypes, scheduleSets } = state.rawData

  function toggleExpand(name) {
    setExpanded(prev => ({ ...prev, [name]: !prev[name] }))
  }

  function selectSpaceType(spaceType, children) {
    dispatch({ type: SET_SELECTED_SPACE_TYPE, payload: spaceType.space_type_name })
    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: children })
    if (!expanded[spaceType.space_type_name]) {
      setExpanded(prev => ({ ...prev, [spaceType.space_type_name]: true }))
    }
  }

  function selectChild(name) {
    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: [name] })
  }

  return (
    <div style={{ fontSize: 13 }}>
      {spaceTypes.map(st => {
        const schedSet = scheduleSets.find(s => s.schedule_set_name === st.schedule_set_name)
        const children = getChildNames(schedSet)
        const isExpanded = expanded[st.space_type_name]
        const isSelectedParent = state.selectedSpaceType === st.space_type_name

        return (
          <div key={st.space_type_name}>
            <div
              style={{
                display: 'flex', alignItems: 'center', padding: '3px 4px', cursor: 'pointer',
                background: isSelectedParent ? '#cce4ff' : 'transparent', borderRadius: 3,
                userSelect: 'none'
              }}
            >
              <span
                onClick={() => toggleExpand(st.space_type_name)}
                style={{ width: 16, textAlign: 'center', flexShrink: 0, color: '#666' }}
              >
                {isExpanded ? '▾' : '▸'}
              </span>
              <span onClick={() => selectSpaceType(st, children)} style={{ flex: 1 }}>
                {st.space_type_name}
              </span>
            </div>
            {isExpanded && children.map(name => (
              <div
                key={name}
                onClick={() => selectChild(name)}
                style={{
                  paddingLeft: 28, paddingTop: 2, paddingBottom: 2, cursor: 'pointer',
                  background: state.selectedScheduleNames.includes(name) && state.selectedScheduleNames.length === 1
                    ? '#e6f3ff' : 'transparent',
                  borderRadius: 3
                }}
              >
                {name}
              </div>
            ))}
          </div>
        )
      })}
    </div>
  )
}
