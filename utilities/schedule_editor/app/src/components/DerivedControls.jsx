import React from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'
import SliderWithInput from './SliderWithInput.jsx'

function paramsArrayFor(category, rawData, workingCopies) {
  if (category === 'Lighting') return workingCopies.lighting_params || rawData.lightingParams
  if (category === 'ElectricEquipment') return workingCopies.elec_equip_params || rawData.elecEquipParams
  if (category === 'GasEquipment') return workingCopies.gas_equip_params || rawData.gasEquipParams
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

  if (!rawObj) return <div style={{ color: '#999', fontSize: 12 }}>No params found for {scheduleName}</div>

  const catLabel = { Lighting: 'Lighting', ElectricEquipment: 'Elec. Equip.', GasEquipment: 'Gas Equip.' }[category] || category

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
    </div>
  )
}
