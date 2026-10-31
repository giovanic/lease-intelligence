import type { PickerOption } from '../../components/RecordPicker'
import { listCounterparties, listProperties } from '../../services/portfolio'
import type { Counterparty, LeaseParty } from '../../types/api'
import { formatTaxId } from '../portfolio/labels'

// Searches for the lease form's pickers. Only active records are offered:
// the API refuses to newly link an archived property or counterparty.

const PAGE_SIZE = 30

export async function searchProperties(tenantId: string, text: string): Promise<PickerOption[]> {
  const page = await listProperties(tenantId, { status: 'active', q: text || undefined, per_page: PAGE_SIZE })
  return page.data.map((property) => ({
    id: property.id,
    label: [property.name, property.code, `${property.address.city}/${property.address.state}`].filter(Boolean).join(' · '),
  }))
}

export async function searchCounterparties(tenantId: string, text: string): Promise<PickerOption[]> {
  const page = await listCounterparties(tenantId, { status: 'active', q: text || undefined, per_page: PAGE_SIZE })
  return page.data.map(counterpartyOption)
}

export function counterpartyOption(counterparty: Pick<Counterparty, 'id' | 'legal_name' | 'trade_name'> & { tax_id?: string | null }): PickerOption {
  const taxId = counterparty.tax_id ? formatTaxId(counterparty.tax_id) : null
  return { id: counterparty.id, label: [counterparty.legal_name, counterparty.trade_name, taxId].filter(Boolean).join(' · ') }
}

export function partyOption(party: LeaseParty): PickerOption {
  return counterpartyOption(party.counterparty)
}
