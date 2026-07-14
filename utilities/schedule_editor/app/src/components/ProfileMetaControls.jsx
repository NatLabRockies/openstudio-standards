import React from 'react'
import {
  useAppState, useAppDispatch,
  SET_PROFILE_META_EDIT, SET_ACTIVE_DAY_TYPE
} from '../context.jsx'
import { findProfileRecord, profileKey } from '../utils/profiles.js'
import { getParametricArray, patchParametricRecord } from '../utils/workingCopy.js'

const VALID_TOKENS = ['Default', 'Wkdy', 'Wknd', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

// Full ISO datetime (matching the data files) from a YYYY-MM-DD date input, or null.
function toIso(dateStr) {
  return dateStr ? `${dateStr}T00:00:00+00:00` : null
}

export default function ProfileMetaControls({ scheduleName, onDatesChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const activeKey = state.activeDayType

  const allRecords = getParametricArray(state)
  const record = findProfileRecord(allRecords, scheduleName, activeKey)

  // The Default (catch-all, full-year) profile's metadata is not editable.
  if (!record || record.day_types === 'Default') return null

  const metaKey = `${scheduleName}|${activeKey}`
  const metaEdit = state.profileMetaEdits[metaKey] || {}

  const currentDayType = metaEdit.dayType ?? record.day_types
  const currentStartDate = metaEdit.startDate ?? (record.start_date ? record.start_date.split('T')[0] : '')
  const currentEndDate = metaEdit.endDate ?? (record.end_date ? record.end_date.split('T')[0] : '')

  const datalistId = `valid-tokens-${scheduleName}`
  const tokenError = currentDayType && !VALID_TOKENS.includes(currentDayType)
    ? `Invalid. Valid tokens: ${VALID_TOKENS.join(', ')}` : null

  // Apply an edit: patch the record (matched by the CURRENT active key) and re-point the
  // active tab to the record's new profile key (day-type / dates change its identity).
  function applyEdit(newDayType, newStart, newEnd) {
    const nextRecord = {
      ...record,
      day_types: newDayType,
      start_date: toIso(newStart),
      end_date: toIso(newEnd),
    }
    patchParametricRecord(state, dispatch, scheduleName, activeKey, {
      day_types: newDayType,
      start_date: toIso(newStart),
      end_date: toIso(newEnd),
    })
    dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: profileKey(nextRecord) })
  }

  function handleDayTypeChange(e) {
    const v = e.target.value
    dispatch({ type: SET_PROFILE_META_EDIT, payload: { key: metaKey, meta: { dayType: v, startDate: currentStartDate, endDate: currentEndDate } } })
    if (VALID_TOKENS.includes(v)) applyEdit(v, currentStartDate, currentEndDate)
  }

  function handleDateChange(field, val) {
    const startDate = field === 'start' ? val : currentStartDate
    const endDate = field === 'end' ? val : currentEndDate
    dispatch({ type: SET_PROFILE_META_EDIT, payload: { key: metaKey, meta: { dayType: currentDayType, startDate, endDate } } })
    if (VALID_TOKENS.includes(currentDayType)) applyEdit(currentDayType, startDate, endDate)
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
