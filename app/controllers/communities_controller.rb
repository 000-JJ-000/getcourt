class CommunitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_community, only: %i[show edit update]
  before_action :authorize_visible!, only: %i[show edit update]
  before_action :authorize_settings!, only: %i[edit update]

  PENDING_CREATE_LIMIT = 10

  def index
    query = Communities::DirectoryQuery.new(viewer: current_user, filters: filter_params)
    @applied_filters = query.applied_filters
    @pagy, @communities = pagy(query.relation, items: Communities::DirectoryQuery::PAGE_SIZE)
    @meta_robots = "noindex, follow"
  end

  def show
    @membership = @community.membership_for(current_user)
    @full_access = @community.visible_to?(current_user)
    @members = @full_access ? @community.memberships.active.includes(:user).order(:role, :created_at) : []
    @pending = @full_access && @community.can_manage?(current_user) ? @community.memberships.pending.includes(:user).order(:created_at) : []
    @pending_invitations = @full_access && @community.can_manage?(current_user) ?
      @community.invitations.pending.includes(:invitee, :inviter).order(created_at: :desc) : []
    @my_invitation = @community.invitations.pending.find_by(invitee_id: current_user.id)
    @my_invitation&.expire_if_needed!
    @upcoming_games = @full_access ? community_games_scope.where("games.date >= ?", Date.current).order(:date, :time).limit(10) : []
    @recent_games = @full_access ? community_games_scope.where("games.date < ?", Date.current).order(date: :desc).limit(10) : []
    @meta_robots = "noindex, follow"
  end

  def new
    @community = Community.new(visibility: "public", membership_policy: "open", play_focus: "both")
    @meta_robots = "noindex, follow"
  end

  def create
    if Community.where(creator_id: current_user.id).where("created_at > ?", 1.day.ago).count >= PENDING_CREATE_LIMIT
      return redirect_to communities_path, alert: t("communities.flash.rate_limited")
    end

    @community = Community.new(community_params.merge(creator: current_user))
    Community.transaction do
      @community.save!
      @community.memberships.create!(user: current_user, role: "owner", status: "active", responded_at: Time.current)
    end
    redirect_to @community, notice: t("communities.flash.created")
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit
    @meta_robots = "noindex, follow"
  end

  def update
    if @community.update(community_params)
      redirect_to @community, notice: t("communities.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_community
    @community = Community.find_by!(slug: params[:id])
  rescue ActiveRecord::RecordNotFound
    @community = Community.find(params[:id])
  end

  def authorize_visible!
    raise ActiveRecord::RecordNotFound unless @community.teaser_accessible?(current_user)
  end

  def authorize_settings!
    head :forbidden unless @community.can_edit_settings?(current_user)
  end

  def community_params
    params.require(:community).permit(
      :name, :description, :city_id, :city_name, :visibility, :membership_policy,
      :ntrp_min, :ntrp_max, :play_focus
    )
  end

  def filter_params
    params.permit(:q, :city_id, :city_name, :play_focus)
  end

  def community_games_scope
    # Invite-only peer matches stay private even if somehow linked.
    @community.games.not_canceled.where(invite_only: false)
  end
end
