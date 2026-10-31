import type { LeasePartyRole, LeaseStatus } from '../../types/api'

export const LEASE_STATUS_LABELS: Record<LeaseStatus, string> = {
  draft: 'Rascunho',
  active: 'Vigente',
  expired: 'Encerrado (fim do prazo)',
  terminated: 'Rescindido',
}

export const LEASE_STATUSES = Object.keys(LEASE_STATUS_LABELS) as LeaseStatus[]

export const PARTY_ROLE_LABELS: Record<LeasePartyRole, string> = {
  lessor: 'Locador',
  guarantor: 'Fiador',
  intervening_party: 'Interveniente anuente',
}

export const PARTY_ROLES = Object.keys(PARTY_ROLE_LABELS) as LeasePartyRole[]
