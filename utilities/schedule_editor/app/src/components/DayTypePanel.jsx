import React, { useState, useMemo, useEffect, useRef } from 'react'
import {
  useAppState, useAppDispatch,
  SET_ACTIVE_DAY_TYPE,
  SET_EXPANDED_PROFILE, SET_EXPANDED_PROFILE_ERROR
} from '../context.jsx'
import { derive, expandParametric } from '../api.js'
import { getUniqueDayTypes } from '../utils/dayAssignment.js'
import { createExpandDebounced } from '../utils/expandDebounced.js'
import { resolveKind } from '../utils/scheduleLookup.js'
import { controlPointParams, offsetsForActiveSet } from '../utils/expandParams.js'
import { evalControlPoint } from '../utils/controlPointCodec.js'
import { diurnalDeriveBody } from '../utils/diurnal.js'
import { getLoadParamArray } from '../utils/workingCopy.js'
import AddProfileDialog from './AddProfileDialog.jsx'
import ProfileChart from './ProfileChart.jsx'
import ControlPointEditor from './ControlPointEditor.jsx'

const CATEGORY_ORDER = ['Occupancy', 'Lighting', 'ElectricEquipment', 'GasEquipment', 'HotWater', 'Diurnal']

function paramsArrayForCategory(category, rawData, workingCopies) {
  if (category === 'Lighting') return workingCopies.lighting_params || rawData.lightingParams || []
  if (category === 'ElectricEquipment') return workingCopies.elec_equip_params || rawData.elecEquipParams || []
  if (category === 'GasEquipment') return workingCopies.gas_equip_params || rawData.gasEquipParams || []
  if (category === 'HotWater') return workingCopies.hot_water_params || rawData.hotWaterParams || []
  return []
}

function categoryFor(scheduleName, rawData, workingCopies) {
  const scheduleSets = workingCopies.schedule_sets || rawData.scheduleSets
  for (const ss of scheduleSets) {
    if (ss.occupancy_schedule === scheduleName) return 'Occupancy'
    if (ss.derived_interior_lighting_parameters === scheduleName) return 'Lighting'
    if (ss.derived_electric_equipment_parameters === scheduleName) return 'ElectricEquipment'
    if (ss.derived_gas_equipment_parameters === scheduleName) return 'GasEquipment'
    if (ss.derived_hot_water_equipment_parameters === scheduleName) return 'HotWater'
  }
  // Fallback: check param arrays
  if ((workingCopies.lighting_params || rawData.lightingParams || []).some(p => p.name === scheduleName)) return 'Lighting'
  if ((workingCopies.elec_equip_params || rawData.elecEquipParams || []).some(p => p.name === scheduleName)) return 'ElectricEquipment'
  if ((workingCopies.gas_equip_params || rawData.gasEquipParams || []).some(p => p.name === scheduleName)) return 'GasEquipment'
  if ((workingCopies.hot_water_params || rawData.hotWaterParams || []).some(p => p.name === scheduleName)) return 'HotWater'
  // Fallback: a parametric record selected directly (e.g. from the Schedules tab) —
  // honor its own category so direct/diurnal schedules render with the right color.
  const paramRec = (workingCopies.parametric_schedules || rawData.parametricSchedules || []).find(p => p.name === scheduleName)
  if (paramRec) {
    if (paramRec.category === 'Lighting') return 'Lighting'
    if (paramRec.category === 'Equipment') return 'ElectricEquipment'
    if (paramRec.category === 'Diurnal') return 'Diurnal'
  }
  return 'Occupancy'
}

