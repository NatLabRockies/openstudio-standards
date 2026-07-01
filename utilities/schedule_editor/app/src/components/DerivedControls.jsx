import React from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'
import SliderWithInput from './SliderWithInput.jsx'
import { diurnalScheduleNames } from '../utils/scheduleLookup.js'
import { patchLoadParamRecord } from '../utils/workingCopy.js'
import { DIURNAL_MODES } from '../utils/diurnal.js'

function paramsArrayFor(category, rawData, workingCopies) {
  if (category === 'Lighting') return workingCopies.lighting_params || rawData.lightingParams
  if (category === 'ElectricEquipment') return workingCopies.elec_equip_params || rawData.elecEquipParams
  if (category === 'GasEquipment') return workingCopies.gas_equip_params || rawData.gasEquipParams
  if (category === 'HotWater') return workingCopies.hot_water_params || rawData.hotWaterParams
  return []
}

export default function DerivedControls({ scheduleName, category, onParamsChanged, onDerivedParamsChanged }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const dayType = state.activeDayType

  const paramsArr = paramsArrayFor(category, state.rawData, state.workingCopies)
  const rawObj = paramsArr.find(p => p.name === scheduleName)

  const profileKey = `${scheduleName}|${dayType}`
  const savedParams = state.editorParams.byProfile[profileKey] || {}

  const params = {
    base:            savedParams.base            ?? rawObj?.base            ?? 0.05,
    peak:            savedParams.peak            ?? rawObj?.peak            ?? 0.9,
    response:        savedParams.response        ?? rawObj?.response        ?? 0.75,
    startSlope:      savedParams.startSlope      ?? rawObj?.start_slope     ?? 0.25,
    endSlope:        savedParams.endSlope        ?? rawObj?.end_slope       ?? 0.25,
    derivationType:  savedParams.derivationType  ?? rawObj?.derivation_type ?? 'exponential',
  }

  const isUpDown = params.derivationType === 'up_down'

  // All four derivation types supported by derive_values
  const derivationTypes = ['linear', 'exponential', 'exponential-inverse', 'up_down']

  function update(field, value) {
    const newParams = { ...params, [field]: value }
    dispatch({ type: SET_EDITOR_PARAMS, payload: { scheduleName, dayType, params: newParams } })
    onParamsChanged?.()
    onDerivedParamsChanged?.(newParams)
  }

  // Diurnal gate inputs live on the derived-load parameter record (saved to the
  // *_parameters.json file). The gate scales occupancy presence before derivation.
  const diurnalOptions = diurnalScheduleNames(state.workingCopies.parametric_schedules || state.rawData.parametricSchedules)
  const diurnalProfile = rawObj?.diurnal_profile || ''
  const diurnalMode = rawObj?.diurnal_mode || 'off_when_asleep'
  const diurnalWeight = rawObj?.diurnal_weight ?? 1.0

  function updateDiurnal(patch) {
    patchLoadParamRecord(state, dispatch, category, scheduleName, patch)
    onParamsChanged?.()
  }

  if (!rawObj) return <div style={{ color: '#999', fontSize: 12 }}>No params found for {scheduleName}</div>

  const catLabel = { Lighting: 'Lighting', ElectricEquipment: 'Elec. Equip.', GasEquipment: 'Gas Equip.', HotWater: 'Hot Water' }[category] || category

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6, color: '#333' }}>
        {catLabel} — {scheduleName}
      </div>
      <div style={{ marginBottom: 8 }}>
        <label style={{ fontSize: 12, color: '#555' }}>Derivation type</label>
        <select
          value={params.derivationType}
          onChange={e => update('derivationType', e.target.value)}
          style={{ width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, marginTop: 2 }}
        >
          {derivationTypes.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
      </div>
      <div style={{ marginBottom: 8 }}>
        <label style={{ fontSize: 12, color: '#555' }} title="absolute: base/peak are absolute output endpoints; relative: scaled by the occupancy base/peak">
          Base/peak mode
        </label>
        <select
          value={rawObj?.base_peak_mode || 'absolute'}
          onChange={e => updateDiurnal({ base_peak_mode: e.target.value })}
          style={{ width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, marginTop: 2 }}
        >
          <option value="absolute">absolute (default)</option>
          <option value="relative">relative (to occupancy)</option>
        </select>
      </div>
      <SliderWithInput label="Base" value={params.base} min={0} max={1} step={0.05}
        stdValue={rawObj.base} onChange={v => update('base', v)} />
      <SliderWithInput label="Peak" value={params.peak} min={0} max={1} step={0.05}
        stdValue={rawObj.peak} onChange={v => update('peak', v)} />
      {isUpDown ? (
        <>
          <SliderWithInput label="Start slope" value={params.startSlope} min={0} max={2} step={0.05}
            stdValue={rawObj.start_slope ?? 0.25} onChange={v => update('startSlope', v)} />
          <SliderWithInput label="End slope" value={params.endSlope} min={0} max={2} step={0.05}
            stdValue={rawObj.end_slope ?? 0.25} onChange={v => update('endSlope', v)} />
        </>
      ) : (
        <SliderWithInput label="Response" value={params.response} min={0} max={1} step={0.05}
          stdValue={rawObj.response} onChange={v => update('response', v)} />
      )}

      <div style={{ marginTop: 8, padding: 8, background: '#f6f2fb', borderRadius: 4, border: '1px solid #e6daf2' }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#7a4ca0', marginBottom: 6 }}>Diurnal gate</div>
        <label style={{ fontSize: 11, color: '#555', display: 'block', marginBottom: 2 }}>Diurnal profile</label>
        <select
          value={diurnalProfile}
          onChange={e => updateDiurnal({ diurnal_profile: e.target.value || null })}
          style={{ width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, marginBottom: 8 }}
        >
          <option value="">(none)</option>
          {diurnalOptions.map(n => <option key={n} value={n}>{n}</option>)}
        </select>
        {diurnalProfile && (
          <>
            <label style={{ fontSize: 11, color: '#555', display: 'block', marginBottom: 2 }}>Mode</label>
            <select
              value={diurnalMode}
              onChange={e => updateDiurnal({ diurnal_mode: e.target.value })}
              style={{ width: '100%', padding: '4px 6px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3, marginBottom: 8 }}
            >
              {DIURNAL_MODES.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
            <SliderWithInput label="Weight" value={diurnalWeight} min={0} max={1} step={0.05}
              onChange={v => updateDiurnal({ diurnal_weight: v })} />
            <div style={{ fontSize: 10, color: '#999' }}>
              gate = {diurnalMode === 'on_when_asleep' ? 'weight·d' : '1 − weight·d'} (saved to {scheduleName})
            </div>
          </>
        )}
      </div>
    </div>
  )
}
