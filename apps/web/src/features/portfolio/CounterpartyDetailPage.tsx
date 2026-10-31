import { Link, useParams } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { StatusBadge } from '../../components/StatusBadge'
import { useApiQuery } from '../../hooks/useApiQuery'
import { fetchCounterparty } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import { RelatedLeases } from '../leases/RelatedLeases'
import { ArchiveToggle } from './ArchiveToggle'
import { COUNTERPARTY_KIND_LABELS, formatTaxId, RECORD_STATUS_LABELS } from './labels'

export function CounterpartyDetailPage() {
  const { id = '' } = useParams()
  const { tenantId, canEdit } = useWorkspace()
  const { state, retry } = useApiQuery(`counterparty:${tenantId}:${id}`, () => fetchCounterparty(tenantId, id))

  return (
    <section className="page">
      <QueryView state={state} onRetry={retry} loadingTitle="Carregando parte…" notFoundTitle="Parte não encontrada.">
        {(counterparty) => (
          <>
            <PageHeader
              title={counterparty.legal_name}
              subtitle={COUNTERPARTY_KIND_LABELS[counterparty.kind]}
              back={{ to: '/counterparties', label: 'Locadores e partes' }}
              actions={
                canEdit && (
                  <>
                    <ArchiveToggle kind="counterparty" id={counterparty.id} status={counterparty.status} onChanged={retry} />
                    <Link className="button button--primary" to={`/counterparties/${counterparty.id}/edit`}>
                      Editar
                    </Link>
                  </>
                )
              }
            />

            <section className="card section">
              <dl className="details">
                <dt>Situação</dt>
                <dd>
                  <StatusBadge
                    label={RECORD_STATUS_LABELS[counterparty.status]}
                    tone={counterparty.status === 'active' ? 'positive' : 'muted'}
                  />
                </dd>
                <dt>Nome fantasia</dt>
                <dd>{counterparty.trade_name ?? '—'}</dd>
                <dt>{counterparty.kind === 'individual' ? 'CPF' : 'CNPJ'}</dt>
                <dd>{formatTaxId(counterparty.tax_id) || '—'}</dd>
                <dt>E-mail</dt>
                <dd>{counterparty.email ?? '—'}</dd>
                <dt>Telefone</dt>
                <dd>{counterparty.phone ?? '—'}</dd>
              </dl>
            </section>

            <RelatedLeases filter={{ counterparty_id: counterparty.id }} emptyTitle="Esta parte não participa de nenhum contrato." />
          </>
        )}
      </QueryView>
    </section>
  )
}
