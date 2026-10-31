import { useState, type FormEvent } from 'react'
import { useNavigate, useParams } from 'react-router'
import { FormField } from '../../components/FormField'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { RecordPicker, type PickerOption } from '../../components/RecordPicker'
import { translateError } from '../../components/validationMessages'
import { useApiQuery } from '../../hooks/useApiQuery'
import { useSubmission } from '../../hooks/useSubmission'
import { createLease, fetchLease, updateLease } from '../../services/leases'
import { useWorkspace } from '../../state/workspace'
import type { Lease, LeaseInput, LeasePartyRole, LeaseStatus } from '../../types/api'
import { LEASE_STATUS_LABELS, LEASE_STATUSES, PARTY_ROLE_LABELS, PARTY_ROLES } from './labels'
import { partyOption, searchCounterparties, searchProperties } from './pickers'

interface PartyRow {
  /** Stable React key; not sent to the API. */
  key: number
  counterparty: PickerOption | null
  role: LeasePartyRole
}

interface FormValues {
  title: string
  code: string
  status: LeaseStatus
  notes: string
  property: PickerOption | null
  parties: PartyRow[]
}

let nextRowKey = 1
const newRow = (role: LeasePartyRole): PartyRow => ({ key: nextRowKey++, counterparty: null, role })

/** /leases/new and /leases/:id/edit */
export function LeaseFormPage() {
  const { id } = useParams()
  return id ? <EditLease id={id} /> : <LeaseForm />
}

function EditLease({ id }: { id: string }) {
  const { tenantId } = useWorkspace()
  const { state, retry } = useApiQuery(`lease:${tenantId}:${id}`, () => fetchLease(tenantId, id))

  return (
    <QueryView state={state} onRetry={retry} loadingTitle="Carregando contrato…" notFoundTitle="Contrato não encontrado.">
      {(lease) => <LeaseForm lease={lease} />}
    </QueryView>
  )
}

function valuesFrom(lease?: Lease): FormValues {
  if (!lease) {
    return { title: '', code: '', status: 'draft', notes: '', property: null, parties: [newRow('lessor')] }
  }
  return {
    title: lease.title,
    code: lease.code ?? '',
    status: lease.status,
    notes: lease.notes ?? '',
    property: { id: lease.property.id, label: lease.property.name },
    parties: lease.parties.map((party) => ({ key: nextRowKey++, counterparty: partyOption(party), role: party.role })),
  }
}

