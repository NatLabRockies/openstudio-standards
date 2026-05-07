import React, { useState, useMemo } from 'react'
import {
  useAppState, useAppDispatch,
  SET_WORKING_COPY, SET_STANDARD_REFERENCE_OVERRIDE, SET_SELECTED_SCHEDULE_NAMES
} from '../context.jsx'

const SCHEDULE_TYPES = ['Occupancy', 'Lighting', 'Electric Equipment', 'Gas Equipment']

function ashraeCategory(scheduleType) {
  if (scheduleType === 'Occupancy') return 'Occupancy'
  if (scheduleType === 'Lighting') return 'Lighting'
  if (scheduleType === 'Electric Equipment') return 'ElectricEquipment'
  if (scheduleType === 'Gas Equipment') return 'GasEquipment'
  return ''
}

function scheduleSetKey(scheduleType) {
  if (scheduleType === 'Occupancy') return 'occupancy_schedule'
  if (scheduleType === 'Lighting') return 'derived_interior_lighting_parameters'
  if (scheduleType === 'Electric Equipment') return 'derived_electric_equipment_parameters'
  if (scheduleType === 'Gas Equipment') return 'derived_gas_equipment_parameters'
  return null
}

function workingCopyTarget(scheduleType) {
  if (scheduleType === 'Occupancy') return 'occupancy_schedules'
  if (scheduleType === 'Lighting') return 'lighting_params'
  if (scheduleType === 'Electric Equipment') return 'elec_equip_params'
  if (scheduleType === 'Gas Equipment') return 'gas_equip_params'
  return null
}

function rawDataKey(scheduleType) {
  if (scheduleType === 'Occupancy') return 'occupancySchedules'
  if (scheduleType === 'Lighting') return 'lightingParams'
  if (scheduleType === 'Electric Equipment') return 'elecEquipParams'
  if (scheduleType === 'Gas Equipment') return 'gasEquipParams'
  return null
}

