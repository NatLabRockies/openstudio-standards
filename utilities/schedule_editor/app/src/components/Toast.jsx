import React, { useState, useImperativeHandle, forwardRef } from 'react'

const Toast = forwardRef(function Toast(_, ref) {
  const [messages, setMessages] = useState([])

  useImperativeHandle(ref, () => ({
    show(message, duration = 3000) {
      const id = Date.now()
      setMessages(ms => [...ms, { id, message }])
      setTimeout(() => {
        setMessages(ms => ms.filter(m => m.id !== id))
      }, duration)
    }
  }))

  return (
    <div style={{
      position: 'fixed', bottom: 24, right: 24, zIndex: 2000,
      display: 'flex', flexDirection: 'column', gap: 8, pointerEvents: 'none'
    }}>
      {messages.map(({ id, message }) => (
        <div key={id} style={{
          background: '#333', color: '#fff', padding: '10px 16px',
          borderRadius: 6, fontSize: 13, boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
          pointerEvents: 'auto'
        }}>
          {message}
        </div>
      ))}
    </div>
  )
})

export default Toast
