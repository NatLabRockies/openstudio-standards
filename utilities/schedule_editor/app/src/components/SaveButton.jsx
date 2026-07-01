import React, { useState, useEffect } from 'react'
import { useAppState, useAppDispatch, SET_RAW_DATA, SET_WORKING_COPY } from '../context.jsx'
import { save, fetchData } from '../api.js'

const RAW_KEY = {
  parametric_schedules: 'parametricSchedules',
  schedule_sets: 'scheduleSets',
  lighting_params: 'lightingParams',
  elec_equip_params: 'elecEquipParams',
  gas_equip_params: 'gasEquipParams',
  hot_water_params: 'hotWaterParams',
}

function computeDiff(workingCopies, rawData) {
  return Object.entries(workingCopies)
    .filter(([target, data]) => {
      const rawKey = RAW_KEY[target]
      if (!rawKey) return false
      return JSON.stringify(data) !== JSON.stringify(rawData[rawKey])
    })
    .map(([target, data]) => ({ target, data }))
}

export default function SaveButton({ onSuccess }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [statuses, setStatuses] = useState({}) // { [target]: 'pending' | 'saving' | 'saved' | 'failed' }

  const diff = computeDiff(state.workingCopies, state.rawData)
  const hasChanges = diff.length > 0

  function openModal() {
    const initial = {}
    diff.forEach(({ target }) => { initial[target] = 'pending' })
    setStatuses(initial)
    setOpen(true)
  }

  function closeModal() {
    if (saving) return
    setOpen(false)
  }

  async function runPostSaveSuccess() {
    try {
      const freshData = await fetchData()
      dispatch({
        type: SET_RAW_DATA,
        payload: {
          spaceTypes: freshData.space_types || [],
          scheduleSets: freshData.schedule_sets || [],
          parametricSchedules: freshData.parametric_schedules || [],
          lightingParams: freshData.lighting_params || [],
          elecEquipParams: freshData.elec_equip_params || [],
          gasEquipParams: freshData.gas_equip_params || [],
          hotWaterParams: freshData.hot_water_params || [],
          ashraeSchedules: freshData.ashrae_schedules || [],
          cbesSchedules: freshData.cbes_schedules || [],
          deerSchedules: freshData.deer_schedules || [],
        }
      })
      Object.keys(state.workingCopies).forEach(t => {
        dispatch({ type: SET_WORKING_COPY, payload: { target: t, data: null } })
      })
      onSuccess?.()
    } catch (e) {
      console.error('Re-fetch after save failed:', e)
    }
    setOpen(false)
  }

  // Trigger success flow when all targets reach 'saved' (handles retry path)
  useEffect(() => {
    if (!open || saving) return
    const vals = Object.values(statuses)
    if (vals.length > 0 && vals.every(s => s === 'saved')) {
      runPostSaveSuccess()
    }
  }, [statuses])

  async function saveTarget(target, data) {
    setStatuses(s => ({ ...s, [target]: 'saving' }))
    try {
      await save(target, data)
      setStatuses(s => ({ ...s, [target]: 'saved' }))
      return true
    } catch {
      setStatuses(s => ({ ...s, [target]: 'failed' }))
      return false
    }
  }

  async function handleConfirm() {
    setSaving(true)
    for (const { target, data } of diff) {
      await saveTarget(target, data)
    }
    setSaving(false)
    // useEffect watching statuses handles post-save success flow
  }

  const statusIcon = { pending: '⏳', saving: '⌛', saved: '✓', failed: '✗' }
  const statusColor = { pending: '#888', saving: '#888', saved: '#27ae60', failed: '#e74c3c' }

  const overlayStyle = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
    display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000
  }
  const modalStyle = {
    background: '#fff', borderRadius: 8, padding: 24, width: 560, maxWidth: '90vw',
    maxHeight: '80vh', overflow: 'auto', boxShadow: '0 4px 24px rgba(0,0,0,0.2)'
  }

  return (
    <>
      <button
        onClick={openModal}
        disabled={!hasChanges}
        style={{
          padding: '6px 16px', fontSize: 13, fontWeight: 600,
          background: hasChanges ? '#2980b9' : '#ccc',
          color: '#fff', border: 'none', borderRadius: 4, cursor: hasChanges ? 'pointer' : 'not-allowed'
        }}
      >
        Save changes {hasChanges ? `(${diff.length})` : ''}
      </button>

      {open && (
        <div style={overlayStyle} onClick={e => { if (e.target === e.currentTarget) closeModal() }}>
          <div style={modalStyle}>
            <h3 style={{ margin: '0 0 16px', fontSize: 16 }}>Save Changes</h3>
            {diff.length === 0 ? (
              <p style={{ color: '#888', fontSize: 13 }}>No changes to save.</p>
            ) : (
              <div>
                {diff.map(({ target, data }) => {
                  const status = statuses[target] || 'pending'
                  const rawKey = RAW_KEY[target]
                  const changedCount = data.filter((item, i) => {
                    const orig = (state.rawData[rawKey] || [])[i]
                    return JSON.stringify(item) !== JSON.stringify(orig)
                  }).length
                  return (
                    <div key={target} style={{ marginBottom: 16, borderBottom: '1px solid #eee', paddingBottom: 12 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                        <strong style={{ fontSize: 13 }}>{target}</strong>
                        <span style={{ fontSize: 13, color: statusColor[status], fontWeight: 600 }}>
                          {statusIcon[status]} {status}
                        </span>
                      </div>
                      <div style={{ fontSize: 11, color: '#666', marginBottom: 6 }}>
                        {changedCount} record{changedCount !== 1 ? 's' : ''} modified
                      </div>
                      {status === 'failed' && !saving && (
                        <button
                          onClick={() => saveTarget(target, data)}
                          style={{ fontSize: 11, padding: '2px 8px', background: '#e74c3c', color: '#fff', border: 'none', borderRadius: 3, cursor: 'pointer' }}
                        >
                          Retry
                        </button>
                      )}
                    </div>
                  )
                })}
              </div>
            )}
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 16 }}>
              <button
                onClick={closeModal}
                disabled={saving}
                style={{ padding: '6px 14px', fontSize: 13, border: '1px solid #ccc', borderRadius: 4, background: '#fff', cursor: saving ? 'not-allowed' : 'pointer' }}
              >
                Cancel
              </button>
              {diff.length > 0 && !Object.values(statuses).every(s => s === 'saved') && (
                <button
                  onClick={handleConfirm}
                  disabled={saving}
                  style={{ padding: '6px 14px', fontSize: 13, background: '#2980b9', color: '#fff', border: 'none', borderRadius: 4, cursor: saving ? 'not-allowed' : 'pointer' }}
                >
                  {saving ? 'Saving…' : 'Confirm Save'}
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
