module PlayerStatistics
  # Confirmation metadata lives on Match#stats for the logical match group.
  # Legacy rows without result_status count as confirmed (pre–P1-05 behavior).
  module MatchResultStatus
    STATUSES = %w[pending confirmed disputed].freeze
    DISPUTE_NOTE_MAX = 500

    module_function

    def status_for(stats)
      value = stats.to_h["result_status"].to_s
      STATUSES.include?(value) ? value : "confirmed"
    end

    def pending?(stats)
      status_for(stats) == "pending"
    end

    def confirmed?(stats)
      status_for(stats) == "confirmed"
    end

    def disputed?(stats)
      status_for(stats) == "disputed"
    end

    def counts_for_elo?(stats)
      confirmed?(stats)
    end

    # Competitive W/L/games counters use the same gate as ELO.
    def counts_for_competitive?(stats)
      counts_for_elo?(stats)
    end

    def requires_peer_confirmation?(game)
      game.present? && game.invite_only?
    end

    def submission_meta(actor:, game:, previous: {})
      previous = previous.to_h
      now = Time.current.utc.iso8601(6)
      if requires_peer_confirmation?(game)
        {
          "result_status" => "pending",
          "submitted_by" => actor.id,
          "result_updated_at" => now,
          "confirmed_by" => nil,
          "disputed_by" => nil,
          "dispute_note" => nil
        }
      else
        {
          "result_status" => "confirmed",
          "submitted_by" => actor.id,
          "confirmed_by" => actor.id,
          "result_updated_at" => previous["result_updated_at"].presence || now
        }
      end
    end

    def opposing_user_ids(stats, submitter_id)
      stats = stats.to_h
      team_a = Array(stats["team_a_ids"]).map(&:to_i)
      team_b = Array(stats["team_b_ids"]).map(&:to_i)
      submitter_id = submitter_id.to_i

      if team_a.include?(submitter_id)
        team_b
      elsif team_b.include?(submitter_id)
        team_a
      else
        (team_a + team_b - [ submitter_id ]).uniq
      end
    end

    def can_confirm_or_dispute?(user:, stats:)
      return false unless user
      return false unless pending?(stats)

      submitter_id = stats.to_h["submitted_by"].to_i
      return false if submitter_id == user.id

      opposing_user_ids(stats, submitter_id).include?(user.id)
    end
  end
end
