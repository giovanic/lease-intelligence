import { useState, type FormEvent } from 'react'
import { ApiError } from '../services/apiClient'

interface LoginPageProps {
  onSignIn: (email: string, password: string) => Promise<void>
}

export function LoginPage({ onSignIn }: LoginPageProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setSubmitting(true)
    setError(null)
    try {
      await onSignIn(email.trim(), password)
    } catch (err) {
      setError(loginErrorMessage(err))
      setSubmitting(false)
    }
  }

  return (
    <main className="auth-layout">
      <form className="card auth-card" onSubmit={handleSubmit} noValidate>
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">LI</span>
          <span className="brand__name">Lease Intelligence</span>
        </div>
        <h1 className="auth-card__title">Entrar</h1>
        <p className="muted">Acesse sua carteira de contratos.</p>

        {error && (
          <div className="alert" role="alert">
            {error}
          </div>
        )}

        <label className="field">
          <span className="field__label">E-mail</span>
          <input
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={submitting}
          />
        </label>

        <label className="field">
          <span className="field__label">Senha</span>
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={submitting}
          />
        </label>

        <button type="submit" className="button button--primary" disabled={submitting || !email || !password}>
          {submitting ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </main>
  )
}

function loginErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === 'invalid_credentials') return 'E-mail ou senha inválidos.'
    if (error.status === 429) return 'Muitas tentativas. Aguarde um minuto e tente novamente.'
    return error.message
  }
  return 'Não foi possível entrar. Tente novamente.'
}
