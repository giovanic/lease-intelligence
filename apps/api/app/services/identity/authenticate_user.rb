module Identity
  # Checks email + password for POST /api/v1/session. Returns the User on
  # success, `:invalid_credentials` for every failure — unknown email,
  # wrong password, or an account Devise considers inactive — so callers
  # cannot tell which one happened. When the email is unknown a dummy
  # bcrypt comparison still runs, keeping response time from revealing
  # whether an account exists.
  class AuthenticateUser
    def self.call(email:, password:)
      new(email: email, password: password).call
    end

    def initialize(email:, password:)
      @email = email.to_s
      @password = password.to_s
    end

    def call
      user = User.find_for_authentication(email: @email)

      if user.nil?
        Devise::Encryptor.compare(User, self.class.dummy_digest, @password)
        return ServiceResult.failure(:invalid_credentials)
      end

      if user.valid_password?(@password) && user.active_for_authentication?
        ServiceResult.success(user)
      else
        ServiceResult.failure(:invalid_credentials)
      end
    end

    def self.dummy_digest
      @dummy_digest ||= Devise::Encryptor.digest(User, SecureRandom.hex(32))
    end
  end
end
