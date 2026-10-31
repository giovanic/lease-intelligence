import type { ApiErrorBody, Page, PageMeta, ValidationDetails } from '../types/api'

// The only place in the SPA that calls fetch (.claude/rules/frontend.md).
// Auth is the httpOnly session cookie the browser sends on its own
// (same-origin, docs/adr/0013) — no token is ever read or stored here.

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  /** Per-field messages of a 422 validation_failed, when the API sent them. */
  readonly details: ValidationDetails

  constructor(status: number, code: string, message: string, details: ValidationDetails = {}) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.details = details
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE'
  body?: unknown
  /** Sent as X-Tenant-Id. The backend validates it against the user's memberships. */
  tenantId?: string
  /** Query string; undefined/empty values are left out. */
  query?: Record<string, string | number | undefined>
}

/** Returns the `data` of the success envelope. */
export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const payload = await send(path, options)
  return (payload as { data: T } | undefined)?.data as T
}

/** For paginated collections: returns `{ data, meta }`. */
export async function apiRequestPage<T>(path: string, options: RequestOptions = {}): Promise<Page<T>> {
  const payload = (await send(path, options)) as { data: T[]; meta: PageMeta }
  return { data: payload.data, meta: payload.meta }
}

async function send(path: string, options: RequestOptions): Promise<unknown> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (options.tenantId) headers['X-Tenant-Id'] = options.tenantId

  let response: Response
  try {
    response = await fetch(`/api/v1${path}${queryString(options.query)}`, {
      method: options.method ?? 'GET',
      headers,
      credentials: 'same-origin',
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    })
  } catch {
    throw new ApiError(0, 'network_error', 'Não foi possível conectar ao servidor.')
  }

  if (response.status === 204) return undefined

  const payload: unknown = await response.json().catch(() => null)

  if (!response.ok) {
    const error = isApiErrorBody(payload) ? payload.error : null
    throw new ApiError(
      response.status,
      error?.code ?? 'unexpected_error',
      error?.message ?? `Erro inesperado (${response.status}).`,
      error?.details,
    )
  }

  return payload
}

function queryString(query: RequestOptions['query']): string {
  if (!query) return ''
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== '') params.set(key, String(value))
  }
  const encoded = params.toString()
  return encoded ? `?${encoded}` : ''
}

function isApiErrorBody(value: unknown): value is ApiErrorBody {
  return (
    typeof value === 'object' &&
    value !== null &&
    'error' in value &&
    typeof (value as ApiErrorBody).error?.code === 'string'
  )
}
