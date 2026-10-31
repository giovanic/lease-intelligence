import type { CounterpartyKind, PropertyType, RecordStatus } from '../../types/api'

export const PROPERTY_TYPE_LABELS: Record<PropertyType, string> = {
  retail: 'Varejo',
  clinic: 'Clínica',
  office: 'Escritório',
  restaurant: 'Restaurante',
  gym: 'Academia',
  school: 'Escola',
  warehouse: 'Galpão',
  other: 'Outro',
}

export const PROPERTY_TYPES = Object.keys(PROPERTY_TYPE_LABELS) as PropertyType[]

export const RECORD_STATUS_LABELS: Record<RecordStatus, string> = {
  active: 'Ativo',
  archived: 'Arquivado',
}

export const RECORD_STATUSES = Object.keys(RECORD_STATUS_LABELS) as RecordStatus[]

export const COUNTERPARTY_KIND_LABELS: Record<CounterpartyKind, string> = {
  individual: 'Pessoa física',
  company: 'Pessoa jurídica',
}

export const COUNTERPARTY_KINDS = Object.keys(COUNTERPARTY_KIND_LABELS) as CounterpartyKind[]

/** 01310100 -> 01310-100 */
export function formatPostalCode(value: string | null): string {
  if (!value) return ''
  return value.length === 8 ? `${value.slice(0, 5)}-${value.slice(5)}` : value
}

/** CPF 12345678909 -> 123.456.789-09; CNPJ 12345678000195 -> 12.345.678/0001-95 */
export function formatTaxId(value: string | null): string {
  if (!value) return ''
  if (value.length === 11) return value.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4')
  if (value.length === 14) return value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5')
  return value
}

/** "152.37" -> "152,37 m²", formatted from the decimal string without float math. */
export function formatArea(value: string | null): string {
  if (!value) return ''
  const [integer, fraction = ''] = value.split('.')
  const grouped = integer.replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  const decimals = fraction.padEnd(2, '0').slice(0, 2)
  return `${grouped},${decimals} m²`
}
