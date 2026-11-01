import { Fragment, useEffect, useState, type ReactNode } from 'react'
import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { listLeaseDocuments } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import type { ContractDocument } from '../../types/api'
import { DocumentUploadForm } from './DocumentUploadForm'
import { ExtractedFieldsPanel } from './ExtractedFieldsPanel'
import { FieldExtractionStatus } from './FieldExtractionStatus'
import { isExtractionRunActive } from './fieldLabels'
import { DOCUMENT_KIND_LABELS, formatBytes, formatDateTime, isTextExtractionActive } from './labels'
import { NewVersionForm } from './NewVersionForm'
import { TextExtractionStatus } from './TextExtractionStatus'
import { useOpenDocumentVersion } from './useOpenDocumentVersion'
import { useRequestExtractionRun } from './useRequestExtractionRun'
import { useRequestTextExtraction } from './useRequestTextExtraction'

const PER_PAGE = 100
/** While a text or field extraction is queued or running, the list refreshes in the background this often. */
const POLL_INTERVAL_MS = 5000

/**
 * The documents of a lease (first 100), each with its version history and,
 * per version, the text extraction status and the AI field extraction
 * status, with the candidate fields on demand.
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
  const {
    request: requestFields,
    requestingId: requestingFieldsId,
    error: requestFieldsError,
  } = useRequestExtractionRun(refresh)
  const [fieldsFor, setFieldsFor] = useState<string | null>(null)

  const documents = state.status === 'success' ? state.data.data : null
  const extracting =
    documents?.some((document) =>
      document.versions.some(
        (version) => isTextExtractionActive(version.text_extraction) || isExtractionRunActive(version.extraction_run),
      ),
    ) ?? false

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

      {[openError, requestError, requestFieldsError].map(
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
                  requestingFieldsId={requestingFieldsId}
                  onRequestFields={requestFields}
                  fieldsFor={fieldsFor}
                  onToggleFields={(versionId) => setFieldsFor((current) => (current === versionId ? null : versionId))}
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
  requestingFieldsId: string | null
  onRequestFields: (versionId: string) => void
  /** The version whose candidate fields are shown, if any. */
  fieldsFor: string | null
  onToggleFields: (versionId: string) => void
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
  requestingFieldsId,
  onRequestFields,
  fieldsFor,
  onToggleFields,
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
              <th>Campos (IA)</th>
              <th aria-label="Ações" />
            </tr>
          </thead>
          <tbody>
            {document.versions.map((version, index) => {
              const run = version.extraction_run
              const showingFields = fieldsFor === version.id && run?.status === 'succeeded'
              return (
                <Fragment key={version.id}>
                  <tr>
                    <td>
                      v{version.version_number}
                      {index === 0 && <span className="muted"> · atual</span>}
                    </td>
                    <td>{version.original_filename}</td>
                    <td className="table__number">{formatBytes(version.byte_size)}</td>
                    <td>{version.uploaded_by.full_name}</td>
                    <td>{formatDateTime(version.created_at)}</td>
                    <td className="table__status">
                      <TextExtractionStatus
                        extraction={version.text_extraction}
                        canEdit={canEdit}
                        requesting={requestingId === version.id}
                        onRequest={() => onRequestText(version.id)}
                      />
                    </td>
                    <td className="table__status">
                      <FieldExtractionStatus
                        run={run}
                        textExtraction={version.text_extraction}
                        canEdit={canEdit}
                        requesting={requestingFieldsId === version.id}
                        onRequest={() => onRequestFields(version.id)}
                        showingFields={showingFields}
                        onToggleFields={() => onToggleFields(version.id)}
                        reviewHref={run ? `/leases/${document.lease_id}/extraction-runs/${run.id}/review` : null}
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
                  {showingFields && run && (
                    <tr className="table__detail-row">
                      <td colSpan={8}>
                        <ExtractedFieldsPanel runId={run.id} />
                      </td>
                    </tr>
                  )}
                </Fragment>
              )
            })}
          </tbody>
        </table>
      </div>
    </article>
  )
}
