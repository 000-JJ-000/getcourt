class GameShareCardsController < ApplicationController
  include GameAccess

  skip_before_action :authenticate_user!, only: :show

  def show
    game = Game.includes(:court, :tournament, :participations).find(params[:game_id])
    authorize_game_visible!(game)
    data = Games::ShareCardRenderer.render_data(game, locale: I18n.locale)

    send_data data,
      filename: "getcourt-game-#{game.id}.png",
      type: "image/png",
      disposition: "inline"
  end
end
