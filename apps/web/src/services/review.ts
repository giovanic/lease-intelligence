import type { DocumentTextPage, ReviewDecision, ReviewDecisionInput } from '../types/api'
import { apiRequest } from './apiClient'

// Human review of AI-extracted fields (docs/adr/0019).

/** 201; 409 stale_run (field of an older run), 422 validation_failed. Reviewers only (403 otherwise). */
export function createReviewDecision(
  tenantId: string,
  fieldId: string,
  input: ReviewDecisionInput,
): Promise<ReviewDecision> {
  return apiRequest<ReviewDecision>(`/extracted_fields/${encodeURIComponent(fieldId)}/review_decisions`, {
    method: 'POST',
    tenantId,
    body: { review_decision: input },
  })
}

/** The full text of one page of the text the run read — contract content, members only. */
export function getRunPage(tenantId: string, runId: string, pageNumber: number): Promise<DocumentTextPage> {
  return apiRequest<DocumentTextPage>(`/extraction_runs/${encodeURIComponent(runId)}/pages/${pageNumber}`, {
    tenantId,
  })
}
