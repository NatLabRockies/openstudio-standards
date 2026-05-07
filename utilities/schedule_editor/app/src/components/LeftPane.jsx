import React, { useState } from 'react'
import SpaceTypeTab from './SpaceTypeTab.jsx'
import ScheduleTab from './ScheduleTab.jsx'

const tabStyle = (active) => ({
  padding: '6px 14px', cursor: 'pointer', border: 'none', background: active ? '#0078d4' : '#eee',
  color: active ? '#fff' : '#333', borderRadius: '4px 4px 0 0', marginRight: 4
})

export default function LeftPane() {
  const [tab, setTab] = useState('spacetypes')
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '8px 8px 0' }}>
        <button style={tabStyle(tab === 'spacetypes')} onClick={() => setTab('spacetypes')}>Space Types</button>
        <button style={tabStyle(tab === 'schedules')} onClick={() => setTab('schedules')}>Schedules</button>
      </div>
      <div style={{ flex: 1, overflow: 'hidden' }}>
        {tab === 'spacetypes' ? <SpaceTypeTab /> : <ScheduleTab />}
      </div>
    </div>
  )
}
