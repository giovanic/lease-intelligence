# Redis connection for Sidekiq, the Active Job backend
# (docs/adr/0006-background-processing-sidekiq.md). Production must set
# REDIS_URL explicitly (with auth/TLS) — booting without it fails instead
# of silently pointing at a localhost Redis. Development and test default
# to a local Redis; the test suite itself uses the :test adapter.
#
# Job arguments are stored in Redis in plain text: pass record ids only,
# never document text, personal data or credentials (ApplicationJob).
redis_url = if Rails.env.production?
  ENV.fetch("REDIS_URL")
else
  ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
end

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
