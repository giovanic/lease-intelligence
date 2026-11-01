import { useState, type FormEvent } from 'react'
import type { ExtractedField, ReviewDecisionInput, TypedPair, TypedValue } from '../../types/api'
import { FIELD_OPTIONS, OPTION_LABELS } from '../documents/fieldLabels'

interface CorrectionFormProps {
  field: ExtractedField
  /** The value to start from: the latest correction, or the AI's value. */
  initial: TypedPair
  submitting: boolean
  valueError: boolean
  onSubmit: (input: ReviewDecisionInput) => void
  onCancel: () => void
}

/**
 * A typed form for a reviewer's corrected value (docs/adr/0019): one input
 * kind per value_type. UX only — the API validates the value with the
 * catalog's rules and answers 422 when it does not fit.
 */
export function CorrectionForm({ field, initial, submitting, valueError, onSubmit, onCancel }: CorrectionFormProps) {
  const [draft, setDraft] = useState<Record<string, string>>(() => draftFrom(initial))
  const [reason, setReason] = useState('')
  const set = (key: string) => (event: { target: { value: string } }) =>
    setDraft((current) => ({ ...current, [key]: event.target.value }))

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    onSubmit({ decision: 'corrected', value: valueFrom(field.value_type, draft), reason: reason.trim() || undefined })
  }

  return (
    <form className="review-form" onSubmit={handleSubmit}>
      {field.value_type === 'date' && (
        <label className="field">
          <span className="field__label">Data</span>
          <input type="date" value={draft.date} onChange={set('date')} required />
        </label>
      )}
      {field.value_type === 'integer' && (
        <label className="field">
          <span className="field__label">Número</span>
          <input type="number" step={1} value={draft.integer} onChange={set('integer')} required />
        </label>
      )}
      {field.value_type === 'money' && (
        <div className="review-form__row">
          <label className="field">
            <span className="field__label">Valor</span>
            <input inputMode="decimal" placeholder="18.500,00" value={draft.amount} onChange={set('amount')} required />
          </label>
          <label className="field review-form__currency">
            <span className="field__label">Moeda</span>
            <input value={draft.currency} onChange={set('currency')} maxLength={3} required />
          </label>
        </div>
      )}
      {field.value_type === 'option' && (
        <label className="field">
          <span className="field__label">Opção</span>
          <select value={draft.option} onChange={set('option')} required>
            {(FIELD_OPTIONS[field.key] ?? []).map((option) => (
              <option key={option} value={option}>
                {OPTION_LABELS[option] ?? option}
              </option>
            ))}
          </select>
        </label>
      )}
      {field.value_type === 'text' && (
        <label className="field">
          <span className="field__label">Texto</span>
          <textarea rows={3} maxLength={1000} value={draft.text} onChange={set('text')} required />
        </label>
      )}
      {field.value_type === 'party' && (
        <div className="review-form__row">
          <label className="field">
            <span className="field__label">Nome</span>
            <input value={draft.name} onChange={set('name')} maxLength={300} required />
          </label>
          <label className="field">
            <span className="field__label">CPF/CNPJ (opcional)</span>
            <input value={draft.tax_id} onChange={set('tax_id')} />
          </label>
        </div>
      )}
      {valueError && <p className="field__error">Valor inválido para este campo.</p>}
      <label className="field">
        <span className="field__label">Motivo (opcional)</span>
        <input value={reason} onChange={(event) => setReason(event.target.value)} maxLength={1000} />
      </label>
      <div className="review-form__actions">
        <button type="submit" className="button button--primary" disabled={submitting}>
          {submitting ? 'Salvando…' : 'Salvar correção'}
        </button>
        <button type="button" className="button button--secondary" onClick={onCancel} disabled={submitting}>
          Cancelar
        </button>
      </div>
    </form>
  )
}

function draftFrom(pair: TypedPair): Record<string, string> {
  switch (pair.value_type) {
    case 'date':
      return { date: pair.value.date }
    case 'integer':
      return { integer: String(pair.value.integer) }
    case 'money':
      return { amount: pair.value.amount.replace('.', ','), currency: pair.value.currency }
    case 'option':
      return { option: pair.value.option }
    case 'text':
      return { text: pair.value.text }
    case 'party':
      return { name: pair.value.name, tax_id: pair.value.tax_id ?? '' }
  }
}

/** "18.500,00" or "18500.00" -> "18500.00": a decimal string, never a number. */
function normalizeAmount(input: string): string {
  const trimmed = input.trim().replace(/\s|R\$/g, '')
  return trimmed.includes(',') ? trimmed.replace(/\./g, '').replace(',', '.') : trimmed
}

function valueFrom(valueType: TypedPair['value_type'], draft: Record<string, string>): TypedValue {
  switch (valueType) {
    case 'date':
      return { date: draft.date }
    case 'integer':
      return { integer: Number.parseInt(draft.integer, 10) }
    case 'money':
      return { amount: normalizeAmount(draft.amount), currency: draft.currency.trim().toUpperCase() }
    case 'option':
      return { option: draft.option }
    case 'text':
      return { text: draft.text }
    case 'party':
      return { name: draft.name, tax_id: draft.tax_id.trim() || null }
  }
}
