import type { MembershipRole } from '../types/api'

const ROLE_LABELS: Record<MembershipRole, string> = {
  owner: 'Proprietário',
  admin: 'Administrador',
  manager: 'Gestor',
  analyst: 'Analista',
  viewer: 'Leitor',
}

/** Display only — authorization is always decided by the API. */
export function RoleBadge({ role }: { role: MembershipRole }) {
  return <span className={`badge badge--${role}`}>{ROLE_LABELS[role]}</span>
}
