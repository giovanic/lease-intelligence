# The signed-in user plus the organizations they can select
# (Identity::SelectableMemberships). Shared by POST /api/v1/session and
# GET /api/v1/me so the SPA gets the same shape from both.
class MeSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    {
      user: UserSerializer.new(@user).as_json,
      memberships: Identity::SelectableMemberships.all(@user).map { |m| MembershipSerializer.new(m).as_json }
    }
  end
end
