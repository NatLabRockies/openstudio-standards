import React from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'

// Only values that divide evenly into 60
const VALID_TPH = [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60]

export default function GlobalControls({ onParamsChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const tph = state.editorParams.timestepsPerHour || 4

  function handle(e) {
    const v = parseInt(e.target.value, 10)
    if (isNaN(v)) return
    dispatch({ type: SET_EDITOR_PARAMS, payload: { params: { timestepsPerHour: v } } })
    onParamsChanged?.()
  }

  return (
    <div style={{ marginBottom: 12 }}>
      <label style={{ fontSize: 12, fontWeight: 600 }}>Timesteps per hour: </label>
      <select value={tph} onChange={handle}
        style={{ padding: '2px 4px', fontSize: 12, marginLeft: 6, border: '1px solid #ccc', borderRadius: 3 }}>
        {VALID_TPH.map(v => <option key={v} value={v}>{v}</option>)}
      </select>
    </div>
  )
}
