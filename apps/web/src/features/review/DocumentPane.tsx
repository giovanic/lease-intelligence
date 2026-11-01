import { useCallback, useState } from 'react'
import { QueryView } from '../../components/QueryView'
import { StatusMessage } from '../../components/StatusMessage'
import { useApiQuery } from '../../hooks/useApiQuery'
import { createDownloadLink } from '../../services/documents'
import { getRunPage } from '../../services/review'
import { useWorkspace } from '../../state/workspace'
import type { Evidence, ExtractionRunDetail } from '../../types/api'

interface DocumentPaneProps {
  run: ExtractionRunDetail
  /** The evidence to highlight; switching it opens the text tab on its page. */
  evidence: Evidence | null
}

type Tab = 'document' | 'text'

/**
 * The left side of the review screen (docs/adr/0019): the file in the
 * browser's own viewer (a fresh 5-minute link, docs/adr/0015) and the text
 * of the cited page with the evidence span highlighted. No PDF library.
 */
export function DocumentPane({ run, evidence }: DocumentPaneProps) {
  const [tab, setTab] = useState<Tab>('document')
  const [shownEvidenceId, setShownEvidenceId] = useState<string | null>(null)

  // A new evidence picked on the right switches to its page text, once.
  if (evidence && evidence.id !== shownEvidenceId) {
    setShownEvidenceId(evidence.id)
    setTab('text')
  }

  return (
    <section className="card review-document" aria-label="Documento">
      <div className="review-tabs" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'document'}
          className={`review-tabs__tab${tab === 'document' ? ' review-tabs__tab--active' : ''}`}
          onClick={() => setTab('document')}
        >
          Documento
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'text'}
          disabled={!evidence}
          className={`review-tabs__tab${tab === 'text' ? ' review-tabs__tab--active' : ''}`}
          onClick={() => setTab('text')}
        >
          {evidence ? `Texto da página ${evidence.page_number}` : 'Texto da página'}
        </button>
      </div>
      {tab === 'document' ? <FileView run={run} /> : evidence && <PageText runId={run.id} evidence={evidence} />}
    </section>
  )
}

function FileView({ run }: { run: ExtractionRunDetail }) {
  const { tenantId } = useWorkspace()
  const version = run.document_version
  const { state, retry } = useApiQuery(`review-file:${tenantId}:${version.id}`, () =>
    createDownloadLink(tenantId, version.id),
  )

  return (
    <QueryView state={state} onRetry={retry} loadingTitle="Abrindo o documento…">
      {(link) => (
        <div className="review-file">
          {version.content_type === 'application/pdf' ? (
            <iframe className="review-file__frame" src={link.url} title={version.original_filename} />
          ) : (
            <img className="review-file__image" src={link.url} alt={version.original_filename} />
          )}
          <p className="muted review-file__hint">
            v{version.version_number} · {version.original_filename}. O link vale 5 minutos —{' '}
            <button type="button" className="button button--link" onClick={retry}>
              recarregar
            </button>
            .
          </p>
        </div>
      )}
    </QueryView>
  )
}

function PageText({ runId, evidence }: { runId: string; evidence: Evidence }) {
  const { tenantId } = useWorkspace()
  const { state, retry } = useApiQuery(`review-page:${tenantId}:${runId}:${evidence.page_number}`, () =>
    getRunPage(tenantId, runId, evidence.page_number),
  )
  // The <mark> is keyed by evidence, so each new evidence mounts it and scrolls to it.
  const scrollToMark = useCallback((node: HTMLElement | null) => node?.scrollIntoView({ block: 'center' }), [])

  return (
    <QueryView state={state} onRetry={retry} loadingTitle="Carregando o texto da página…">
      {(page) =>
        page.text.length === 0 ? (
          <StatusMessage kind="empty" title="Página sem texto." />
        ) : (
          <div className="review-text">
            {page.source === 'ocr' && (
              <p className="muted">Texto obtido por OCR: pode ter erros de leitura — confira no documento.</p>
            )}
            <pre className="review-text__body">
              {page.text.slice(0, evidence.start_offset)}
              <mark ref={scrollToMark} key={evidence.id}>
                {page.text.slice(evidence.start_offset, evidence.end_offset)}
              </mark>
              {page.text.slice(evidence.end_offset)}
            </pre>
          </div>
        )
      }
    </QueryView>
  )
}
