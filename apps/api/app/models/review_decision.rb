# A human decision on one ExtractedField (docs/adr/0012, docs/adr/0019):
# `approved` (the AI value as is), `corrected` (approved with the
# reviewer's value, in the same typed columns as the field) or `rejected`.
# Written once, by ContractReview::RecordDecision; the database rejects any
# UPDATE or DELETE (db/migrate/20261101120000_create_review_decisions.rb).
# A field's current state is its latest decision. Not a contract term by
# itself: only ContractualCondition (next phase) may consume it.
class ReviewDecision < ApplicationRecord
  REASON_MAX_LENGTH = 1_000

  belongs_to :tenant
  belongs_to :extracted_field, inverse_of: :review_decisions
  belongs_to :reviewed_by, class_name: "User"

  # approved: the field's value is right; corrected: right after the
  # reviewer's correction (value_* columns); rejected: not usable (reason
  # optional).
  enum :decision, { approved: "approved", corrected: "corrected", rejected: "rejected" }, validate: true
  enum :value_type, ExtractedField.value_types, prefix: :value, validate: true

  validates :reason, length: { maximum: REASON_MAX_LENGTH }, allow_nil: true

  def readonly?
    persisted? || super
  end
end
