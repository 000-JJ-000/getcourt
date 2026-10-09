require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Trust only private/loopback proxies by default. Never treat arbitrary client
  # X-Forwarded-For as authoritative. Operators behind Cloudflare (or other CDNs)
  # must list those proxy CIDRs in TRUSTED_PROXIES (comma-separated).
  require "ipaddr"
  trusted = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("::1"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16")
  ]
  ENV.fetch("TRUSTED_PROXIES", "").split(",").each do |cidr|
    cidr = cidr.strip
    next if cidr.blank?

    trusted << IPAddr.new(cidr)
  rescue IPAddr::InvalidAddressError
    Rails.logger.warn("[production] Ignoring invalid TRUSTED_PROXIES entry: #{cidr}")
  end
  config.action_dispatch.trusted_proxies = trusted

  # Skip http-to-https redirect for the health check (Compose / load balancers use HTTP locally).
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Production must use SMTP (never :file). Password from SMTP_PASSWORD, or
  # intentionally RESEND_API_KEY when using Resend's SMTP relay (documented).
  # Skip hard requirement during asset precompile (SECRET_KEY_BASE_DUMMY).
  smtp_password = ENV["SMTP_PASSWORD"].presence || ENV["RESEND_API_KEY"].presence
  if smtp_password.blank? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
    raise "SMTP_PASSWORD or RESEND_API_KEY is required for production mail delivery"
  end

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", "smtp.resend.com"),
    port: ENV.fetch("SMTP_PORT", "2587").to_i,
    enable_starttls_auto: ENV.fetch("SMTP_ENABLE_STARTTLS", "true") == "true",
    user_name: ENV.fetch("SMTP_USERNAME", "resend"),
    password: smtp_password,
    authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym
  }

  # Set host to be used by links generated in mailer templates.
  mailer_host = ENV.fetch("APP_HOST", "https://getcourt.co").to_s.sub(%r{\Ahttps?://}i, "")
  config.action_mailer.default_url_options = { host: mailer_host, protocol: "https" }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts << "getcourt.co"
  config.hosts << /\A(?:www|[a-z]{2})\.getcourt\.co\z/
  config.hosts << "127.0.0.1"
  config.hosts << "localhost"
  ENV.fetch("RAILS_ALLOWED_HOSTS", "").split(",").each do |host|
    host = host.strip
    config.hosts << host if host.present?
  end

  # Skip Host authorization for health checks from the container network.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Allow Rails to serve precompiled assets if you don't use nginx to serve /public
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
end
