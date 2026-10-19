module MatchResults
  class Notifier
    def self.submitted(game, group_id)
      new(game, group_id).notify_opponents_of_submitter(:submitted)
    end

    def self.confirmed(game, group_id)
      new(game, group_id).notify_participants(:confirmed)
    end

    def self.disputed(game, group_id)
      new(game, group_id).notify_participants(:disputed)
    end

    def self.peer_canceled(game, _group_id = nil)
      new(game, nil).notify_approved_participants(:peer_canceled)
    end

    def initialize(game, group_id)
      @game = game
      @group_id = group_id
    end

    def notify_opponents_of_submitter(event)
      rows = group_rows
      return if rows.empty?

      stats = rows.first.stats.to_h
      submitter_id = stats["submitted_by"].to_i
      PlayerStatistics::MatchResultStatus.opposing_user_ids(stats, submitter_id).each do |uid|
        user = User.find_by(id: uid)
        deliver(user, event) if user
      end
    end

    def notify_participants(event)
      group_rows.map(&:user_id).uniq.each do |uid|
        user = User.find_by(id: uid)
        deliver(user, event) if user
      end
    end

    def notify_approved_participants(event)
      users = [ @game.user ]
      users.concat(@game.participations.approved.includes(:user).filter_map(&:user))
      users.compact.uniq(&:id).each { |user| deliver(user, event) }
    end

    private

    def group_rows
      return [] if @group_id.blank?

      PlayerStatistics::MatchGroups.find(@game, @group_id)
    end

    def deliver(user, event)
      NotificationDelivery.deliver(user: user, notification: notification_for(user, event))
    rescue StandardError => e
      Rails.logger.warn("[MatchResults::Notifier] #{event} failed for game ##{@game.id}: #{e.class}: #{e.message}")
      false
    end

    def notification_for(_user, event)
      url = detail_url
      NotificationDelivery::Notification.new(
        subject: ->(locale) { I18n.t("match_results.mail.#{event}.subject", locale: locale) },
        body: ->(locale, _channel) {
          I18n.t(
            "match_results.mail.#{event}.body",
            locale: locale,
            date: @game.date ? I18n.l(@game.date, format: :long, locale: locale) : ""
          )
        },
        actions: lambda { |locale|
          [ { label: I18n.t("match_results.mail.view", locale: locale), url: url, row: 0 } ]
        }
      )
    end

    def detail_url
      Rails.application.routes.url_helpers.game_url(@game, **PublicAppHost.url_options)
    end
  end
end
