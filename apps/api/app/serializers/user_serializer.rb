# Explicit JSON shape for a User — never `to_json` on the model, which
# would expose Devise columns (encrypted_password, tracking IPs, ...).
class UserSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    { id: @user.id, email: @user.email, full_name: @user.full_name }
  end
end
