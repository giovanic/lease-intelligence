import type { Me, Membership } from '../types/api'
import { apiRequest } from './apiClient'

export function signIn(email: string, password: string): Promise<Me> {
  return apiRequest<Me>('/session', { method: 'POST', body: { email, password } })
}

export function signOut(): Promise<void> {
  return apiRequest<void>('/session', { method: 'DELETE' })
}

export function fetchMe(): Promise<Me> {
  return apiRequest<Me>('/me')
}

/** Confirms the selected organization server-side and returns the caller's role in it. */
export function fetchCurrentMembership(tenantId: string): Promise<Membership> {
  return apiRequest<Membership>('/current_membership', { tenantId })
}
