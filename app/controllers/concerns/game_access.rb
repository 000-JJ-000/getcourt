# Shared invite-only / canceled gates for GamesController and nested resources.
module GameAccess
  extend ActiveSupport::Concern

  private

  def authorize_game_visible!(game = @game)
    return if game.blank?
    return if game.visible_to?(current_user)

    raise ActiveRecord::RecordNotFound
  end

  def reject_canceled_game!(game = @game)
    return if game.blank? || !game.canceled?

    redirect_to game_path(game), alert: I18n.t("games.flash.canceled_locked", default: "This game was canceled.")
  end
end
