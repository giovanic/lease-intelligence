import type { ExtractionRun, TextExtraction } from '../../types/api'
import { EXTRACTION_RUN_ERROR_LABELS } from './fieldLabels'

interface FieldExtractionStatusProps {
  run: ExtractionRun | null
  /** The organization turned AI extraction on (docs/adr/0018); off, no run is requested or offered. */
  aiEnabled: boolean
  textExtraction: TextExtraction | null
  canEdit: boolean
  requesting: boolean
  onRequest: () => void
  showingFields: boolean
  onToggleFields: () => void
}

/**
 * Where a version's AI field extraction stands (docs/adr/0017): waiting for
 * the text, queued, running, done (with a button to show the candidates) or
 * failed (with why). Editors can start one once the text is extracted, or
 * retry a failure — only while the organization has AI extraction on.
 */
export function FieldExtractionStatus({
  run,
  aiEnabled,
  textExtraction,
  canEdit,
  requesting,
  onRequest,
  showingFields,
  onToggleFields,
}: FieldExtractionStatusProps) {
  const action = (label: string) =>
    canEdit &&
    aiEnabled && (
      <button type="button" className="button button--link" onClick={onRequest} disabled={requesting}>
        {requesting ? 'Pedindo…' : label}
      </button>
    )

  if (!run) {
    if (!aiEnabled) {
      return (
        <span className="muted" title="Proprietários e administradores podem ligar em Configurações.">
          IA desligada
        </span>
      )
    }
    if (textExtraction?.status !== 'succeeded') return <span className="muted">Aguardando o texto</span>
    return (
      <span className="text-extraction">
        <span className="badge badge--muted">Não processado</span>
        {action('Extrair campos')}
      </span>
    )
  }

  switch (run.status) {
    case 'pending':
      return <span className="badge badge--neutral">Na fila</span>
    case 'running':
      return <span className="badge badge--neutral">Lendo com IA…</span>
    case 'succeeded': {
      const count = run.field_count ?? 0
      return (
        <span className="text-extraction">
          <span className="badge badge--positive">{count === 1 ? '1 campo' : `${count} campos`}</span>
          {count > 0 && (
            <button
              type="button"
              className="button button--link"
              onClick={onToggleFields}
              aria-expanded={showingFields}
            >
              {showingFields ? 'Ocultar' : 'Ver campos'}
            </button>
          )}
        </span>
      )
    }
    case 'failed':
      return (
        <span className="text-extraction">
          <span className="badge badge--negative">Falhou</span>
          <span className="muted">
            {run.error_code ? EXTRACTION_RUN_ERROR_LABELS[run.error_code] : 'erro desconhecido'}
          </span>
          {action('Tentar novamente')}
        </span>
      )
  }
}
