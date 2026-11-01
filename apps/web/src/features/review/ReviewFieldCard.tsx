import { useState } from 'react'
import { useSubmission } from '../../hooks/useSubmission'
import { ApiError } from '../../services/apiClient'
import { createReviewDecision } from '../../services/review'
import { useWorkspace } from '../../state/workspace'
import type { Evidence, ExtractedField, ReviewDecisionInput, TypedPair } from '../../types/api'
import {
  FIELD_LABELS,
  formatFieldValue,
  formatTypedValue,
  REVIEW_BADGES,
  REVIEW_LABELS,
} from '../documents/fieldLabels'
import { formatDateTime } from '../documents/labels'
import { CorrectionForm } from './CorrectionForm'

interface ReviewFieldCardProps {
  field: ExtractedField
  canReview: boolean
  /** Shows an evidence in the document pane. */
  onShowEvidence: (evidence: Evidence) => void
  activeEvidenceId: string | null
  onDecided: () => void
}

/**
 * One AI candidate under review (docs/adr/0019): its value, the quoted
 * evidence (click to see it highlighted in the page), its current decision
 * and — for reviewers — Aprovar / Corrigir / Rejeitar. Every action writes a
 * new decision; earlier ones stay in history.
 */
export function ReviewFieldCard({
  field,
  canReview,
  onShowEvidence,
  activeEvidenceId,
  onDecided,
}: ReviewFieldCardProps) {
  const { tenantId } = useWorkspace()
  const { submitting, error, fieldErrors, run, reset } = useSubmission()
  const [mode, setMode] = useState<'idle' | 'correct' | 'reject'>('idle')
  const [reason, setReason] = useState('')
  const review = field.review
  const state = review?.decision ?? 'pending'
  // A correction's value has the field's own type (enforced by the API).
  const corrected =
    review?.decision === 'corrected' && review.value
      ? ({ value_type: field.value_type, value: review.value } as TypedPair)
      : null

  async function decide(input: ReviewDecisionInput) {
    const result = await run(async () => {
      try {
        return await createReviewDecision(tenantId, field.id, input)
      } catch (err) {
        if (err instanceof ApiError && err.code === 'stale_run') {
          throw new Error('Esta versão tem uma extração mais recente; revise a dela.')
        }
        throw err
      }
    })
    if (result) {
      setMode('idle')
      setReason('')
      onDecided()
    }
  }

  function cancel() {
    reset()
    setMode('idle')
  }

  return (
    <article className={`review-field review-field--${state}`}>
      <header className="review-field__header">
        <h3 className="review-field__label">{FIELD_LABELS[field.key]}</h3>
        <span className={`badge ${REVIEW_BADGES[state]}`}>{REVIEW_LABELS[state]}</span>
      </header>

      <p className="review-field__value">
        {corrected ? (
          <>
            <span className="review-field__ai-value">{formatFieldValue(field)}</span>
            <span>{formatTypedValue(field.key, corrected)}</span>
          </>
        ) : (
          formatFieldValue(field)
        )}
      </p>

      {review && (
        <p className="muted review-field__meta">
          {REVIEW_LABELS[state]} por {review.reviewed_by.full_name} em {formatDateTime(review.created_at)}
          {review.reason && ` — “${review.reason}”`}
          {field.review_count > 1 && ` · ${field.review_count} decisões no histórico`}
        </p>
      )}

      <ul className="review-field__evidence">
        {field.evidence.map((evidence) => (
          <li key={evidence.id}>
            <button
              type="button"
              className={`review-evidence${activeEvidenceId === evidence.id ? ' review-evidence--active' : ''}`}
              onClick={() => onShowEvidence(evidence)}
            >
              <span className="muted">
                Página {evidence.page_number}
                {evidence.source === 'ocr' && ' · OCR'}
              </span>
              <q>{evidence.snippet}</q>
            </button>
          </li>
        ))}
      </ul>

      {error && (
        <div className="alert" role="alert">
          {error}
        </div>
      )}

      {canReview && mode === 'idle' && (
        <div className="review-field__actions">
          <button
            type="button"
            className="button button--primary"
            disabled={submitting}
            onClick={() => decide({ decision: 'approved' })}
          >
            Aprovar
          </button>
          <button
            type="button"
            className="button button--secondary"
            disabled={submitting}
            onClick={() => setMode('correct')}
          >
            Corrigir
          </button>
          <button
            type="button"
            className="button button--secondary"
            disabled={submitting}
            onClick={() => setMode('reject')}
          >
            Rejeitar
          </button>
        </div>
      )}

      {canReview && mode === 'correct' && (
        <CorrectionForm
          field={field}
          initial={corrected ?? field}
          submitting={submitting}
          valueError={Boolean(fieldErrors.value)}
          onSubmit={decide}
          onCancel={cancel}
        />
      )}

      {canReview && mode === 'reject' && (
        <form
          className="review-form"
          onSubmit={(event) => {
            event.preventDefault()
            decide({ decision: 'rejected', reason: reason.trim() || undefined })
          }}
        >
          <label className="field">
            <span className="field__label">Motivo da rejeição (opcional)</span>
            <input value={reason} onChange={(event) => setReason(event.target.value)} maxLength={1000} />
          </label>
          <div className="review-form__actions">
            <button type="submit" className="button button--primary" disabled={submitting}>
              {submitting ? 'Salvando…' : 'Confirmar rejeição'}
            </button>
            <button type="button" className="button button--secondary" onClick={cancel} disabled={submitting}>
              Cancelar
            </button>
          </div>
        </form>
      )}
    </article>
  )
}
