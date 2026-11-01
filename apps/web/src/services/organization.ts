import type { OrganizationSettings } from '../types/api'
import { apiRequest } from './apiClient'

// /api/v1/organization_settings — the current organization's settings,
// for now the consent for AI field extraction (docs/adr/0018).

export function getOrganizationSettings(tenantId: string): Promise<OrganizationSettings> {
  return apiRequest<OrganizationSettings>('/organization_settings', { tenantId })
}

/** Owner/admin only; 403 otherwise. */
export function updateAiExtractionConsent(tenantId: string, enabled: boolean): Promise<OrganizationSettings> {
  return apiRequest<OrganizationSettings>('/organization_settings', {
    method: 'PATCH',
    tenantId,
    body: { organization_settings: { ai_extraction_enabled: enabled } },
  })
}
