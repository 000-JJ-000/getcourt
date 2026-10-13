class MatchHistoriesController < ApplicationController
  before_action :authenticate_user!

  def show
    scope = Match.where(user_id: current_user.id)
      .includes(:opponent, :game)
      .order(played_at: :desc, id: :desc)

    @pagy, @matches = pagy(scope, items: 20)
    @meta_robots = "noindex, follow"
  end
end
