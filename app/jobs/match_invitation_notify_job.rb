class MatchInvitationNotifyJob < ApplicationJob
  queue_as :default

  EVENTS = {
    "created" => :created,
    "accepted" => :accepted,
    "declined" => :declined,
    "canceled" => :canceled,
    "proposal_submitted" => :proposal_submitted,
    "proposal_changed" => :proposal_changed,
    "scheduled" => :scheduled,
    "scheduling_reminder" => :scheduling_reminder
  }.freeze

  def perform(invitation_id, event)
    invitation = MatchInvitation.find_by(id: invitation_id)
    return unless invitation

    method = EVENTS[event.to_s]
    return unless method

    MatchInvitations::Notifier.public_send(method, invitation)
  end
end
