# Tenant-owned landlord/lessor record (docs/domain/portfolio.md). Not a
# User: no login, no membership. See
# db/migrate/20261031150001_create_counterparties.rb for the RLS policy
# and the database constraints these validations mirror.
class Counterparty < ApplicationRecord
  belongs_to :tenant

  # individual: a natural person (CPF); company: a legal entity (CNPJ).
  enum :kind, { individual: "individual", company: "company" }, validate: true
  # archived: no longer used for new leases, kept for history.
  enum :status, { active: "active", archived: "archived" }, default: "active", validate: true

  normalizes :legal_name, :trade_name, :phone, with: ->(value) { value.strip.presence }
  normalizes :tax_id, with: ->(value) { value.gsub(/\D/, "").presence }
  normalizes :email, with: ->(value) { value.strip.downcase.presence }

  validates :legal_name, presence: true, length: { maximum: 255 }
  validates :trade_name, length: { maximum: 255 }
  validates :phone, length: { maximum: 30 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 255 }, allow_nil: true
  validates :tax_id, uniqueness: { scope: :tenant_id }, allow_nil: true
  validate :tax_id_matches_kind

  private

  def tax_id_matches_kind
    return if tax_id.nil? || kind.nil?

    valid = individual? ? BrazilianTaxId.valid_cpf?(tax_id) : BrazilianTaxId.valid_cnpj?(tax_id)
    errors.add(:tax_id, individual? ? "is not a valid CPF" : "is not a valid CNPJ") unless valid
  end
end
