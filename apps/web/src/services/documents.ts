import type { ContractDocument, ContractDocumentInput, DocumentVersion, DownloadLink, Page } from '../types/api'
import { apiRequest, apiRequestPage } from './apiClient'

// /api/v1/leases/:lease_id/documents and file access (docs/domain/documents.md,
// docs/adr/0015). Uploads go as multipart/form-data.

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

export function uploadDocument(tenantId: string, leaseId: string, input: ContractDocumentInput): Promise<ContractDocument> {
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