export default function NewScheduleDialog({ mode, prefill, onClose }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [name, setName] = useState(prefill.scheduleName || '')
  const [schedType, setSchedType] = useState('Occupancy')
  const [ashraeFilter, setAshraeFilter] = useState('')
  const [selectedAshrae, setSelectedAshrae] = useState('')

  const allNames = useMemo(() => {
    const sets = [
      ...state.rawData.occupancySchedules,
      ...state.rawData.lightingParams,
      ...state.rawData.elecEquipParams,
      ...state.rawData.gasEquipParams,
    ]
    return [...new Set(sets.map(s => s.name))]
  }, [state.rawData])

  const ashraeOptions = useMemo(() => {
    const cat = ashraeCategory(schedType)
    return state.rawData.ashraeSchedules.filter(s =>
      (s.category === cat || s.category === schedType) &&
      s.day_types === 'Default' &&
      s.name.toLowerCase().includes(ashraeFilter.toLowerCase())
    )
  }, [state.rawData.ashraeSchedules, schedType, ashraeFilter])

  const isDuplicate = allNames.includes(name.trim())
  const canConfirm = name.trim().length > 0 && !isDuplicate

  function handleConfirm() {
    const newName = name.trim()
    const target = workingCopyTarget(schedType)
    const rawKey = rawDataKey(schedType)
    const setCopyKey = scheduleSetKey(schedType)

    // Get current data arrays
    const currentArray = state.workingCopies[target]
      ? [...state.workingCopies[target]]
      : [...(state.rawData[rawKey] || [])]

    if (mode === 'duplicate') {
      // Deep-copy all records of the source schedule (all day types)
      const sourceName = (prefill.scheduleName || '').replace(/ copy$/, '')
      const copies = currentArray
        .filter(obj => obj.name === sourceName)
        .map(obj => ({ ...obj, name: newName }))
      if (copies.length === 0) {
        // fallback: duplicate the first selected schedule
        const fallback = currentArray.find(obj => obj.name === state.selectedScheduleNames[0])
        if (fallback) copies.push({ ...fallback, name: newName })
      }
      dispatch({ type: SET_WORKING_COPY, payload: { target, data: [...currentArray, ...copies] } })
    } else {
      // Create new default object
      let newObj
      if (schedType === 'Occupancy') {
        newObj = {
          name: newName, day_types: 'Default', type: 'parametric',
          base_std: 0.0, peak_std: 1.0, st_std: 8, et_std: 18,
          start_date: null, end_date: null,
          control_points: [['st-1','base'],['st','peak'],['et','peak'],['et+1','base']]
        }
      } else {
        newObj = {
          name: newName, category: schedType, derivation_type: 'exponential',
          base: 0.05, peak: 0.9, response: 0.75,
          winter_design_day_peak: 0.0, summer_design_day_base: 1.0
        }
      }
      dispatch({ type: SET_WORKING_COPY, payload: { target, data: [...currentArray, newObj] } })
    }

    // Update schedule_sets to link new schedule to current space type
    if (state.selectedSpaceType && setCopyKey) {
      const { spaceTypes, scheduleSets } = state.rawData
      const spaceType = spaceTypes.find(st => st.space_type_name === state.selectedSpaceType)
      if (spaceType) {
        const currentSets = state.workingCopies.schedule_sets
          ? [...state.workingCopies.schedule_sets]
          : scheduleSets.map(s => ({ ...s }))
        const idx = currentSets.findIndex(s => s.schedule_set_name === spaceType.schedule_set_name)
        if (idx !== -1) {
          currentSets[idx] = { ...currentSets[idx], [setCopyKey]: newName }
          dispatch({ type: SET_WORKING_COPY, payload: { target: 'schedule_sets', data: currentSets } })
        }
      }
    }

    // Store standard reference override
    if (selectedAshrae) {
      dispatch({ type: SET_STANDARD_REFERENCE_OVERRIDE, payload: { scheduleName: newName, ashraeScheduleName: selectedAshrae } })
    }

    dispatch({ type: SET_SELECTED_SCHEDULE_NAMES, payload: [newName] })
    onClose()
  }

  const overlayStyle = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)',
    display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000
  }
  const modalStyle = {
    background: '#fff', borderRadius: 8, padding: 24, width: 420,
    boxShadow: '0 4px 24px rgba(0,0,0,0.2)'
  }
  const fieldStyle = { display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 16 }
  const labelStyle = { fontSize: 12, fontWeight: 600, color: '#444' }
  const inputStyle = { padding: '6px 8px', border: '1px solid #ccc', borderRadius: 4, fontSize: 13 }

  return (
    <div style={overlayStyle} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={modalStyle}>
        <h3 style={{ margin: '0 0 16px', fontSize: 16 }}>
          {mode === 'duplicate' ? 'Duplicate Schedule' : 'New Schedule'}
        </h3>

        <div style={fieldStyle}>
          <label style={labelStyle}>Schedule name</label>
          <input style={{ ...inputStyle, borderColor: isDuplicate ? 'red' : '#ccc' }}
            value={name} onChange={e => setName(e.target.value)} placeholder="e.g. office occupancy 2" />
          {isDuplicate && <span style={{ fontSize: 11, color: 'red' }}>Name already exists</span>}
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>Schedule type</label>
          <select style={inputStyle} value={schedType} onChange={e => { setSchedType(e.target.value); setSelectedAshrae('') }}>
            {SCHEDULE_TYPES.map(t => <option key={t}>{t}</option>)}
          </select>
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>Standard schedule to compare (optional)</label>
          <input style={inputStyle} placeholder="Filter…" value={ashraeFilter}
            onChange={e => setAshraeFilter(e.target.value)} />
          <select style={{ ...inputStyle, height: 100 }} size={5} value={selectedAshrae}
            onChange={e => setSelectedAshrae(e.target.value)}>
            <option value="">(none)</option>
            {[...new Map(ashraeOptions.map(s => [s.name, s])).values()].map(s => (
              <option key={s.name} value={s.name}>{s.name}</option>
            ))}
          </select>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
          <button style={{ padding: '6px 16px', borderRadius: 4, border: '1px solid #aaa', cursor: 'pointer' }}
            onClick={onClose}>Cancel</button>
          <button
            style={{ padding: '6px 16px', borderRadius: 4, border: 'none', background: canConfirm ? '#0078d4' : '#ccc',
              color: '#fff', cursor: canConfirm ? 'pointer' : 'not-allowed' }}
            disabled={!canConfirm} onClick={handleConfirm}>
            {mode === 'duplicate' ? 'Duplicate' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  )
}
