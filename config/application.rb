require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GetCourt
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
    config.time_zone = ENV.fetch("APP_TIME_ZONE", "Asia/Yekaterinburg")
    # PostGIS images also install tiger/topology schemas; keep schema.rb on public only
    # so db:schema:load / db:test:prepare do not fight extension-owned tables.
    config.active_record.dump_schemas = "public"

    # Absolute authenticated lifetime is enforced server-side (see ApplicationController).
    # Cookie Max-Age matches that ceiling; activity may refresh the cookie but not
    # extend authenticated_at past SESSION_ABSOLUTE_TTL.
    config.x.session_absolute_ttl = 30.days
    config.session_store :cookie_store,
      key: "_get_court_session_v2",
      expire_after: 30.days,
      domain: :all,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
  end
end
