// JSON shapes returned by the Rails API (apps/api/app/serializers). Keep
// in sync with the serializers and the request specs that encode them.

export type MembershipRole = 'owner' | 'admin' | 'manager' | 'analyst' | 'viewer'

export interface User {
  id: string
  email: string
  full_name: string
}

export interface TenantSummary {
  id: string
  name: string
  slug: string
  /** Whether the organization turned AI field extraction on (docs/adr/0018). */
  ai_extraction_enabled: boolean
}

export interface Membership {
  id: string
  role: MembershipRole
  status: 'active' | 'suspended'
  tenant: TenantSummary
}

/** GET /api/v1/me and POST /api/v1/session */
export interface Me {
  user: User
  memberships: Membership[]
}

export interface ApiErrorBody {
  error: { code: string; message: string; details?: ValidationDetails }
}

/** 422 validation_failed: messages per field, e.g. { "parties[0].role": ["..."] }. */
export type ValidationDetails = Record<string, string[]>

/** meta of every paginated collection (apps/api/app/controllers/concerns/paginated.rb). */
export interface PageMeta {
  page: number
  per_page: number
  total_count: number
  total_pages: number
}

export interface Page<T> {
  data: T[]
  meta: PageMeta
}

export type RecordStatus = 'active' | 'archived'

// Portfolio — PropertySerializer / CounterpartySerializer

export type PropertyType = 'retail' | 'clinic' | 'office' | 'restaurant' | 'gym' | 'school' | 'warehouse' | 'other'

export interface Address {
  street: string
  number: string | null
  complement: string | null
  district: string | null
  city: string
  state: string
  postal_code: string | null
  country_code: string
}

export interface Property {
  id: string
  name: string
  code: string | null
  property_type: PropertyType
  status: RecordStatus
  address: Address
  /** Decimal sent as a string ("152.37") — never parsed into a float. */
  area_sqm: string | null
  created_at: string
  updated_at: string
}

/** Body of POST/PATCH /properties (address fields are flat in the request). */
export interface PropertyInput {
  name: string
  code: string
  property_type: PropertyType
  street: string
  number: string
  complement: string
  district: string
  city: string
  state: string
  postal_code: string
  area_sqm: string
  status?: RecordStatus
}

export type CounterpartyKind = 'individual' | 'company'

export interface Counterparty {
  id: string
  kind: CounterpartyKind
  legal_name: string
  trade_name: string | null
  tax_id: string | null
  email: string | null
  phone: string | null
  status: RecordStatus
  created_at: string
  updated_at: string
}

export interface CounterpartyInput {
  kind: CounterpartyKind
  legal_name: string
  trade_name: string
  tax_id: string
  email: string
  phone: string
  status?: RecordStatus
}

// Leases — LeaseSerializer

export type LeaseStatus = 'draft' | 'active' | 'expired' | 'terminated'
export type LeasePartyRole = 'lessor' | 'guarantor' | 'intervening_party'

export interface LeaseParty {
  id: string
  role: LeasePartyRole
  counterparty: Pick<Counterparty, 'id' | 'kind' | 'legal_name' | 'trade_name'>
}

export interface Lease {
  id: string
  title: string
  code: string | null
  status: LeaseStatus
  notes: string | null
  property: Pick<Property, 'id' | 'name' | 'code'> & Pick<Address, 'city' | 'state'>
  parties: LeaseParty[]
  created_at: string
  updated_at: string
}

export interface LeaseInput {
  title: string
  code: string
  status: LeaseStatus
  notes: string
  property_id: string
  /** Replaces the lease's parties; at least one lessor. */
  parties: { counterparty_id: string; role: LeasePartyRole }[]
}

// Documents — ContractDocumentSerializer / DocumentVersionSerializer

export type DocumentKind = 'original_contract' | 'amendment' | 'other'
export type DocumentContentType = 'application/pdf' | 'image/jpeg' | 'image/png' | 'image/tiff'

/** An immutable uploaded file of a document (docs/adr/0010). */
export interface DocumentVersion {
  id: string
  contract_document_id: string
  version_number: number
  original_filename: string
  content_type: DocumentContentType
  byte_size: number
  sha256: string
  uploaded_by: Pick<User, 'id' | 'full_name'>
  /** The latest text extraction attempt, or null for a version never processed (docs/adr/0016). */
  text_extraction: TextExtraction | null
  /** The latest AI field extraction run, or null when none was requested (docs/adr/0017). */
  extraction_run: ExtractionRun | null
  created_at: string
}

