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
 */
export function useApiQuery<T>(key: string, fetcher: () => Promise<T>) {
  const [attempt, setAttempt] = useState(0)
  // The answer for one specific (key, attempt); anything else is loading.
  const [settled, setSettled] = useState<{ key: string; state: Settled<T> } | null>(null)
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
        if (!cancelled) setSettled({ key: requestKey, state: { status: 'success', data } })
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
  }, [requestKey])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  const state: QueryState<T> = settled?.key === requestKey ? settled.state : { status: 'loading' }

  return { state, retry }
}
