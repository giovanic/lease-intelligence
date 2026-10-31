import type { DocumentKind } from '../../types/api'

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
