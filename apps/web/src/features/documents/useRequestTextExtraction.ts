import { useCallback, useState } from 'react'
import { ApiError } from '../../services/apiClient'
import { requestTextExtraction } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'

/**
 * Asks the API for a new text extraction of a version (docs/adr/0016) and
 * calls `onRequested` once it is queued, so the list can refresh. Shown
 * only to editors — the API authorizes the request on its own.
 */
export function useRequestTextExtraction(onRequested: () => void) {
  const { tenantId } = useWorkspace()
  const [requestingId, setRequestingId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const request = useCallback(
    async (versionId: string) => {
      setRequestingId(versionId)
      setError(null)
      try {
        await requestTextExtraction(tenantId, versionId)
        onRequested()
      } catch (err) {
        if (err instanceof ApiError && err.code === 'extraction_in_progress') {
          // Someone else (or the upload) already queued one: just show it.
          onRequested()
        } else {
          setError(err instanceof Error ? err.message : 'Não foi possível pedir a extração do texto.')
        }
      } finally {
        setRequestingId(null)
      }
    },
    [tenantId, onRequested],
  )

  return { request, requestingId, error }
}
