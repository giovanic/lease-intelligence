import { useCallback, useEffect, useRef, useState } from 'react'
import { ApiError } from '../services/apiClient'

export type QueryState<T> =
  | { status: 'loading' }
  | { status: 'error'; message: string; notFound: boolean }
  | { status: 'success'; data: T }

type Settled<T> = Exclude<QueryState<T>, { status: 'loading' }>

/**
 * Runs `fetcher` (a services/ call) whenever `key` changes and exposes
 * loading / error / success explicitly (.claude/rules/frontend.md). `key`
 * must change whenever the request changes — include every id and
 * filter. No caching between screens (docs/adr/0014).
 *
 * `retry` refetches through the loading state. `refresh` refetches in the
 * background, for polling: the last data of the same `key` stays on screen
 * while it runs, and also if it fails (the next refresh tries again).
 */
export function useApiQuery<T>(key: string, fetcher: () => Promise<T>) {
  const [attempt, setAttempt] = useState(0)
  const [silent, setSilent] = useState(false)
  // The answer for one specific (key, attempt); anything else is loading.
  const [settled, setSettled] = useState<{ key: string; state: Settled<T> } | null>(null)
  const [lastData, setLastData] = useState<{ key: string; data: T } | null>(null)
  const fetcherRef = useRef(fetcher)
  const requestKey = `${key}#${attempt}`

  useEffect(() => {
    fetcherRef.current = fetcher
  })

  useEffect(() => {
    let cancelled = false
    fetcherRef
      .current()
      .then((data) => {
        if (cancelled) return
        setSettled({ key: requestKey, state: { status: 'success', data } })
        setLastData({ key, data })
      })
      .catch((error: unknown) => {
        if (cancelled) return
        const notFound = error instanceof ApiError && error.status === 404
        const message = error instanceof Error ? error.message : 'Erro inesperado.'
        setSettled({ key: requestKey, state: { status: 'error', message, notFound } })
      })

    return () => {
      cancelled = true
    }
  }, [key, requestKey])

  const retry = useCallback(() => {
    setSilent(false)
    setAttempt((n) => n + 1)
  }, [])
  const refresh = useCallback(() => {
    setSilent(true)
    setAttempt((n) => n + 1)
  }, [])

  const current = settled?.key === requestKey ? settled.state : null
  const kept = silent && lastData?.key === key ? lastData : null
  let state: QueryState<T>
  if (current && !(current.status === 'error' && kept)) state = current
  else if (kept) state = { status: 'success', data: kept.data }
  else state = { status: 'loading' }

  return { state, retry, refresh }
}
