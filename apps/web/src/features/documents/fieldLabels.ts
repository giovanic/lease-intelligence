import type {
  ExtractedField,
  ExtractedFieldKey,
  ExtractionRun,
  ExtractionRunErrorCode,
  ReviewDecisionKind,
  TypedPair,
} from '../../types/api'
import { formatTaxId } from '../portfolio/labels'

/** Names of the AI-extracted fields (FieldExtraction::Catalog, docs/adr/0017), in catalog order. */
export const FIELD_LABELS: Record<ExtractedFieldKey, string> = {
  signature_date: 'Data de assinatura',
  effective_date: 'Início da vigência',
  commencement_date: 'Início da posse',
  expiration_date: 'Término',
  term_months: 'Prazo',
  monthly_rent: 'Aluguel mensal',
  rent_due_day: 'Vencimento do aluguel',
  readjustment_index: 'Índice de reajuste',
  readjustment_frequency_months: 'Periodicidade do reajuste',
  guarantee_type: 'Garantia',
  security_deposit_amount: 'Valor da caução',
  termination_notice_days: 'Aviso prévio',
  renewal_terms: 'Renovação',
  early_termination_penalty: 'Multa por rescisão antecipada',
  lessor: 'Locador',
  lessee: 'Locatário',
  guarantor: 'Fiador',
}

export const OPTION_LABELS: Record<string, string> = {
  igp_m: 'IGP-M',
  ipca: 'IPCA',
  inpc: 'INPC',
  igp_di: 'IGP-DI',
  ivar: 'IVAR',
  other: 'Outro índice',
  security_deposit: 'Caução',
  personal_guarantee: 'Fiança',
  surety_insurance: 'Seguro-fiança',
  capitalization_bond: 'Título de capitalização',
  investment_fund_assignment: 'Cessão de quotas de fundo de investimento',
  none: 'Sem garantia',
}

/** The codes a field of type `option` accepts (FieldExtraction::Catalog). */
export const FIELD_OPTIONS: Partial<Record<ExtractedFieldKey, string[]>> = {
  readjustment_index: ['igp_m', 'ipca', 'inpc', 'igp_di', 'ivar', 'other'],
  guarantee_type: [
    'security_deposit',
    'personal_guarantee',
    'surety_insurance',
    'capitalization_bond',
    'investment_fund_assignment',
    'none',
  ],
}

/** A field's current review state (docs/adr/0019). */
export const REVIEW_LABELS: Record<ReviewDecisionKind | 'pending', string> = {
  pending: 'Pendente',
  approved: 'Aprovado',
  corrected: 'Corrigido',
  rejected: 'Rejeitado',
}

export const REVIEW_BADGES: Record<ReviewDecisionKind | 'pending', string> = {
  pending: 'badge--neutral',
  approved: 'badge--positive',
  corrected: 'badge--positive',
  rejected: 'badge--negative',
}

/** Why a field extraction failed, for the person who can retry it (docs/adr/0017). */
export const EXTRACTION_RUN_ERROR_LABELS: Record<ExtractionRunErrorCode, string> = {
  rate_limited: 'limite de uso da IA atingido',
  provider_unavailable: 'serviço de IA indisponível',
  timeout: 'a IA demorou demais',
  output_truncated: 'resposta da IA incompleta',
  refused: 'a IA recusou o documento',
  invalid_output: 'resposta da IA em formato inválido',
  text_too_long: 'texto longo demais para a IA',
  abandoned: 'processamento interrompido',
  internal_error: 'erro interno',
}

export function isExtractionRunActive(run: ExtractionRun | null): boolean {
  return run?.status === 'pending' || run?.status === 'running'
}

/** "2024-01-10" -> "10/01/2024", without going through Date (no timezone shift). */
function formatDate(iso: string): string {
  const [year, month, day] = iso.split('-')
  return `${day}/${month}/${year}`
}

/** "12345.6" + "BRL" -> "R$ 12.345,60", from the decimal string without float math. */
function formatMoney(amount: string, currency: string): string {
  const [integer, fraction = ''] = amount.split('.')
  const grouped = integer.replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  const value = `${grouped},${fraction.padEnd(2, '0').slice(0, 2)}`
  return currency === 'BRL' ? `R$ ${value}` : `${currency} ${value}`
}

function plural(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`
}

function formatInteger(key: ExtractedFieldKey, value: number): string {
  switch (key) {
    case 'term_months':
      return plural(value, 'mês', 'meses')
    case 'rent_due_day':
      return `dia ${value}`
    case 'readjustment_frequency_months':
      return `a cada ${plural(value, 'mês', 'meses')}`
    case 'termination_notice_days':
      return plural(value, 'dia', 'dias')
    default:
      return String(value)
  }
}

/** The candidate value as a person reads it. */
export function formatFieldValue(field: ExtractedField): string {
  return formatTypedValue(field.key, field)
}

/** A typed value (the AI's or a reviewer's correction) as a person reads it. */
export function formatTypedValue(key: ExtractedFieldKey, pair: TypedPair): string {
  switch (pair.value_type) {
    case 'date':
      return formatDate(pair.value.date)
    case 'integer':
      return formatInteger(key, pair.value.integer)
    case 'money':
      return formatMoney(pair.value.amount, pair.value.currency)
    case 'option':
      return OPTION_LABELS[pair.value.option] ?? pair.value.option
    case 'text':
      return pair.value.text
    case 'party': {
      const taxId = pair.value.tax_id
      if (!taxId) return pair.value.name
      return `${pair.value.name} · ${taxId.length === 11 ? 'CPF' : 'CNPJ'} ${formatTaxId(taxId)}`
    }
  }
}
