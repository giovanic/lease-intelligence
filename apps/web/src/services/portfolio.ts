import type { Counterparty, CounterpartyInput, Page, Property, PropertyInput } from '../types/api'
import { apiRequest, apiRequestPage } from './apiClient'

// /api/v1/properties and /api/v1/counterparties (docs/domain/portfolio.md).

export interface PropertyFilters {
  status?: string
  q?: string
  page?: number
  per_page?: number
}

export function listProperties(tenantId: string, filters: PropertyFilters = {}): Promise<Page<Property>> {
  return apiRequestPage<Property>('/properties', { tenantId, query: { ...filters } })
}

export function fetchProperty(tenantId: string, id: string): Promise<Property> {
  return apiRequest<Property>(`/properties/${encodeURIComponent(id)}`, { tenantId })
}

export function createProperty(tenantId: string, property: PropertyInput): Promise<Property> {
  return apiRequest<Property>('/properties', { method: 'POST', tenantId, body: { property } })
}

export function updateProperty(tenantId: string, id: string, property: Partial<PropertyInput>): Promise<Property> {
  return apiRequest<Property>(`/properties/${encodeURIComponent(id)}`, { method: 'PATCH', tenantId, body: { property } })
}

export interface CounterpartyFilters {
  status?: string
  kind?: string
  q?: string
  page?: number
  per_page?: number
}

export function listCounterparties(tenantId: string, filters: CounterpartyFilters = {}): Promise<Page<Counterparty>> {
  return apiRequestPage<Counterparty>('/counterparties', { tenantId, query: { ...filters } })
}

export function fetchCounterparty(tenantId: string, id: string): Promise<Counterparty> {
  return apiRequest<Counterparty>(`/counterparties/${encodeURIComponent(id)}`, { tenantId })
}

export function createCounterparty(tenantId: string, counterparty: CounterpartyInput): Promise<Counterparty> {
  return apiRequest<Counterparty>('/counterparties', { method: 'POST', tenantId, body: { counterparty } })
}

export function updateCounterparty(
  tenantId: string,
  id: string,
  counterparty: Partial<CounterpartyInput>,
): Promise<Counterparty> {
  return apiRequest<Counterparty>(`/counterparties/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    tenantId,
    body: { counterparty },
  })
}
