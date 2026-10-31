import { useSubmission } from '../../hooks/useSubmission'
import { updateCounterparty, updateProperty } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import type { RecordStatus } from '../../types/api'

interface ArchiveToggleProps {
  kind: 'property' | 'counterparty'
  id: string
  status: RecordStatus
  onChanged: () => void
}

/** Archives (or reactivates) a portfolio record — there is no delete. */
export function ArchiveToggle({ kind, id, status, onChanged }: ArchiveToggleProps) {
  const { tenantId } = useWorkspace()
  const { submitting, error, run } = useSubmission()
  const next: RecordStatus = status === 'active' ? 'archived' : 'active'

  async function handleClick() {
    if (next === 'archived' && !window.confirm('Arquivar este registro? Ele deixa de poder ser vinculado a novos contratos.')) {
      return
    }
    const result = await run<unknown>(() =>
      kind === 'property'
        ? updateProperty(tenantId, id, { status: next })
        : updateCounterparty(tenantId, id, { status: next }),
    )
    if (result) onChanged()
  }

  return (
    <>
      {error && (
        <span className="inline-error" role="alert">
          {error}
        </span>
      )}
      <button type="button" className="button button--secondary" disabled={submitting} onClick={handleClick}>
        {next === 'archived' ? 'Arquivar' : 'Reativar'}
      </button>
    </>
  )
}
