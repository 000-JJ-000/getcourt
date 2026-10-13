class CommunityInvitationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_community, only: :create
  before_action :set_invitation, only: %i[accept decline revoke]

  def index
    @received = CommunityInvitation.pending.for_invitee(current_user).includes(:community, :inviter).order(created_at: :desc)
    @meta_robots = "noindex, follow"
  end

  def create
    return head :forbidden unless @community.can_manage?(current_user)

    invitee = User.find(params[:user_id])
    invitation = @community.invitations.new(inviter: current_user, invitee: invitee)
    if invitation.save
      CommunityNotifyJob.perform_later("invitation_created", @community.id, invitation.id)
      redirect_to @community, notice: t("communities.flash.invite_sent")
    else
      redirect_to @community, alert: invitation.errors.full_messages.to_sentence.presence || t("communities.flash.invite_failed")
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to @community, alert: t("communities.flash.invite_failed")
  rescue ActiveRecord::RecordNotUnique
    redirect_to @community, alert: t("communities.flash.invite_duplicate")
  end

  def accept
    @invitation.expire_if_needed!
    @invitation.accept!(by: current_user)
    CommunityNotifyJob.perform_later("invitation_accepted", @invitation.community_id, @invitation.id)
    redirect_to @invitation.community, notice: t("communities.flash.invite_accepted")
  rescue ArgumentError => e
    redirect_to community_invitations_path, alert: invite_alert(e)
  end

  def decline
    @invitation.expire_if_needed!
    @invitation.decline!(by: current_user)
    redirect_to community_invitations_path, notice: t("communities.flash.invite_declined")
  rescue ArgumentError => e
    redirect_to community_invitations_path, alert: invite_alert(e)
  end

  def revoke
    @invitation.expire_if_needed!
    @invitation.revoke!(by: current_user)
    redirect_to @invitation.community, notice: t("communities.flash.invite_revoked")
  rescue ArgumentError => e
    redirect_to @invitation.community, alert: invite_alert(e)
  end

  private

  def set_community
    raw = params[:id].presence || params[:community_id]
    @community = Community.find_by(slug: raw) || Community.find(raw)
  end

  def set_invitation
    @invitation = CommunityInvitation.find(params[:id])
  end

  def invite_alert(error)
    case error.message
    when "unauthorized" then t("communities.flash.unauthorized")
    when "not_pending" then t("communities.flash.invite_not_pending")
    when "already_member" then t("communities.flash.already_member")
    else t("communities.flash.failed")
    end
  end
end
