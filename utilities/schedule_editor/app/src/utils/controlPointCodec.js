// Codec between absolute (timeHours, value) points and the symbolic control-point
// grammar used by default_parametric_schedules.json, e.g. ["st+2", "peak*0.87"].
//
// All editing happens in STANDARD coordinates (st_std / et_std / base_std /
// peak_std), where the evaluator's adjustment_multiplier is 1, so a control point's
// time offset is exactly (timeHours - anchor) in whole hours. The Ruby time grammar
// truncates offsets to integers (time_point[2].to_i), so time offsets snap to whole
// hours from st/et; values are fractional.

const PARSER = /([a-z]+)(?:([+\-*])(\d+(?:\.\d+)?))?/

function applyOp(val, op, num) {
  if (op === '+') return val + num
  if (op === '-') return val - num
  if (op === '*') return val * num
  return val
}

function fmtNum(n) {
  return parseFloat(n.toFixed(3)).toString()
}

// --- evaluation (symbolic -> absolute, std coords) — mirrors Ruby evaluate_schedule_control_points

export function evalTimeExpr(expr, record, tph = 4) {
  const m = PARSER.exec(expr || '') || []
  const anchor = m[1]
  let t = anchor === 'st' ? record.st_std : anchor === 'et' ? record.et_std : 0
  if (m[2] && m[3] != null) {
    const num = parseInt(m[3], 10) // Ruby uses .to_i for the time magnitude
    t = applyOp(t, m[2], num)      // adjustment_multiplier == 1 in std coords
  }
  return Math.round(t * tph) / tph
}

export function evalValueExpr(expr, record) {
  const m = PARSER.exec(expr || '') || []
  const anchor = m[1]
  let v = anchor === 'base' ? record.base_std : anchor === 'peak' ? record.peak_std : 0
  if (m[2] && m[3] != null) {
    v = applyOp(v, m[2], parseFloat(m[3])) // Ruby uses .to_f for the value magnitude
  }
  return Math.min(1, Math.max(0, v))
}

export function evalControlPoint(cp, record, tph = 4) {
  return [evalTimeExpr(cp[0], record, tph), evalValueExpr(cp[1], record)]
}

// --- encoding (absolute -> symbolic, std coords)

export function encodeTime(timeHours, record) {
  const dSt = Math.abs(timeHours - record.st_std)
  const dEt = Math.abs(timeHours - record.et_std)
  const anchor = dSt <= dEt ? 'st' : 'et'
  const anchorVal = anchor === 'st' ? record.st_std : record.et_std
  const offset = Math.round(timeHours - anchorVal) // integer hours
  if (offset === 0) return anchor
  return `${anchor}${offset > 0 ? '+' : '-'}${Math.abs(offset)}`
}

export function encodeValue(value, record) {
  const dBase = Math.abs(value - record.base_std)
  const dPeak = Math.abs(value - record.peak_std)
  const anchor = dBase <= dPeak ? 'base' : 'peak'
  const anchorVal = anchor === 'base' ? record.base_std : record.peak_std
  if (Math.abs(value - anchorVal) < 1e-6) return anchor
  if (Math.abs(anchorVal) > 1e-6) {
    return `${anchor}*${fmtNum(value / anchorVal)}` // multiplicative (matches seeded data)
  }
  const delta = value // anchor value is 0 -> additive
  return `${anchor}${delta >= 0 ? '+' : '-'}${fmtNum(Math.abs(delta))}`
}

export function encodePoint(timeHours, value, record) {
  return [encodeTime(timeHours, record), encodeValue(value, record)]
}

// Parse a symbolic expression into { anchor, op, num } for the per-point editor.
export function parseExpr(expr) {
  const m = PARSER.exec(expr || '') || []
  return { anchor: m[1] || '', op: m[2] || '', num: m[3] != null ? m[3] : '' }
}

export function buildExpr({ anchor, op, num }) {
  if (!op || num === '' || num == null) return anchor
  return `${anchor}${op}${num}`
}
