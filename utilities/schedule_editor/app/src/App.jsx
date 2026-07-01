import React, { useEffect, useRef } from 'react'
import { AppProvider, useAppState, useAppDispatch, SET_RAW_DATA, SET_LOADING, SET_ERROR } from './context.jsx'
import { fetchData } from './api.js'
import LeftPane from './components/LeftPane.jsx'
import MiddlePane from './components/MiddlePane.jsx'
import RightPane from './components/RightPane.jsx'
import SaveButton from './components/SaveButton.jsx'
import Toast from './components/Toast.jsx'

function DataLoader({ children }) {
  const state = useAppState()
  const dispatch = useAppDispatch()

  useEffect(() => {
    load()
  }, [])

  function load() {
    dispatch({ type: SET_LOADING, payload: true })
    fetchData()
      .then(data => {
        dispatch({
          type: SET_RAW_DATA,
          payload: {
            spaceTypes: data.space_types || [],
            scheduleSets: data.schedule_sets || [],
            parametricSchedules: data.parametric_schedules || [],
            lightingParams: data.lighting_params || [],
            elecEquipParams: data.elec_equip_params || [],
            gasEquipParams: data.gas_equip_params || [],
            hotWaterParams: data.hot_water_params || [],
            ashraeSchedules: data.ashrae_schedules || [],
            cbesSchedules: data.cbes_schedules || [],
            deerSchedules: data.deer_schedules || [],
          }
        })
      })
      .catch(err => {
        dispatch({ type: SET_ERROR, payload: err.message })
      })
  }

  if (state.loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' }}>
        <p>Loading schedule data…</p>
      </div>
    )
  }

  if (state.error) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100vh', gap: 16 }}>
        <p style={{ color: 'red' }}>Error loading data: {state.error}</p>
        <button onClick={load}>Retry</button>
      </div>
    )
  }

  return children
}

const paneStyle = {
  border: '1px solid #ccc',
  padding: 16,
  overflowY: 'auto',
}

function Shell() {
  const toastRef = useRef(null)
  return (
    <DataLoader>
      <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden', fontFamily: 'sans-serif' }}>
        <div style={{ height: 44, background: '#2c3e50', display: 'flex', alignItems: 'center', padding: '0 16px', gap: 12, flexShrink: 0 }}>
          <span style={{ color: '#fff', fontWeight: 700, fontSize: 14, flex: 1 }}>Schedule Editor</span>
          <SaveButton onSuccess={() => toastRef.current?.show('All changes saved')} />
        </div>
        <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
          <div style={{ ...paneStyle, width: 280, flexShrink: 0, padding: 0 }}>
            <LeftPane />
          </div>
          <div style={{ ...paneStyle, flex: 1, padding: 0 }}>
            <MiddlePane />
          </div>
          <div style={{ ...paneStyle, width: 320, flexShrink: 0, padding: 0 }}>
            <RightPane />
          </div>
        </div>
      </div>
      <Toast ref={toastRef} />
    </DataLoader>
  )
}

export default function App() {
  return (
    <AppProvider>
      <Shell />
    </AppProvider>
  )
}
