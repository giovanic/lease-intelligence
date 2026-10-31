module Documents
  # Short-lived links to a document version's bytes (docs/adr/0015). The
  # token is signed by the app, expires in TTL and names one version, one
  # tenant and one user. It is never enough on its own:
  # DocumentFilesController also requires that user's session and a live
  # membership in that tenant, then loads the version under RLS and
  # authorizes it again.
  class DownloadLink
    TTL = 5.minutes
    PURPOSE = "document_download".freeze

    Link = Data.define(:token, :expires_at)

    def self.issue(version:, user:)
      expires_at = TTL.from_now
      claims = { "version_id" => version.id, "tenant_id" => version.tenant_id, "user_id" => user.id }
      Link.new(token: verifier.generate(claims, expires_at: expires_at, purpose: PURPOSE), expires_at: expires_at)
    end

    # The claims hash, or nil for a tampered, expired or malformed token.
    def self.resolve(token)
      return unless token.is_a?(String)

      claims = verifier.verified(token, purpose: PURPOSE)
      claims if claims.is_a?(Hash) && claims.values_at("version_id", "tenant_id", "user_id").all?(String)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, JSON::ParserError
      nil
    end

    def self.verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("documents/download_link"),
        digest: "SHA256", serializer: JSON, url_safe: true
      )
    end
    private_class_method :verifier
  end
end
