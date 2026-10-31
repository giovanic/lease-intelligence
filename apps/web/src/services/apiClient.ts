import type { ApiErrorBody } from '../types/api'

// The only place in the SPA that calls fetch (.claude/rules/frontend.md).
// Auth is the httpOnly session cookie the browser sends on its own
// (same-origin, docs/adr/0013) — no token is ever read or stored here.

export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'DELETE'
  body?: unknown
  /** Sent as X-Tenant-Id. The backend validates it against the user's memberships. */
  tenantId?: string
}

export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (options.tenantId) headers['X-Tenant-Id'] = options.tenantId

  let response: Response
  try {
    response = await fetch(`/api/v1${path}`, {
      method: options.method ?? 'GET',
      headers,
      credentials: 'same-origin',
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    })
  } catch {
    throw new ApiError(0, 'network_error', 'Não foi possível conectar ao servidor.')
  }

  if (response.status === 204) return undefined as T

  const payload: unknown = await response.json().catch(() => null)

  if (!response.ok) {
    const error = isApiErrorBody(payload) ? payload.error : null
    throw new ApiError(
      response.status,
      error?.code ?? 'unexpected_error',
      error?.message ?? `Erro inesperado (${response.status}).`,
    )
  }

  return (payload as { data: T }).data
}

function isApiErrorBody(value: unknown): value is ApiErrorBody {
  return (
    typeof value === 'object' &&
    value !== null &&
    'error' in value &&
    typeof (value as ApiErrorBody).error?.code === 'string'
  )
}
