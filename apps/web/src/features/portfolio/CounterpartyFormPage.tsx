import { useState, type FormEvent } from 'react'
import { useNavigate, useParams } from 'react-router'
import { FormField } from '../../components/FormField'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { useApiQuery } from '../../hooks/useApiQuery'
import { useSubmission } from '../../hooks/useSubmission'
import { createCounterparty, fetchCounterparty, updateCounterparty } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import type { Counterparty, CounterpartyInput } from '../../types/api'
import { COUNTERPARTY_KIND_LABELS, COUNTERPARTY_KINDS, formatTaxId } from './labels'

const EMPTY: CounterpartyInput = { kind: 'company', legal_name: '', trade_name: '', tax_id: '', email: '', phone: '' }

/** /counterparties/new and /counterparties/:id/edit */
export function CounterpartyFormPage() {
  const { id } = useParams()
  return id ? <EditCounterparty id={id} /> : <CounterpartyForm />
}

function EditCounterparty({ id }: { id: string }) {
  const { tenantId } = useWorkspace()
  const { state, retry } = useApiQuery(`counterparty:${tenantId}:${id}`, () => fetchCounterparty(tenantId, id))

  return (
    <QueryView state={state} onRetry={retry} loadingTitle="Carregando parte…" notFoundTitle="Parte não encontrada.">
      {(counterparty) => <CounterpartyForm counterparty={counterparty} />}
    </QueryView>
  )
}

function inputFrom(counterparty: Counterparty): CounterpartyInput {
  return {
    kind: counterparty.kind,
    legal_name: counterparty.legal_name,
    trade_name: counterparty.trade_name ?? '',
    tax_id: formatTaxId(counterparty.tax_id),
    email: counterparty.email ?? '',
    phone: counterparty.phone ?? '',
  }
}

function CounterpartyForm({ counterparty }: { counterparty?: Counterparty }) {
  const { tenantId, canEdit } = useWorkspace()
  const navigate = useNavigate()
  const [values, setValues] = useState<CounterpartyInput>(() => (counterparty ? inputFrom(counterparty) : EMPTY))
  const { submitting, error, fieldErrors, run } = useSubmission()
  const individual = values.kind === 'individual'

  function set<K extends keyof CounterpartyInput>(key: K, value: CounterpartyInput[K]) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const saved = await run(() =>
      counterparty ? updateCounterparty(tenantId, counterparty.id, values) : createCounterparty(tenantId, values),
    )
    if (saved) navigate(`/counterparties/${saved.id}`)
  }

  const back = counterparty
    ? { to: `/counterparties/${counterparty.id}`, label: counterparty.legal_name }
    : { to: '/counterparties', label: 'Locadores e partes' }

  return (
    <section className="page">
      <PageHeader title={counterparty ? 'Editar parte' : 'Nova parte'} back={back} />

      {!canEdit && <p className="alert">Seu papel nesta organização não permite cadastrar ou editar partes.</p>}

      <form className="card form" onSubmit={handleSubmit} noValidate>
        {error && (
          <div className="alert" role="alert">
            {error}
          </div>
        )}

        <div className="form__grid">
          <FormField label="Tipo" required errors={fieldErrors.kind}>
            <select value={values.kind} onChange={(e) => set('kind', e.target.value as CounterpartyInput['kind'])}>
              {COUNTERPARTY_KINDS.map((kind) => (
                <option key={kind} value={kind}>
                  {COUNTERPARTY_KIND_LABELS[kind]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label={individual ? 'Nome completo' : 'Razão social'} required errors={fieldErrors.legal_name}>
            <input value={values.legal_name} onChange={(e) => set('legal_name', e.target.value)} required />
          </FormField>
          {!individual && (
            <FormField label="Nome fantasia" errors={fieldErrors.trade_name}>
              <input value={values.trade_name} onChange={(e) => set('trade_name', e.target.value)} />
            </FormField>
          )}
          <FormField
            label={individual ? 'CPF' : 'CNPJ'}
            hint="Com ou sem pontuação. Opcional."
            errors={fieldErrors.tax_id}
          >
            <input inputMode="numeric" value={values.tax_id} onChange={(e) => set('tax_id', e.target.value)} />
          </FormField>
          <FormField label="E-mail" errors={fieldErrors.email}>
            <input type="email" value={values.email} onChange={(e) => set('email', e.target.value)} />
          </FormField>
          <FormField label="Telefone" errors={fieldErrors.phone}>
            <input type="tel" value={values.phone} onChange={(e) => set('phone', e.target.value)} />
          </FormField>
        </div>

        <div className="form__actions">
          <button type="button" className="button button--secondary" onClick={() => navigate(back.to)}>
            Cancelar
          </button>
          <button type="submit" className="button button--primary" disabled={submitting || !canEdit}>
            {submitting ? 'Salvando…' : 'Salvar'}
          </button>
        </div>
      </form>
    </section>
  )
}
