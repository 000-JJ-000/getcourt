module Communities
  class Notifier
    def self.membership_requested(membership)
      new(membership.community).notify_managers(:membership_requested, membership.user)
    end

    def self.membership_approved(membership)
      new(membership.community).deliver(membership.user, :membership_approved)
    end

    def self.game_announced(community, game)
      new(community).notify_active_members(:game_announced, except: game.user_id, game: game)
    end

    def self.invitation_created(invitation)
      new(invitation.community).deliver(invitation.invitee, :invitation_created, requester: invitation.inviter)
    end

    def self.invitation_accepted(invitation)
      new(invitation.community).notify_managers(:invitation_accepted, invitation.invitee)
    end

    def initialize(community)
      @community = community
    end

    def notify_managers(event, requester)
      managers = @community.memberships.active.where(role: %w[owner moderator]).includes(:user).map(&:user)
      managers << @community.creator if managers.exclude?(@community.creator)
      managers.compact.uniq(&:id).each { |user| deliver(user, event, requester: requester) }
    end

    def notify_active_members(event, except: nil, game: nil)
      @community.memberships.active.includes(:user).find_each do |membership|
        next if except && membership.user_id == except

        deliver(membership.user, event, game: game)
      end
    end

    def deliver(user, event, requester: nil, game: nil)
      NotificationDelivery.deliver(
        user: user,
        notification: notification_for(user, event, requester: requester, game: game)
      )
    rescue StandardError => e
      Rails.logger.warn("[Communities::Notifier] #{event} failed for community ##{@community.id}: #{e.class}: #{e.message}")
      false
    end

    private

    attr_reader :community

    def notification_for(_user, event, requester:, game:)
      url = detail_url(game)
      NotificationDelivery::Notification.new(
        subject: ->(locale) { I18n.t("communities.mail.#{event}.subject", locale: locale, name: community.name) },
        body: ->(locale, _channel) {
          I18n.t(
            "communities.mail.#{event}.body",
            locale: locale,
            name: community.name,
            user: requester&.name.presence || I18n.t("users.show.anonymous_name", locale: locale),
            date: game&.date ? I18n.l(game.date, format: :long, locale: locale) : ""
          )
        },
        actions: lambda { |locale|
          [ { label: I18n.t("communities.mail.view", locale: locale), url: url, row: 0 } ]
        }
      )
    end

    def detail_url(game)
      host = ENV.fetch("APP_HOST", "http://localhost:3000")
      if game
        Rails.application.routes.url_helpers.game_url(game, host: host)
      else
        Rails.application.routes.url_helpers.community_url(community, host: host)
      end
    end
  end
end
