import { useCallback, useEffect, useState } from 'react'
import { ApiError } from '../services/apiClient'
import * as sessionService from '../services/session'
import type { Me } from '../types/api'

export type SessionState =
  | { status: 'loading' }
  | { status: 'signedOut' }
  | { status: 'signedIn'; me: Me }
  | { status: 'error'; message: string }

/**
 * Who is signed in. The source of truth is the server session cookie:
 * on start the SPA asks GET /me; a 401 simply means "signed out".
 */
export function useSession() {
  const [state, setState] = useState<SessionState>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    void loadSession().then((next) => {
      if (!cancelled) setState(next)
    })
    return () => {
      cancelled = true
    }
  }, [])

  const retry = useCallback(() => {
    setState({ status: 'loading' })
    void loadSession().then(setState)
  }, [])

  /** Throws ApiError on failure so the login form can show the reason. */
  const signIn = useCallback(async (email: string, password: string) => {
    const me = await sessionService.signIn(email, password)
    setState({ status: 'signedIn', me })
  }, [])

  const signOut = useCallback(async () => {
    try {
      await sessionService.signOut()
    } finally {
      setState({ status: 'signedOut' })
    }
  }, [])

  return { state, signIn, signOut, retry }
}

async function loadSession(): Promise<SessionState> {
  try {
    return { status: 'signedIn', me: await sessionService.fetchMe() }
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return { status: 'signedOut' }
    return { status: 'error', message: messageFor(error) }
  }
}

function messageFor(error: unknown): string {
  return error instanceof Error ? error.message : 'Erro inesperado.'
}
