import { NavLink, Outlet } from 'react-router'
import { RoleBadge } from '../components/RoleBadge'
import { StatusMessage } from '../components/StatusMessage'
import type { CurrentMembershipState } from '../hooks/useTenantSelection'
import { WorkspaceContext, workspaceFor } from '../state/workspace'
import type { Me } from '../types/api'

interface WorkspaceLayoutProps {
  me: Me
  current: CurrentMembershipState
  onSwitchOrganization: () => void
  onRetry: () => void
  onRefresh: () => void
  onSignOut: () => void
}

const NAV_ITEMS = [
  { to: '/leases', label: 'Contratos' },
  { to: '/properties', label: 'Imóveis' },
  { to: '/counterparties', label: 'Locadores e partes' },
  { to: '/settings', label: 'Configurações' },
]

/**
 * Shell of every routed screen. The screens (Outlet) only render once the
 * API confirmed the organization; they read it from WorkspaceContext.
 */
export function WorkspaceLayout({
  me,
  current,
  onSwitchOrganization,
  onRetry,
  onRefresh,
  onSignOut,
}: WorkspaceLayoutProps) {
  return (
    <div className="app-layout">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">
            LI
          </span>
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

      <div className="workspace">
        <nav className="sidebar" aria-label="Módulos">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (isActive ? 'sidebar__link sidebar__link--active' : 'sidebar__link')}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>

        <main className="workspace__content">
          {current.status === 'loading' || current.status === 'none' ? (
            <StatusMessage kind="loading" title="Carregando organização…" />
          ) : current.status === 'error' ? (
            <StatusMessage
              kind="error"
              title="Não foi possível carregar a organização."
              description={current.message}
              onRetry={onRetry}
            />
          ) : (
            <WorkspaceContext.Provider value={workspaceFor(current.membership, onRefresh)}>
              <Outlet />
            </WorkspaceContext.Provider>
          )}
        </main>
      </div>
    </div>
  )
}
