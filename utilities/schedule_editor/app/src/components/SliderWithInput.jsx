import React from 'react'

export default function SliderWithInput({ label, value, min, max, step, stdValue, onChange, formatValue }) {
  const fmt = formatValue || (v => v)

  function handleSlider(e) {
    onChange(parseFloat(e.target.value))
  }

  function handleInput(e) {
    const v = parseFloat(e.target.value)
    if (!isNaN(v) && v >= min && v <= max) onChange(v)
  }

  // Position of the std mark as a percentage
  const stdPct = stdValue != null ? ((stdValue - min) / (max - min)) * 100 : null

  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 2 }}>
        <label style={{ fontSize: 12, color: '#555' }}>{label}</label>
        <input
          type="number"
          value={value}
          min={min} max={max} step={step}
          onChange={handleInput}
          style={{ width: 60, padding: '2px 4px', fontSize: 12, border: '1px solid #ccc', borderRadius: 3 }}
        />
      </div>
      <div style={{ position: 'relative' }}>
        <input
          type="range" min={min} max={max} step={step}
          value={value}
          onChange={handleSlider}
          style={{ width: '100%' }}
        />
        {stdPct != null && (
          <div
            title={`Default: ${fmt(stdValue)}`}
            style={{
              position: 'absolute', top: 0, left: `${stdPct}%`,
              transform: 'translateX(-50%)',
              width: 3, height: '100%',
              background: 'rgba(0,0,0,0.25)', pointerEvents: 'none', borderRadius: 2
            }}
          />
        )}
      </div>
      {stdPct != null && (
        <div style={{ fontSize: 10, color: '#999', textAlign: 'right' }}>
          default: {fmt(stdValue)}
        </div>
      )}
    </div>
  )
}
