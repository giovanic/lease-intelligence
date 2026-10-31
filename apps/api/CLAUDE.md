# LEASE INTELLIGENCE — ENGINEERING CONTEXT

## 1. PROJECT IDENTITY

Project: Lease Intelligence

Type: International-ready B2B SaaS

Initial market: Brazil

Business model: Multi-tenant subscription software

Primary customers: Companies that rent and operate multiple commercial properties.

Initial target segments:
- Healthcare networks
- Gyms
- Restaurants
- Retail chains
- Franchises
- Educational institutions
- Companies with distributed operations

Primary objective:

Transform commercial lease agreements and related documents into structured, traceable and actionable business intelligence.

The product centralizes properties, leases, amendments, contractual clauses, financial conditions, obligations, deadlines and document evidence.

The platform uses AI to accelerate document interpretation, but human validation remains essential for critical contractual information.

## 2. PRODUCT PRINCIPLES

The following principles are mandatory:

1. Evidence-first architecture.
2. Human-in-the-loop for critical contractual information.
3. Immutable original documents.
4. Explicit document versioning.
5. Historical preservation of contractual conditions.
6. Strict tenant data isolation.
7. Auditable business operations.
8. Asynchronous document processing.
9. Provider-independent AI and OCR integrations.
10. Modular monolith before microservices.
11. Security and privacy by design.
12. No automatic legal or financial decisions.

Never treat an AI-generated extraction as an approved contractual fact without the required validation.

## 3. INITIAL PRODUCT SCOPE

Core modules:

- Organization Management
- User Management
- Memberships and Permissions
- Portfolio Management
- Property Management
- Lease Management
- Counterparty Management
- Document Management
- Document Versioning
- OCR Processing
- AI Contract Intelligence
- Evidence Management
- Human Review
- Amendment Management
- Contractual Conditions
- Lease Obligations
- Calendar
- Notifications
- Audit Trail
- Dashboard

Out of initial scope:

- Full lease accounting (CPC 06 / IFRS 16)
- Automated legal opinions
- Automated payments
- Electronic signatures
- Advanced ERP integrations
- Native mobile applications
- Autonomous legal decisions

## 4. TECHNOLOGY STACK

Backend:
- Ruby on Rails
- PostgreSQL
- REST API
- Sidekiq
- Redis
- Active Storage

Frontend:
- React
- TypeScript
- Vite

Infrastructure:
- Docker
- PostgreSQL
- Redis
- S3-compatible object storage

Engineering:
- RSpec
- FactoryBot
- Shoulda Matchers
- Pundit
- Devise
- Rack Attack

AI:
- Provider abstraction for OCR
- Provider abstraction for LLM
- Structured JSON extraction
- Schema validation
- Evidence validation
- Human review

Use stable, compatible and explicitly pinned dependency versions.

Do not introduce dependencies without explaining their architectural value.

## 5. ARCHITECTURE

Use a modular monolith.

Organize the backend around business domains, keeping controllers thin and business logic outside controllers.

Suggested domains:

- Identity
- Tenancy
- Portfolio
- Leases
- Documents
- Contract Intelligence
- Contract Review
- Obligations
- Calendar
- Notifications
- Audit
- Integrations

Do not create microservices during the initial development.

Do not create Rails Engines for every domain.

Prefer explicit service objects, policies, domain models and well-defined boundaries.

Avoid unnecessary abstractions.

## 6. MULTI-TENANCY

Architecture:

Shared database.
Shared schema.
Tenant ID on tenant-owned records.
PostgreSQL Row-Level Security.

Core entities:

- User
- Tenant
- Membership

Important rules:

- Users are global identities.
- A user may belong to multiple tenants.
- Membership represents access to an organization.
- Every business record must belong to a tenant.
- Every tenant-scoped operation must validate authorization.
- PostgreSQL RLS is mandatory for tenant-owned tables.
- The application database role must not bypass RLS.
- Use transaction-local tenant context.
- Never allow tenant context leakage through connection pooling.
- Background jobs must explicitly establish tenant context.
- Cross-tenant relationships must be prevented with database constraints where applicable.

Never rely exclusively on Rails default_scope for tenant isolation.

Never trust a tenant_id supplied by the frontend without authorization.

## 7. DOMAIN MODELING RULES

Separate:

- Original documents
- Document versions
- AI extraction results
- Human review decisions
- Approved contractual facts
- Historical contractual conditions

An amendment must not overwrite the original contract.

Contractual conditions must support effective dates and historical validity.

Every critical extracted field must be traceable to its source document and evidence.

AI output must be immutable as an extraction result. Corrections should create new review records or approved representations.

Do not confuse:
- Document upload date
- Document signature date
- Contract effective date
- Contract commencement date
- Contract expiration date

Use database types that preserve their actual semantics. Use date columns for calendar dates without time-of-day semantics.

Use decimal types for financial values. Never use floating-point types for money.

