class WeathersController < ApplicationController
  include GameAccess

  skip_before_action :authenticate_user!, only: :show

  def show
    game = Game.find(params[:game_id])
    authorize_game_visible!(game)
    reading = Weather::GoogleForecast.for_game(game)
    render partial: "games/weather_badge", locals: { game: game, reading: reading, details: params[:context] == "details" }
  end
end
