import React from 'react'
import SpaceTypeTree from './SpaceTypeTree.jsx'
import ScheduleActionBar from './ScheduleActionBar.jsx'

export default function SpaceTypeTab() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ flex: 1, overflow: 'auto', padding: 8 }}>
        <SpaceTypeTree />
      </div>
      <div style={{ borderTop: '1px solid #ddd', padding: 8 }}>
        <ScheduleActionBar />
      </div>
    </div>
  )
}