function LeaseForm({ lease }: { lease?: Lease }) {
  const { tenantId, canEdit } = useWorkspace()
  const navigate = useNavigate()
  const [values, setValues] = useState<FormValues>(() => valuesFrom(lease))
  const [missingParty, setMissingParty] = useState(false)
  const { submitting, error, fieldErrors, run } = useSubmission()
  // Mirrors the API rule (Leases::LeaseWriter); the API still enforces it.
  const propertyLocked = lease !== undefined && lease.status !== 'draft'

  function set<K extends keyof FormValues>(key: K, value: FormValues[K]) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  function updateRow(key: number, change: Partial<PartyRow>) {
    set(
      'parties',
      values.parties.map((row) => (row.key === key ? { ...row, ...change } : row)),
    )
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    // A row without a counterparty would come back as "not found"; ask for it here.
    if (values.parties.some((row) => !row.counterparty)) {
      setMissingParty(true)
      return
    }
    setMissingParty(false)

    const body: LeaseInput = {
      title: values.title,
      code: values.code,
      status: values.status,
      notes: values.notes,
      property_id: values.property?.id ?? '',
      parties: values.parties.map((row) => ({ counterparty_id: row.counterparty?.id ?? '', role: row.role })),
    }
    const saved = await run(() => (lease ? updateLease(tenantId, lease.id, body) : createLease(tenantId, body)))
    if (saved) navigate(`/leases/${saved.id}`)
  }

  const back = lease ? { to: `/leases/${lease.id}`, label: lease.title } : { to: '/leases', label: 'Contratos' }
  const partiesErrors = fieldErrors.parties

  return (
    <section className="page">
      <PageHeader title={lease ? 'Editar contrato' : 'Novo contrato'} back={back} />

      {!canEdit && <p className="alert">Seu papel nesta organização não permite cadastrar ou editar contratos.</p>}

      <form className="card form" onSubmit={handleSubmit} noValidate>
        {error && (
          <div className="alert" role="alert">
            {error}
          </div>
        )}

        <div className="form__grid">
          <FormField label="Título" required hint="Ex.: Locação Clínica Boa Viagem" errors={fieldErrors.title}>
            <input value={values.title} onChange={(e) => set('title', e.target.value)} required />
          </FormField>
          <FormField label="Código interno" hint="Único na organização. Opcional." errors={fieldErrors.code}>
            <input value={values.code} onChange={(e) => set('code', e.target.value)} />
          </FormField>
          <FormField label="Situação" required errors={fieldErrors.status}>
            <select value={values.status} onChange={(e) => set('status', e.target.value as LeaseStatus)}>
              {LEASE_STATUSES.map((status) => (
                <option key={status} value={status}>
                  {LEASE_STATUS_LABELS[status]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField
            label="Imóvel"
            required
            hint={propertyLocked ? 'O imóvel só pode ser trocado enquanto o contrato é rascunho.' : undefined}
            errors={fieldErrors.property_id}
          >
            <RecordPicker
              label="imóvel"
              value={values.property}
              onChange={(option) => set('property', option)}
              search={(text) => searchProperties(tenantId, text)}
              searchKey={`property-picker:${tenantId}`}
              placeholder="Buscar imóvel por nome, código ou cidade"
              disabled={propertyLocked}
              invalid={Boolean(fieldErrors.property_id)}
            />
          </FormField>
        </div>

        <fieldset className="parties">
          <legend className="section__title">Partes</legend>
          <p className="muted">Inclua ao menos um locador. Cada pessoa ou empresa aparece uma vez.</p>
          {partiesErrors && <p className="field__error">{partiesErrors.map(translateError).join('; ')}</p>}
          {missingParty && <p className="field__error">Selecione a pessoa ou empresa de cada linha, ou remova a linha.</p>}

          {values.parties.map((row, index) => {
            const counterpartyErrors = fieldErrors[`parties[${index}].counterparty_id`]
            const roleErrors = fieldErrors[`parties[${index}].role`]
            return (
              <div className="parties__row" key={row.key}>
                <FormField label="Pessoa ou empresa" errors={counterpartyErrors}>
                  <RecordPicker
                    label={`parte ${index + 1}`}
                    value={row.counterparty}
                    onChange={(option) => updateRow(row.key, { counterparty: option })}
                    search={(text) => searchCounterparties(tenantId, text)}
                    searchKey={`counterparty-picker:${tenantId}`}
                    placeholder="Buscar por nome ou CPF/CNPJ"
                    invalid={Boolean(counterpartyErrors) || (missingParty && !row.counterparty)}
                  />
                </FormField>
                <FormField label="Papel" errors={roleErrors}>
                  <select
                    value={row.role}
                    onChange={(e) => updateRow(row.key, { role: e.target.value as LeasePartyRole })}
                  >
                    {PARTY_ROLES.map((role) => (
                      <option key={role} value={role}>
                        {PARTY_ROLE_LABELS[role]}
                      </option>
                    ))}
                  </select>
                </FormField>
                <button
                  type="button"
                  className="button button--link parties__remove"
                  onClick={() => set('parties', values.parties.filter((other) => other.key !== row.key))}
                >
                  Remover
                </button>
              </div>
            )
          })}

          <button
            type="button"
            className="button button--secondary"
            onClick={() => set('parties', [...values.parties, newRow(values.parties.length === 0 ? 'lessor' : 'guarantor')])}
          >
            Adicionar parte
          </button>
        </fieldset>

        <FormField label="Observações" errors={fieldErrors.notes}>
          <textarea rows={4} value={values.notes} onChange={(e) => set('notes', e.target.value)} />
        </FormField>

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
