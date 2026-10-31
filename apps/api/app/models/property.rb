# Tenant-owned leased location (docs/domain/portfolio.md). See
# db/migrate/20261031150000_create_properties.rb for the RLS policy and
# the database constraints these validations mirror; the constraints are
# the real guarantee.
class Property < ApplicationRecord
  BRAZILIAN_STATES = %w[
    AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO
  ].freeze

  belongs_to :tenant

  # retail/clinic/office/restaurant/gym/school/warehouse: the operating
  # segments in docs/product/vision.md; other: anything else.
  enum :property_type, {
    retail: "retail", clinic: "clinic", office: "office", restaurant: "restaurant",
    gym: "gym", school: "school", warehouse: "warehouse", other: "other"
  }, validate: true
  # archived: no longer part of the active portfolio, kept for history
  # (future leases reference it, so properties are never hard-deleted).
  enum :status, { active: "active", archived: "archived" }, default: "active", validate: true

  normalizes :name, :street, :number, :complement, :district, :city, with: ->(value) { value.strip.presence }
  normalizes :code, with: ->(value) { value.strip.upcase.presence }
  normalizes :state, :country_code, with: ->(value) { value.strip.upcase }
  normalizes :postal_code, with: ->(value) { value.gsub(/\D/, "").presence }

  validates :name, :street, :city, :state, :country_code, presence: true
  validates :name, :street, :city, :district, :complement, length: { maximum: 255 }
  validates :code, length: { maximum: 50 }, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates :number, length: { maximum: 20 }
  validates :country_code, format: { with: /\A[A-Z]{2}\z/ }
  validates :state, inclusion: { in: BRAZILIAN_STATES }, if: -> { country_code == "BR" }
  validates :state, format: { with: /\A[A-Z]{2}\z/ }
  validates :postal_code, format: { with: /\A\d{8}\z/ }, allow_nil: true
  validates :area_sqm, numericality: { greater_than: 0, less_than: 10**10 }, allow_nil: true
end
