import { useCallback } from 'react'
import { Navigate, Route, Routes, useNavigate } from 'react-router'
import { StatusMessage } from './components/StatusMessage'
import { LeaseDetailPage } from './features/leases/LeaseDetailPage'
import { LeaseFormPage } from './features/leases/LeaseFormPage'
import { LeaseListPage } from './features/leases/LeaseListPage'
import { CounterpartyDetailPage } from './features/portfolio/CounterpartyDetailPage'
import { CounterpartyFormPage } from './features/portfolio/CounterpartyFormPage'
import { CounterpartyListPage } from './features/portfolio/CounterpartyListPage'
import { PropertyDetailPage } from './features/portfolio/PropertyDetailPage'
import { PropertyFormPage } from './features/portfolio/PropertyFormPage'
import { PropertyListPage } from './features/portfolio/PropertyListPage'
import { useSession } from './hooks/useSession'
import { useTenantSelection } from './hooks/useTenantSelection'
import { LoginPage } from './pages/LoginPage'
import { OrganizationSettingsPage } from './features/organization/OrganizationSettingsPage'
import { NotFoundPage } from './pages/NotFoundPage'
import { OrganizationSelectPage } from './pages/OrganizationSelectPage'
import { ReviewPage } from './features/review/ReviewPage'
import { WorkspaceLayout } from './pages/WorkspaceLayout'

// Session and organization gate in front of the router (docs/adr/0014):
// login -> organization -> routed workspace. A deep link opened while
// signed out keeps its URL and renders once the gate is passed.
export default function App() {
  const session = useSession()
  const signedIn = session.state.status === 'signedIn'
  const tenant = useTenantSelection(signedIn)
  const navigate = useNavigate()

  const { signOut } = session
  const { clear } = tenant
  const handleSignOut = useCallback(async () => {
    clear()
    await signOut()
  }, [clear, signOut])

  // A record URL belongs to the organization it was opened in; after a
  // switch, start from the home screen of the new one.
  const handleSwitchOrganization = useCallback(() => {
    clear()
    navigate('/')
  }, [clear, navigate])

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
          <StatusMessage
            kind="error"
            title="Não foi possível conectar."
            description={session.state.message}
            onRetry={session.retry}
          />
        </div>
      )
    case 'signedOut':
      return <LoginPage onSignIn={session.signIn} />
    case 'signedIn':
      if (!tenant.tenantId) {
        return <OrganizationSelectPage me={session.state.me} onSelect={tenant.select} onSignOut={handleSignOut} />
      }
      return (
        // Keyed by tenant: no screen state survives an organization switch.
        <Routes key={tenant.tenantId}>
          <Route
            element={
              <WorkspaceLayout
                me={session.state.me}
                current={tenant.current}
                onSwitchOrganization={handleSwitchOrganization}
                onRetry={tenant.retry}
                onRefresh={tenant.refresh}
                onSignOut={handleSignOut}
              />
            }
          >
            <Route index element={<Navigate to="/leases" replace />} />
            <Route path="leases" element={<LeaseListPage />} />
            <Route path="leases/new" element={<LeaseFormPage />} />
            <Route path="leases/:id" element={<LeaseDetailPage />} />
            <Route path="leases/:id/edit" element={<LeaseFormPage />} />
            <Route path="leases/:leaseId/extraction-runs/:runId/review" element={<ReviewPage />} />
            <Route path="properties" element={<PropertyListPage />} />
            <Route path="properties/new" element={<PropertyFormPage />} />
            <Route path="properties/:id" element={<PropertyDetailPage />} />
            <Route path="properties/:id/edit" element={<PropertyFormPage />} />
            <Route path="counterparties" element={<CounterpartyListPage />} />
            <Route path="counterparties/new" element={<CounterpartyFormPage />} />
            <Route path="counterparties/:id" element={<CounterpartyDetailPage />} />
            <Route path="counterparties/:id/edit" element={<CounterpartyFormPage />} />
            <Route path="settings" element={<OrganizationSettingsPage />} />
            <Route path="*" element={<NotFoundPage />} />
          </Route>
        </Routes>
      )
  }
}
