require "rails_helper"

RSpec.describe Identity::AuthenticateUser do
  let!(:user) { create(:user, email: "ana@example.com") }

  it "succeeds with the right credentials, case-insensitively on email" do
    result = described_class.call(email: " ANA@example.com ", password: "password123!")

    expect(result).to be_success
    expect(result.value).to eq(user)
  end

  it "fails with :invalid_credentials for a wrong password" do
    result = described_class.call(email: "ana@example.com", password: "nope")

    expect(result).to be_failure
    expect(result.error).to eq(:invalid_credentials)
  end

  it "fails with the same error for an unknown email, still running a password comparison" do
    expect(Devise::Encryptor).to receive(:compare).and_call_original

    result = described_class.call(email: "ghost@example.com", password: "password123!")

    expect(result.error).to eq(:invalid_credentials)
  end

  it "fails for blank input without raising" do
    expect(described_class.call(email: nil, password: nil).error).to eq(:invalid_credentials)
  end
end
