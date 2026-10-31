import { useState, type FormEvent } from 'react'
import { FormField } from '../../components/FormField'
import { useSubmission } from '../../hooks/useSubmission'
import { uploadDocument } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import type { DocumentKind } from '../../types/api'
import { ACCEPTED_FILES, DOCUMENT_KIND_LABELS, DOCUMENT_KINDS, fileProblem } from './labels'

interface DocumentUploadFormProps {
  leaseId: string
  /** Hides "Contrato original" when the lease already has one (the API refuses a second). */
  hasOriginal: boolean
  onUploaded: () => void
  onCancel: () => void
}

/** Registers a document of the lease with its first file (version 1). */
export function DocumentUploadForm({ leaseId, hasOriginal, onUploaded, onCancel }: DocumentUploadFormProps) {
  const { tenantId } = useWorkspace()
  const kinds = DOCUMENT_KINDS.filter((kind) => !(hasOriginal && kind === 'original_contract'))
  const [kind, setKind] = useState<DocumentKind>(kinds[0])
  const [title, setTitle] = useState(hasOriginal ? '' : DOCUMENT_KIND_LABELS.original_contract)
  const [file, setFile] = useState<File | null>(null)
  const [localError, setLocalError] = useState<string | null>(null)
  const { submitting, error, fieldErrors, run } = useSubmission()

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    const problem = fileProblem(file)
    setLocalError(problem)
    if (problem || !file) return

    const saved = await run(() => uploadDocument(tenantId, leaseId, { kind, title, file }))
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

      <div className="form__grid">
        <FormField label="Tipo" required errors={fieldErrors.kind}>
          <select value={kind} onChange={(e) => setKind(e.target.value as DocumentKind)}>
            {kinds.map((option) => (
              <option key={option} value={option}>
                {DOCUMENT_KIND_LABELS[option]}
              </option>
            ))}
          </select>
        </FormField>
        <FormField label="Título" required hint="Ex.: Aditivo nº 2 — reajuste" errors={fieldErrors.title}>
          <input value={title} onChange={(e) => setTitle(e.target.value)} required />
        </FormField>
      </div>

      <FormField label="Arquivo" required hint="PDF, JPEG, PNG ou TIFF, até 50 MB." errors={fileErrors}>
        <input type="file" accept={ACCEPTED_FILES} onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
      </FormField>

      <div className="form__actions">
        <button type="button" className="button button--secondary" onClick={onCancel} disabled={submitting}>
          Cancelar
        </button>
        <button type="submit" className="button button--primary" disabled={submitting}>
          {submitting ? 'Enviando…' : 'Enviar documento'}
        </button>
      </div>
    </form>
  )
}
