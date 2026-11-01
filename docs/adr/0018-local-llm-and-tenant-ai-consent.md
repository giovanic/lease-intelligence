# ADR-0018: Local LLM (Ollama) and Per-Organization AI Consent

## Context

ADR-0017 shipped contract field extraction with one adapter, Claude. Two
facts about it:

- It is **paid per token** and **sends contract text — including names
  and CPF/CNPJ — to a third party**. ADR-0017 left the LGPD prerequisites
  (processor agreement, international transfer basis, consent per
  organization) as open items.
- It is **global**: once `ANTHROPIC_API_KEY` is set, every version of
  every organization goes to the provider. An organization has no say.

The `Llm` interface (ADR-0009) was built so a second vendor is one more
adapter. Ollama serves open-weight models on our own hardware over a
local HTTP API, with JSON-Schema-constrained output (`format`). The
development machine already runs Ollama 0.23 with an 8 GB GPU, enough for
7–8B models.

## Problem

Offer a field extraction path with no per-token cost and no third-party
processor, keep Claude available where its quality is wanted, and make
sending any organization's contracts to an AI an explicit decision of
that organization — off until someone with authority turns it on.

## Decision

### Ollama adapter (`Llm::OllamaProvider`)

- `POST {OLLAMA_URL}/api/chat` with `stream: false`, the instructions as a
  `system` message and the document alone as the `user` message (same
  separation as ADR-0017), `format: <the catalog's JSON Schema>`, and
  `options: { temperature: 0, num_ctx: OLLAMA_NUM_CTX }`.
- Plain `Net::HTTP` from the standard library: there is no official
  Ruby SDK, and the API is two endpoints — a community gem would add a
  dependency for nothing.
- Defaults: `OLLAMA_URL=http://127.0.0.1:11434`, `OLLAMA_MODEL=qwen2.5:7b`
  (multilingual, follows JSON Schema well at this size, ~4.7 GB),
  `OLLAMA_NUM_CTX=32768`.
- **Cloud models are refused.** Ollama names ending in `:cloud`/`-cloud`
  run on ollama.com, not on the host — content would leave. The adapter
  raises at configuration time for such a name. `OLLAMA_URL` may point at
  another host we operate (a GPU server); that is a deployment decision,
  documented, not blocked.
- Recorded on the run: `provider = "ollama"`, `model` = the configured
  name, `model_version` = `name@digest` (first 12 hex chars, from
  `/api/tags`, so a re-pulled model is visible), `effort = "n/a"`, tokens
  from `prompt_eval_count`/`eval_count`. No cache tokens.
- Failures map to the existing `Llm` errors: connection refused or 5xx →
  `UnavailableError` (also a model that is not pulled: 404); read timeout
  (600 s) → `TimeoutError`; `done_reason: "length"` → `TruncatedError`;
  content that is not a JSON object → `InvalidOutputError`.

### Input limit per provider

Ollama silently drops the start of a prompt longer than `num_ctx`. Each
provider now exposes `max_input_characters`; `ExtractFields` fails with
`text_too_long` above it instead of sending a truncated contract. Ollama:
`(num_ctx − 8 192 reserved for instructions and answer) × 3` characters
(a conservative 3 characters per token for Portuguese) — about 74 000
characters, roughly 25–35 pages, at the default context. Claude keeps
1 500 000.

### Provider selection

`LLM_PROVIDER=ollama` or `anthropic`. Unset: Anthropic when its key is
configured (ADR-0017 behavior), otherwise none — the feature is off. The
choice is per deployment, not per organization: an organization decides
*whether* its documents go to the AI, the operator decides *which* AI.

### Per-organization consent

- `tenants.ai_extraction_enabled` (boolean, **default false**, existing
  organizations included), plus `ai_extraction_changed_at` and
  `ai_extraction_changed_by_id` (who last turned it on or off, and when).
  `tenants` has no RLS (ADR-0003); the setting is only ever read and
  written for the tenant resolved by `TenantScoped`.
- `GET /api/v1/organization_settings` (any active member) and
  `PATCH /api/v1/organization_settings` (owner/admin) — the response also
  says which provider is configured and whether it sends content outside
  our infrastructure, so the person deciding sees what they agree to.
- Off: no run is requested after a text extraction; the manual request
  answers 422 `extraction_disabled`; a run already queued when it was
  turned off fails with the new error code `ai_disabled` before any
  provider call.
- The SPA gains a "Configurações" screen with the switch (owner/admin) and
  the documents table says "IA desligada" instead of offering a run.

## Alternatives considered

- **Free tiers of cloud LLM APIs** — no cost, but they typically allow the
  provider to use submitted data, and the content still leaves.
  Rejected for contracts.
- **Replace Claude with Ollama** — simpler, but loses the higher-quality
  option before any measurement says the local model is enough.
- **Consent per provider** (opt in to "local AI" and "external AI"
  separately) — finer, but two switches for a choice the operator already
  makes per deployment. Revisit if one deployment ever offers both.
- **An `ollama-ai` gem** — no benefit over two `Net::HTTP` calls.

## Consequences

- Positive: an extraction path with no per-token cost and no third-party
  processor; organizations opt in explicitly, with who/when recorded; the
  same evidence check and review apply whatever the model.
- Negative: local 7B quality is expected to be below Claude's and is
  unmeasured (no annotated dataset yet — the evidence check drops
  invented quotes, but cannot catch a wrong value with a real quote);
  long contracts beyond ~25–35 pages hit `text_too_long` at the default
  context; production needs GPU capacity; a newly created organization
  never gets AI extraction until an owner/admin turns it on.

## Security implications

- Ollama keeps content on our hosts; cloud model names are refused so a
  configuration slip cannot route contracts to ollama.com. The Ollama API
  has no authentication: it must listen on loopback or a private network
  only (its default is `127.0.0.1`).
- The consent switch is authorized by Pundit (owner/admin), and only for
  the current tenant; the change is recorded on the tenant row (there is
  no audit module yet — ADR pending).
- Unchanged from ADR-0017: document text only in the user turn, schema-
  constrained output, evidence checked against stored text, nothing
  becomes a fact without human review.

## Implementation status

**Accepted — implemented** (`feat/ollama-e-consentimento-ia`):
`Llm::OllamaProvider` (+ `Transport`), provider selection in `Llm.provider`,
`max_input_characters` per provider, `tenants.ai_extraction_*`,
`Organizations::UpdateAiConsent`, `GET/PATCH /api/v1/organization_settings`
(`OrganizationSettingsPolicy`), consent checks in
`FieldExtraction::RequestRun`/`StartRun` (`ai_disabled`), the
"Configurações" screen and "IA desligada" in the documents table.

**Measured on the development machine** (RTX 4060 Laptop, 8 GB;
`qwen2.5:7b@845dbda0ea48`) with a realistic 2-page contract through the
real pipeline: 15 fields, 0 rejected, every quote found in the stored
text; parties' CNPJ/CPF right. 177 s at `num_ctx` 32768 (the model spilled
17% to the CPU) and 59 s at 16384 (100% GPU), same output. Quality
observations: it copied the same date into `effective_date` and
`commencement_date` where the contract only said "com início em", and
missed the renewal clause. One contract is not a measurement — the
annotated dataset is still to be built.
