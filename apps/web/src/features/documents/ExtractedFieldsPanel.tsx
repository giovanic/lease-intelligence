import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { getExtractionRun } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'
import type { ExtractedField } from '../../types/api'
import { FIELD_LABELS, formatFieldValue } from './fieldLabels'

/**
 * The candidate fields of one AI extraction run, each with the quoted
 * evidence it was read from (docs/adr/0011, docs/adr/0017). Read-only and
 * explicitly marked as unreviewed: approving a value is the review step,
 * which does not exist yet.
 */
export function ExtractedFieldsPanel({ runId }: { runId: string }) {
  const { tenantId } = useWorkspace()
  const { state, retry } = useApiQuery(`extraction-run:${tenantId}:${runId}`, () => getExtractionRun(tenantId, runId))

  return (
    <div className="extracted-fields">
      <QueryView
        state={state}
        onRetry={retry}
        loadingTitle="Carregando campos…"
        notFoundTitle="Extração não encontrada."
      >
        {(run) => (
          <>
            <p className="extracted-fields__notice" role="note">
              <strong>Extraído por IA, não revisado.</strong> Confira cada valor no trecho citado antes de usá-lo.
              {rejectedNotice(run.rejected_field_count ?? 0)}
            </p>
            {run.fields.length === 0 ? (
              <StatusMessage kind="empty" title="Nenhum campo encontrado no texto." />
            ) : (
              <dl className="extracted-fields__list">
                {run.fields.map((field) => (
                  <FieldRow key={field.id} field={field} />
                ))}
              </dl>
            )}
          </>
        )}
      </QueryView>
    </div>
  )
}

function rejectedNotice(count: number): string {
  if (count === 0) return ''
  if (count === 1) return ' 1 valor foi descartado: inválido ou sem trecho correspondente no texto.'
  return ` ${count} valores foram descartados: inválidos ou sem trecho correspondente no texto.`
}

function FieldRow({ field }: { field: ExtractedField }) {
  return (
    <div className="extracted-fields__item">
      <dt>{FIELD_LABELS[field.key]}</dt>
      <dd>
        <span className="extracted-fields__value">{formatFieldValue(field)}</span>
        {field.evidence.map((evidence) => (
          <blockquote key={evidence.id} className="extracted-fields__evidence">
            <span className="muted">
              Página {evidence.page_number}
              {evidence.source === 'ocr' && ' · OCR'}
            </span>
            <q>{evidence.snippet}</q>
          </blockquote>
        ))}
      </dd>
    </div>
  )
}
