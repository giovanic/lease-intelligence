import { Link } from 'react-router'
import { StatusBadge } from '../../components/StatusBadge'
import type { Lease } from '../../types/api'
import { LEASE_STATUS_LABELS } from './labels'

/** Leases as a table; also embedded in the property and counterparty screens. */
export function LeaseTable({ leases, showProperty = true }: { leases: Lease[]; showProperty?: boolean }) {
  return (
    <div className="table-wrapper">
      <table className="table">
        <thead>
          <tr>
            <th>Contrato</th>
            <th>Código</th>
            {showProperty && <th>Imóvel</th>}
            <th>Locador(es)</th>
            <th>Situação</th>
          </tr>
        </thead>
        <tbody>
          {leases.map((lease) => (
            <tr key={lease.id}>
              <td>
                <Link to={`/leases/${lease.id}`}>{lease.title}</Link>
              </td>
              <td>{lease.code ?? '—'}</td>
              {showProperty && (
                <td>
                  <Link to={`/properties/${lease.property.id}`}>{lease.property.name}</Link>
                </td>
              )}
              <td>{lessorNames(lease) || '—'}</td>
              <td>
                <LeaseStatusBadge status={lease.status} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function LeaseStatusBadge({ status }: { status: Lease['status'] }) {
  const tone = status === 'active' ? 'positive' : status === 'draft' ? 'neutral' : 'muted'
  return <StatusBadge label={LEASE_STATUS_LABELS[status]} tone={tone} />
}

function lessorNames(lease: Lease): string {
  return lease.parties
    .filter((party) => party.role === 'lessor')
    .map((party) => party.counterparty.trade_name ?? party.counterparty.legal_name)
    .join(', ')
}
