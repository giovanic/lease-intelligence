import { Link, useParams } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { StatusBadge } from '../../components/StatusBadge'
import { useApiQuery } from '../../hooks/useApiQuery'
import { fetchProperty } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import { RelatedLeases } from '../leases/RelatedLeases'
import { ArchiveToggle } from './ArchiveToggle'
import { formatArea, formatPostalCode, PROPERTY_TYPE_LABELS, RECORD_STATUS_LABELS } from './labels'

export function PropertyDetailPage() {
  const { id = '' } = useParams()
  const { tenantId, canEdit } = useWorkspace()
  const { state, retry } = useApiQuery(`property:${tenantId}:${id}`, () => fetchProperty(tenantId, id))

  return (
    <section className="page">
      <QueryView state={state} onRetry={retry} loadingTitle="Carregando imóvel…" notFoundTitle="Imóvel não encontrado.">
        {(property) => {
          const { address } = property
          const streetLine = [address.street, address.number, address.complement].filter(Boolean).join(', ')

          return (
            <>
              <PageHeader
                title={property.name}
                subtitle={PROPERTY_TYPE_LABELS[property.property_type]}
                back={{ to: '/properties', label: 'Imóveis' }}
                actions={
                  canEdit && (
                    <>
                      <ArchiveToggle kind="property" id={property.id} status={property.status} onChanged={retry} />
                      <Link className="button button--primary" to={`/properties/${property.id}/edit`}>
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
                      label={RECORD_STATUS_LABELS[property.status]}
                      tone={property.status === 'active' ? 'positive' : 'muted'}
                    />
                  </dd>
                  <dt>Código</dt>
                  <dd>{property.code ?? '—'}</dd>
                  <dt>Endereço</dt>
                  <dd>
                    {streetLine}
                    {address.district && ` — ${address.district}`}
                    <br />
                    {address.city}/{address.state}
                    {address.postal_code && ` · CEP ${formatPostalCode(address.postal_code)}`}
                  </dd>
                  <dt>Área</dt>
                  <dd>{formatArea(property.area_sqm) || '—'}</dd>
                </dl>
              </section>

              <RelatedLeases filter={{ property_id: property.id }} emptyTitle="Nenhum contrato para este imóvel." />
            </>
          )
        }}
      </QueryView>
    </section>
  )
}
