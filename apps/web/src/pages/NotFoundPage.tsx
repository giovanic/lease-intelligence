import { Link } from 'react-router'
import { StatusMessage } from '../components/StatusMessage'

export function NotFoundPage() {
  return (
    <section className="page">
      <StatusMessage kind="empty" title="Página não encontrada." />
      <p>
        <Link to="/leases">Ir para os contratos</Link>
      </p>
    </section>
  )
}
