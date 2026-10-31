import { useCallback, useState } from 'react'
import { createDownloadLink } from '../../services/documents'
import { useWorkspace } from '../../state/workspace'

/**
 * Opens a version's file in a new tab through a 5-minute link issued by
 * the API (docs/adr/0015). The tab is opened synchronously, inside the
 * click, so pop-up blockers allow it; it is pointed at the link once the
 * API answers, or closed if it refuses.
 */
export function useOpenDocumentVersion() {
  const { tenantId } = useWorkspace()
  const [openingId, setOpeningId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const open = useCallback(
    async (versionId: string) => {
      const tab = window.open('', '_blank')
      setOpeningId(versionId)
      setError(null)
      try {
        const link = await createDownloadLink(tenantId, versionId)
        if (tab) {
          tab.opener = null
          tab.location.href = link.url
        } else {
          window.location.assign(link.url)
        }
      } catch (err) {
        tab?.close()
        setError(err instanceof Error ? err.message : 'Não foi possível abrir o arquivo.')
      } finally {
        setOpeningId(null)
      }
    },
    [tenantId],
  )

  return { open, openingId, error }
}
