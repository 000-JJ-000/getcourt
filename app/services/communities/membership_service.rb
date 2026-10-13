module Communities
  class MembershipService
    def initialize(community, actor:)
      @community = community
      @actor = actor
    end

    def join_or_request!
      raise ArgumentError, "unauthorized" unless @actor
      raise ArgumentError, "invite_required" if @community.private?

      CommunityMembership.transaction do
        membership = @community.memberships.lock.find_by(user_id: @actor.id)
        if membership
          raise ArgumentError, "already_member" if membership.active?
          raise ArgumentError, "already_pending" if membership.pending?

          membership.update!(
            status: @community.open_join? ? "active" : "pending",
            role: "member",
            responded_at: @community.open_join? ? Time.current : nil
          )
          return membership
        end

        @community.memberships.create!(
          user: @actor,
          role: "member",
          status: @community.open_join? ? "active" : "pending",
          responded_at: @community.open_join? ? Time.current : nil
        )
      end
    end

    def approve!(membership)
      authorize_manage!
      raise ArgumentError, "not_pending" unless membership.pending?

      membership.with_lock do
        membership.reload
        raise ArgumentError, "not_pending" unless membership.pending?

        membership.update!(status: "active", responded_at: Time.current)
      end
      membership
    end

    def decline!(membership)
      authorize_manage!
      raise ArgumentError, "not_pending" unless membership.pending?

      membership.with_lock do
        membership.reload
        raise ArgumentError, "not_pending" unless membership.pending?

        membership.update!(status: "removed", responded_at: Time.current)
      end
      membership
    end

    def leave!
      raise ArgumentError, "unauthorized" unless @actor

      membership = @community.memberships.find_by!(user_id: @actor.id)
      raise ArgumentError, "not_active" unless membership.active?
      raise ArgumentError, "sole_owner" if membership.owner? && sole_active_owner?(membership)

      membership.update!(status: "removed", responded_at: Time.current, role: "member")
      membership
    end

    def remove!(membership)
      authorize_manage!
      raise ArgumentError, "not_active" unless membership.active?
      raise ArgumentError, "cannot_remove_owner" if membership.owner? && !@community.owner?(@actor) && !@actor.admin?
      raise ArgumentError, "sole_owner" if membership.owner? && sole_active_owner?(membership)

      membership.update!(status: "removed", responded_at: Time.current, role: "member")
      membership
    end

    def promote!(membership)
      authorize_owner!
      raise ArgumentError, "not_active" unless membership.active?
      raise ArgumentError, "already_owner" if membership.owner?

      membership.update!(role: "moderator")
      membership
    end

    def demote!(membership)
      authorize_owner!
      raise ArgumentError, "not_active" unless membership.active?
      raise ArgumentError, "not_moderator" unless membership.moderator_role?

      membership.update!(role: "member")
      membership
    end

    def transfer_ownership!(membership)
      authorize_owner!
      raise ArgumentError, "not_active" unless membership.active?
      raise ArgumentError, "self" if membership.user_id == @actor.id

      CommunityMembership.transaction do
        current = @community.memberships.active.owners.lock.find_by!(user_id: @actor.id)
        membership.with_lock do
          membership.reload
          raise ArgumentError, "not_active" unless membership.active?

          current.update!(role: "moderator")
          membership.update!(role: "owner")
        end
      end
      membership
    end

    private

    def authorize_manage!
      raise ArgumentError, "unauthorized" unless @community.can_manage?(@actor)
    end

    def authorize_owner!
      raise ArgumentError, "unauthorized" unless @community.owner?(@actor) || @actor&.admin?
    end

    def sole_active_owner?(membership)
      @community.memberships.active.owners.where.not(id: membership.id).none?
    end
  end
end
