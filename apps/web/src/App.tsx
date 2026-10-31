import { useCallback } from 'react'
import { StatusMessage } from './components/StatusMessage'
import { useSession } from './hooks/useSession'
import { useTenantSelection } from './hooks/useTenantSelection'
import { LoginPage } from './pages/LoginPage'
import { OrganizationSelectPage } from './pages/OrganizationSelectPage'
import { WorkspacePage } from './pages/WorkspacePage'

// Three screens (login -> organization -> workspace), switched by session
// state. No router yet: picking one is a dependency decision deferred to
// the first phase with real navigation (.claude/rules/frontend.md).
export default function App() {
  const session = useSession()
  const signedIn = session.state.status === 'signedIn'
  const tenant = useTenantSelection(signedIn)

  const { signOut } = session
  const { clear } = tenant
  const handleSignOut = useCallback(async () => {
    clear()
    await signOut()
  }, [clear, signOut])

  switch (session.state.status) {
    case 'loading':
      return (
        <div className="auth-layout">
          <StatusMessage kind="loading" title="Carregando…" />
        </div>
      )
    case 'error':
      return (
        <div className="auth-layout">
          <StatusMessage kind="error" title="Não foi possível conectar." description={session.state.message} onRetry={session.retry} />
        </div>
      )
    case 'signedOut':
      return <LoginPage onSignIn={session.signIn} />
    case 'signedIn':
      if (!tenant.tenantId) {
        return <OrganizationSelectPage me={session.state.me} onSelect={tenant.select} onSignOut={handleSignOut} />
      }
      return (
        <WorkspacePage
          me={session.state.me}
          current={tenant.current}
          onSwitchOrganization={tenant.clear}
          onRetry={tenant.retry}
          onSignOut={handleSignOut}
        />
      )
  }
}
