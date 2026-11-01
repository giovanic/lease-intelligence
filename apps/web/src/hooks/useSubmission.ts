import { useCallback, useState } from 'react'
import { ApiError } from '../services/apiClient'
import type { ValidationDetails } from '../types/api'

/**
 * State of a form submission: `submitting`, a general error message and
 * the API's per-field 422 messages. `run` resolves to the result, or to
 * undefined when the request failed (the error is then in state). `reset`
 * clears the messages (e.g. when the user cancels the form).
 */
export function useSubmission() {
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [fieldErrors, setFieldErrors] = useState<ValidationDetails>({})

  const run = useCallback(async <T>(request: () => Promise<T>): Promise<T | undefined> => {
    setSubmitting(true)
    setError(null)
    setFieldErrors({})
    try {
      return await request()
    } catch (err) {
      if (err instanceof ApiError && err.code === 'validation_failed') {
        setFieldErrors(err.details)
        setError('Revise os campos destacados.')
      } else if (err instanceof ApiError && err.status === 403) {
        setError('Você não tem permissão para esta ação.')
      } else {
        setError(err instanceof Error ? err.message : 'Erro inesperado.')
      }
      return undefined
    } finally {
      setSubmitting(false)
    }
  }, [])

  const reset = useCallback(() => {
    setError(null)
    setFieldErrors({})
  }, [])

  return { submitting, error, fieldErrors, run, reset }
}
