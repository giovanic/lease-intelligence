import { useState } from 'react'
import { useParams } from 'react-router'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { getExtractionRun } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import type { Evidence, ExtractionRunDetail, MembershipRole } from '../../types/api'
import { REVIEW_LABELS } from '../documents/fieldLabels'
import { DocumentPane } from './DocumentPane'
import { ReviewFieldCard } from './ReviewFieldCard'

/** UX only — mirrors ReviewDecisionPolicy::REVIEWER_ROLES; the API decides. */
const REVIEWER_ROLES: MembershipRole[] = ['owner', 'admin', 'manager', 'analyst']

/**
 * Human review of one AI extraction run (docs/adr/0012, docs/adr/0019):
 * the document on the left, the candidate fields on the right, side by
 * side as the product requires (apps/api/CLAUDE.md §12).
 */
export function ReviewPage() {
  const { leaseId = '', runId = '' } = useParams()
  const { tenantId, membership } = useWorkspace()
  const { state, retry, refresh } = useApiQuery(`review:${tenantId}:${runId}`, () => getExtractionRun(tenantId, runId))

  return (
    <section className="page page--wide">
      <PageHeader
        title="Revisão dos campos extraídos"
        back={{ to: `/leases/${leaseId}`, label: 'Voltar ao contrato' }}
        subtitle="Aprove, corrija ou rejeite cada valor conferindo o trecho no documento."
      />
      <QueryView
        state={state}
        onRetry={retry}
        loadingTitle="Carregando a revisão…"
        notFoundTitle="Extração não encontrada."
      >
        {(run) =>
          run.status !== 'succeeded' ? (
            <StatusMessage kind="empty" title="Esta extração ainda não terminou ou falhou." />
          ) : (
            <ReviewWorkspace run={run} canReview={REVIEWER_ROLES.includes(membership.role)} onDecided={refresh} />
          )
        }
      </QueryView>
    </section>
  )
}

function ReviewWorkspace({
  run,
  canReview,
  onDecided,
}: {
  run: ExtractionRunDetail
  canReview: boolean
  onDecided: () => void
}) {
  const [evidence, setEvidence] = useState<Evidence | null>(null)
  const summary = run.review_summary

  return (
    <>
      <div className="review-summary" role="status">
        {(['pending', 'approved', 'corrected', 'rejected'] as const).map((state) => (
          <span key={state} className="review-summary__item">
            <strong>{summary[state]}</strong> {REVIEW_LABELS[state].toLowerCase()}
            {summary[state] === 1 ? '' : 's'}
          </span>
        ))}
        <span className="muted">
          Os valores aprovados ainda não alimentam as condições do contrato — isso vem na próxima etapa.
        </span>
      </div>
      {!canReview && <p className="muted">Seu papel permite ver a revisão, mas não decidir.</p>}
      <div className="review">
        <DocumentPane run={run} evidence={evidence} />
        <div className="review__fields">
          {run.fields.length === 0 ? (
            <StatusMessage kind="empty" title="Nenhum campo extraído nesta versão." />
          ) : (
            run.fields.map((field) => (
              <ReviewFieldCard
                key={field.id}
                field={field}
                canReview={canReview}
                onShowEvidence={setEvidence}
                activeEvidenceId={evidence?.id ?? null}
                onDecided={onDecided}
              />
            ))
          )}
        </div>
      </div>
    </>
  )
}
