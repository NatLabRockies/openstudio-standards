import React, { createContext, useContext, useReducer } from 'react'

// Action types
export const SET_RAW_DATA = 'SET_RAW_DATA'
export const SET_LOADING = 'SET_LOADING'
export const SET_ERROR = 'SET_ERROR'
export const SET_SELECTED_SPACE_TYPE = 'SET_SELECTED_SPACE_TYPE'
export const SET_SELECTED_SCHEDULE_NAMES = 'SET_SELECTED_SCHEDULE_NAMES'
export const SET_ACTIVE_DAY_TYPE = 'SET_ACTIVE_DAY_TYPE'
export const SET_SELECTED_DATE = 'SET_SELECTED_DATE'
export const SET_DAY_ASSIGNMENTS = 'SET_DAY_ASSIGNMENTS'
export const SET_STANDARD_PROFILES = 'SET_STANDARD_PROFILES'
export const SET_STANDARD_REFERENCE_OVERRIDE = 'SET_STANDARD_REFERENCE_OVERRIDE'
export const SET_EXPANDED_PROFILE = 'SET_EXPANDED_PROFILE'
export const SET_EXPANDED_PROFILE_ERROR = 'SET_EXPANDED_PROFILE_ERROR'
export const SET_WORKING_COPY = 'SET_WORKING_COPY'
export const SET_EDITOR_PARAMS = 'SET_EDITOR_PARAMS'
export const SET_PROFILE_META_EDIT = 'SET_PROFILE_META_EDIT'
export const SET_ASHRAE_SPACE_TYPE_REF = 'SET_ASHRAE_SPACE_TYPE_REF'

const initialState = {
  loading: true,
  error: null,

  rawData: {
    spaceTypes: [],
    scheduleSets: [],
    parametricSchedules: [],
    lightingParams: [],
    elecEquipParams: [],
    gasEquipParams: [],
    hotWaterParams: [],
    ashraeSchedules: [],
    cbesSchedules: [],
    deerSchedules: [],
  },

  selectedSpaceType: null,
  selectedScheduleNames: [],
  activeDayType: 'Default',

  calendarYear: new Date().getFullYear(),
  selectedDate: null,

  // Map<scheduleName, Map<'YYYY-MM-DD', dayTypeKey>>
  dayAssignments: {},

  // Map<'scheduleName|dayType', [time, value][]>
  standardProfiles: {},

  // Map<parametricScheduleName, ashraeScheduleName>
  standardReferenceOverrides: {},

  // { template: string, spaceTypeKey: string }
  ashraeSpaceTypeRef: { template: '90.1-2013', spaceTypeKey: '' },

  // Map<'scheduleName|dayType|paramsHash', [time, value][]>
  expandedProfiles: {},

  // Map<'scheduleName|dayType', { message }>
  expandedProfileErrors: {},

  // Map<target, Array<object>>
  workingCopies: {},

  editorParams: {
    timestepsPerHour: 4,
    // Map<'scheduleName|dayType', paramObject>
    byProfile: {},
  },

  // Map<'scheduleName|dayType', { dayType, startDate, endDate }>
  profileMetaEdits: {},
}

function reducer(state, action) {
  switch (action.type) {
    case SET_LOADING:
      return { ...state, loading: action.payload }

    case SET_ERROR:
      return { ...state, loading: false, error: action.payload }

    case SET_RAW_DATA:
      return { ...state, loading: false, error: null, rawData: action.payload }

    case SET_SELECTED_SPACE_TYPE:
      return { ...state, selectedSpaceType: action.payload }

    case SET_SELECTED_SCHEDULE_NAMES:
      return { ...state, selectedScheduleNames: action.payload, activeDayType: 'Default', selectedDate: null }

    case SET_ACTIVE_DAY_TYPE:
      return { ...state, activeDayType: action.payload }

    case SET_SELECTED_DATE:
      return { ...state, selectedDate: action.payload }

    case SET_DAY_ASSIGNMENTS:
      return { ...state, dayAssignments: { ...state.dayAssignments, ...action.payload } }

    case SET_STANDARD_PROFILES:
      return { ...state, standardProfiles: { ...state.standardProfiles, ...action.payload } }

    case SET_STANDARD_REFERENCE_OVERRIDE:
      return {
        ...state,
        standardReferenceOverrides: {
          ...state.standardReferenceOverrides,
          [action.payload.scheduleName]: action.payload.ashraeScheduleName
        }
      }

    case SET_EXPANDED_PROFILE:
      return {
        ...state,
        expandedProfiles: { ...state.expandedProfiles, [action.payload.key]: action.payload.pairs },
        expandedProfileErrors: { ...state.expandedProfileErrors, [action.payload.profileKey]: null }
      }

    case SET_EXPANDED_PROFILE_ERROR:
      return {
        ...state,
        expandedProfileErrors: {
          ...state.expandedProfileErrors,
          [action.payload.profileKey]: { message: action.payload.message }
        }
      }

    case SET_WORKING_COPY: {
      const { target, data } = action.payload
      if (data === null) {
        const next = { ...state.workingCopies }
        delete next[target]
        return { ...state, workingCopies: next }
      }
      return { ...state, workingCopies: { ...state.workingCopies, [target]: data } }
    }

    case SET_EDITOR_PARAMS: {
      const { scheduleName, dayType, params } = action.payload
      if (scheduleName && dayType) {
        const key = `${scheduleName}|${dayType}`
        return {
          ...state,
          editorParams: {
            ...state.editorParams,
            byProfile: { ...state.editorParams.byProfile, [key]: params }
          }
        }
      }
      // global params (e.g. timestepsPerHour)
      return { ...state, editorParams: { ...state.editorParams, ...params } }
    }

    case SET_PROFILE_META_EDIT: {
      const key = action.payload.key
      return {
        ...state,
        profileMetaEdits: { ...state.profileMetaEdits, [key]: action.payload.meta }
      }
    }

    case SET_ASHRAE_SPACE_TYPE_REF:
      return { ...state, ashraeSpaceTypeRef: action.payload }

    default:
      return state
  }
}

const AppContext = createContext(null)
const AppDispatchContext = createContext(null)

export function AppProvider({ children }) {
  const [state, dispatch] = useReducer(reducer, initialState)
  return (
    <AppContext.Provider value={state}>
      <AppDispatchContext.Provider value={dispatch}>
        {children}
      </AppDispatchContext.Provider>
    </AppContext.Provider>
  )
}

export function useAppState() {
  return useContext(AppContext)
}

export function useAppDispatch() {
  return useContext(AppDispatchContext)
}
