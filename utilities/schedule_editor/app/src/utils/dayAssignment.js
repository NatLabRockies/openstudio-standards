const WEEKDAY_TOKENS = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
const WEEKGROUP_TOKENS = ['Wkdy','Wknd']
const EXCLUDED = ['WntrDsn','SmrDsn']

// JS Date.getDay(): 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
const DAY_TOKEN_MAP = { 0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat' }

function specificity(dayType) {
  if (WEEKDAY_TOKENS.includes(dayType)) return 2
  if (WEEKGROUP_TOKENS.includes(dayType)) return 1
  if (dayType === 'Default') return 0
  return -1
}

function inDateRange(scheduleObj, month, day) {
  // month is 1-based, day is 1-based
  const { start_date, end_date } = scheduleObj
  if (!start_date && !end_date) return true
  if (!start_date || !end_date) return true  // partial = year-round

  // Parse month-day from ISO string "YYYY-MM-DDT..."
  const [sm, sd] = start_date.split('T')[0].split('-').slice(1).map(Number)
  const [em, ed] = end_date.split('T')[0].split('-').slice(1).map(Number)

  const current = month * 100 + day
  const start = sm * 100 + sd
  const end = em * 100 + ed

  if (start <= end) {
    return current >= start && current <= end
  } else {
    // wraps around year boundary
    return current >= start || current <= end
  }
}

function weekGroupFor(jsDay) {
  // jsDay: 0=Sun..6=Sat
  return (jsDay === 0 || jsDay === 6) ? 'Wknd' : 'Wkdy'
}

export function assignDayTypes(scheduleObjects, year) {
  const result = {}
  const eligible = scheduleObjects.filter(o => !EXCLUDED.includes(o.day_types))

  const startOfYear = new Date(year, 0, 1)
  const endOfYear = new Date(year, 11, 31)
  const days = Math.round((endOfYear - startOfYear) / 86400000) + 1 // 365 or 366

  for (let d = 0; d < days; d++) {
    const date = new Date(year, 0, 1 + d)
    const month = date.getMonth() + 1  // 1-based
    const dayOfMonth = date.getDate()
    const jsDay = date.getDay()        // 0=Sun
    const isoDate = date.toISOString().split('T')[0]

    const namedDayToken = DAY_TOKEN_MAP[jsDay]
    const weekGroupToken = weekGroupFor(jsDay)

    // Filter objects in range
    const inRange = eligible.filter(o => inDateRange(o, month, dayOfMonth))

    // Find best match
    let best = null
    let bestSpec = -1

    for (const obj of inRange) {
      const tok = obj.day_types
      // Check if this token matches the current day
      let matches = false
      if (tok === namedDayToken) matches = true
      else if (tok === weekGroupToken) matches = true
      else if (tok === 'Default') matches = true

      if (matches) {
        const spec = specificity(tok)
        if (spec > bestSpec) {
          bestSpec = spec
          best = tok
        }
      }
    }

    result[isoDate] = best || 'Default'
  }

  return result
}

export function getUniqueDayTypes(scheduleObjects) {
  return [...new Set(
    scheduleObjects
      .filter(o => !['WntrDsn','SmrDsn'].includes(o.day_types))
      .map(o => o.day_types)
  )]
}
