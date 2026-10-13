class CommunityGamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_community
  before_action :authorize_member!

  def new
    redirect_to new_game_path(community_id: @community.to_param)
  end

  def create
    game = current_user.games.find(params[:game_id])
    raise ActiveRecord::RecordNotFound if game.invite_only?
    raise ActiveRecord::RecordNotFound unless game.visible_to?(current_user)

    game.update!(community: @community)
    CommunityNotifyJob.perform_later("game_announced", @community.id, game.id)
    redirect_to @community, notice: t("communities.flash.game_linked")
  rescue ActiveRecord::RecordNotFound
    redirect_to @community, alert: t("communities.flash.game_link_failed")
  end

  def destroy
    game = @community.games.find(params[:id])
    unless @community.can_manage?(current_user) || game.user_id == current_user.id
      return head :forbidden
    end

    game.update!(community_id: nil)
    redirect_to @community, notice: t("communities.flash.game_unlinked")
  end

  private

  def set_community
    @community = Community.find_by(slug: params[:community_id]) || Community.find(params[:community_id])
    raise ActiveRecord::RecordNotFound unless @community.visible_to?(current_user)
  end

  def authorize_member!
    head :forbidden unless @community.active_member?(current_user) || current_user.admin?
  end
end
