class PlayersController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = Players::DirectoryQuery.new(viewer: current_user, filters: filter_params)
    @filters = @query.filters
    @selected_city = City.find_by(id: @filters.city_id) if @filters.city_id
    @pagy, @players = pagy(@query.relation, items: Players::DirectoryQuery::PAGE_SIZE)
    @meta_robots = "noindex, follow"
  end

  private

  def filter_params
    permitted = params.permit(:city_id, :city_name, :ntrp_min, :ntrp_max, :play_format, :play_style, :selected_city_id)
    # City picker posts selected_city_id; keep city_id as the canonical filter key.
    if permitted[:selected_city_id].present?
      permitted = permitted.merge(city_id: permitted[:selected_city_id])
    end
    permitted
  end
end
