import { RoleBadge } from '../components/RoleBadge'
import { StatusMessage } from '../components/StatusMessage'
import type { CurrentMembershipState } from '../hooks/useTenantSelection'
import type { Me } from '../types/api'

interface WorkspacePageProps {
  me: Me
  current: CurrentMembershipState
  onSwitchOrganization: () => void
  onRetry: () => void
  onSignOut: () => void
}

/** Shell shown once an organization is confirmed by the API. */
export function WorkspacePage({ me, current, onSwitchOrganization, onRetry, onSignOut }: WorkspacePageProps) {
  return (
    <div className="app-layout">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">LI</span>
          <span className="brand__name">Lease Intelligence</span>
        </div>
        {current.status === 'ready' && (
          <div className="topbar__org">
            <span className="topbar__org-name">{current.membership.tenant.name}</span>
            <RoleBadge role={current.membership.role} />
          </div>
        )}
        <div className="topbar__actions">
          {me.memberships.length > 1 && (
            <button type="button" className="button button--secondary" onClick={onSwitchOrganization}>
              Trocar organização
            </button>
          )}
          <span className="muted">{me.user.full_name}</span>
          <button type="button" className="button button--link" onClick={onSignOut}>
            Sair
          </button>
        </div>
      </header>

      <main className="content">
        {current.status === 'loading' || current.status === 'none' ? (
          <StatusMessage kind="loading" title="Carregando organização…" />
        ) : current.status === 'error' ? (
          <StatusMessage kind="error" title="Não foi possível carregar a organização." description={current.message} onRetry={onRetry} />
        ) : (
          <StatusMessage
            kind="empty"
            title={`Bem-vindo à ${current.membership.tenant.name}`}
            description="Os módulos de imóveis, contratos e documentos serão adicionados nas próximas fases."
          />
        )}
      </main>
    </div>
  )
}
