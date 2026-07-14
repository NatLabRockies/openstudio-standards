// 'Standard' reference (comparison) schedules from the PNNL support schedules.
//
// Unlike the ASHRAE reference (which needs a template + space type mapping), these are keyed by
// the schedule_set_name from level_1_space_types.json, so a selected space type maps directly to
// its reference curves. Each record carries a `values` array (the server converts the source
// hr_1..hr_24 keys) and a pipe-delimited `day_types` string.

// Editor load category -> support schedule category. The support data uses a single generic
// 'Equipment' category for both electric and gas equipment, and has no hot water category.
const CATEGORY_TO_STANDARD = {
  Occupancy: 'Occupancy',
  Lighting: 'Lighting',
  ElectricEquipment: 'Equipment',
  GasEquipment: 'Equipment',
}

// Does a support record's pipe-delimited day_types cover the active profile's day-type token?
// The parametric profiles use Wkdy / Wknd / Default; the support data splits the weekend into
// Sat and Sun, so Wknd matches either.
function dayTypesCover(dayTypesString, token) {
  const tokens = String(dayTypesString || '').split('|')
  if (token === 'Wknd') return tokens.includes('Sat') || tokens.includes('Sun')
  if (token === 'Default') return tokens.includes('Default')
  return tokens.includes(token)
}

// The schedule set name (support schedule key) for the currently selected space type.
export function standardScheduleSetName(state) {
  const spaceType = (state.rawData.spaceTypes || []).find(st => st.space_type_name === state.selectedSpaceType)
  return spaceType?.schedule_set_name || null
}

// The reference comparison curve for one profile from the standard schedules, or null when the
// schedule set, category, or day type has no matching support record. Returns [{ h, v }].
export function standardScheduleData(standardSchedules, scheduleSetName, category, activeToken) {
  if (!scheduleSetName) return null
  const standardCategory = CATEGORY_TO_STANDARD[category]
  if (!standardCategory) return null

  const candidates = (standardSchedules || []).filter(
    s => s.name === scheduleSetName && s.category === standardCategory
  )
  if (candidates.length === 0) return null

  const record = candidates.find(s => dayTypesCover(s.day_types, activeToken))
    || candidates.find(s => dayTypesCover(s.day_types, 'Default'))
  if (!record || !Array.isArray(record.values)) return null

  return record.values.map((v, i) => ({ h: i, v }))
}