// AI field extraction — ExtractionRunSerializer / ExtractedFieldSerializer (docs/adr/0017)

export type ExtractionRunStatus = 'pending' | 'running' | 'succeeded' | 'failed'

export type ExtractionRunErrorCode =
  | 'rate_limited'
  | 'provider_unavailable'
  | 'timeout'
  | 'output_truncated'
  | 'refused'
  | 'invalid_output'
  | 'text_too_long'
  | 'ai_disabled'
  | 'abandoned'
  | 'internal_error'

/** One AI field extraction over a version's text. Its fields are unreviewed candidates, never facts. */
export interface ExtractionRun {
  id: string
  document_version_id: string
  status: ExtractionRunStatus
  field_count: number | null
  /** Candidates dropped for an invalid value or no evidence found in the text. */
  rejected_field_count: number | null
  error_code: ExtractionRunErrorCode | null
  started_at: string | null
  finished_at: string | null
  created_at: string
}

export type ExtractedFieldKey =
  | 'signature_date'
  | 'effective_date'
  | 'commencement_date'
  | 'expiration_date'
  | 'term_months'
  | 'monthly_rent'
  | 'rent_due_day'
  | 'readjustment_index'
  | 'readjustment_frequency_months'
  | 'guarantee_type'
  | 'security_deposit_amount'
  | 'termination_notice_days'
  | 'renewal_terms'
  | 'early_termination_penalty'
  | 'lessor'
  | 'lessee'
  | 'guarantor'

/** Where a value was read: the quoted span of a page of the extracted text. */
export interface Evidence {
  id: string
  page_number: number
  /** Whether the page's text came from the PDF itself or from OCR. */
  source: 'native' | 'ocr'
  start_offset: number
  end_offset: number
  snippet: string
}

interface ExtractedFieldBase {
  id: string
  key: ExtractedFieldKey
  evidence: Evidence[]
}

/** A candidate value; `value`'s shape follows `value_type`. Money is a decimal string, never a number. */
export type ExtractedField = ExtractedFieldBase &
  (
    | { value_type: 'date'; value: { date: string } }
    | { value_type: 'integer'; value: { integer: number } }
    | { value_type: 'money'; value: { amount: string; currency: string } }
    | { value_type: 'option'; value: { option: string } }
    | { value_type: 'text'; value: { text: string } }
    | { value_type: 'party'; value: { name: string; tax_id: string | null } }
  )

export interface ExtractionRunDetail extends ExtractionRun {
  fields: ExtractedField[]
}

export type TextExtractionStatus = 'pending' | 'running' | 'succeeded' | 'failed'

export type TextExtractionErrorCode =
  | 'unreadable_file'
  | 'encrypted_pdf'
  | 'too_many_pages'
  | 'timeout'
  | 'ocr_unavailable'
  | 'storage_unavailable'
  | 'abandoned'
  | 'internal_error'

/** Status and counts only — the extracted text is not exposed by the API yet. */
export interface TextExtraction {
  id: string
  document_version_id: string
  status: TextExtractionStatus
  page_count: number | null
  native_page_count: number | null
  ocr_page_count: number | null
  error_code: TextExtractionErrorCode | null
  started_at: string | null
  finished_at: string | null
  created_at: string
}

export interface ContractDocument {
  id: string
  lease_id: string
  kind: DocumentKind
  title: string
  /** Newest first. */
  versions: DocumentVersion[]
  created_at: string
  updated_at: string
}

export interface ContractDocumentInput {
  kind: DocumentKind
  title: string
  file: File
}

/** A same-origin URL to the file, valid for 5 minutes, only for this user (docs/adr/0015). */
export interface DownloadLink {
  url: string
  expires_at: string
}

// Organization settings — OrganizationSettingsSerializer (docs/adr/0018)

export interface OrganizationSettings {
  ai_extraction_enabled: boolean
  ai_extraction_changed_at: string | null
  ai_extraction_changed_by: Pick<User, 'id' | 'full_name'> | null
  /** The deployment's configured AI, or null when none; `external` = contracts leave our infrastructure. */
  ai_provider: { name: string; model: string; external: boolean } | null
}
