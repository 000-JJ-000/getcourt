class CommunityNotifyJob < ApplicationJob
  queue_as :default

  def perform(event, community_id, extra_id = nil)
    community = Community.find_by(id: community_id)
    return unless community

    case event.to_s
    when "membership_requested"
      membership = community.memberships.find_by(id: extra_id)
      Communities::Notifier.membership_requested(membership) if membership
    when "membership_approved"
      membership = community.memberships.find_by(id: extra_id)
      Communities::Notifier.membership_approved(membership) if membership
    when "game_announced"
      game = community.games.find_by(id: extra_id)
      Communities::Notifier.game_announced(community, game) if game
    when "invitation_created"
      invitation = community.invitations.find_by(id: extra_id)
      Communities::Notifier.invitation_created(invitation) if invitation
    when "invitation_accepted"
      invitation = community.invitations.find_by(id: extra_id)
      Communities::Notifier.invitation_accepted(invitation) if invitation
    end
  end
end
