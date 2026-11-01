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
  /** UX only — mirrors OrganizationSettingsPolicy::MANAGER_ROLES (docs/adr/0018). */
  canManageOrganization: boolean
  /** Whether the organization turned AI field extraction on (docs/adr/0018). */
  aiExtractionEnabled: boolean
  /** Re-reads the membership in the background, e.g. after the organization's settings changed. */
  refreshMembership: () => void
}

const EDITOR_ROLES: MembershipRole[] = ['owner', 'admin', 'manager']
const MANAGER_ROLES: MembershipRole[] = ['owner', 'admin']

export function workspaceFor(membership: Membership, refreshMembership: () => void): Workspace {
  return {
    tenantId: membership.tenant.id,
    membership,
    canEdit: EDITOR_ROLES.includes(membership.role),
    canManageOrganization: MANAGER_ROLES.includes(membership.role),
    aiExtractionEnabled: membership.tenant.ai_extraction_enabled,
    refreshMembership,
  }
}

export const WorkspaceContext = createContext<Workspace | null>(null)

export function useWorkspace(): Workspace {
  const workspace = useContext(WorkspaceContext)
  if (!workspace) throw new Error('useWorkspace must be used inside WorkspaceLayout')
  return workspace
}
