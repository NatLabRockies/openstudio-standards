import React, { useState, useEffect, useMemo } from 'react'
import {
  useAppState, useAppDispatch,
  SET_STANDARD_REFERENCE_OVERRIDE,
  SET_ASHRAE_SPACE_TYPE_REF
} from '../context.jsx'
import { fetchSpaceTypes } from '../api.js'

const TEMPLATES = [
  '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013',
  '90.1-2016', '90.1-2019', 'DOE Ref 1980-2004', 'DOE Ref Pre-1980'
]

// Map category → spc_typ schedule field name
const CATEGORY_SCHEDULE_FIELD = {
  Occupancy:         'occupancy_schedule',
  Lighting:          'lighting_schedule',
  ElectricEquipment: 'electric_equipment_schedule',
  GasEquipment:      'gas_equipment_schedule',
}

// StandardReferenceSelector is rendered once (not per schedule).
// It controls the shared template + space type reference for all selected schedules.
export default function StandardReferenceSelector({ scheduleInfos }) {
  const state = useAppState()
  const dispatch = useAppDispatch()

  const { template, spaceTypeKey } = state.ashraeSpaceTypeRef
  const [spaceTypes, setSpaceTypes] = useState([])
  const [loadError, setLoadError] = useState(null)
  const [filter, setFilter] = useState('')

  // Load space types whenever template changes
  useEffect(() => {
    setLoadError(null)
    setSpaceTypes([])
    fetchSpaceTypes(template)
      .then(data => setSpaceTypes(Array.isArray(data) ? data : []))
      .catch(err => setLoadError(err.message))
  }, [template])

  const filteredSpaceTypes = useMemo(() => {
    const q = filter.toLowerCase()
    return spaceTypes.filter(st => st.key.toLowerCase().includes(q))
  }, [spaceTypes, filter])

  // When space type changes, dispatch the 4 schedule overrides
  function applySpaceType(key) {
    dispatch({ type: SET_ASHRAE_SPACE_TYPE_REF, payload: { template, spaceTypeKey: key } })
    if (!key) return
    const entry = spaceTypes.find(st => st.key === key)
    if (!entry) return

    for (const { name, category } of scheduleInfos) {
      const field = CATEGORY_SCHEDULE_FIELD[category]
      if (!field) continue
      const schedName = entry[field]
      if (schedName) {
        dispatch({ type: SET_STANDARD_REFERENCE_OVERRIDE, payload: { scheduleName: name, ashraeScheduleName: schedName } })
      }
    }
  }

  const inputStyle = { padding: '3px 6px', fontSize: 11, border: '1px solid #ccc', borderRadius: 3, width: '100%', boxSizing: 'border-box' }
  const labelStyle = { fontSize: 11, fontWeight: 600, color: '#555', display: 'block', marginBottom: 2 }

  return (
    <div style={{ marginBottom: 12, padding: '8px', background: '#f5f5f5', borderRadius: 4, border: '1px solid #ddd' }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: '#444', marginBottom: 6 }}>ASHRAE Reference</div>

      <div style={{ marginBottom: 6 }}>
        <label style={labelStyle}>Template version</label>
        <select
          value={template}
          onChange={e => {
            dispatch({ type: SET_ASHRAE_SPACE_TYPE_REF, payload: { template: e.target.value, spaceTypeKey: '' } })
            setFilter('')
          }}
          style={inputStyle}
        >
          {TEMPLATES.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
      </div>

      <div style={{ marginBottom: 4 }}>
        <label style={labelStyle}>Space type</label>
        <input
          placeholder="Filter space types…"
          value={filter}
          onChange={e => setFilter(e.target.value)}
          style={{ ...inputStyle, marginBottom: 3 }}
        />
        {loadError && <div style={{ fontSize: 10, color: '#e74c3c', marginBottom: 3 }}>⚠ {loadError}</div>}
        <select
          value={spaceTypeKey}
          onChange={e => applySpaceType(e.target.value)}
          style={{ ...inputStyle, height: 80 }}
          size={4}
        >
          <option value="">— select space type —</option>
          {filteredSpaceTypes.map(st => (
            <option key={st.key} value={st.key}>{st.key}</option>
          ))}
        </select>
      </div>

      {spaceTypeKey && scheduleInfos.length > 0 && (
        <div style={{ marginTop: 4, fontSize: 10, color: '#666' }}>
          {scheduleInfos.map(({ name, category }) => {
            const field = CATEGORY_SCHEDULE_FIELD[category]
            const entry = spaceTypes.find(st => st.key === spaceTypeKey)
            const refName = entry?.[field] || '—'
            return (
              <div key={name} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 1 }}>
                <span style={{ color: '#888' }}>{category}:</span>
                <span style={{ fontStyle: refName === '—' ? 'italic' : 'normal' }}>{refName}</span>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
