class TelegramAuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    verified = Telegram::WebAppAuth.verify(params[:init_data].to_s, ENV["TELEGRAM_BOT_TOKEN"].to_s)
    unless verified
      render json: { error: "invalid initData" }, status: :unauthorized and return
    end

    tg_user = JSON.parse(verified["user"].to_s)
    user = User.find_by(telegram_chat_id: tg_user["id"].to_i)
    # Ghost /start accounts (chat_id without email) must not receive a web session.
    unless user&.email.present?
      render json: { error: "telegram account not connected" }, status: :not_found and return
    end

    sign_in(user)
    render json: { ok: true }
  rescue JSON::ParserError
    render json: { error: "invalid user data" }, status: :unauthorized
  end
end
