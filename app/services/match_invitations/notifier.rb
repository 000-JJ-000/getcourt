module MatchInvitations
  # External notify via existing NotificationDelivery. Failures are logged and
  # never raise into invitation state transitions.
  class Notifier
    def self.created(invitation)
      new(invitation).notify_invitee(:created)
    end

    def self.accepted(invitation)
      new(invitation).notify_inviter(:accepted)
    end

    def self.declined(invitation)
      new(invitation).notify_inviter(:declined)
    end

    def self.canceled(invitation)
      new(invitation).notify_invitee(:canceled)
    end

    def self.proposal_submitted(invitation)
      new(invitation).notify_other_from_proposer(:proposal_submitted)
    end

    def self.proposal_changed(invitation)
      new(invitation).notify_other_from_proposer(:proposal_changed)
    end

    def self.scheduled(invitation)
      new(invitation).notify_both(:scheduled)
    end

    def self.scheduling_reminder(invitation)
      new(invitation).notify_both(:scheduling_reminder)
    end

    def initialize(invitation)
      @invitation = invitation
    end

    def notify_invitee(event)
      deliver(invitation.invitee, event)
    end

    def notify_inviter(event)
      deliver(invitation.inviter, event)
    end

    def notify_other_from_proposer(event)
      other = invitation.other_participant(invitation.proposed_by)
      deliver(other, event) if other
    end

    def notify_both(event)
      deliver(invitation.inviter, event)
      deliver(invitation.invitee, event)
    end

    private

    attr_reader :invitation

    def deliver(user, event)
      NotificationDelivery.deliver(user: user, notification: notification_for(user, event))
    rescue StandardError => e
      Rails.logger.warn("[MatchInvitations::Notifier] #{event} failed for invitation ##{invitation.id}: #{e.class}: #{e.message}")
      false
    end

    def notification_for(user, event)
      url = detail_url
      NotificationDelivery::Notification.new(
        subject: ->(locale) { I18n.t("match_invitations.mail.#{event}.subject", locale: locale) },
        body: ->(locale, _channel) { body_text(locale, event, user) },
        actions: lambda { |locale|
          [ { label: I18n.t("match_invitations.mail.view", locale: locale), url: url, row: 0 } ]
        }
      )
    end

    def body_text(locale, event, user)
      other = invitation.other_participant(user)
      name = other&.name.presence || I18n.t("users.show.anonymous_name", locale: locale)
      I18n.t(
        "match_invitations.mail.#{event}.body",
        locale: locale,
        name: name,
        format: I18n.t("users.profile.play_format.#{invitation.play_format}", locale: locale),
        when: when_phrase(locale, event)
      )
    end

    def when_phrase(locale, event)
      return "" if invitation.proposed_at.blank?

      stamped = I18n.l(invitation.proposed_at, format: :short, locale: locale)
      event.to_s == "scheduled" ? " (#{stamped})" : stamped
    end

    def detail_url
      host = ENV.fetch("APP_HOST", "http://localhost:3000")
      if invitation.scheduled? && invitation.game_id.present?
        Rails.application.routes.url_helpers.game_url(invitation.game, host: host)
      else
        Rails.application.routes.url_helpers.invitation_url(invitation, host: host)
      end
    end
  end
end
