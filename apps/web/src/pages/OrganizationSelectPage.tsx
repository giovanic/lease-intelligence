import { RoleBadge } from '../components/RoleBadge'
import { StatusMessage } from '../components/StatusMessage'
import type { Me } from '../types/api'

interface OrganizationSelectPageProps {
  me: Me
  onSelect: (tenantId: string) => void
  onSignOut: () => void
}

export function OrganizationSelectPage({ me, onSelect, onSignOut }: OrganizationSelectPageProps) {
  return (
    <main className="auth-layout">
      <section className="card auth-card">
        <h1 className="auth-card__title">Escolha a organização</h1>
        <p className="muted">
          Conectado como <strong>{me.user.full_name}</strong> ({me.user.email})
        </p>

        {me.memberships.length === 0 ? (
          <StatusMessage
            kind="empty"
            title="Você ainda não faz parte de nenhuma organização."
            description="Peça a um administrador da sua empresa que envie um convite."
          />
        ) : (
          <ul className="org-list">
            {me.memberships.map((membership) => (
              <li key={membership.id}>
                <button type="button" className="org-list__item" onClick={() => onSelect(membership.tenant.id)}>
                  <span className="org-list__name">{membership.tenant.name}</span>
                  <RoleBadge role={membership.role} />
                </button>
              </li>
            ))}
          </ul>
        )}

        <button type="button" className="button button--link" onClick={onSignOut}>
          Sair
        </button>
      </section>
    </main>
  )
}
