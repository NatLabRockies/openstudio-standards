import React, { useState } from 'react'
import { useAppState, useAppDispatch, SET_SELECTED_SPACE_TYPE, SET_SELECTED_SCHEDULE_NAMES } from '../context.jsx'
import { resolveKind } from '../utils/scheduleLookup.js'

const SLOT_CATEGORY = [
  ['occupancy_schedule', 'Occupancy'],
  ['derived_interior_lighting_parameters', 'Lighting'],
  ['derived_electric_equipment_parameters', 'ElectricEquipment'],
  ['derived_gas_equipment_parameters', 'GasEquipment'],
  ['derived_hot_water_equipment_parameters', 'HotWater'],
]

function getChildren(scheduleSet, paramRecords) {
  if (!scheduleSet) return []
  return SLOT_CATEGORY
    .map(([slot, category]) => {
      const name = scheduleSet[slot]
      if (!name) return null
      return { name, category, kind: resolveKind(name, category, paramRecords) }
    })
    .filter(Boolean)
}

export default function SpaceTypeTree() {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [expanded, setExpanded] = useState({})

  const { spaceTypes, scheduleSets, parametricSchedules } = state.rawData

  function toggleExpand(name) {
    setExpanded(prev => ({ ...prev, [name]: !prev[name] }))
  }

  function selectSpaceType(spaceType, childNames) {
    dispatch({ type: SET_SELECTED_SPACE_TYPE, payload: spaceType.space_type_name })
    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: childNames })
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
        const children = getChildren(schedSet, parametricSchedules)
        const childNames = children.map(c => c.name)
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
              <span onClick={() => selectSpaceType(st, childNames)} style={{ flex: 1 }}>
                {st.space_type_name}
              </span>
            </div>
            {isExpanded && children.map(({ name, kind }) => (
              <div
                key={name}
                onClick={() => selectChild(name)}
                style={{
                  display: 'flex', alignItems: 'center', gap: 6,
                  paddingLeft: 28, paddingTop: 2, paddingBottom: 2, cursor: 'pointer',
                  background: state.selectedScheduleNames.includes(name) && state.selectedScheduleNames.length === 1
                    ? '#e6f3ff' : 'transparent',
                  borderRadius: 3
                }}
              >
                <span style={{ flex: 1 }}>{name}</span>
                {kind === 'direct' && (
                  <span style={{ fontSize: 9, color: '#fff', background: '#9b59b6', borderRadius: 3, padding: '0 4px' }}
                    title="Direct parametric load schedule (expanded from its own control points)">direct</span>
                )}
              </div>
            ))}
          </div>
        )
      })}
    </div>
  )
}
