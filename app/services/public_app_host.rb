# Normalizes ENV["APP_HOST"] for Rails url_helpers.
#
# APP_HOST is conventionally a full URL with scheme (mailers, Telegram buttons).
# ActionDispatch *_url(host:) expects a bare host (optional :port) plus protocol:.
module PublicAppHost
  module_function

  def url_options
    raw = ENV.fetch("APP_HOST", "https://getcourt.co").to_s.strip
    protocol = "https"
    hostport = raw

    if (m = raw.match(%r{\A(https?)://(.+)\z}i))
      protocol = m[1].downcase
      hostport = m[2]
    end

    hostport = hostport.sub(%r{/+\z}, "").split("/").first.to_s
    host, port = hostport.split(":", 2)
    opts = { host: host, protocol: protocol }
    opts[:port] = port.to_i if port.present?
    opts
  end
end
