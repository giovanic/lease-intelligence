import { useState, type FormEvent } from 'react'
import { FormField } from '../../components/FormField'
import { useSubmission } from '../../hooks/useSubmission'
import { uploadDocumentVersion } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import { ACCEPTED_FILES, fileProblem } from './labels'

interface NewVersionFormProps {
  leaseId: string
  documentId: string
  onUploaded: () => void
  onCancel: () => void
}

/** Uploads a new file version; earlier versions stay untouched (docs/adr/0010). */
export function NewVersionForm({ leaseId, documentId, onUploaded, onCancel }: NewVersionFormProps) {
  const { tenantId } = useWorkspace()
  const [file, setFile] = useState<File | null>(null)
  const [localError, setLocalError] = useState<string | null>(null)
  const { submitting, error, fieldErrors, run } = useSubmission()

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    const problem = fileProblem(file)
    setLocalError(problem)
    if (problem || !file) return

    const saved = await run(() => uploadDocumentVersion(tenantId, leaseId, documentId, file))
    if (saved) onUploaded()
  }

  const fileErrors = [...(localError ? [localError] : []), ...(fieldErrors.file ?? [])]

  return (
    <form className="form" onSubmit={handleSubmit} noValidate>
      {error && (
        <div className="alert" role="alert">
          {error}
        </div>
      )}
      <FormField
        label="Novo arquivo"
        required
        hint="A versão atual é mantida no histórico; nada é sobrescrito."
        errors={fileErrors}
      >
        <input type="file" accept={ACCEPTED_FILES} onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
      </FormField>
      <div className="form__actions">
        <button type="button" className="button button--secondary" onClick={onCancel} disabled={submitting}>
          Cancelar
        </button>
        <button type="submit" className="button button--primary" disabled={submitting}>
          {submitting ? 'Enviando…' : 'Enviar nova versão'}
        </button>
      </div>
    </form>
  )
}
