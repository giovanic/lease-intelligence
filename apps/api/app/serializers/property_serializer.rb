# Explicit JSON shape for a Property. area_sqm is a decimal sent as a
# string ("152.37") so no JSON number/float conversion can alter it.
class PropertySerializer
  def initialize(property)
    @property = property
  end

  def as_json(*)
    {
      id: @property.id,
      name: @property.name,
      code: @property.code,
      property_type: @property.property_type,
      status: @property.status,
      address: {
        street: @property.street,
        number: @property.number,
        complement: @property.complement,
        district: @property.district,
        city: @property.city,
        state: @property.state,
        postal_code: @property.postal_code,
        country_code: @property.country_code
      },
      area_sqm: @property.area_sqm&.to_s("F"),
      created_at: @property.created_at,
      updated_at: @property.updated_at
    }
  end
end
