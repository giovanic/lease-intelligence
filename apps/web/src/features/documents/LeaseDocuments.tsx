import { useEffect, useState, type ReactNode } from 'react'
import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { listLeaseDocuments } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import type { ContractDocument } from '../../types/api'
import { DocumentUploadForm } from './DocumentUploadForm'
import { DOCUMENT_KIND_LABELS, formatBytes, formatDateTime, isTextExtractionActive } from './labels'
import { NewVersionForm } from './NewVersionForm'
import { TextExtractionStatus } from './TextExtractionStatus'
import { useOpenDocumentVersion } from './useOpenDocumentVersion'
import { useRequestTextExtraction } from './useRequestTextExtraction'

const PER_PAGE = 100
/** While an extraction is queued or running, the list refreshes in the background this often. */
const POLL_INTERVAL_MS = 5000

/**
 * The documents of a lease (first 100), each with its version history and
 * the text extraction status of every version.
 */
export function LeaseDocuments({ leaseId }: { leaseId: string }) {
  const { tenantId, canEdit } = useWorkspace()
  const { state, retry, refresh } = useApiQuery(`lease-documents:${tenantId}:${leaseId}`, () =>
    listLeaseDocuments(tenantId, leaseId, { per_page: PER_PAGE }),
  )
  const [uploading, setUploading] = useState(false)
  const [versionFormFor, setVersionFormFor] = useState<string | null>(null)
  const { open, openingId, error: openError } = useOpenDocumentVersion()
  const { request, requestingId, error: requestError } = useRequestTextExtraction(refresh)

  const documents = state.status === 'success' ? state.data.data : null
  const extracting =
    documents?.some((document) => document.versions.some((version) => isTextExtractionActive(version.text_extraction))) ??
    false

  // One timer per answer: each refresh brings new data, which re-arms it
  // until nothing is queued or running.
  useEffect(() => {
    if (!extracting) return
    const timer = window.setTimeout(refresh, POLL_INTERVAL_MS)
    return () => window.clearTimeout(timer)
  }, [extracting, documents, refresh])

  function refreshAfterUpload() {
    setUploading(false)
    setVersionFormFor(null)
    retry()
  }

  return (
    <section className="card section">
      <div className="section__header">
        <h2 className="section__title">Documentos</h2>
        {canEdit && !uploading && (
          <button type="button" className="button button--primary" onClick={() => setUploading(true)}>
            Enviar documento
          </button>
        )}
      </div>

      {[openError, requestError].map(
        (message) =>
          message && (
            <div key={message} className="alert" role="alert">
              {message}
            </div>
          ),
      )}

      <QueryView state={state} onRetry={retry} loadingTitle="Carregando documentos…">
        {({ data, meta }) => (
          <>
            {uploading && (
              <DocumentUploadForm
                leaseId={leaseId}
                hasOriginal={data.some((document) => document.kind === 'original_contract')}
                onUploaded={refreshAfterUpload}
                onCancel={() => setUploading(false)}
              />
            )}

            {data.length === 0 ? (
              <StatusMessage
                kind="empty"
                title="Nenhum documento enviado."
                description="Envie o contrato assinado (PDF ou digitalização) para guardá-lo com histórico de versões."
              />
            ) : (
              data.map((document) => (
                <DocumentCard
                  key={document.id}
                  document={document}
                  canEdit={canEdit}
                  openingId={openingId}
                  onOpen={open}
                  requestingId={requestingId}
                  onRequestText={request}
                  showVersionForm={versionFormFor === document.id}
                  onToggleVersionForm={(show) => setVersionFormFor(show ? document.id : null)}
                  versionForm={
                    <NewVersionForm
                      leaseId={leaseId}
                      documentId={document.id}
                      onUploaded={refreshAfterUpload}
                      onCancel={() => setVersionFormFor(null)}
                    />
                  }
                />
              ))
            )}

            {meta.total_count > data.length && (
              <p className="muted">
                Mostrando {data.length} de {meta.total_count} documentos.
              </p>
            )}
          </>
        )}
      </QueryView>
    </section>
  )
}

interface DocumentCardProps {
  document: ContractDocument
  canEdit: boolean
  openingId: string | null
  onOpen: (versionId: string) => void
  requestingId: string | null
  onRequestText: (versionId: string) => void
  showVersionForm: boolean
  onToggleVersionForm: (show: boolean) => void
  versionForm: ReactNode
}

function DocumentCard({
  document,
  canEdit,
  openingId,
  onOpen,
  requestingId,
  onRequestText,
  showVersionForm,
  onToggleVersionForm,
  versionForm,
}: DocumentCardProps) {
  return (
    <article className="document">
      <header className="document__header">
        <div>
          <h3 className="document__title">{document.title}</h3>
          <span className="badge">{DOCUMENT_KIND_LABELS[document.kind]}</span>
        </div>
        {canEdit && !showVersionForm && (
          <button type="button" className="button button--secondary" onClick={() => onToggleVersionForm(true)}>
            Nova versão
          </button>
        )}
      </header>

      {showVersionForm && versionForm}

      <div className="table-wrapper">
        <table className="table">
          <thead>
            <tr>
              <th>Versão</th>
              <th>Arquivo</th>
              <th className="table__number">Tamanho</th>
              <th>Enviado por</th>
              <th>Enviado em</th>
              <th>Texto</th>
              <th aria-label="Ações" />
            </tr>
          </thead>
          <tbody>
            {document.versions.map((version, index) => (
              <tr key={version.id}>
                <td>
                  v{version.version_number}
                  {index === 0 && <span className="muted"> · atual</span>}
                </td>
                <td>{version.original_filename}</td>
                <td className="table__number">{formatBytes(version.byte_size)}</td>
                <td>{version.uploaded_by.full_name}</td>
                <td>{formatDateTime(version.created_at)}</td>
                <td>
                  <TextExtractionStatus
                    extraction={version.text_extraction}
                    canEdit={canEdit}
                    requesting={requestingId === version.id}
                    onRequest={() => onRequestText(version.id)}
                  />
                </td>
                <td>
                  <button
                    type="button"
                    className="button button--link"
                    onClick={() => onOpen(version.id)}
                    disabled={openingId === version.id}
                  >
                    {openingId === version.id ? 'Abrindo…' : 'Abrir'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </article>
  )
}
