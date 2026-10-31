import { useCallback } from 'react'
import { useSearchParams } from 'react-router'

/**
 * Filters and page of a list screen, kept in the query string so a list
 * survives reloads and back/forward (docs/adr/0014). Values are raw
 * strings: each screen must validate them before sending to the API.
 * Changing a filter goes back to page 1.
 */
export function useListParams<K extends string>(filterKeys: readonly K[]) {
  const [params, setParams] = useSearchParams()

  const filters = {} as Record<K, string>
  for (const key of filterKeys) filters[key] = params.get(key) ?? ''

  const rawPage = Number(params.get('page'))
  const page = Number.isInteger(rawPage) && rawPage >= 1 ? rawPage : 1

  const setFilters = useCallback(
    (next: Partial<Record<K, string>>) => {
      setParams((current) => {
        const updated = new URLSearchParams(current)
        for (const [key, value] of Object.entries(next) as [K, string | undefined][]) {
          if (value) updated.set(key, value)
          else updated.delete(key)
        }
        updated.delete('page')
        return updated
      })
    },
    [setParams],
  )

  const setPage = useCallback(
    (nextPage: number) => {
      setParams((current) => {
        const updated = new URLSearchParams(current)
        if (nextPage > 1) updated.set('page', String(nextPage))
        else updated.delete('page')
        return updated
      })
    },
    [setParams],
  )

  return { filters, page, setFilters, setPage }
}

/** The value when it is one of `allowed`, otherwise undefined ("all"). */
export function oneOf<T extends string>(value: string, allowed: readonly T[]): T | undefined {
  return (allowed as readonly string[]).includes(value) ? (value as T) : undefined
}
