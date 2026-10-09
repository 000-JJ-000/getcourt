class ExpireMatchInvitationsJob < ApplicationJob
  queue_as :default

  def perform
    MatchInvitation.pending_expired.find_each do |invitation|
      invitation.expire_if_needed!
    end
  end
end
