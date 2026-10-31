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
import { listProperties } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import { formatArea, PROPERTY_TYPE_LABELS, RECORD_STATUS_LABELS, RECORD_STATUSES } from './labels'

const FILTERS = ['q', 'status'] as const

export function PropertyListPage() {
  const { tenantId, canEdit } = useWorkspace()
  const { filters, page, setFilters, setPage } = useListParams(FILTERS)
  const status = oneOf(filters.status, RECORD_STATUSES)
  const query = { q: filters.q || undefined, status, page }
  const { state, retry } = useApiQuery(`properties:${tenantId}:${JSON.stringify(query)}`, () =>
    listProperties(tenantId, query),
  )
  const filtered = Boolean(query.q || status)

  return (
    <section className="page">
      <PageHeader
        title="Imóveis"
        subtitle="Unidades da carteira da organização."
        actions={
          canEdit && (
            <Link className="button button--primary" to="/properties/new">
              Novo imóvel
            </Link>
          )
        }
      />

      <div className="filters">
        <SearchBox value={filters.q} placeholder="Buscar por nome, código ou cidade" onSearch={(q) => setFilters({ q })} />
        <SelectFilter
          label="Situação"
          value={status ?? ''}
          options={RECORD_STATUSES}
          labels={RECORD_STATUS_LABELS}
          onChange={(value) => setFilters({ status: value })}
        />
      </div>

      <QueryView state={state} onRetry={retry} loadingTitle="Carregando imóveis…">
        {({ data, meta }) =>
          data.length === 0 ? (
            <StatusMessage
              kind="empty"
              title={filtered ? 'Nenhum imóvel encontrado com esses filtros.' : 'Nenhum imóvel cadastrado.'}
              description={filtered || !canEdit ? undefined : 'Cadastre o primeiro imóvel para vincular contratos a ele.'}
            />
          ) : (
            <>
              <div className="table-wrapper">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Nome</th>
                      <th>Código</th>
                      <th>Tipo</th>
                      <th>Cidade/UF</th>
                      <th className="table__number">Área</th>
                      <th>Situação</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.map((property) => (
                      <tr key={property.id}>
                        <td>
                          <Link to={`/properties/${property.id}`}>{property.name}</Link>
                        </td>
                        <td>{property.code ?? '—'}</td>
                        <td>{PROPERTY_TYPE_LABELS[property.property_type]}</td>
                        <td>
                          {property.address.city}/{property.address.state}
                        </td>
                        <td className="table__number">{formatArea(property.area_sqm) || '—'}</td>
                        <td>
                          <StatusBadge
                            label={RECORD_STATUS_LABELS[property.status]}
                            tone={property.status === 'active' ? 'positive' : 'muted'}
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
