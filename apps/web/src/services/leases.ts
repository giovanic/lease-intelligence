import type { Lease, LeaseInput, Page } from '../types/api'
import { apiRequest, apiRequestPage } from './apiClient'

// /api/v1/leases (docs/domain/leases.md).

export interface LeaseFilters {
  status?: string
  property_id?: string
  counterparty_id?: string
  q?: string
  page?: number
  per_page?: number
}

export function listLeases(tenantId: string, filters: LeaseFilters = {}): Promise<Page<Lease>> {
  return apiRequestPage<Lease>('/leases', { tenantId, query: { ...filters } })
}

export function fetchLease(tenantId: string, id: string): Promise<Lease> {
  return apiRequest<Lease>(`/leases/${encodeURIComponent(id)}`, { tenantId })
}

export function createLease(tenantId: string, lease: LeaseInput): Promise<Lease> {
  return apiRequest<Lease>('/leases', { method: 'POST', tenantId, body: { lease } })
}

export function updateLease(tenantId: string, id: string, lease: Partial<LeaseInput>): Promise<Lease> {
  return apiRequest<Lease>(`/leases/${encodeURIComponent(id)}`, { method: 'PATCH', tenantId, body: { lease } })
}
