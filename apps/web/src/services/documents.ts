import type {
  ContractDocument,
  ContractDocumentInput,
  DocumentVersion,
  DownloadLink,
  ExtractionRun,
  ExtractionRunDetail,
  Page,
  TextExtraction,
} from '../types/api'
import { apiRequest, apiRequestPage } from './apiClient'

// /api/v1/leases/:lease_id/documents, file access (docs/domain/documents.md,
// docs/adr/0015), text extraction (docs/adr/0016) and AI field extraction
// (docs/adr/0017). Uploads go as
// multipart/form-data.

function documentsPath(leaseId: string): string {
  return `/leases/${encodeURIComponent(leaseId)}/documents`
}

export function listLeaseDocuments(
  tenantId: string,
  leaseId: string,
  query: { page?: number; per_page?: number } = {},
): Promise<Page<ContractDocument>> {
  return apiRequestPage<ContractDocument>(documentsPath(leaseId), { tenantId, query })
}

export function uploadDocument(
  tenantId: string,
  leaseId: string,
  input: ContractDocumentInput,
): Promise<ContractDocument> {
  const body = new FormData()
  body.append('document[kind]', input.kind)
  body.append('document[title]', input.title)
  body.append('document[file]', input.file)
  return apiRequest<ContractDocument>(documentsPath(leaseId), { method: 'POST', tenantId, body })
}

export function uploadDocumentVersion(
  tenantId: string,
  leaseId: string,
  documentId: string,
  file: File,
): Promise<DocumentVersion> {
  const body = new FormData()
  body.append('version[file]', file)
  return apiRequest<DocumentVersion>(`${documentsPath(leaseId)}/${encodeURIComponent(documentId)}/versions`, {
    method: 'POST',
    tenantId,
    body,
  })
}

export function createDownloadLink(tenantId: string, versionId: string): Promise<DownloadLink> {
  return apiRequest<DownloadLink>(`/document_versions/${encodeURIComponent(versionId)}/download_link`, {
    method: 'POST',
    tenantId,
  })
}

/** Queues a new text extraction of a version; 409 extraction_in_progress while one is pending/running. */
export function requestTextExtraction(tenantId: string, versionId: string): Promise<TextExtraction> {
  return apiRequest<TextExtraction>(`/document_versions/${encodeURIComponent(versionId)}/text_extractions`, {
    method: 'POST',
    tenantId,
  })
}

/**
 * Queues a new AI field extraction of a version over its latest extracted text. 409 extraction_in_progress
 * while one is pending/running, 422 text_not_ready, 503 extraction_unavailable (not configured).
 */
export function requestExtractionRun(tenantId: string, versionId: string): Promise<ExtractionRun> {
  return apiRequest<ExtractionRun>(`/document_versions/${encodeURIComponent(versionId)}/extraction_runs`, {
    method: 'POST',
    tenantId,
  })
}

/** A run with its candidate fields and the quoted evidence of each. */
export function getExtractionRun(tenantId: string, runId: string): Promise<ExtractionRunDetail> {
  return apiRequest<ExtractionRunDetail>(`/extraction_runs/${encodeURIComponent(runId)}`, { tenantId })
}
