import React, { useState } from 'react'
import {
  useAppState, useAppDispatch,
  SET_WORKING_COPY, SET_ACTIVE_DAY_TYPE
} from '../context.jsx'

const VALID_TOKENS = ['Default','Wkdy','Wknd','Mon','Tue','Wed','Thu','Fri','Sat','Sun']

export default function AddProfileDialog({ occupancyScheduleName, onClose }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [dayType, setDayType] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')

  const isValidToken = VALID_TOKENS.includes(dayType.trim())
  const tokenError = dayType.trim() && !isValidToken
    ? `Invalid token. Valid: ${VALID_TOKENS.join(', ')}` : null

  const allRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
  const alreadyExists = allRecords.some(
    o => o.name === occupancyScheduleName && o.day_types === dayType.trim()
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
      start_date: startDate || null,
      end_date: endDate || null,
    }
    const updated = [...allRecords, newObj]
    dispatch({ type: SET_WORKING_COPY, payload: { target: 'occupancy_schedules', data: updated } })
    dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: tok })
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
          {alreadyExists && <span style={{ fontSize: 11, color: 'orange' }}>Profile already exists for this day type</span>}
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>Start date (YYYY-MM-DD, optional)</label>
          <input style={inputStyle} type="date" value={startDate} onChange={e => setStartDate(e.target.value)} />
        </div>

        <div style={fieldStyle}>
          <label style={labelStyle}>End date (YYYY-MM-DD, optional)</label>
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
