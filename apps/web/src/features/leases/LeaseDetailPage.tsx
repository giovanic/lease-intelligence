import { Link, useParams } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { fetchLease } from '../../services/leases'
import { useWorkspace } from '../../state/workspace'
import { LeaseDocuments } from '../documents/LeaseDocuments'
import { COUNTERPARTY_KIND_LABELS } from '../portfolio/labels'
import { PARTY_ROLE_LABELS } from './labels'
import { LeaseStatusBadge } from './LeaseTable'

export function LeaseDetailPage() {
  const { id = '' } = useParams()
  const { tenantId, canEdit } = useWorkspace()
  const { state, retry } = useApiQuery(`lease:${tenantId}:${id}`, () => fetchLease(tenantId, id))

  return (
    <section className="page">
      <QueryView state={state} onRetry={retry} loadingTitle="Carregando contrato…" notFoundTitle="Contrato não encontrado.">
        {(lease) => (
          <>
            <PageHeader
              title={lease.title}
              subtitle={lease.code ?? undefined}
              back={{ to: '/leases', label: 'Contratos' }}
              actions={
                canEdit && (
                  <Link className="button button--primary" to={`/leases/${lease.id}/edit`}>
                    Editar
                  </Link>
                )
              }
            />

            <section className="card section">
              <dl className="details">
                <dt>Situação</dt>
                <dd>
                  <LeaseStatusBadge status={lease.status} />
                </dd>
                <dt>Imóvel</dt>
                <dd>
                  <Link to={`/properties/${lease.property.id}`}>{lease.property.name}</Link>
                  <span className="muted">
                    {' '}
                    · {lease.property.city}/{lease.property.state}
                  </span>
                </dd>
                <dt>Observações</dt>
                <dd className="details__multiline">{lease.notes ?? '—'}</dd>
              </dl>
            </section>

            <section className="card section">
              <h2 className="section__title">Partes</h2>
              <div className="table-wrapper">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Papel</th>
                      <th>Nome</th>
                      <th>Tipo</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lease.parties.map((party) => (
                      <tr key={party.id}>
                        <td>{PARTY_ROLE_LABELS[party.role]}</td>
                        <td>
                          <Link to={`/counterparties/${party.counterparty.id}`}>{party.counterparty.legal_name}</Link>
                          {party.counterparty.trade_name && <span className="muted"> · {party.counterparty.trade_name}</span>}
                        </td>
                        <td>{COUNTERPARTY_KIND_LABELS[party.counterparty.kind]}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>

            <LeaseDocuments leaseId={lease.id} />

            <section className="card section">
              <h2 className="section__title">Condições contratuais</h2>
              <StatusMessage
                kind="empty"
                title="Nenhuma condição aprovada ainda."
                description="Datas, aluguel e reajuste virão do contrato enviado e revisado por uma pessoa — não são digitados no cadastro."
              />
            </section>
          </>
        )}
      </QueryView>
    </section>
  )
}
