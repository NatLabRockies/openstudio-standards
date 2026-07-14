// Profile identity for the schedule editor.
//
// A schedule's records share a `name` but each record is a distinct *profile* keyed by
// its day_type token AND its start_date/end_date range. e.g. "school classroom occupancy"
// has three separate `Wkdy` profiles (1/1-6/30, 7/1-9/1, 9/1-12/31). The editor treats
// each such record as its own tab / calendar color / editable profile.
//
// profileKey(record) is the stable identity used as the active-tab value and in editor
// state keys. For a full-year record it is just the day_type token (so simple schedules
// behave exactly as before); for a date-ranged record it is `day_type@M/D-M/D`.

const DESIGN_DAYS = ['WntrDsn', 'SmrDsn']
const WEEKDAY_TOKENS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const WEEKGROUP_TOKENS = ['Wkdy', 'Wknd']

// JS Date.getDay(): 0=Sun … 6=Sat
const DAY_TOKEN_MAP = { 0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat' }

export const DAY_TYPE_COLORS = {
  Default: '#b0b0b0', Wkdy: '#4a90d9', Wknd: '#e67e22',
  Mon: '#2ecc71', Tue: '#1abc9c', Wed: '#3498db',
  Thu: '#9b59b6', Fri: '#f39c12', Sat: '#e74c3c', Sun: '#e91e63',
}

// [month, day] (1-based) from an ISO date string, or null.
function dateParts(iso) {
  if (!iso) return null
  const [, m, d] = iso.split('T')[0].split('-')
  return [parseInt(m, 10), parseInt(d, 10)]
}

// A record with no dates, or exactly 1/1–12/31, is "full year" (no range label).
export function isFullYear(record) {
  const s = dateParts(record.start_date)
  const e = dateParts(record.end_date)
  if (!s || !e) return true
  return s[0] === 1 && s[1] === 1 && e[0] === 12 && e[1] === 31
}

// "M/D-M/D" range label, or null for full-year.
export function rangeLabel(record) {
  if (isFullYear(record)) return null
  const s = dateParts(record.start_date)
  const e = dateParts(record.end_date)
  if (!s || !e) return null
  return `${s[0]}/${s[1]}-${e[0]}/${e[1]}`
}

export function profileKey(record) {
  const range = rangeLabel(record)
  return range ? `${record.day_types}@${range}` : record.day_types
}

export function profileLabel(record) {
  const range = rangeLabel(record)
  return range ? `${record.day_types} ${range}` : record.day_types
}

// The day_type token portion of a profile key (for ASHRAE reference matching etc.).
export function dayTypeOf(key) {
  return key.includes('@') ? key.split('@')[0] : key
}

// Records that are editable profiles (excludes design days).
function editableRecords(records, name) {
  return records.filter(r => r.name === name && !DESIGN_DAYS.includes(r.day_types))
}

// Sorted list of profile descriptors for a schedule: Default first, then by day-type
// order, then by start date. Each: { key, label, dayType, record }.
export function listProfiles(records, name) {
  const order = ['Default', 'Wkdy', 'Wknd', ...WEEKDAY_TOKENS]
  return editableRecords(records, name)
    .map(r => ({ key: profileKey(r), label: profileLabel(r), dayType: r.day_types, record: r }))
    .sort((a, b) => {
      const oa = order.indexOf(a.dayType), ob = order.indexOf(b.dayType)
      if (oa !== ob) return (oa < 0 ? 99 : oa) - (ob < 0 ? 99 : ob)
      const sa = dateParts(a.record.start_date), sb = dateParts(b.record.start_date)
      return (sa ? sa[0] * 100 + sa[1] : 0) - (sb ? sb[0] * 100 + sb[1] : 0)
    })
}

// Find the record for a schedule matching a profile key, with graceful fallbacks
// (exact key -> same day-type token -> Default) so loads whose profiles don't line up
// with the driving occupancy schedule still resolve.
export function findProfileRecord(records, name, key) {
  const forName = records.filter(r => r.name === name)
  return (
    forName.find(r => profileKey(r) === key) ||
    forName.find(r => r.day_types === dayTypeOf(key)) ||
    forName.find(r => r.day_types === 'Default') ||
    null
  )
}

// --- calendar assignment ----------------------------------------------------

function specificity(dayType) {
  if (WEEKDAY_TOKENS.includes(dayType)) return 2
  if (WEEKGROUP_TOKENS.includes(dayType)) return 1
  if (dayType === 'Default') return 0
  return -1
}

function inDateRange(record, month, day) {
  const s = dateParts(record.start_date)
  const e = dateParts(record.end_date)
  if (!s || !e) return true
  const current = month * 100 + day
  const start = s[0] * 100 + s[1]
  const end = e[0] * 100 + e[1]
  return start <= end ? (current >= start && current <= end) : (current >= start || current <= end)
}

function rangeSpanDays(record) {
  const s = dateParts(record.start_date)
  const e = dateParts(record.end_date)
  if (!s || !e) return 366
  return (e[0] * 31 + e[1]) - (s[0] * 31 + s[1])
}

function weekGroupFor(jsDay) {
  return (jsDay === 0 || jsDay === 6) ? 'Wknd' : 'Wkdy'
}

// Map each day of the year to the winning profile's key. Among in-range matches the most
// specific day-type wins; ties break to the narrower date range.
export function assignProfiles(records, name, year) {
  const result = {}
  const eligible = editableRecords(records, name)

  const start = new Date(year, 0, 1)
  const end = new Date(year, 11, 31)
  const numDays = Math.round((end - start) / 86400000) + 1

  for (let i = 0; i < numDays; i++) {
    const date = new Date(year, 0, 1 + i)
    const month = date.getMonth() + 1
    const dom = date.getDate()
    const jsDay = date.getDay()
    const iso = `${year}-${String(month).padStart(2, '0')}-${String(dom).padStart(2, '0')}`

    const namedToken = DAY_TOKEN_MAP[jsDay]
    const weekGroup = weekGroupFor(jsDay)

    let best = null, bestSpec = -1, bestSpan = Infinity
    for (const obj of eligible) {
      const tok = obj.day_types
      const matches = tok === namedToken || tok === weekGroup || tok === 'Default'
      if (!matches || !inDateRange(obj, month, dom)) continue
      const spec = specificity(tok)
      const span = rangeSpanDays(obj)
      if (spec > bestSpec || (spec === bestSpec && span < bestSpan)) {
        best = obj; bestSpec = spec; bestSpan = span
      }
    }
    result[iso] = best ? profileKey(best) : 'Default'
  }
  return result
}

// --- colors -----------------------------------------------------------------

function shadeHex(hex, amt) {
  const n = parseInt(hex.slice(1), 16)
  let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255
  const target = amt >= 0 ? 255 : 0
  const p = Math.abs(amt)
  r = Math.round(r + (target - r) * p)
  g = Math.round(g + (target - g) * p)
  b = Math.round(b + (target - b) * p)
  return '#' + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('')
}

// Assign a color per profile key: base color by day-type token, with distinct lightness
// shades when a token has multiple date-ranged profiles.
export function profileColorMap(profiles) {
  const byToken = {}
  profiles.forEach(p => { (byToken[p.dayType] = byToken[p.dayType] || []).push(p) })
  const map = {}
  Object.entries(byToken).forEach(([tok, ps]) => {
    const base = DAY_TYPE_COLORS[tok] || '#888888'
    if (ps.length === 1) { map[ps[0].key] = base; return }
    ps.forEach((p, i) => {
      const amt = (i / (ps.length - 1)) * 0.55 - 0.2 // spread lightness -0.2 … +0.35
      map[p.key] = shadeHex(base, amt)
    })
  })
  return map
}
