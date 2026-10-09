class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[new create verify check]

  def new
    if session[:return_to].blank? && request.referer.present?
      uri = URI.parse(request.referer) rescue nil
      if uri && (uri.host.nil? || uri.host == request.host) && uri.path != new_session_path
        session[:return_to] = uri.request_uri
      end
    end
  end

  # POST /sign_in — always issues an email OTP; never establishes a session here.
  def create
    result = Sessions::EmailLogin.request(
      email: params[:email],
      ip: request.remote_ip,
      locale: I18n.locale.to_s,
      telegram_locale: I18n.locale.to_s
    )

    unless result.ok?
      message = case result.error
      when :blank_email then "Email required"
      else "Enter a valid email address"
      end
      redirect_to new_session_path, alert: message and return
    end

    begin
      UserMailer.login_code_email(result.challenge.email, result.raw_code).deliver_now
    rescue StandardError => e
      Rails.logger.error("[SessionsController#create] mail delivery failed: #{e.class}")
      result.challenge.update_columns(consumed_at: Time.current)
      redirect_to new_session_path, alert: t("sessions.delivery_failed") and return
    end

    # Bind the challenge to this browser session — not to the URL.
    session[:login_challenge_id] = result.challenge.id
    redirect_to verify_session_path, notice: t("sessions.login_code_sent_email"), status: :see_other
  end

  def verify
    @challenge = current_login_challenge
    unless @challenge&.usable?
      redirect_to new_session_path, alert: t("sessions.challenge_missing") and return
    end

    @email = @challenge.email
    @via = "email"
  end

  # POST /sign_in/verify
  def check
    challenge = current_login_challenge
    if challenge.blank?
      redirect_to new_session_path, alert: t("sessions.challenge_missing") and return
    end

    result = Sessions::EmailLogin.verify(challenge: challenge, code: params[:code])

    unless result.ok?
      @challenge = challenge
      @email = challenge.email
      @via = "email"
      flash.now[:alert] = verify_error_message(result.error)
      render :verify, status: :unprocessable_entity and return
    end

    session.delete(:login_challenge_id)
    sign_in(result.user)

    target = session.delete(:return_to) || root_path
    redirect_to target, notice: "Signed in as #{result.user.email}", status: :see_other
  end

  def destroy
    sign_out

    target = root_path
    if request.referer.present?
      uri = URI.parse(request.referer) rescue nil
      if uri && (uri.host.nil? || uri.host == request.host)
        target = uri.request_uri
      end
    end

    redirect_to target, notice: "Signed out"
  end

  private

  def current_login_challenge
    id = session[:login_challenge_id]
    return if id.blank?

    EmailLoginChallenge.find_by(id: id)
  end

  def verify_error_message(error)
    case error
    when :expired then t("sessions.verify.expired")
    when :locked then t("sessions.verify.locked")
    when :consumed, :missing_challenge then t("sessions.challenge_missing")
    else t("sessions.verify.invalid")
    end
  end
end
