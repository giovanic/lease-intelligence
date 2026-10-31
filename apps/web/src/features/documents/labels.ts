import type { DocumentKind, TextExtraction, TextExtractionErrorCode } from '../../types/api'

export const DOCUMENT_KIND_LABELS: Record<DocumentKind, string> = {
  original_contract: 'Contrato original',
  amendment: 'Aditivo',
  other: 'Outro documento',
}

export const DOCUMENT_KINDS = Object.keys(DOCUMENT_KIND_LABELS) as DocumentKind[]

/**
 * UX only — the API checks the real file bytes and the size again
 * (docs/adr/0015). Extensions here just pre-filter the file picker.
 */
export const ACCEPTED_FILES = '.pdf,.jpg,.jpeg,.png,.tif,.tiff,application/pdf,image/jpeg,image/png,image/tiff'
export const MAX_FILE_BYTES = 50 * 1024 * 1024

export function fileProblem(file: File | null): string | null {
  if (!file) return 'Selecione um arquivo.'
  if (file.size === 0) return 'O arquivo está vazio.'
  if (file.size > MAX_FILE_BYTES) return 'O arquivo passa de 50 MB.'
  return null
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1).replace('.', ',')} MB`
}

const DATE_TIME = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' })

export function formatDateTime(iso: string): string {
  return DATE_TIME.format(new Date(iso))
}

/** Why a text extraction failed, for the person who can retry it (docs/adr/0016). */
export const TEXT_EXTRACTION_ERROR_LABELS: Record<TextExtractionErrorCode, string> = {
  unreadable_file: 'arquivo ilegível ou corrompido',
  encrypted_pdf: 'PDF protegido por senha',
  too_many_pages: 'mais de 300 páginas',
  timeout: 'o OCR demorou demais',
  ocr_unavailable: 'OCR indisponível no servidor',
  storage_unavailable: 'arquivo indisponível no armazenamento',
  abandoned: 'processamento interrompido',
  internal_error: 'erro interno',
}

export function isTextExtractionActive(extraction: TextExtraction | null): boolean {
  return extraction?.status === 'pending' || extraction?.status === 'running'
}

export function pagesLabel(count: number): string {
  return count === 1 ? '1 página' : `${count} páginas`
}
