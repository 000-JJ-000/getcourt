class MatchResultsController < ApplicationController
  include GameAccess

  before_action :authenticate_user!
  before_action :set_game
  before_action :authorize_game_visible!
  before_action :reject_if_canceled!

  def confirm
    PlayerStatistics::ConfirmMatchResultService.new(
      game: @game,
      group_id: params[:group_id],
      by: current_user,
      result_updated_at: params[:result_updated_at]
    ).call
    MatchResultNotifyJob.perform_later(@game.id, params[:group_id], "confirmed")
    redirect_to game_path(@game), notice: t("match_results.flash.confirmed")
  rescue ArgumentError => e
    redirect_to game_path(@game), alert: result_alert(e)
  end

  def dispute
    PlayerStatistics::DisputeMatchResultService.new(
      game: @game,
      group_id: params[:group_id],
      by: current_user,
      result_updated_at: params[:result_updated_at],
      note: params[:dispute_note]
    ).call
    MatchResultNotifyJob.perform_later(@game.id, params[:group_id], "disputed")
    redirect_to game_path(@game), notice: t("match_results.flash.disputed")
  rescue ArgumentError => e
    redirect_to game_path(@game), alert: result_alert(e)
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def reject_if_canceled!
    return unless @game.canceled?

    redirect_to game_path(@game), alert: t("games.flash.canceled_locked")
  end

  def result_alert(error)
    case error.message
    when "unauthorized" then t("match_results.flash.unauthorized")
    when "stale_result" then t("match_results.flash.stale")
    when "not_pending", "already_confirmed" then t("match_results.flash.not_pending")
    when "canceled" then t("games.flash.canceled_locked")
    else t("match_results.flash.failed")
    end
  end
end
