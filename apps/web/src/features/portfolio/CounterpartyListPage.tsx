import { Link } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { Pagination } from '../../components/Pagination'
import { QueryView } from '../../components/QueryView'
import { SearchBox } from '../../components/SearchBox'
import { SelectFilter } from '../../components/SelectFilter'
import { StatusBadge } from '../../components/StatusBadge'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { oneOf, useListParams } from '../../hooks/useListParams'
import { listCounterparties } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import {
  COUNTERPARTY_KIND_LABELS,
  COUNTERPARTY_KINDS,
  formatTaxId,
  RECORD_STATUS_LABELS,
  RECORD_STATUSES,
} from './labels'

const FILTERS = ['q', 'status', 'kind'] as const

export function CounterpartyListPage() {
  const { tenantId, canEdit } = useWorkspace()
  const { filters, page, setFilters, setPage } = useListParams(FILTERS)
  const status = oneOf(filters.status, RECORD_STATUSES)
  const kind = oneOf(filters.kind, COUNTERPARTY_KINDS)
  const query = { q: filters.q || undefined, status, kind, page }
  const { state, retry } = useApiQuery(`counterparties:${tenantId}:${JSON.stringify(query)}`, () =>
    listCounterparties(tenantId, query),
  )
  const filtered = Boolean(query.q || status || kind)

  return (
    <section className="page">
      <PageHeader
        title="Locadores e partes"
        subtitle="Pessoas e empresas que participam dos contratos (locadores, fiadores, intervenientes)."
        actions={
          canEdit && (
            <Link className="button button--primary" to="/counterparties/new">
              Nova parte
            </Link>
          )
        }
      />

      <div className="filters">
        <SearchBox value={filters.q} placeholder="Buscar por nome ou CPF/CNPJ" onSearch={(q) => setFilters({ q })} />
        <SelectFilter
          label="Tipo"
          value={kind ?? ''}
          options={COUNTERPARTY_KINDS}
          labels={COUNTERPARTY_KIND_LABELS}
          onChange={(value) => setFilters({ kind: value })}
        />
        <SelectFilter
          label="Situação"
          value={status ?? ''}
          options={RECORD_STATUSES}
          labels={RECORD_STATUS_LABELS}
          onChange={(value) => setFilters({ status: value })}
        />
      </div>

      <QueryView state={state} onRetry={retry} loadingTitle="Carregando partes…">
        {({ data, meta }) =>
          data.length === 0 ? (
            <StatusMessage
              kind="empty"
              title={filtered ? 'Nenhuma parte encontrada com esses filtros.' : 'Nenhuma parte cadastrada.'}
              description={filtered || !canEdit ? undefined : 'Cadastre o locador antes de registrar o contrato.'}
            />
          ) : (
            <>
              <div className="table-wrapper">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Razão social / nome</th>
                      <th>Nome fantasia</th>
                      <th>Tipo</th>
                      <th>CPF/CNPJ</th>
                      <th>Situação</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.map((counterparty) => (
                      <tr key={counterparty.id}>
                        <td>
                          <Link to={`/counterparties/${counterparty.id}`}>{counterparty.legal_name}</Link>
                        </td>
                        <td>{counterparty.trade_name ?? '—'}</td>
                        <td>{COUNTERPARTY_KIND_LABELS[counterparty.kind]}</td>
                        <td>{formatTaxId(counterparty.tax_id) || '—'}</td>
                        <td>
                          <StatusBadge
                            label={RECORD_STATUS_LABELS[counterparty.status]}
                            tone={counterparty.status === 'active' ? 'positive' : 'muted'}
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <Pagination meta={meta} onPage={setPage} />
            </>
          )
        }
      </QueryView>
    </section>
  )
}
