const BASE = '/api'

async function request(path, options = {}) {
  const res = await fetch(BASE + path, options)
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`)
  return json
}

export function fetchData() {
  return request('/data')
}

export function fetchSpaceTypes(template) {
  return request('/spc_typ/' + encodeURIComponent(template))
}

export function expandParametric(scheduleData, params) {
  return request('/expand_parametric', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ schedule_data: scheduleData, params })
  })
}

export function expandSlope(scheduleData, params) {
  return request('/expand_slope', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ schedule_data: scheduleData, params })
  })
}

export function evaluateControlPoints(scheduleData, params) {
  return request('/evaluate_control_points', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ schedule_data: scheduleData, params })
  })
}

export function derive(body) {
  return request('/derive', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  })
}

export function save(target, data) {
  return request('/save', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target, data })
  })
}
