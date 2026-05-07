import React from 'react'
import { useAppState, useAppDispatch, SET_EXPANDED_PROFILE, SET_EXPANDED_PROFILE_ERROR } from '../context.jsx'
import { derive } from '../api.js'
import GlobalControls from './GlobalControls.jsx'
import StandardReferenceSelector from './StandardReferenceSelector.jsx'
import ProfileMetaControls from './ProfileMetaControls.jsx'
import ScheduleControls from './ScheduleControls.jsx'
import DerivedControls from './DerivedControls.jsx'

const CATEGORY_ORDER = ['Occupancy','Lighting','ElectricEquipment','GasEquipment','HotWater']

function categoryFor(scheduleName, rawData, workingCopies) {
  const scheduleSets = workingCopies.schedule_sets || rawData.scheduleSets
  for (const ss of scheduleSets) {
    if (ss.occupancy_schedule === scheduleName) return 'Occupancy'
    if (ss.derived_interior_lighting_parameters === scheduleName) return 'Lighting'
    if (ss.derived_electric_equipment_parameters === scheduleName) return 'ElectricEquipment'
    if (ss.derived_gas_equipment_parameters === scheduleName) return 'GasEquipment'
    if (ss.derived_hot_water_equipment_parameters === scheduleName) return 'HotWater'
  }
  if ((workingCopies.lighting_params || rawData.lightingParams || []).some(p => p.name === scheduleName)) return 'Lighting'
  if ((workingCopies.elec_equip_params || rawData.elecEquipParams || []).some(p => p.name === scheduleName)) return 'ElectricEquipment'
  if ((workingCopies.gas_equip_params || rawData.gasEquipParams || []).some(p => p.name === scheduleName)) return 'GasEquipment'
  return 'Occupancy'
}

export default function RightPane() {
  const state = useAppState()
  const dispatch = useAppDispatch()

  const scheduleInfos = state.selectedScheduleNames
    .map(name => ({ name, category: categoryFor(name, state.rawData, state.workingCopies) }))
    .sort((a, b) => CATEGORY_ORDER.indexOf(a.category) - CATEGORY_ORDER.indexOf(b.category))

  const occupancyInfo = scheduleInfos.find(s => s.category === 'Occupancy')

  // Called by controls when params change — DayTypePanel.useEffect handles re-expansion
  function handleParamsChanged() {
    // DayTypePanel.useEffect handles re-expansion when editorParams change
  }

  // Called when derived params change — triggers derive API call
  function handleDerivedParamsChanged(name, category, newParams) {
    const occupancyName = occupancyInfo?.name
    if (!occupancyName) return

    // Compute occupancy params to look up the expand key (same logic as DayTypePanel)
    const allOccRecords = state.workingCopies.occupancy_schedules || state.rawData.occupancySchedules
    const dayType = state.activeDayType
    const schedObj = allOccRecords.find(o => o.name === occupancyName && o.day_types === dayType)
                  || allOccRecords.find(o => o.name === occupancyName && o.day_types === 'Default')
    if (!schedObj) return

    const occProfileKey = `${occupancyName}|${dayType}`
    const occProfileParams = state.editorParams.byProfile[occProfileKey]
    const occParams = {
      base: occProfileParams?.base ?? schedObj.base_std,
      peak: occProfileParams?.peak ?? schedObj.peak_std,
      st:   occProfileParams?.st   ?? schedObj.st_std,
      et:   occProfileParams?.et   ?? schedObj.et_std,
      timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
    }
    const expandKey = `${occupancyName}|${dayType}|${JSON.stringify(occParams)}`
    const initial_values = state.expandedProfiles[expandKey]

    if (!initial_values) return

    const derivationType = newParams.derivationType || 'exponential'
    derive({
      derivation_type: derivationType,
      base: newParams.base,
      peak: newParams.peak,
      response: derivationType !== 'up_down' ? newParams.response : undefined,
      start_slope: derivationType === 'up_down' ? newParams.startSlope : undefined,
      end_slope:   derivationType === 'up_down' ? newParams.endSlope   : undefined,
      initial_values,
      timesteps_per_hour: state.editorParams.timestepsPerHour || 4,
      schedule_name: name,
    }).then(result => {
      const derivedProfileKey = `${name}|${dayType}`
      dispatch({ type: SET_EXPANDED_PROFILE, payload: { key: derivedProfileKey, pairs: result.time_value_pairs, profileKey: derivedProfileKey } })
    }).catch(err => {
      const derivedProfileKey = `${name}|${dayType}`
      dispatch({ type: SET_EXPANDED_PROFILE_ERROR, payload: { profileKey: derivedProfileKey, message: err.message } })
    })
  }

  // Called when ProfileMetaControls dates change — MiddlePane.useEffect handles recomputation
  function handleDatesChanged() {
    // MiddlePane.useEffect handles day-assignment recomputation
  }

  if (state.selectedScheduleNames.length === 0) {
    return (
      <div style={{ padding: 16, color: '#888', fontSize: 13 }}>
        Select a space type or schedule to edit parameters.
      </div>
    )
  }

  return (
    <div style={{ padding: 12, overflowY: 'auto', height: '100%', boxSizing: 'border-box' }}>
      <GlobalControls onParamsChanged={handleParamsChanged} />

      {occupancyInfo && (
        <ProfileMetaControls
          scheduleName={occupancyInfo.name}
          onDatesChanged={handleDatesChanged}
        />
      )}

      <StandardReferenceSelector scheduleInfos={scheduleInfos} />

      {scheduleInfos.map(({ name, category }) => (
        <div key={name}>
          {category === 'Occupancy'
            ? <ScheduleControls scheduleName={name} onParamsChanged={handleParamsChanged} />
            : <DerivedControls scheduleName={name} category={category} onParamsChanged={handleParamsChanged} onDerivedParamsChanged={(newParams) => handleDerivedParamsChanged(name, category, newParams)} />
          }
        </div>
      ))}
    </div>
  )
}
