require "rails_helper"
require "pundit/rspec"

RSpec.describe UserPolicy do
  subject { described_class }

  let(:user) { create(:user) }

  permissions :show? do
    it "allows reading one's own profile" do
      expect(subject).to permit(AuthorizationContext.new(user: user), user)
    end

    it "denies reading another user's profile" do
      expect(subject).not_to permit(AuthorizationContext.new(user: user), create(:user))
    end
  end

  permissions :index?, :create?, :update?, :destroy? do
    it "denies by default" do
      expect(subject).not_to permit(AuthorizationContext.new(user: user), user)
    end
  end
end
