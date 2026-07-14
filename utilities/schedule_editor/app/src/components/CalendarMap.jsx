import React from 'react'
import { useAppDispatch, SET_ACTIVE_DAY_TYPE, SET_SELECTED_DATE } from '../context.jsx'

const EMPTY_COLOR = '#eeeeee'

const DOW_LABELS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
const MONTH_NAMES = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

function isLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
}

// Layout constants
const CELL = 13
const GAP = 2
const STEP = CELL + GAP
const DOW_W = 20   // left margin for day-of-week labels
const MONTH_H = 16 // top margin for month labels

export default function CalendarMap({ assignments, year, profiles = [], colorMap = {} }) {
  const dispatch = useAppDispatch()
  const labelByKey = Object.fromEntries(profiles.map(p => [p.key, p.label]))

  const jan1 = new Date(year, 0, 1)
  const firstDow = jan1.getDay()  // 0=Sun … 6=Sat
  const numDays = isLeapYear(year) ? 366 : 365
  const numWeeks = Math.ceil((firstDow + numDays) / 7)

  // Build one record per day of the year
  const days = []
  for (let i = 0; i < numDays; i++) {
    const date = new Date(year, 0, 1 + i)
    const dow = date.getDay()
    const weekIndex = Math.floor((firstDow + i) / 7)
    const mo = date.getMonth()
    const d = date.getDate()
    const isoDate = `${year}-${String(mo + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    days.push({ isoDate, weekIndex, dow, month: mo })
  }

  // First weekIndex of each month (for placing month labels)
  const monthLabels = Array.from({ length: 12 }, (_, m) => {
    const first = days.find(d => d.month === m)
    return first ? { month: m, weekIndex: first.weekIndex } : null
  }).filter(Boolean)

  const svgWidth = DOW_W + numWeeks * STEP
  const svgHeight = MONTH_H + 7 * STEP

  return (
    <div>
      <svg
        width={svgWidth}
        height={svgHeight}
        style={{ display: 'block', overflow: 'visible', maxWidth: '100%' }}
      >
        {/* Month labels */}
        {monthLabels.map(({ month, weekIndex }) => (
          <text
            key={month}
            x={DOW_W + weekIndex * STEP}
            y={MONTH_H - 3}
            fontSize={10}
            fill="#555"
          >
            {MONTH_NAMES[month]}
          </text>
        ))}

        {/* Day-of-week labels — show Mo, We, Fr only (like D3) */}
        {[1, 3, 5].map(dow => (
          <text
            key={dow}
            x={DOW_W - 3}
            y={MONTH_H + dow * STEP + CELL - 2}
            fontSize={9}
            fill="#888"
            textAnchor="end"
          >
            {DOW_LABELS[dow]}
          </text>
        ))}

        {/* Day cells — colored by the profile (day-type + date range) assigned to each day */}
        {days.map(({ isoDate, weekIndex, dow }) => {
          const key = assignments?.[isoDate]
          const fill = key ? (colorMap[key] || EMPTY_COLOR) : EMPTY_COLOR
          const x = DOW_W + weekIndex * STEP
          const y = MONTH_H + dow * STEP
          return (
            <g
              key={isoDate}
              onClick={() => {
                if (!key) return
                dispatch({ type: SET_SELECTED_DATE, payload: isoDate })
                dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: key })
              }}
              style={{ cursor: key ? 'pointer' : 'default' }}
            >
              <title>{`${isoDate}: ${(key && labelByKey[key]) || key || '—'}`}</title>
              <rect x={x} y={y} width={CELL} height={CELL} rx={2} ry={2} fill={fill} />
            </g>
          )
        })}
      </svg>

      {/* Legend — only the profiles present in the selected schedule */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 12px', marginTop: 6 }}>
        {profiles.map(({ key, label }) => (
          <span
            key={key}
            onClick={() => dispatch({ type: SET_ACTIVE_DAY_TYPE, payload: key })}
            style={{ display: 'flex', alignItems: 'center', gap: 3, fontSize: 11, cursor: 'pointer' }}
          >
            <span style={{ width: 10, height: 10, background: colorMap[key] || EMPTY_COLOR, borderRadius: 2, display: 'inline-block' }} />
            {label}
          </span>
        ))}
      </div>
    </div>
  )
}
