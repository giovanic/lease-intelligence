import { Link } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { Pagination } from '../../components/Pagination'
import { QueryView } from '../../components/QueryView'
import { SearchBox } from '../../components/SearchBox'
import { SelectFilter } from '../../components/SelectFilter'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { oneOf, useListParams } from '../../hooks/useListParams'
import { listLeases } from '../../services/leases'
import { useWorkspace } from '../../state/workspace'
import { LEASE_STATUS_LABELS, LEASE_STATUSES } from './labels'
import { LeaseTable } from './LeaseTable'

const FILTERS = ['q', 'status'] as const

export function LeaseListPage() {
  const { tenantId, canEdit } = useWorkspace()
  const { filters, page, setFilters, setPage } = useListParams(FILTERS)
  const status = oneOf(filters.status, LEASE_STATUSES)
  const query = { q: filters.q || undefined, status, page }
  const { state, retry } = useApiQuery(`leases:${tenantId}:${JSON.stringify(query)}`, () => listLeases(tenantId, query))
  const filtered = Boolean(query.q || status)

  return (
    <section className="page">
      <PageHeader
        title="Contratos"
        subtitle="Contratos de locação da organização."
        actions={
          canEdit && (
            <Link className="button button--primary" to="/leases/new">
              Novo contrato
            </Link>
          )
        }
      />

      <div className="filters">
        <SearchBox value={filters.q} placeholder="Buscar por título ou código" onSearch={(q) => setFilters({ q })} />
        <SelectFilter
          label="Situação"
          value={status ?? ''}
          options={LEASE_STATUSES}
          labels={LEASE_STATUS_LABELS}
          onChange={(value) => setFilters({ status: value })}
        />
      </div>

      <QueryView state={state} onRetry={retry} loadingTitle="Carregando contratos…">
        {({ data, meta }) =>
          data.length === 0 ? (
            <StatusMessage
              kind="empty"
              title={filtered ? 'Nenhum contrato encontrado com esses filtros.' : 'Nenhum contrato cadastrado.'}
              description={
                filtered || !canEdit ? undefined : 'Cadastre o imóvel e o locador, depois registre o contrato.'
              }
            />
          ) : (
            <>
              <LeaseTable leases={data} />
              <Pagination meta={meta} onPage={setPage} />
            </>
          )
        }
      </QueryView>
    </section>
  )
}
