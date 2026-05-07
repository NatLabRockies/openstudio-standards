import React, { useState, useMemo, useEffect, useRef } from 'react'
import {
  useAppState, useAppDispatch,
  SET_ACTIVE_DAY_TYPE,
  SET_EXPANDED_PROFILE, SET_EXPANDED_PROFILE_ERROR
} from '../context.jsx'
import { derive } from '../api.js'
import { getUniqueDayTypes } from '../utils/dayAssignment.js'
import { createExpandDebounced } from '../utils/expandDebounced.js'
import AddProfileDialog from './AddProfileDialog.jsx'
import ProfileChart from './ProfileChart.jsx'

const CATEGORY_ORDER = ['Occupancy', 'Lighting', 'ElectricEquipment', 'GasEquipment', 'HotWater']

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
  return 'Occupancy'
}

export default function DayTypePanel({ occupancyScheduleName, assignments }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [showAddDialog, setShowAddDialog] = useState(false)

  // Create a stable debounced expand function
  const expandRef = useRef(null)
  if (!expandRef.current) {
    expandRef.current = createExpandDebounced(dispatch, 150)
  }
  const scheduleExpand = expandRef.current
  const lastDerivedRef = useRef({})

  const allOccRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules

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
    const infos = state.selectedScheduleNames.map(name => ({
      name,
      category: categoryFor(name, state.rawData, state.workingCopies),
    }))
    infos.sort((a, b) =>
      CATEGORY_ORDER.indexOf(a.category) - CATEGORY_ORDER.indexOf(b.category)
    )
    return infos
  }, [state.selectedScheduleNames, state.rawData, state.workingCopies])

  // Trigger expand for occupancy schedules when activeTab or selection changes
  useEffect(() => {
    const occRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
    for (const { name, category } of scheduleInfos) {
      if (category !== 'Occupancy') continue
      const schedObj = occRecords.find(o => o.name === name && o.day_types === activeTab)
                    || occRecords.find(o => o.name === name && o.day_types === 'Default')
      if (!schedObj) continue
      const profileKey = `${name}|${activeTab}`
      const profileParams = state.editorParams.byProfile[profileKey]
      const params = {
        base: profileParams?.base ?? schedObj.base_std,
        peak: profileParams?.peak ?? schedObj.peak_std,
        st:   profileParams?.st   ?? schedObj.st_std,
        et:   profileParams?.et   ?? schedObj.et_std,
        timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
      }
      scheduleExpand(name, activeTab, schedObj, params)
    }
  }, [activeTab, scheduleInfos, state.editorParams])

  // Auto-derive non-occupancy schedules when occupancy profile expands or params change
  useEffect(() => {
    if (!occupancyScheduleName) return
    const allOcc = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
    const occSchedObj = allOcc.find(o => o.name === occupancyScheduleName && o.day_types === activeTab)
                     || allOcc.find(o => o.name === occupancyScheduleName && o.day_types === 'Default')
    if (!occSchedObj) return

    const occProfileKey = `${occupancyScheduleName}|${activeTab}`
    const occEditorParams = state.editorParams.byProfile[occProfileKey]
    const occExpandParams = {
      base: occEditorParams?.base ?? occSchedObj.base_std,
      peak: occEditorParams?.peak ?? occSchedObj.peak_std,
      st:   occEditorParams?.st   ?? occSchedObj.st_std,
      et:   occEditorParams?.et   ?? occSchedObj.et_std,
      timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
    }
    const occExpandKey = `${occupancyScheduleName}|${activeTab}|${JSON.stringify(occExpandParams)}`
    const initial_values = state.expandedProfiles[occExpandKey]
    if (!initial_values) return

    for (const { name, category } of scheduleInfos) {
      if (category === 'Occupancy') continue
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
        {scheduleInfos.map(({ name, category }) => {
          const ashraeRefName = state.standardReferenceOverrides[name]
          const ashraeObjs = state.rawData.ashraeSchedules.filter(s => {
            const cat = (s.category === 'Electric Equipment') ? 'ElectricEquipment' : s.category
            return ashraeRefName ? s.name === ashraeRefName : cat === category
          })
          const ashraeObj = ashraeObjs.find(s => s.day_types === activeTab)
                         || ashraeObjs.find(s => s.day_types === 'Default')
          const standardData = ashraeObj?.values?.map((v, i) => ({ h: i, v })) || null

          const occRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
          const schedObj = occRecords.find(o => o.name === name && o.day_types === activeTab)
                        || occRecords.find(o => o.name === name && o.day_types === 'Default')

          let expandedData = null
          // Resolve occupancy schedule object and its current st/et for reference lines
          const occScheduleName = occupancyScheduleName
          const allOccRecs = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
          const occSchedObjForChart = occScheduleName
            ? (allOccRecs.find(o => o.name === occScheduleName && o.day_types === activeTab)
              || allOccRecs.find(o => o.name === occScheduleName && o.day_types === 'Default'))
            : null
          const occProfileKeyForChart = occScheduleName ? `${occScheduleName}|${activeTab}` : null
          const occEditorParamsForChart = occProfileKeyForChart ? state.editorParams.byProfile[occProfileKeyForChart] : null
          const stTime = occSchedObjForChart
            ? (occEditorParamsForChart?.st ?? occSchedObjForChart.st_std ?? null)
            : null
          const etTime = occSchedObjForChart
            ? (occEditorParamsForChart?.et ?? occSchedObjForChart.et_std ?? null)
            : null

          if (category === 'Occupancy' && schedObj) {
            const profileKey = `${name}|${activeTab}`
            const profileParams = state.editorParams.byProfile[profileKey]
            const params = {
              base: profileParams?.base ?? schedObj.base_std,
              peak: profileParams?.peak ?? schedObj.peak_std,
              st:   profileParams?.st   ?? schedObj.st_std,
              et:   profileParams?.et   ?? schedObj.et_std,
              timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
            }
            const paramsHash = JSON.stringify(params)
            const expandKey = `${name}|${activeTab}|${paramsHash}`
            const pairs = state.expandedProfiles[expandKey]
            expandedData = pairs?.map(([h, v]) => ({ h, v })) || null
          } else if (category !== 'Occupancy') {
            const derivedKey = `${name}|${activeTab}`
            const pairs = state.expandedProfiles[derivedKey]
            expandedData = pairs?.map(([h, v]) => ({ h, v })) || null
          }

          const profileKey = `${name}|${activeTab}`
          const errorState = state.expandedProfileErrors[profileKey]

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
            />
          )
        })}
      </div>

      {showAddDialog && (
        <AddProfileDialog occupancyScheduleName={occupancyScheduleName} onClose={() => setShowAddDialog(false)} />
      )}
    </div>
  )
}
