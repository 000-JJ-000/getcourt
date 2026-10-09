# Rack::Attack is inserted into the middleware stack by its railtie.
#
# Ahoy exposes public, unauthenticated endpoints (/ahoy/visits, /ahoy/events)
# when Ahoy.api is enabled. Throttle them per IP so a client can't flood the
# database with arbitrary events. See https://github.com/ankane/ahoy#throttling
#
# Counters use Rails.cache (Solid Cache in production) so limits survive process
# restarts and apply across multiple web instances — not an in-process MemoryStore.
Rails.application.config.after_initialize do
  Rack::Attack.cache.store = Rails.cache if defined?(Rack::Attack)
end

class Rack::Attack
  # Тело запроса читаем сами, поэтому ограничиваем: разбирать мегабайты ради
  # одного поля незачем.
  JSON_BODY_LIMIT = 64.kilobytes
  UNPARSED_EMAIL = "unparsed".freeze

  throttle("ahoy/ip", limit: 20, period: 20.seconds) do |request|
    request.ip if request.path.start_with?("/ahoy")
  end

  throttle("court_suggestions/ip", limit: 5, period: 1.hour) do |request|
    if request.post? && request.path.match?(%r{\A/courts/\d+/suggestions\z})
      request.ip
    end
  end

  # Публичная JSON-выдача игр и MCP-эндпоинт: оба без сессии, оба бьют в базу.
  # MCP-клиент за один вопрос делает несколько вызовов подряд, поэтому лимит выше.
  throttle("api/ip", limit: 60, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/api/")
  end

  # MCP узнаём по маршруту, а не по строке пути: Rails принимает и /mcp.json, и
  # /mcp.js%6fn, и лишние слэши (см. recognized_route ниже). Маршрут только POST,
  # так что роутер спрашиваем лишь для POST-запросов.
  def self.mcp_request?(request)
    return false unless request.post?

    route = recognized_route(request)
    route.present? && route[:controller] == "mcp"
  end

  throttle("mcp/ip", limit: 120, period: 1.minute) do |request|
    request.ip if mcp_request?(request)
  end

  # Всплески отдельно: минутный лимит можно выбрать за пару секунд. Пока request.ip —
  # адрес узла Cloudflare, а не клиента, счётчик общий для всех, кто пришёл через
  # тот же узел, и может задеть обычные запросы.
  throttle("mcp/ip/burst", limit: 20, period: 10.seconds) do |request|
    request.ip if mcp_request?(request)
  end

  # Rails разбирает JSON-тело в params ещё до контроллера, поэтому большое тело
  # отсекаем здесь. Content-Length может не быть или он может врать, так что
  # читаем не больше лимита и перематываем поток обратно.
  def self.mcp_body_too_large?(request)
    return false unless request.body && mcp_request?(request)

    request.body.rewind
    request.body.read(JSON_BODY_LIMIT + 1).to_s.bytesize > JSON_BODY_LIMIT
  rescue IOError, ArgumentError
    false
  ensure
    request.body&.rewind
  end

  blocklist("mcp/body_size") { |request| mcp_body_too_large?(request) }

  self.blocklisted_responder = lambda do |request|
    if request.env["rack.attack.matched"] == "mcp/body_size"
      [ 413, { "content-type" => "text/plain" }, [ "Payload Too Large\n" ] ]
    else
      [ 403, { "content-type" => "text/plain" }, [ "Forbidden\n" ] ]
    end
  end

  # Login OTP is six digits and lives 10 minutes. Failed attempts do not consume
  # the code, so without throttling brute force is practical. Email + IP buckets
  # cover single-account guessing and spray across many addresses.
  #
  # The same counters cover API-token ownership confirmation (same OTP shape).
  CODE_ACTIONS = [ %w[sessions check], %w[api_tokens confirm] ].freeze

  # Сравнивать путь строкой бесполезно: Rails узнаёт тот же маршрут и в
  # /sign_in/verify.html, и в /sign_in/verify.ht%6dl, и в /sign_in/verify.html-foo,
  # и с лишними или хвостовыми слэшами. Поэтому спрашиваем сам роутер.
  def self.code_attempt?(request)
    return false unless request.post?

    route = recognized_route(request)
    route.present? && CODE_ACTIONS.include?([ route[:controller], route[:action] ])
  end

  def self.recognized_route(request)
    request.env.fetch("getcourt.recognized_route") do
      request.env["getcourt.recognized_route"] =
        begin
          Rails.application.routes.recognize_path(request.path, method: request.request_method)
        rescue StandardError
          nil
        end
    end
  end

  # Порядок тот же, что у Rails: query перекрывает тело, а не наоборот, как в
  # Rack::Request#params. Иначе почту в счётчике и почту, по которой контроллер
  # ищет пользователя, можно развести и перебирать код мимо лимита.
  def self.attempt_email(request)
    email = query_email(request)
    email = body_email(request) if email.blank?
    email = session_challenge_email(request) if email.blank?
    email.is_a?(String) ? email.strip.downcase.presence : nil
  end

  # Web OTP verify binds the challenge in the cookie session, not in params.
  def self.session_challenge_email(request)
    route = recognized_route(request)
    return unless route && route[:controller] == "sessions" && route[:action] == "check"

    challenge_id = request.session[:login_challenge_id]
    return if challenge_id.blank?

    EmailLoginChallenge.where(id: challenge_id).pick(:email)
  rescue StandardError
    nil
  end

  def self.query_email(request)
    request.GET["email"]
  rescue StandardError
    nil
  end

  def self.body_email(request)
    return json_body_email(request) if request.media_type.to_s.include?("json")

    request.POST["email"]
  rescue StandardError
    UNPARSED_EMAIL
  end

  # Тело читаем сами, поэтому его размер приходится ограничивать. Всё, что не
  # разобралось, попадает в общий счётчик: пропустить такую попытку — значит
  # отдать лимит любому, кто добавит в JSON лишнее поле подлиннее.
  def self.json_body_email(request)
    request.body.rewind
    body = request.body.read(JSON_BODY_LIMIT + 1).to_s
    request.body.rewind
    return UNPARSED_EMAIL if body.bytesize > JSON_BODY_LIMIT

    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed["email"] : UNPARSED_EMAIL
  rescue JSON::ParserError, IOError, ArgumentError
    UNPARSED_EMAIL
  end

  throttle("login_code/email", limit: 10, period: 15.minutes) do |request|
    attempt_email(request) if code_attempt?(request)
  end

  throttle("login_code/ip", limit: 30, period: 1.hour) do |request|
    request.ip if code_attempt?(request)
  end

  # OTP issuance (POST /sign_in): limit requests per email and IP.
  def self.login_request?(request)
    return false unless request.post?

    route = recognized_route(request)
    route.present? && route[:controller] == "sessions" && route[:action] == "create"
  end

  throttle("login_request/email", limit: 5, period: 15.minutes) do |request|
    attempt_email(request) if login_request?(request)
  end

  throttle("login_request/ip", limit: 20, period: 1.hour) do |request|
    request.ip if login_request?(request)
  end

  # Telegram WebApp auth: limit initData POSTs per IP (replay / probing noise).
  def self.telegram_web_app_auth?(request)
    return false unless request.post?

    route = recognized_route(request)
    route.present? && route[:controller] == "telegram_auth" && route[:action] == "create"
  end

  throttle("telegram_web_app_auth/ip", limit: 30, period: 1.hour) do |request|
    request.ip if telegram_web_app_auth?(request)
  end
end
