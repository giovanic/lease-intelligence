interface StatusMessageProps {
  kind: 'loading' | 'empty' | 'error'
  title: string
  description?: string
  onRetry?: () => void
}

/** Shared loading / empty / error state (every data view needs all three). */
export function StatusMessage({ kind, title, description, onRetry }: StatusMessageProps) {
  return (
    <div className={`status status--${kind}`} role={kind === 'error' ? 'alert' : 'status'}>
      {kind === 'loading' && <span className="spinner" aria-hidden="true" />}
      <p className="status__title">{title}</p>
      {description && <p className="status__description">{description}</p>}
      {onRetry && (
        <button type="button" className="button button--secondary" onClick={onRetry}>
          Tentar novamente
        </button>
      )}
    </div>
  )
}
