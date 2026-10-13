class ExpireCommunityInvitationsJob < ApplicationJob
  queue_as :default

  def perform
    CommunityInvitation.pending_expired.find_each(&:expire_if_needed!)
  end
end
