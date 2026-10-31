import { createContext, useContext } from 'react'
import type { Membership, MembershipRole } from '../types/api'

/**
 * The organization the routed screens work in, as confirmed by
 * GET /current_membership (useTenantSelection). Provided by
 * WorkspaceLayout; only exists once that confirmation arrived.
 */
export interface Workspace {
  tenantId: string
  membership: Membership
  /**
   * UX only — hides create/edit actions the API would refuse anyway
   * (ADR-0005). Mirrors TenantOwnedPolicy::EDITOR_ROLES.
   */
  canEdit: boolean
}

const EDITOR_ROLES: MembershipRole[] = ['owner', 'admin', 'manager']

export function workspaceFor(membership: Membership): Workspace {
  return { tenantId: membership.tenant.id, membership, canEdit: EDITOR_ROLES.includes(membership.role) }
}

export const WorkspaceContext = createContext<Workspace | null>(null)

export function useWorkspace(): Workspace {
  const workspace = useContext(WorkspaceContext)
  if (!workspace) throw new Error('useWorkspace must be used inside WorkspaceLayout')
  return workspace
}
