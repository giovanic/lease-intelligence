import type { ReactNode } from 'react'
import type { QueryState } from '../hooks/useApiQuery'
import { StatusMessage } from './StatusMessage'

interface QueryViewProps<T> {
  state: QueryState<T>
  onRetry: () => void
  loadingTitle?: string
  /** Shown for a 404 — also what a record of another organization looks like. */
  notFoundTitle?: string
  children: (data: T) => ReactNode
}

/** Loading and error states of a useApiQuery; the success state is `children`. */
export function QueryView<T>({ state, onRetry, loadingTitle, notFoundTitle, children }: QueryViewProps<T>) {
  switch (state.status) {
    case 'loading':
      return <StatusMessage kind="loading" title={loadingTitle ?? 'Carregando…'} />
    case 'error':
      if (state.notFound) {
        return (
          <StatusMessage
            kind="empty"
            title={notFoundTitle ?? 'Registro não encontrado.'}
            description="Ele pode ter sido removido ou pertencer a outra organização."
          />
        )
      }
      return <StatusMessage kind="error" title="Não foi possível carregar." description={state.message} onRetry={onRetry} />
    case 'success':
      return <>{children(state.data)}</>
  }
}
