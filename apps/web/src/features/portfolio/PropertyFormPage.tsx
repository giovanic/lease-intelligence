import { useState, type FormEvent } from 'react'
import { useNavigate, useParams } from 'react-router'
import { FormField } from '../../components/FormField'
import { PageHeader } from '../../components/PageHeader'
import { QueryView } from '../../components/QueryView'
import { useApiQuery } from '../../hooks/useApiQuery'
import { useSubmission } from '../../hooks/useSubmission'
import { createProperty, fetchProperty, updateProperty } from '../../services/portfolio'
import { useWorkspace } from '../../state/workspace'
import type { Property, PropertyInput } from '../../types/api'
import { formatPostalCode, PROPERTY_TYPE_LABELS, PROPERTY_TYPES } from './labels'

const EMPTY: PropertyInput = {
  name: '',
  code: '',
  property_type: 'retail',
  street: '',
  number: '',
  complement: '',
  district: '',
  city: '',
  state: '',
  postal_code: '',
  area_sqm: '',
}

/** /properties/new and /properties/:id/edit */
export function PropertyFormPage() {
  const { id } = useParams()
  return id ? <EditProperty id={id} /> : <PropertyForm />
}

function EditProperty({ id }: { id: string }) {
  const { tenantId } = useWorkspace()
  const { state, retry } = useApiQuery(`property:${tenantId}:${id}`, () => fetchProperty(tenantId, id))

  return (
    <QueryView state={state} onRetry={retry} loadingTitle="Carregando imóvel…" notFoundTitle="Imóvel não encontrado.">
      {(property) => <PropertyForm property={property} />}
    </QueryView>
  )
}

function inputFrom(property: Property): PropertyInput {
  const { address } = property
  return {
    name: property.name,
    code: property.code ?? '',
    property_type: property.property_type,
    street: address.street,
    number: address.number ?? '',
    complement: address.complement ?? '',
    district: address.district ?? '',
    city: address.city,
    state: address.state,
    postal_code: formatPostalCode(address.postal_code),
    area_sqm: property.area_sqm?.replace('.', ',') ?? '',
  }
}

function PropertyForm({ property }: { property?: Property }) {
  const { tenantId, canEdit } = useWorkspace()
  const navigate = useNavigate()
  const [values, setValues] = useState<PropertyInput>(() => (property ? inputFrom(property) : EMPTY))
  const { submitting, error, fieldErrors, run } = useSubmission()

  function set<K extends keyof PropertyInput>(key: K, value: PropertyInput[K]) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    // The decimal comma typed in Brazil is sent as the API's decimal point.
    const body = { ...values, area_sqm: values.area_sqm.trim().replace(',', '.') }
    const saved = await run(() =>
      property ? updateProperty(tenantId, property.id, body) : createProperty(tenantId, body),
    )
    if (saved) navigate(`/properties/${saved.id}`)
  }

  const back = property
    ? { to: `/properties/${property.id}`, label: property.name }
    : { to: '/properties', label: 'Imóveis' }

  return (
    <section className="page">
      <PageHeader title={property ? 'Editar imóvel' : 'Novo imóvel'} back={back} />

      {!canEdit && <p className="alert">Seu papel nesta organização não permite cadastrar ou editar imóveis.</p>}

      <form className="card form" onSubmit={handleSubmit} noValidate>
        {error && (
          <div className="alert" role="alert">
            {error}
          </div>
        )}

        <div className="form__grid">
          <FormField label="Nome" required errors={fieldErrors.name}>
            <input value={values.name} onChange={(e) => set('name', e.target.value)} required />
          </FormField>
          <FormField label="Código interno" hint="Ex.: SP-014. Único na organização." errors={fieldErrors.code}>
            <input value={values.code} onChange={(e) => set('code', e.target.value)} />
          </FormField>
          <FormField label="Tipo" required errors={fieldErrors.property_type}>
            <select
              value={values.property_type}
              onChange={(e) => set('property_type', e.target.value as PropertyInput['property_type'])}
            >
              {PROPERTY_TYPES.map((type) => (
                <option key={type} value={type}>
                  {PROPERTY_TYPE_LABELS[type]}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Área (m²)" hint="Ex.: 152,37" errors={fieldErrors.area_sqm}>
            <input inputMode="decimal" value={values.area_sqm} onChange={(e) => set('area_sqm', e.target.value)} />
          </FormField>
        </div>

        <h2 className="section__title">Endereço</h2>
        <div className="form__grid">
          <FormField label="Logradouro" required errors={fieldErrors.street}>
            <input value={values.street} onChange={(e) => set('street', e.target.value)} required />
          </FormField>
          <FormField label="Número" errors={fieldErrors.number}>
            <input value={values.number} onChange={(e) => set('number', e.target.value)} />
          </FormField>
          <FormField label="Complemento" errors={fieldErrors.complement}>
            <input value={values.complement} onChange={(e) => set('complement', e.target.value)} />
          </FormField>
          <FormField label="Bairro" errors={fieldErrors.district}>
            <input value={values.district} onChange={(e) => set('district', e.target.value)} />
          </FormField>
          <FormField label="Cidade" required errors={fieldErrors.city}>
            <input value={values.city} onChange={(e) => set('city', e.target.value)} required />
          </FormField>
          <FormField label="UF" required errors={fieldErrors.state}>
            <input value={values.state} maxLength={2} onChange={(e) => set('state', e.target.value)} required />
          </FormField>
          <FormField label="CEP" errors={fieldErrors.postal_code}>
            <input inputMode="numeric" value={values.postal_code} onChange={(e) => set('postal_code', e.target.value)} />
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
