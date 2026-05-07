import React from 'react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  ReferenceLine
} from 'recharts'

const CATEGORY_COLORS = {
  Occupancy:        '#e74c3c',
  Lighting:         '#f1c40f',
  ElectricEquipment:'#2ecc71',
  GasEquipment:     '#e67e22',
  HotWater:         '#3498db',
}

function formatHour(h) {
  return `${h}:00`
}

// Build unified data array for Recharts: [{ h, standard, parametric }, ...]
// Standard data uses step-after semantics: its value is held until the next defined point.
// When parametric data has finer time resolution, we fill standard forward so it renders
// as a continuous step-after line rather than invisible nubs at integer-hour positions.
function buildChartData(standardData, expandedData) {
  // Collect all unique h values across both datasets
  const allHSet = new Set()
  if (standardData) standardData.forEach(({ h }) => allHSet.add(h))
  if (expandedData) expandedData.forEach(({ h }) => allHSet.add(h))
  const allH = Array.from(allHSet).sort((a, b) => a - b)

  // Build step-after lookup: for any h, find the last standard value at or before h
  const sortedStd = standardData ? [...standardData].sort((a, b) => a.h - b.h) : []
  function stepAfterValue(h) {
    let val = null
    for (const pt of sortedStd) {
      if (pt.h <= h) val = pt.v
      else break
    }
    return val
  }

  const map = {}
  allH.forEach(h => { map[h] = { h } })

  if (standardData) {
    allH.forEach(h => {
      const v = stepAfterValue(h)
      if (v !== null) map[h].standard = v
    })
  }

  if (expandedData) {
    expandedData.forEach(({ h, v }) => {
      map[h].parametric = v
    })
  }

  return allH.map(h => map[h])
}

export default function ProfileChart({ scheduleName, category, standardData, expandedData, hasError, errorMessage, isLoading, stTime, etTime }) {
  const color = CATEGORY_COLORS[category] || '#999'
  const data = buildChartData(standardData, expandedData)

  const xTicks = Array.from({ length: 13 }, (_, i) => i * 2)

  return (
    <div style={{
      marginBottom: 16,
      border: hasError ? '2px solid #e74c3c' : '1px solid #eee',
      borderRadius: 6, padding: 8, background: '#fafafa'
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
        <strong style={{ fontSize: 12, color: '#444' }}>{scheduleName} — {category}</strong>
        {isLoading && <span style={{ fontSize: 11, color: '#999' }}>Updating…</span>}
        {hasError && <span style={{ fontSize: 11, color: '#e74c3c' }}>⚠ {errorMessage}</span>}
      </div>
      <ResponsiveContainer width="100%" height={180}>
        <LineChart data={data} margin={{ top: 4, right: 8, bottom: 4, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
          <XAxis
            dataKey="h"
            type="number"
            domain={[0, 24]}
            ticks={xTicks}
            tickFormatter={formatHour}
            tick={{ fontSize: 10 }}
          />
          <YAxis domain={[0, 1]} tick={{ fontSize: 10 }} width={30} />
          <Tooltip formatter={(v) => v?.toFixed(3)} labelFormatter={formatHour} />
          <Legend wrapperStyle={{ fontSize: 11 }} />
          {standardData && (
            <Line
              dataKey="standard"
              name="Standard (ASHRAE)"
              stroke="#aaa"
              strokeWidth={1.5}
              dot={false}
              type="stepAfter"
              isAnimationActive={false}
            />
          )}
          {expandedData && (
            <Line
              dataKey="parametric"
              name="Parametric"
              stroke={color}
              strokeWidth={2}
              dot={false}
              type="linear"
              isAnimationActive={false}
            />
          )}
          {stTime != null && (
            <ReferenceLine
              x={stTime}
              stroke="#555"
              strokeDasharray="4 3"
              strokeWidth={1.5}
              label={{ value: 'st', position: 'top', fontSize: 9, fill: '#555' }}
            />
          )}
          {etTime != null && (
            <ReferenceLine
              x={etTime}
              stroke="#555"
              strokeDasharray="4 3"
              strokeWidth={1.5}
              label={{ value: 'et', position: 'top', fontSize: 9, fill: '#555' }}
            />
          )}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
