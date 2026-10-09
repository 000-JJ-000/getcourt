class MatchInvitationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invitation, only: %i[show accept decline cancel propose confirm]
  before_action :expire_invitation!, only: %i[show accept decline cancel propose confirm]
  before_action :require_participant!, only: %i[show propose confirm]

  def index
    @received_pending = MatchInvitation.received_by(current_user).pending.includes(:inviter, :court).order(created_at: :desc)
    @sent_pending = MatchInvitation.sent_by(current_user).pending.includes(:invitee, :court).order(created_at: :desc)
    @scheduling = MatchInvitation.involving(current_user).needs_scheduling.includes(:inviter, :invitee, :court, :proposed_by).order(updated_at: :desc)
    @history = MatchInvitation.involving(current_user)
      .where.not(status: "pending")
      .where.not(scheduling_status: %w[needed proposed])
      .includes(:inviter, :invitee, :court, :game)
      .order(responded_at: :desc, created_at: :desc)
      .limit(50)
    @meta_robots = "noindex, follow"
  end

  def new
    @invitee = find_invitable_invitee!
    @invitation = MatchInvitation.new(invitee: @invitee, play_format: "singles")
    prepare_form_courts
    @meta_robots = "noindex, follow"
  end

  def create
    @invitee = find_invitable_invitee!
    @invitation = MatchInvitation.new(invitation_params.merge(inviter: current_user, invitee: @invitee))
    prepare_form_courts

    if pending_limit_reached?
      @invitation.errors.add(:base, :rate_limited)
      return render :new, status: :too_many_requests
    end

    if @invitation.save
      MatchInvitationNotifyJob.perform_later(@invitation.id, "created")
      redirect_to invitations_path, notice: t("match_invitations.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @invitation.errors.add(:base, :duplicate_pending)
    render :new, status: :unprocessable_entity
  end

  def show
    prepare_form_courts
    @meta_robots = "noindex, follow"
  end

  def accept
    return head :forbidden unless current_user.id == @invitation.invitee_id

    @invitation.accept!(by: current_user)
    MatchInvitationNotifyJob.perform_later(@invitation.id, "accepted")
    redirect_after_accept
  rescue ArgumentError => e
    redirect_to invitations_path, alert: transition_alert(e)
  end

  def decline
    return head :forbidden unless current_user.id == @invitation.invitee_id

    @invitation.decline!(by: current_user)
    MatchInvitationNotifyJob.perform_later(@invitation.id, "declined")
    redirect_to invitations_path, notice: t("match_invitations.flash.declined")
  rescue ArgumentError => e
    redirect_to invitations_path, alert: transition_alert(e)
  end

  def cancel
    return head :forbidden unless current_user.id == @invitation.inviter_id

    @invitation.cancel!(by: current_user)
    MatchInvitationNotifyJob.perform_later(@invitation.id, "canceled")
    redirect_to invitations_path, notice: t("match_invitations.flash.canceled")
  rescue ArgumentError => e
    redirect_to invitations_path, alert: transition_alert(e)
  end

  def propose
    previous_status = @invitation.scheduling_status
    @invitation.propose_schedule!(
      by: current_user,
      proposed_at: params.dig(:match_invitation, :proposed_at),
      court_id: params.dig(:match_invitation, :court_id),
      note: params.dig(:match_invitation, :proposal_note)
    )
    event = previous_status == "proposed" ? "proposal_changed" : "proposal_submitted"
    MatchInvitationNotifyJob.perform_later(@invitation.id, event)
    redirect_to invitation_path(@invitation), notice: t("match_invitations.flash.proposal_sent")
  rescue ArgumentError => e
    redirect_to invitation_path(@invitation), alert: transition_alert(e)
  end

  def confirm
    @invitation.confirm_schedule!(
      by: current_user,
      proposal_updated_at: params[:proposal_updated_at]
    )
    MatchInvitationNotifyJob.perform_later(@invitation.id, "scheduled")
    redirect_to game_path(@invitation.game), notice: t("match_invitations.flash.scheduled")
  rescue ArgumentError => e
    redirect_to invitation_path(@invitation), alert: transition_alert(e)
  end

  private

  def set_invitation
    @invitation = MatchInvitation.find(params[:id])
  end

  def expire_invitation!
    @invitation.expire_if_needed!
  end

  def require_participant!
    head :forbidden unless @invitation.visible_to?(current_user)
  end

  def find_invitable_invitee!
    user = User.find(params[:user_id])
    unless user.community_profile_eligible? && user.profile_visible_to?(current_user) && user.accepts_match_invitations?
      raise ActiveRecord::RecordNotFound
    end
    raise ActiveRecord::RecordNotFound if user.id == current_user.id

    user
  end

  def invitation_params
    params.require(:match_invitation).permit(:play_format, :proposed_at, :court_id, :message)
  end

  def prepare_form_courts
    @courts = Court.visible_to(current_user).order(:name).limit(200)
  end

  def pending_limit_reached?
    MatchInvitation.sent_by(current_user).pending.count >= MatchInvitation::PENDING_PER_SENDER_LIMIT
  end

  def redirect_after_accept
    if @invitation.scheduled? && @invitation.game_id.present?
      redirect_to game_path(@invitation.game), notice: t("match_invitations.flash.accepted_with_game")
    elsif @invitation.scheduling_needed?
      redirect_to invitation_path(@invitation), notice: t("match_invitations.flash.accepted_needs_schedule")
    else
      redirect_to invitations_path, notice: t("match_invitations.flash.accepted")
    end
  end

  def transition_alert(error)
    case error.message
    when "not_pending" then t("match_invitations.flash.not_pending")
    when "unauthorized" then t("match_invitations.flash.unauthorized")
    when "stale_proposal" then t("match_invitations.flash.stale_proposal")
    when "cannot_confirm_own" then t("match_invitations.flash.cannot_confirm_own")
    when "invalid_time" then t("match_invitations.flash.invalid_time")
    when "invalid_court" then t("match_invitations.flash.invalid_court")
    when "already_scheduled" then t("match_invitations.flash.already_scheduled")
    when "not_proposed", "not_accepted" then t("match_invitations.flash.not_pending")
    else t("match_invitations.flash.failed")
    end
  end
end
