import type { PageMeta } from '../types/api'

interface PaginationProps {
  meta: PageMeta
  onPage: (page: number) => void
}

export function Pagination({ meta, onPage }: PaginationProps) {
  if (meta.total_pages <= 1) return null

  return (
    <nav className="pagination" aria-label="Paginação">
      <button
        type="button"
        className="button button--secondary"
        disabled={meta.page <= 1}
        onClick={() => onPage(meta.page - 1)}
      >
        Anterior
      </button>
      <span className="muted">
        Página {meta.page} de {meta.total_pages} · {meta.total_count} registros
      </span>
      <button
        type="button"
        className="button button--secondary"
        disabled={meta.page >= meta.total_pages}
        onClick={() => onPage(meta.page + 1)}
      >
        Próxima
      </button>
    </nav>
  )
}
