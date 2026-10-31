import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { listLeases } from '../../services/leases'
import { useWorkspace } from '../../state/workspace'
import { LeaseTable } from './LeaseTable'

interface RelatedLeasesProps {
  filter: { property_id: string } | { counterparty_id: string }
  emptyTitle: string
}

/** The leases of one property or one counterparty (first 100). */
export function RelatedLeases({ filter, emptyTitle }: RelatedLeasesProps) {
  const { tenantId } = useWorkspace()
  const query = { ...filter, per_page: 100 }
  const { state, retry } = useApiQuery(`leases:${tenantId}:${JSON.stringify(query)}`, () => listLeases(tenantId, query))

  return (
    <section className="card section">
      <h2 className="section__title">Contratos</h2>
      <QueryView state={state} onRetry={retry} loadingTitle="Carregando contratos…">
        {({ data, meta }) =>
          data.length === 0 ? (
            <StatusMessage kind="empty" title={emptyTitle} />
          ) : (
            <>
              <LeaseTable leases={data} showProperty={!('property_id' in filter)} />
              {meta.total_count > data.length && (
                <p className="muted">
                  Mostrando {data.length} de {meta.total_count}. Use a lista de contratos para ver todos.
                </p>
              )}
            </>
          )
        }
      </QueryView>
    </section>
  )
}
