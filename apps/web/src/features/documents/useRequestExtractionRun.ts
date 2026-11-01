import { useCallback, useState } from 'react'
import { ApiError } from '../../services/apiClient'
import { requestExtractionRun } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'

/**
 * Asks the API for a new AI field extraction of a version (docs/adr/0017)
 * and calls `onRequested` once it is queued, so the list can refresh. Shown
 * only to editors — the API authorizes the request on its own.
 */
export function useRequestExtractionRun(onRequested: () => void) {
  const { tenantId } = useWorkspace()
  const [requestingId, setRequestingId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const request = useCallback(
    async (versionId: string) => {
      setRequestingId(versionId)
      setError(null)
      try {
        await requestExtractionRun(tenantId, versionId)
        onRequested()
      } catch (err) {
        if (err instanceof ApiError && err.code === 'extraction_in_progress') {
          // Already queued (by the text extraction or someone else): just show it.
          onRequested()
        } else if (err instanceof ApiError && err.code === 'extraction_disabled') {
          setError('A extração por IA está desligada nesta organização (Configurações).')
        } else if (err instanceof ApiError && err.code === 'extraction_unavailable') {
          setError('A extração de campos por IA não está configurada neste ambiente.')
        } else {
          setError(err instanceof Error ? err.message : 'Não foi possível pedir a extração dos campos.')
        }
      } finally {
        setRequestingId(null)
      }
    },
    [tenantId, onRequested],
  )

  return { request, requestingId, error }
}
