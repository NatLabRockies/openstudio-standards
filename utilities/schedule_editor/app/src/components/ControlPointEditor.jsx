import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react'
import { useAppState, useAppDispatch, SET_EDITOR_PARAMS } from '../context.jsx'
import { findRecord, patchParametricRecord } from '../utils/workingCopy.js'
import {
  evalControlPoint, encodePoint, parseExpr, buildExpr,
} from '../utils/controlPointCodec.js'

// Plot geometry (SVG user units)
const W = 600, H = 320, PAD_L = 36, PAD_R = 14, PAD_T = 14, PAD_B = 26
const PLOT_W = W - PAD_L - PAD_R
const PLOT_H = H - PAD_T - PAD_B
const yOf = (v) => PAD_T + (1 - v) * PLOT_H
const vOf = (py) => 1 - (py - PAD_T) / PLOT_H

// The control-point editor pins the chart to STANDARD coordinates so a drag maps
// deterministically back into the relative [timeExpr, valExpr] grammar. Edits are
// applied live to the parametric_schedules working copy.
export default function ControlPointEditor({ scheduleName, dayType, category, onClose }) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const tph = state.editorParams.timestepsPerHour || 4

  const record = useMemo(() => findRecord(state, scheduleName, dayType), [state, scheduleName, dayType])
  // Modal owns the control_points during its lifetime; seed once from the record.
  const [cps, setCps] = useState(() => (record ? record.control_points.map(p => [...p]) : []))
  const [selected, setSelected] = useState(null)
  const [dragIdx, setDragIdx] = useState(null)
  const [anchorDrag, setAnchorDrag] = useState(null)   // 'st' | 'et' | null (drag gate)
  const [anchorValue, setAnchorValue] = useState(null) // live dragged anchor value
  const anchorSnap = useRef(null)
  const svgRef = useRef(null)

  // Effective record: overlays the live-dragged st_std/et_std so the chart, markers, and
  // reference lines all follow an in-progress anchor drag before it is committed.
  const effRecord = useMemo(() => {
    if (!record) return null
    return {
      ...record,
      st_std: anchorDrag === 'st' ? anchorValue : record.st_std,
      et_std: anchorDrag === 'et' ? anchorValue : record.et_std,
    }
  }, [record, anchorDrag, anchorValue])

  // Persist the current control points (and any record-field changes) to the working copy.
  const persist = useCallback((next, extra = {}) => {
    patchParametricRecord(state, dispatch, scheduleName, dayType, { control_points: next, ...extra })
  }, [state, dispatch, scheduleName, dayType])

  const markers = useMemo(
    () => (effRecord ? cps.map((cp, i) => ({ i, expr: cp, pt: evalControlPoint(cp, effRecord, tph) })) : []),
    [cps, effRecord, tph]
  )

  // Adaptive x-domain: residential schedules wrap past 24h (et_std up to 32), so the
  // axis extends to fit the active window and any next-/prev-day anchors. During an anchor
  // drag the domain is frozen (with headroom captured at drag start) so the axis does not
  // rescale under the cursor as the guide line moves.
  const [xMin, xMax] = useMemo(() => {
    if (anchorDrag && anchorSnap.current) return anchorSnap.current.domain
    let lo = 0, hi = 24
    const ts = [effRecord?.st_std ?? 0, effRecord?.et_std ?? 24, ...markers.map(m => m.pt[0])]
    ts.forEach(t => { if (t < lo) lo = t; if (t > hi) hi = t })
    lo = Math.floor(lo / 4) * 4
    hi = Math.ceil(hi / 4) * 4
    return [lo, hi]
  }, [effRecord, markers, anchorDrag])

  const xOf = useCallback((t) => PAD_L + ((t - xMin) / (xMax - xMin)) * PLOT_W, [xMin, xMax])
  const tOf = useCallback((px) => xMin + ((px - PAD_L) / PLOT_W) * (xMax - xMin), [xMin, xMax])

  // --- point drag ----------------------------------------------------------
  const pointerToData = useCallback((evt) => {
    const rect = svgRef.current.getBoundingClientRect()
    const px = ((evt.clientX - rect.left) / rect.width) * W
    const py = ((evt.clientY - rect.top) / rect.height) * H
    let t = tOf(px), v = vOf(py)
    t = Math.max(xMin, Math.min(xMax, t))
    v = Math.max(0, Math.min(1, v))
    return { t, v }
  }, [tOf, xMin, xMax])

  useEffect(() => {
    if (dragIdx == null) return
    function onMove(evt) {
      const { t, v } = pointerToData(evt)
      setCps(prev => {
        const next = prev.map(p => [...p])
        next[dragIdx] = encodePoint(t, v, effRecord)
        return next
      })
    }
    function onUp() {
      setDragIdx(null)
      setCps(prev => { persist(prev); return prev })
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    return () => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
  }, [dragIdx, effRecord, persist, pointerToData])

  // --- anchor (st_std / et_std) drag --------------------------------------
  // Dragging an anchor moves its reference line to a new whole-hour value while keeping
  // every control point at the same absolute hour: points anchored to the dragged anchor
  // get their time offset recomputed (new_offset = round(abs_time - new_anchor)); points
  // on the other anchor are untouched. On release the new st_std/et_std is written to the
  // record and propagated to the right-pane start/end-time sliders.
  function startAnchorDrag(which, e) {
    if (!effRecord) return
    e.preventDefault()
    e.stopPropagation()
    const value = which === 'st' ? effRecord.st_std : effRecord.et_std
    anchorSnap.current = {
      which,
      // headroom so the guide line can be dragged a few hours beyond the current extent
      domain: [xMin, xMax + 8],
      absTimes: cps.map(cp => evalControlPoint(cp, effRecord, tph)[0]),
      exprs: cps.map(cp => [...cp]),
      isDragAnchor: cps.map(cp => parseExpr(cp[0]).anchor === which),
      value,
    }
    setAnchorValue(value)
    setAnchorDrag(which)
  }

  useEffect(() => {
    if (anchorDrag == null) return
    function onMove(evt) {
      const snap = anchorSnap.current
      const [dMin, dMax] = snap.domain
      const rect = svgRef.current.getBoundingClientRect()
      const px = ((evt.clientX - rect.left) / rect.width) * W
      let t = dMin + ((px - PAD_L) / PLOT_W) * (dMax - dMin)
      t = Math.round(t)                          // whole-hour snap keeps offsets integral
      t = Math.max(dMin, Math.min(dMax, t))
      snap.value = t
      const next = snap.exprs.map((cp, i) => {
        if (!snap.isDragAnchor[i]) return [...cp]
        const offset = Math.round(snap.absTimes[i] - t)
        const timeExpr = offset === 0 ? snap.which : `${snap.which}${offset > 0 ? '+' : '-'}${Math.abs(offset)}`
        return [timeExpr, cp[1]]
      })
      setCps(next)
      setAnchorValue(t)
    }
    function onUp() {
      const snap = anchorSnap.current
      const field = snap.which === 'st' ? 'st_std' : 'et_std'
      setCps(prev => {
        patchParametricRecord(state, dispatch, scheduleName, dayType, { [field]: snap.value, control_points: prev })
        return prev
      })
      // propagate the new standard time to the right-pane slider (its working value + reference mark)
      const key = `${scheduleName}|${dayType}`
      const existing = state.editorParams.byProfile[key] || {}
      dispatch({ type: SET_EDITOR_PARAMS, payload: { scheduleName, dayType, params: { ...existing, [snap.which]: snap.value } } })
      setAnchorDrag(null)
      setAnchorValue(null)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    return () => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
  }, [anchorDrag, state, dispatch, scheduleName, dayType])

  if (!record) return null

  function addPoint() {
    const t = (effRecord.st_std + effRecord.et_std) / 2
    const v = (effRecord.base_std + effRecord.peak_std) / 2
    const next = [...cps.map(p => [...p]), encodePoint(t, v, effRecord)]
    setCps(next); setSelected(next.length - 1); persist(next)
  }

  function deletePoint(i) {
    if (cps.length <= 2) return
    const next = cps.filter((_, idx) => idx !== i).map(p => [...p])
    setCps(next); setSelected(null); persist(next)
  }

  // Background double-click to add a point at the clicked location.
  function onPlotDblClick(evt) {
    const { t, v } = pointerToData(evt)
    const next = [...cps.map(p => [...p]), encodePoint(t, v, effRecord)]
    setCps(next); setSelected(next.length - 1); persist(next)
  }

  function updateExprPart(i, which, part, value) {
    const next = cps.map(p => [...p])
    const parsed = parseExpr(next[i][which === 'time' ? 0 : 1])
    parsed[part] = value
    next[i][which === 'time' ? 0 : 1] = buildExpr(parsed)
    setCps(next); persist(next)
  }

  // Control polygon: anchors connected in time order (aligns exactly with markers,
  // including next-/prev-day wrap positions).
  const polygonPath = useMemo(() => {
    const sorted = [...markers].sort((a, b) => a.pt[0] - b.pt[0])
    return sorted.map((m, i) => `${i === 0 ? 'M' : 'L'}${xOf(m.pt[0]).toFixed(1)},${yOf(m.pt[1]).toFixed(1)}`).join(' ')
  }, [markers, xOf])

  const xticks = []
  for (let t = xMin; t <= xMax; t += 4) xticks.push(t)
  const yticks = [0, 0.25, 0.5, 0.75, 1]

  const overlay = { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1100 }
  const modal = { background: '#fff', borderRadius: 8, padding: 20, width: 680, maxWidth: '94vw', maxHeight: '90vh', overflow: 'auto', boxShadow: '0 4px 24px rgba(0,0,0,0.25)' }

  const ANCHORS_T = ['st', 'et']
  const ANCHORS_V = ['base', 'peak']
  const OPS = ['', '+', '-', '*']

  return (
    <div style={overlay} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={modal}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: 15 }}>Edit control points — {scheduleName} <span style={{ color: '#888', fontWeight: 400 }}>· {dayType}</span></h3>
          <button onClick={onClose} style={{ border: 'none', background: 'transparent', fontSize: 18, cursor: 'pointer', color: '#888' }}>✕</button>
        </div>
        <div style={{ fontSize: 11, color: '#777', marginBottom: 8 }}>
          Pinned to standard coordinates (st_std {effRecord.st_std}h, et_std {effRecord.et_std}h, base_std {effRecord.base_std}, peak_std {effRecord.peak_std}).
          Drag a point to move it · double-click the plot to add · drag the <b>st</b>/<b>et</b> guide lines to change st_std/et_std (points hold their hour; sliders update).
        </div>

        <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', border: '1px solid #eee', borderRadius: 4, background: '#fafafa', userSelect: 'none' }}
          onDoubleClick={onPlotDblClick}>
          {/* gridlines + axes */}
          {yticks.map(v => (
            <g key={`y${v}`}>
              <line x1={PAD_L} y1={yOf(v)} x2={W - PAD_R} y2={yOf(v)} stroke="#eee" />
              <text x={PAD_L - 5} y={yOf(v) + 3} fontSize="9" textAnchor="end" fill="#999">{v}</text>
            </g>
          ))}
          {xticks.map(t => (
            <g key={`x${t}`}>
              <line x1={xOf(t)} y1={PAD_T} x2={xOf(t)} y2={H - PAD_B} stroke="#eee" />
              <text x={xOf(t)} y={H - PAD_B + 14} fontSize="9" textAnchor="middle" fill="#999">{t}:00</text>
            </g>
          ))}
          {/* st / et reference lines (draggable) */}
          {[['st', effRecord.st_std], ['et', effRecord.et_std]].map(([lbl, t]) => {
            const active = anchorDrag === lbl
            return (
              <g key={lbl} style={{ cursor: 'ew-resize' }} onMouseDown={(e) => startAnchorDrag(lbl, e)}>
                {/* wide transparent hit area for easy grabbing */}
                <line x1={xOf(t)} y1={PAD_T} x2={xOf(t)} y2={H - PAD_B} stroke="transparent" strokeWidth="12" />
                <line x1={xOf(t)} y1={PAD_T} x2={xOf(t)} y2={H - PAD_B}
                  stroke={active ? '#2980b9' : '#bbb'} strokeWidth={active ? 2 : 1} strokeDasharray="4 3" />
                <rect x={xOf(t) - 4} y={PAD_T - 2} width="8" height="6" rx="1" fill={active ? '#2980b9' : '#bbb'} />
                <text x={xOf(t) + 3} y={PAD_T + 10} fontSize="9" fill={active ? '#2980b9' : '#999'}>{lbl}_std {t}h</text>
              </g>
            )
          })}
          {/* control polygon (anchors connected in time order) */}
          {polygonPath && <path d={polygonPath} fill="none" stroke="#e74c3c" strokeWidth="2" />}
          {/* markers */}
          {markers.map(({ i, pt }) => (
            <circle
              key={i}
              cx={xOf(pt[0])} cy={yOf(pt[1])} r={selected === i ? 7 : 5}
              fill={selected === i ? '#2980b9' : '#fff'} stroke="#2980b9" strokeWidth="2"
              style={{ cursor: 'grab' }}
              onMouseDown={(e) => { e.preventDefault(); setSelected(i); setDragIdx(i) }}
            />
          ))}
        </svg>

        <div style={{ display: 'flex', gap: 8, margin: '10px 0' }}>
          <button onClick={addPoint} style={{ fontSize: 12, padding: '4px 10px', border: '1px solid #2980b9', background: '#fff', color: '#2980b9', borderRadius: 4, cursor: 'pointer' }}>＋ Add point</button>
          <button onClick={() => selected != null && deletePoint(selected)} disabled={selected == null || cps.length <= 2}
            style={{ fontSize: 12, padding: '4px 10px', border: '1px solid #e74c3c', background: '#fff', color: '#e74c3c', borderRadius: 4, cursor: selected == null ? 'not-allowed' : 'pointer', opacity: selected == null ? 0.5 : 1 }}>🗑 Delete selected</button>
        </div>

        {/* per-point table */}
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
          <thead>
            <tr style={{ textAlign: 'left', color: '#666' }}>
              <th style={{ padding: 4 }}>#</th>
              <th style={{ padding: 4 }}>time</th>
              <th style={{ padding: 4 }}>value</th>
              <th style={{ padding: 4 }}>→ (h, val)</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {markers.map(({ i, pt }) => {
              const tp = parseExpr(cps[i][0])
              const vp = parseExpr(cps[i][1])
              const cell = { padding: '2px 4px' }
              const sel = { fontSize: 11, padding: '1px 2px' }
              const numIn = { width: 44, fontSize: 11, padding: '1px 3px' }
              return (
                <tr key={i} style={{ background: selected === i ? '#eaf3fb' : 'transparent', cursor: 'pointer' }}
                  onClick={() => setSelected(i)}>
                  <td style={cell}>{i + 1}</td>
                  <td style={cell}>
                    <select style={sel} value={tp.anchor} onChange={e => updateExprPart(i, 'time', 'anchor', e.target.value)}>
                      {ANCHORS_T.map(a => <option key={a}>{a}</option>)}
                    </select>
                    <select style={sel} value={tp.op} onChange={e => updateExprPart(i, 'time', 'op', e.target.value)}>
                      {OPS.map(o => <option key={o} value={o}>{o || '·'}</option>)}
                    </select>
                    {tp.op && <input style={numIn} value={tp.num} onChange={e => updateExprPart(i, 'time', 'num', e.target.value)} />}
                  </td>
                  <td style={cell}>
                    <select style={sel} value={vp.anchor} onChange={e => updateExprPart(i, 'value', 'anchor', e.target.value)}>
                      {ANCHORS_V.map(a => <option key={a}>{a}</option>)}
                    </select>
                    <select style={sel} value={vp.op} onChange={e => updateExprPart(i, 'value', 'op', e.target.value)}>
                      {OPS.map(o => <option key={o} value={o}>{o || '·'}</option>)}
                    </select>
                    {vp.op && <input style={numIn} value={vp.num} onChange={e => updateExprPart(i, 'value', 'num', e.target.value)} />}
                  </td>
                  <td style={{ ...cell, color: '#999' }}>{pt[0]}h, {pt[1].toFixed(2)}</td>
                  <td style={cell}>
                    <button onClick={(e) => { e.stopPropagation(); deletePoint(i) }} disabled={cps.length <= 2}
                      style={{ border: 'none', background: 'transparent', color: '#e74c3c', cursor: cps.length <= 2 ? 'not-allowed' : 'pointer' }}>✕</button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 12 }}>
          <button onClick={onClose} style={{ padding: '6px 16px', fontSize: 13, background: '#2980b9', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer' }}>Done</button>
        </div>
      </div>
    </div>
  )
}
