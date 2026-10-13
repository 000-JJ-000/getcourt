class CommunityMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_community
  before_action :set_membership, only: %i[approve decline remove promote demote transfer]

  def create
    membership = Communities::MembershipService.new(@community, actor: current_user).join_or_request!
    if membership.pending?
      CommunityNotifyJob.perform_later("membership_requested", @community.id, membership.id)
      redirect_to @community, notice: t("communities.flash.request_sent")
    else
      redirect_to @community, notice: t("communities.flash.joined")
    end
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to @community, alert: t("communities.flash.already_member")
  end

  def destroy
    Communities::MembershipService.new(@community, actor: current_user).leave!
    redirect_to communities_path, notice: t("communities.flash.left")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def approve
    Communities::MembershipService.new(@community, actor: current_user).approve!(@membership)
    CommunityNotifyJob.perform_later("membership_approved", @community.id, @membership.id)
    redirect_to @community, notice: t("communities.flash.approved")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def decline
    Communities::MembershipService.new(@community, actor: current_user).decline!(@membership)
    redirect_to @community, notice: t("communities.flash.declined")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def remove
    Communities::MembershipService.new(@community, actor: current_user).remove!(@membership)
    redirect_to @community, notice: t("communities.flash.removed")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def promote
    Communities::MembershipService.new(@community, actor: current_user).promote!(@membership)
    redirect_to @community, notice: t("communities.flash.promoted")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def demote
    Communities::MembershipService.new(@community, actor: current_user).demote!(@membership)
    redirect_to @community, notice: t("communities.flash.demoted")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  def transfer
    Communities::MembershipService.new(@community, actor: current_user).transfer_ownership!(@membership)
    redirect_to @community, notice: t("communities.flash.transferred")
  rescue ArgumentError => e
    redirect_to @community, alert: membership_alert(e)
  end

  private

  def set_community
    @community = Community.find_by(slug: params[:community_id]) || Community.find(params[:community_id])
  end

  def set_membership
    @membership = @community.memberships.find(params[:id])
  end

  def membership_alert(error)
    case error.message
    when "unauthorized" then t("communities.flash.unauthorized")
    when "invite_required" then t("communities.flash.invite_required")
    when "already_member", "already_pending" then t("communities.flash.already_member")
    when "sole_owner" then t("communities.flash.sole_owner")
    else t("communities.flash.failed")
    end
  end
end