export default function DayTypePanel({ occupancyScheduleName, assignments }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [showAddDialog, setShowAddDialog] = useState(false)
  const [editingCp, setEditingCp] = useState(null) // { name, dayType, category } | null
  const [gateCurves, setGateCurves] = useState({}) // loadName -> [{ h, v }] diurnal gate
  const gateCacheRef = useRef({})

  // Create a stable debounced expand function
  const expandRef = useRef(null)
  if (!expandRef.current) {
    expandRef.current = createExpandDebounced(dispatch, 150)
  }
  const scheduleExpand = expandRef.current
  const lastDerivedRef = useRef({})

  const allOccRecords = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules

  const schedObjects = useMemo(() =>
    occupancyScheduleName
      ? allOccRecords.filter(o => o.name === occupancyScheduleName)
      : [],
    [occupancyScheduleName, allOccRecords]
  )

  const dayTypes = useMemo(() => {
    const types = getUniqueDayTypes(schedObjects)
    return ['Default', ...types.filter(t => t !== 'Default')]
  }, [schedObjects])

  const activeTab = dayTypes.includes(state.activeDayType) ? state.activeDayType : (dayTypes[0] || 'Default')

  // Build schedule info for all selected schedules
  const scheduleInfos = useMemo(() => {
    const paramRecords = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
    const infos = state.selectedScheduleNames.map(name => {
      const category = categoryFor(name, state.rawData, state.workingCopies)
      return { name, category, kind: resolveKind(name, category, paramRecords) }
    })
    infos.sort((a, b) =>
      CATEGORY_ORDER.indexOf(a.category) - CATEGORY_ORDER.indexOf(b.category)
    )
    return infos
  }, [state.selectedScheduleNames, state.rawData, state.workingCopies])

  // Trigger expand for control-point schedules (occupancy + direct loads)
  useEffect(() => {
    const occRecords = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
    const offsets = offsetsForActiveSet(state)
    for (const { name, kind } of scheduleInfos) {
      if (kind !== 'occupancy' && kind !== 'direct') continue
      const schedObj = occRecords.find(o => o.name === name && o.day_types === activeTab)
                    || occRecords.find(o => o.name === name && o.day_types === 'Default')
      if (!schedObj) continue
      const params = controlPointParams(state, schedObj, activeTab, { offsets: kind === 'direct' ? offsets : null })
      scheduleExpand(name, activeTab, schedObj, params)
    }
  }, [activeTab, scheduleInfos, state.editorParams, state.workingCopies])

  // Auto-derive non-occupancy schedules when occupancy profile expands or params change
  useEffect(() => {
    if (!occupancyScheduleName) return
    const allOcc = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
    const occSchedObj = allOcc.find(o => o.name === occupancyScheduleName && o.day_types === activeTab)
                     || allOcc.find(o => o.name === occupancyScheduleName && o.day_types === 'Default')
    if (!occSchedObj) return

    const occExpandParams = controlPointParams(state, occSchedObj, activeTab)
    const occExpandKey = `${occupancyScheduleName}|${activeTab}|${JSON.stringify(occExpandParams)}`
    const initial_values = state.expandedProfiles[occExpandKey]
    if (!initial_values) return

    for (const { name, category, kind } of scheduleInfos) {
      if (kind !== 'derived') continue
      const paramsArr = paramsArrayForCategory(category, state.rawData, state.workingCopies)
      const rawObj = paramsArr.find(p => p.name === name)
      if (!rawObj) continue

      const derivedProfileKey = `${name}|${activeTab}`
      const derivedEditorParams = state.editorParams.byProfile[derivedProfileKey] || {}
      const derivationType = derivedEditorParams.derivationType ?? rawObj.derivation_type ?? 'exponential'
      const body = {
        derivation_type: derivationType,
        base: derivedEditorParams.base ?? rawObj.base ?? 0.05,
        peak: derivedEditorParams.peak ?? rawObj.peak ?? 0.9,
        response: derivationType !== 'up_down' ? (derivedEditorParams.response ?? rawObj.response ?? 0.75) : undefined,
        start_slope: derivationType === 'up_down' ? (derivedEditorParams.startSlope ?? rawObj.start_slope ?? 0.25) : undefined,
        end_slope:   derivationType === 'up_down' ? (derivedEditorParams.endSlope   ?? rawObj.end_slope   ?? 0.25) : undefined,
        initial_values,
        timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
        schedule_name: name,
        base_peak_mode: rawObj.base_peak_mode || 'absolute',
        ...diurnalDeriveBody(state, category, name),
      }
      // Only re-derive if occupancy profile or derived params changed
      const cacheKey = `${occExpandKey}||${JSON.stringify(body)}`
      if (lastDerivedRef.current[derivedProfileKey] === cacheKey) continue
      lastDerivedRef.current = { ...lastDerivedRef.current, [derivedProfileKey]: cacheKey }

      derive(body)
        .then(result => {
          dispatch({ type: SET_EXPANDED_PROFILE, payload: { key: derivedProfileKey, pairs: result.time_value_pairs, profileKey: derivedProfileKey } })
        })
        .catch(err => {
          dispatch({ type: SET_EXPANDED_PROFILE_ERROR, payload: { profileKey: derivedProfileKey, message: err.message } })
        })
    }
  }, [state.expandedProfiles, activeTab, scheduleInfos, state.editorParams])

  // Compute the diurnal gate curve for any derived load that has a diurnal profile,
  // so it can be drawn as a faint overlay alongside the gated load.
  useEffect(() => {
    const tph = state.editorParams.timestepsPerHour || 4
    const params = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
    for (const { name, category, kind } of scheduleInfos) {
      if (kind !== 'derived') continue
      const rec = getLoadParamArray(state, category).find(p => p.name === name)
      if (!rec || !rec.diurnal_profile) {
        if (gateCacheRef.current[name]) { gateCacheRef.current[name] = null; setGateCurves(g => ({ ...g, [name]: null })) }
        continue
      }
      const dRec = params.find(o => o.name === rec.diurnal_profile && o.day_types === 'Default')
      if (!dRec) continue
      const mode = rec.diurnal_mode || 'off_when_asleep'
      const weight = rec.diurnal_weight ?? 1.0
      const cacheKey = `${rec.diurnal_profile}|${mode}|${weight}|${tph}|${JSON.stringify(dRec.control_points)}`
      if (gateCacheRef.current[name] === cacheKey) continue
      gateCacheRef.current[name] = cacheKey
      const dParams = { base: dRec.base_std, peak: dRec.peak_std, st: dRec.st_std, et: dRec.et_std, timesteps_per_hour: tph }
      expandParametric(dRec, dParams).then(r => {
        const curve = (r.time_value_pairs || []).map(([h, d]) => {
          let g = mode === 'on_when_asleep' ? weight * d : 1 - weight * d
          g = Math.max(0, Math.min(1, g))
          return { h, v: g }
        })
        setGateCurves(g => ({ ...g, [name]: curve }))
      }).catch(() => {})
    }
  }, [scheduleInfos, activeTab, state.editorParams, state.workingCopies])

  const tabStyle = (active) => ({
    padding: '5px 12px', cursor: 'pointer', border: 'none', fontSize: 12, borderRadius: '4px 4px 0 0',
    background: active ? '#0078d4' : '#eee', color: active ? '#fff' : '#333', marginRight: 2
  })

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '8px 12px 0', borderBottom: '1px solid #ddd', flexShrink: 0 }}>
        {dayTypes.map(dt => (
          <button key={dt} style={tabStyle(dt === activeTab)}
            onClick={() => dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: dt })}>
            {dt}
          </button>
        ))}
        <button style={{ ...tabStyle(false), background: '#f0f8ff', color: '#0078d4', marginLeft: 4 }}
          onClick={() => setShowAddDialog(true)} title="Add day-type profile">+</button>
      </div>

      <div style={{ flex: 1, padding: '12px', overflow: 'auto' }}>
        {scheduleInfos.map(({ name, category, kind }) => {
          const ashraeRefName = state.standardReferenceOverrides[name]
          const ashraeObjs = state.rawData.ashraeSchedules.filter(s => {
            const cat = s.category === 'Electric Equipment' ? 'ElectricEquipment'
              : s.category === 'Service Water Heating' ? 'HotWater'
              : s.category
            return ashraeRefName ? s.name === ashraeRefName : cat === category
          })
          const ashraeObj = ashraeObjs.find(s => s.day_types === activeTab)
                         || ashraeObjs.find(s => s.day_types === 'Default')
          const standardData = ashraeObj?.values?.map((v, i) => ({ h: i, v })) || null

          const occRecords = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
          const schedObj = occRecords.find(o => o.name === name && o.day_types === activeTab)
                        || occRecords.find(o => o.name === name && o.day_types === 'Default')

          let expandedData = null
          // Resolve occupancy schedule object and its current st/et for reference lines
          const occScheduleName = occupancyScheduleName
          const allOccRecs = state.workingCopies.parametric_schedules || state.rawData.parametricSchedules
          const occSchedObjForChart = occScheduleName
            ? (allOccRecs.find(o => o.name === occScheduleName && o.day_types === activeTab)
              || allOccRecs.find(o => o.name === occScheduleName && o.day_types === 'Default'))
            : null
          const occParamsForChart = occSchedObjForChart
            ? controlPointParams(state, occSchedObjForChart, activeTab)
            : null
          const stTime = occParamsForChart ? occParamsForChart.st : null
          const etTime = occParamsForChart ? occParamsForChart.et : null

          if ((kind === 'occupancy' || kind === 'direct') && schedObj) {
            const params = controlPointParams(state, schedObj, activeTab, {
              offsets: kind === 'direct' ? offsetsForActiveSet(state) : null,
            })
            const paramsHash = JSON.stringify(params)
            const expandKey = `${name}|${activeTab}|${paramsHash}`
            const pairs = state.expandedProfiles[expandKey]
            expandedData = pairs?.map(([h, v]) => ({ h, v })) || null
          } else {
            const derivedKey = `${name}|${activeTab}`
            const pairs = state.expandedProfiles[derivedKey]
            expandedData = pairs?.map(([h, v]) => ({ h, v })) || null
          }

          const profileKey = `${name}|${activeTab}`
          const errorState = state.expandedProfileErrors[profileKey]

          const editable = kind === 'occupancy' || kind === 'direct'
          // Spillover: control-point profile whose anchors extend past midnight (or
          // before hour 0) spills into the adjacent day (library emits a boundary rule).
          let spillNote = null
          if (editable && schedObj?.control_points) {
            const times = schedObj.control_points.map(cp => evalControlPoint(cp, schedObj, state.editorParams.timestepsPerHour || 4)[0])
            const maxT = Math.max(...times), minT = Math.min(...times)
            if (maxT > 24) spillNote = '→ next day'
            else if (minT < 0) spillNote = 'prev day ←'
          }
          return (
            <ProfileChart
              key={name}
              scheduleName={name}
              category={category}
              standardData={standardData}
              expandedData={expandedData}
              hasError={!!errorState}
              errorMessage={errorState?.message || null}
              isLoading={!expandedData && !errorState}
              stTime={stTime}
              etTime={etTime}
              onEditControlPoints={editable ? () => setEditingCp({ name, dayType: activeTab, category }) : null}
              spillNote={spillNote}
              gateData={kind === 'derived' ? (gateCurves[name] || null) : null}
            />
          )
        })}
      </div>

      {showAddDialog && (
        <AddProfileDialog occupancyScheduleName={occupancyScheduleName} onClose={() => setShowAddDialog(false)} />
      )}

      {editingCp && (
        <ControlPointEditor
          scheduleName={editingCp.name}
          dayType={editingCp.dayType}
          category={editingCp.category}
          onClose={() => setEditingCp(null)}
        />
      )}
    </div>
  )
}
