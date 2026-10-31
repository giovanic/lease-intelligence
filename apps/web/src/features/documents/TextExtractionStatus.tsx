import type { TextExtraction } from '../../types/api'
import { pagesLabel, TEXT_EXTRACTION_ERROR_LABELS } from './labels'

interface TextExtractionStatusProps {
  extraction: TextExtraction | null
  canEdit: boolean
  requesting: boolean
  onRequest: () => void
}

/**
 * Where a version's text extraction stands (docs/adr/0016): queued,
 * running, done (with how many pages came from OCR) or failed (with why).
 * Editors can start one for a version never processed, or retry a failure.
 */
export function TextExtractionStatus({ extraction, canEdit, requesting, onRequest }: TextExtractionStatusProps) {
  const action = (label: string) =>
    canEdit && (
      <button type="button" className="button button--link" onClick={onRequest} disabled={requesting}>
        {requesting ? 'Pedindo…' : label}
      </button>
    )

  if (!extraction) {
    return (
      <span className="text-extraction">
        <span className="badge badge--muted">Não processado</span>
        {action('Extrair texto')}
      </span>
    )
  }

  switch (extraction.status) {
    case 'pending':
      return <span className="badge badge--neutral">Na fila</span>
    case 'running':
      return <span className="badge badge--neutral">Extraindo texto…</span>
    case 'succeeded': {
      const ocr = extraction.ocr_page_count ?? 0
      return (
        <span className="text-extraction">
          <span className="badge badge--positive">Texto extraído</span>
          <span className="muted">
            {pagesLabel(extraction.page_count ?? 0)}
            {ocr > 0 && ` · ${ocr} por OCR`}
          </span>
        </span>
      )
    }
    case 'failed':
      return (
        <span className="text-extraction">
          <span className="badge badge--negative">Falhou</span>
          <span className="muted">
            {extraction.error_code ? TEXT_EXTRACTION_ERROR_LABELS[extraction.error_code] : 'erro desconhecido'}
          </span>
          {action('Tentar novamente')}
        </span>
      )
  }
}
