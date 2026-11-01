import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { useApiQuery } from '../../hooks/useApiQuery'
import { useSubmission } from '../../hooks/useSubmission'
import { getOrganizationSettings, updateAiExtractionConsent } from '../../services/organization'
import { useWorkspace } from '../../state/workspace'
import type { OrganizationSettings } from '../../types/api'
import { formatDateTime } from '../documents/labels'

/**
 * The organization's settings (docs/adr/0018): the consent for AI field
 * extraction, off until an owner/admin turns it on, with which AI the
 * deployment uses and whether contracts would leave our infrastructure.
 * Everyone sees it; the switch is for owners/admins (the API checks too).
 */
export function OrganizationSettingsPage() {
  const { tenantId, membership } = useWorkspace()
  const { state, retry } = useApiQuery(`organization-settings:${tenantId}`, () => getOrganizationSettings(tenantId))

  return (
    <section className="page">
      <PageHeader title="Configurações" subtitle={membership.tenant.name} />
      <QueryView state={state} onRetry={retry} loadingTitle="Carregando configurações…">
        {(settings) => <AiExtractionCard settings={settings} onChanged={retry} />}
      </QueryView>
    </section>
  )
}

function AiExtractionCard({ settings, onChanged }: { settings: OrganizationSettings; onChanged: () => void }) {
  const { tenantId, canManageOrganization, refreshMembership } = useWorkspace()
  const { submitting, error, run } = useSubmission()
  const provider = settings.ai_provider
  const enabled = settings.ai_extraction_enabled

  async function toggle() {
    const next = !enabled
    if (next && provider?.external) {
      const confirmed = window.confirm(
        `Ao ligar, o texto dos contratos desta organização será enviado a ${providerName(provider.name)}, ` +
          'fora da nossa infraestrutura. Confirmar?',
      )
      if (!confirmed) return
    }
    const result = await run(() => updateAiExtractionConsent(tenantId, next))
    if (result) {
      onChanged()
      refreshMembership()
    }
  }

  return (
    <section className="card section">
      <div className="section__header">
        <h2 className="section__title">Extração de campos por IA</h2>
        <span className={`badge ${enabled ? 'badge--positive' : 'badge--muted'}`}>
          {enabled ? 'Ligada' : 'Desligada'}
        </span>
      </div>

      <p className="muted">
        Quando ligada, a IA lê o texto de cada contrato enviado e sugere datas, valores, reajuste, garantia e partes,
        cada um com o trecho do documento de onde saiu. Nada vira informação oficial sem revisão humana.
      </p>

      <dl className="details">
        <dt>IA configurada</dt>
        <dd>{provider ? providerDescription(provider) : 'Nenhuma IA configurada neste ambiente.'}</dd>
        <dt>Última alteração</dt>
        <dd>
          {settings.ai_extraction_changed_at && settings.ai_extraction_changed_by
            ? `${enabled ? 'Ligada' : 'Desligada'} por ${settings.ai_extraction_changed_by.full_name} em ${formatDateTime(settings.ai_extraction_changed_at)}`
            : 'Nunca alterada (desligada por padrão).'}
        </dd>
      </dl>

      {error && (
        <div className="alert" role="alert">
          {error}
        </div>
      )}

      {canManageOrganization ? (
        <div>
          <button
            type="button"
            className={`button ${enabled ? 'button--secondary' : 'button--primary'}`}
            onClick={toggle}
            disabled={submitting || (!enabled && !provider)}
          >
            {submitting ? 'Salvando…' : enabled ? 'Desligar extração por IA' : 'Ligar extração por IA'}
          </button>
        </div>
      ) : (
        <p className="muted">Somente proprietários e administradores da organização podem alterar.</p>
      )}
    </section>
  )
}

function providerName(name: string): string {
  return name === 'anthropic' ? 'Anthropic (Claude)' : name === 'ollama' ? 'um modelo local (Ollama)' : name
}

function providerDescription(provider: NonNullable<OrganizationSettings['ai_provider']>): string {
  const where = provider.external
    ? 'o texto dos contratos é enviado a um serviço externo'
    : 'o texto dos contratos não sai da nossa infraestrutura'
  const name = providerName(provider.name)
  return `${name.charAt(0).toUpperCase()}${name.slice(1)} — ${provider.model}; ${where}.`
}