Use explicit currency codes.

## 8. DOCUMENT INTELLIGENCE

Document processing must be asynchronous.

Expected pipeline:

1. Upload.
2. File validation.
3. SHA-256 checksum.
4. Private object storage.
5. PDF text extraction.
6. OCR if necessary.
7. Page normalization.
8. Document classification.
9. Structured AI extraction.
10. Schema validation.
11. Evidence validation.
12. Review workflow.
13. Approved fact publication.

Each processing run must record:

- Provider
- Model
- Model version
- Prompt version
- Input document version
- Processing status
- Token usage where available
- Cost where available
- Execution time
- Errors
- Output version

Never send unrestricted document instructions to the AI model.

Treat uploaded document contents as untrusted input.

## 9. SECURITY

Mandatory security principles:

- Tenant isolation
- RLS
- Pundit authorization
- Private file storage
- Encryption in transit
- Secure secrets management
- Audit trail
- Input validation
- Rate limiting
- Background job isolation
- LGPD compliance considerations

Never expose sensitive contract information in logs.

Never expose storage credentials or permanent public document URLs.

Never implement administrative tenant bypasses without explicit authorization, audit and documented justification.

## 10. BACKEND ENGINEERING RULES

- Keep controllers thin.
- Keep business rules out of controllers.
- Use explicit service objects for complex workflows.
- Use database transactions for multi-record business operations.
- Use database constraints for critical invariants.
- Prefer explicit queries over hidden default scopes.
- Avoid unnecessary callbacks.
- Avoid giant models.
- Use enums carefully and document their meanings.
- Use UUID primary keys.
- Add appropriate database indexes.
- Implement pagination for collections.
- Make asynchronous operations idempotent.
- Handle external provider failures.
- Never assume external APIs are always available.

## 11. API CONVENTIONS

Base path:

/api/v1

Use REST conventions.

Return predictable JSON structures.

Use consistent HTTP status codes.

Validate input parameters.

Enforce authorization at the backend.

Do not trust frontend permissions.

Document endpoints and response schemas.

## 12. FRONTEND CONVENTIONS

Use React with TypeScript.

Keep API communication isolated in a client layer.

Separate:
- Pages
- Components
- Features
- Hooks
- Services
- Types
- State management

Implement loading, empty, error and success states.

The interface should be professional, responsive and suitable for enterprise users.

Contract review must support side-by-side document and extracted-data visualization.

## 13. TESTING

Every business feature must include automated tests.

Mandatory coverage:

- Models
- Policies
- Services
- API requests
- Tenant isolation
- RLS
- Background jobs
- Document processing
- Contract versioning
- Financial calculations
- Review workflows

For security-sensitive features, test both permitted and denied operations.

Never consider a feature complete merely because the happy path works.

## 14. AI ENGINEERING BEHAVIOR

When implementing AI functionality:

- Use provider interfaces.
- Use structured outputs.
- Validate schemas.
- Validate evidence references.
- Preserve original outputs.
- Version prompts.
- Record model versions.
- Handle timeouts and retries.
- Measure accuracy against annotated datasets.
- Never treat model confidence as calibrated probability without validation.

Critical contractual facts require appropriate human review.

## 15. CLAUDE CODE WORKING RULES

Before implementing any feature:

1. Read the relevant product documentation.
2. Read the relevant architecture documentation.
3. Inspect the existing implementation.
4. Identify affected domains.
5. Identify security and tenant implications.
6. Present an implementation plan.
7. Identify required tests.
8. Wait for approval for significant architectural changes.

During implementation:

- Follow existing patterns.
- Do not duplicate existing abstractions.
- Do not silently change architecture.
- Do not introduce unrelated refactoring.
- Do not remove tests to make builds pass.
- Do not weaken security controls.
- Do not fabricate completed work.

After implementation:

1. Run relevant tests.
2. Run lint and static checks.
3. Inspect database migrations.
4. Verify tenant isolation.
5. Summarize changes.
6. Report remaining risks.
7. Update documentation.

## 16. DOCUMENTATION

Maintain:

- docs/architecture/
- docs/adr/
- docs/domain/
- docs/product/
- docs/runbooks/

Architectural decisions must be recorded as ADRs.

Documentation must reflect the actual implementation.

Do not document hypothetical features as implemented.

## 17. DEFINITION OF DONE

A feature is complete only when:

- Business requirements are satisfied.
- Authorization is implemented.
- Tenant isolation is preserved.
- Database integrity is protected.
- Tests pass.
- Error cases are handled.
- Audit requirements are satisfied.
- Documentation is updated.
- No critical security regression is introduced.

## 18. PRIMARY ENGINEERING PRINCIPLE

Lease Intelligence is an evidence-first, multi-tenant contract intelligence platform.

The reliability of contractual information is more important than the amount of information the AI can extract.

Build a maintainable, secure and auditable system.

Prefer explicit engineering decisions over clever abstractions.