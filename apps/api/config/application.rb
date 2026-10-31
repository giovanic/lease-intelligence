require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Api
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # UUID primary keys project-wide (docs/adr/0004-uuid-primary-keys.md) —
    # set once here so every generated migration defaults to id: :uuid
    # instead of needing it repeated per migration.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # The Ruby schema format (db/schema.rb, the Rails default) cannot
    # represent RLS policies, FORCE ROW LEVEL SECURITY, or the custom SQL
    # functions RLS policies depend on (see
    # db/migrate/20261031133221_enable_tenancy_sql_functions.rb) — it only
    # captures tables/columns/indexes/FKs/check constraints. Any
    # environment rebuilt from schema.rb (e.g. `db:test:prepare`) would
    # silently lose all RLS protection. docs/adr/0003-postgresql-rls.md.
    config.active_record.schema_format = :sql

    # The SPA authenticates with a Devise/Warden session in an httpOnly,
    # SameSite=Lax cookie (docs/adr/0013-spa-session-auth-and-tenant-selection.md).
    # api_only strips the cookie/session middleware, so it is re-added here
    # — *outside* Warden, so a session Warden ends (logout, idle timeout via
    # `throw :warden`) is still committed back to the cookie.
    config.session_store :cookie_store,
      key: "_lease_intelligence_session",
      httponly: true,
      same_site: :lax,
      secure: !(Rails.env.development? || Rails.env.test?)
    config.middleware.insert_before Warden::Manager, ActionDispatch::Cookies
    config.middleware.insert_before Warden::Manager, config.session_store, config.session_options

    # Extra origins allowed to send state-changing requests besides the
    # API's own origin (RequestOriginVerification). Empty by default: the
    # SPA is served same-origin (Vite proxy in dev, reverse proxy in prod).
    config.x.extra_allowed_origins = ENV.fetch("APP_EXTRA_ALLOWED_ORIGINS", "")
      .split(",").map(&:strip).reject(&:empty?)

    # Background jobs run on Sidekiq + Redis in every environment except
    # test (docs/adr/0006-background-processing-sidekiq.md). Redis
    # location and queues: config/initializers/sidekiq.rb, config/sidekiq.yml.
    config.active_job.queue_adapter = :sidekiq
  end
end
