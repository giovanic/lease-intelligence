# Brute-force / credential-stuffing protection for sign-in
# (docs/architecture/security.md, ADR-0013). Uses Rails.cache as its
# store (solid_cache in production, memory in development).
class Rack::Attack
  SIGN_IN_PATH = "/api/v1/session".freeze

  def self.sign_in_attempt?(req)
    req.post? && req.path == SIGN_IN_PATH
  end

  throttle("sign_in/ip", limit: 10, period: 1.minute) do |req|
    req.ip if sign_in_attempt?(req)
  end

  # Per-account throttle, so a distributed attack on one email is still
  # limited. Parsed with ActionDispatch so the JSON body is parsed once
  # and reused by the controller.
  throttle("sign_in/email", limit: 5, period: 1.minute) do |req|
    next unless sign_in_attempt?(req)

    email = begin
      ActionDispatch::Request.new(req.env).request_parameters["email"]
    rescue ActionDispatch::Http::Parameters::ParseError
      nil
    end
    email.to_s.strip.downcase.presence
  end

  # Document uploads (docs/adr/0015): each one is up to 50 MB of hashing
  # and storage, so they are throttled per IP like sign-in
  # (.claude/rules/security.md). Generous for a person uploading a batch
  # of scanned amendments, tight for a script.
  DOCUMENT_UPLOAD_PATH = %r{\A/api/v1/leases/[^/]+/documents(/[^/]+/versions)?\z}

  throttle("document_uploads/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.post? && DOCUMENT_UPLOAD_PATH.match?(req.path)
  end

  # Manual reprocessing (docs/adr/0016, docs/adr/0017): each request can end
  # in a paid LLM call — a field extraction run directly, a text extraction
  # by requesting one when it succeeds. One run per version is in flight at
  # a time; this caps how fast someone can chain them.
  REPROCESS_PATH = %r{\A/api/v1/document_versions/[^/]+/(text_extractions|extraction_runs)\z}

  throttle("reprocessing/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && REPROCESS_PATH.match?(req.path)
  end

  self.throttled_responder = lambda do |req|
    retry_after = req.env["rack.attack.match_data"].to_h[:period].to_i
    [
      429,
      { "content-type" => "application/json", "retry-after" => retry_after.to_s },
      [ { error: { code: "too_many_requests", message: "Too many attempts. Try again later." } }.to_json ]
    ]
  end
end
