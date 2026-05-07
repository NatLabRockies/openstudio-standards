import React from 'react'
import {
  useAppState, useAppDispatch,
  SET_PROFILE_META_EDIT, SET_ACTIVE_DAY_TYPE, SET_WORKING_COPY
} from '../context.jsx'

export default function ProfileMetaControls({ scheduleName, onDatesChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const activeDayType = state.activeDayType

  if (activeDayType === 'Default') return null

  const metaKey = `${scheduleName}|${activeDayType}`
  const metaEdit = state.profileMetaEdits[metaKey] || {}

  // Get current values from working copy or raw data
  const allRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
  const record = allRecords.find(o => o.name === scheduleName && o.day_types === activeDayType)

  const currentDayType = metaEdit.dayType ?? record?.day_types ?? activeDayType
  const currentStartDate = metaEdit.startDate ?? (record?.start_date ? record.start_date.split('T')[0] : '')
  const currentEndDate = metaEdit.endDate ?? (record?.end_date ? record.end_date.split('T')[0] : '')

  const VALID_TOKENS = ['Default','Wkdy','Wknd','Mon','Tue','Wed','Thu','Fri','Sat','Sun']
  const datalistId = `valid-tokens-${scheduleName}-${activeDayType}`
  const tokenError = currentDayType && !VALID_TOKENS.includes(currentDayType)
    ? `Invalid. Valid tokens: ${VALID_TOKENS.join(', ')}` : null

  function updateRecord(newDayType, newStart, newEnd) {
    if (!record) return
    const updated = allRecords.map(o =>
      o.name === scheduleName && o.day_types === activeDayType
        ? { ...o, day_types: newDayType, start_date: newStart || null, end_date: newEnd || null }
        : o
    )
    dispatch({ type: SET_WORKING_COPY, payload: { target: 'occupancy_schedules', data: updated } })
  }

  function handleDayTypeChange(e) {
    const v = e.target.value
    const meta = { dayType: v, startDate: currentStartDate, endDate: currentEndDate }
    dispatch({ type: SET_PROFILE_META_EDIT, payload: { key: metaKey, meta } })
    if (VALID_TOKENS.includes(v)) {
      dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: v })
      updateRecord(v, currentStartDate, currentEndDate)
    }
  }

  function handleDateChange(field, val) {
    const meta = {
      dayType: currentDayType,
      startDate: field === 'start' ? val : currentStartDate,
      endDate:   field === 'end'   ? val : currentEndDate,
    }
    dispatch({ type: SET_PROFILE_META_EDIT, payload: { key: metaKey, meta } })
    updateRecord(currentDayType, meta.startDate, meta.endDate)
    onDatesChanged?.()
  }

  const inputStyle = { width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, boxSizing: 'border-box' }
  const labelStyle = { fontSize: 11, fontWeight: 600, color: '#666', display: 'block', marginBottom: 2 }

  return (
    <div style={{ padding: '8px 0', borderBottom: '1px solid #eee', marginBottom: 10 }}>
      <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 8, color: '#444' }}>Profile Metadata</div>
      <div style={{ marginBottom: 8 }}>
        <label style={labelStyle}>Day type</label>
        <input
          style={{ ...inputStyle, borderColor: tokenError ? 'red' : '#ccc' }}
          value={currentDayType}
          onChange={handleDayTypeChange}
          list={datalistId}
        />
        <datalist id={datalistId}>
          {VALID_TOKENS.filter(t => t !== 'Default').map(t => <option key={t} value={t} />)}
        </datalist>
        {tokenError && <span style={{ fontSize: 11, color: 'red' }}>{tokenError}</span>}
      </div>
      <div style={{ marginBottom: 8 }}>
        <label style={labelStyle}>Start date</label>
        <input type="date" style={inputStyle} value={currentStartDate}
          onChange={e => handleDateChange('start', e.target.value)} />
      </div>
      <div style={{ marginBottom: 8 }}>
        <label style={labelStyle}>End date</label>
        <input type="date" style={inputStyle} value={currentEndDate}
          onChange={e => handleDateChange('end', e.target.value)} />
      </div>
    </div>
  )
}
