class MatchInvitationSchedulingReminderJob < ApplicationJob
  queue_as :default

  def perform
    MatchInvitation.due_for_scheduling_reminder.find_each do |invitation|
      invitation.with_lock do
        invitation.reload
        next unless invitation.scheduling_needed?
        next if invitation.scheduling_reminded_at.present?

        invitation.update!(scheduling_reminded_at: Time.current)
      end
      MatchInvitationNotifyJob.perform_later(invitation.id, "scheduling_reminder")
    end
  end
end
