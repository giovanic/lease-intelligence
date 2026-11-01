import { useCallback, useEffect, useState } from 'react'
import { ApiError } from '../services/apiClient'
import { fetchCurrentMembership } from '../services/session'
import type { Membership } from '../types/api'

// Per-tab (sessionStorage), so two tabs can work in two organizations.
// Only an id the backend re-validates on every request — not a secret.
const STORAGE_KEY = 'lease-intelligence.selectedTenantId'

export type CurrentMembershipState =
  | { status: 'none' }
  | { status: 'loading' }
  | { status: 'ready'; membership: Membership }
  | { status: 'error'; message: string }

type SettledState = Extract<CurrentMembershipState, { status: 'ready' | 'error' }>

/**
 * The organization the user is working in. Selecting one asks the API to
 * confirm it (GET /current_membership with X-Tenant-Id); the role shown
 * comes from that answer, never from local state.
 *
 * `retry` refetches through the loading state; `refresh` refetches in the
 * background (after the organization's settings changed): the last answer
 * for the same organization stays on screen meanwhile.
 */
export function useTenantSelection(enabled: boolean) {
  const [tenantId, setTenantId] = useState<string | null>(() => sessionStorage.getItem(STORAGE_KEY))
  const [attempt, setAttempt] = useState(0)
  const [silent, setSilent] = useState(false)
  const [lastReady, setLastReady] = useState<{ tenantId: string; membership: Membership } | null>(null)
  // The answer for one specific (tenant, attempt) request; anything else
  // is derived during render, so the effect only sets state asynchronously.
  const [settled, setSettled] = useState<{ key: string; state: SettledState } | null>(null)

  const requestKey = enabled && tenantId ? `${tenantId}:${attempt}` : null

  useEffect(() => {
    if (!requestKey || !tenantId) return

    let cancelled = false
    fetchCurrentMembership(tenantId)
      .then((membership) => {
        if (cancelled) return
        setSettled({ key: requestKey, state: { status: 'ready', membership } })
        setLastReady({ tenantId, membership })
      })
      .catch((error: unknown) => {
        if (cancelled) return
        if (error instanceof ApiError && error.status === 403) {
          // Access was removed (or the stored id is stale): back to the picker.
          sessionStorage.removeItem(STORAGE_KEY)
          setTenantId(null)
        } else {
          const message = error instanceof Error ? error.message : 'Erro inesperado.'
          setSettled({ key: requestKey, state: { status: 'error', message } })
        }
      })

    return () => {
      cancelled = true
    }
  }, [requestKey, tenantId])

  let current: CurrentMembershipState
  if (!requestKey) current = { status: 'none' }
  else if (settled?.key === requestKey) current = settled.state
  else if (silent && lastReady?.tenantId === tenantId) current = { status: 'ready', membership: lastReady.membership }
  else current = { status: 'loading' }

  const select = useCallback((id: string) => {
    sessionStorage.setItem(STORAGE_KEY, id)
    setTenantId(id)
  }, [])

  const clear = useCallback(() => {
    sessionStorage.removeItem(STORAGE_KEY)
    setTenantId(null)
  }, [])

  const retry = useCallback(() => {
    setSilent(false)
    setAttempt((n) => n + 1)
  }, [])
  const refresh = useCallback(() => {
    setSilent(true)
    setAttempt((n) => n + 1)
  }, [])

  return { tenantId, current, select, clear, retry, refresh }
}
