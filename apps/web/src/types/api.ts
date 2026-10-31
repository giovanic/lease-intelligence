// JSON shapes returned by the Rails API (apps/api/app/serializers). Keep
// in sync with the serializers and the request specs that encode them.

export type MembershipRole = 'owner' | 'admin' | 'manager' | 'analyst' | 'viewer'

export interface User {
  id: string
  email: string
  full_name: string
}

export interface TenantSummary {
  id: string
  name: string
  slug: string
}

export interface Membership {
  id: string
  role: MembershipRole
  status: 'active' | 'suspended'
  tenant: TenantSummary
}

/** GET /api/v1/me and POST /api/v1/session */
export interface Me {
  user: User
  memberships: Membership[]
}

export interface ApiErrorBody {
  error: { code: string; message: string }
}
