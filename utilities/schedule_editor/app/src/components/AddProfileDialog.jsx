import React, { useState } from 'react'
import {
  useAppState, useAppDispatch,
  SET_WORKING_COPY, SET_ACTIVE_DAY_TYPE
} from '../context.jsx'
import { profileKey } from '../utils/profiles.js'

const VALID_TOKENS = ['Default','Wkdy','Wknd','Mon','Tue','Wed','Thu','Fri','Sat','Sun']

function toIso(dateStr) {
  return dateStr ? `${dateStr}T00:00:00+00:00` : null
}

export default function AddProfileDialog({ occupancyScheduleName, onClose }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const year = state.calendarYear
  const [dayType, setDayType] = useState('')
  // New profiles default to a full-year 1/1–12/31 range.
  const [startDate, setStartDate] = useState(`${year}-01-01`)
  const [endDate, setEndDate] = useState(`${year}-12-31`)

  const isValidToken = VALID_TOKENS.includes(dayType.trim())
  const tokenError = dayType.trim() && !isValidToken
    ? `Invalid token. Valid: ${VALID_TOKENS.join(', ')}` : null

  const allRecords = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules

  // A profile is identified by day-type + date range, so the same token may repeat with a
  // different range. Only reject an exact duplicate profile (same token AND same range).
  const prospective = { day_types: dayType.trim(), start_date: toIso(startDate), end_date: toIso(endDate) }
  const prospectiveKey = isValidToken ? profileKey(prospective) : null
  const alreadyExists = prospectiveKey != null && allRecords.some(
    o => o.name === occupancyScheduleName && profileKey(o) === prospectiveKey
  )
  const canConfirm = isValidToken && !alreadyExists && dayType.trim() !== ''

  function handleConfirm() {
    const tok = dayType.trim()
    // Clone the Default profile for this schedule
    const defaults = allRecords.filter(
      o => o.name === occupancyScheduleName && o.day_types === 'Default'
    )
    if (defaults.length === 0) return
    const newObj = {
      ...defaults[0],
      day_types: tok,
      start_date: toIso(startDate),
      end_date: toIso(endDate),
    }
    const updated = [...allRecords, newObj]
    dispatch({ type: SET_WORKING_COPY, payload: { target: 'parametric_schedules', data: updated } })
    dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: profileKey(newObj) })
    onClose()
  }

  const overlayStyle = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.35)',
    display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000
  }
  const modalStyle = {
    background: '#fff', borderRadius: 8, padding: 24, width: 360,
    boxShadow: '0 4px 24px rgba(0,0,0,0.2)'
  }
  const fieldStyle = { marginBottom: 14 }
  const labelStyle = { display: 'block', fontSize: 12, fontWeight: 600, marginBottom: 4 }
  const inputStyle = { width: '100%', padding: '6px 8px', border: '1px solid #ccc', borderRadius: 4, fontSize: 13, boxSizing: 'border-box' }

  return (
    <div style={overlayStyle} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={modalStyle}>
        <h3 style={{ margin: '0 0 16px', fontSize: 16 }}>Add Day-Type Profile</h3>

        <div style={fieldStyle}>
          <label style={labelStyle}>Day type token</label>
          <input
            style={{ ...inputStyle, borderColor: tokenError ? 'red' : '#ccc' }}
            value={dayType} onChange={e => setDayType(e.target.value)}
            placeholder="e.g. Wknd, Mon, Wkdy"
            list="valid-tokens"
          />
          <datalist id="valid-tokens">
            {VALID_TOKENS.filter(t => t !== 'Default').map(t => <option key={t} value={t} />)}
          </datalist>
          {tokenError && <span style={{ fontSize: 11, color: 'red' }}>{tokenError}</span>}
          {alreadyExists && <span style={{ fontSize: 11, color: 'orange' }}>A profile with this day type and date range already exists</span>}
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>Start date (defaults to 1/1)</label>
          <input style={inputStyle} type="date" value={startDate} onChange={e => setStartDate(e.target.value)} />
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>End date (defaults to 12/31)</label>
          <input style={inputStyle} type="date" value={endDate} onChange={e => setEndDate(e.target.value)} />
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
          <button style={{ padding: '6px 16px', borderRadius: 4, border: '1px solid #aaa', cursor: 'pointer' }}
            onClick={onClose}>Cancel</button>
          <button
            style={{ padding: '6px 16px', borderRadius: 4, border: 'none',
              background: canConfirm ? '#0078d4' : '#ccc', color: '#fff',
              cursor: canConfirm ? 'pointer' : 'not-allowed' }}
            disabled={!canConfirm} onClick={handleConfirm}>
            Add Profile
          </button>
        </div>
      </div>
    </div>
  )
}
