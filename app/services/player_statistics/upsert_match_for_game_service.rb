module PlayerStatistics
  class UpsertMatchForGameService
    def initialize(user:, game:, actor:, mode:, won: nil, outcome: nil, played_at: nil, opponent: nil, score: nil, hours: nil, stats: {}, force_new: false, match: nil)
      @user = user
      @game = game
      @actor = actor
      @mode = mode.to_s

      # backward-compatible:
      # - old callers pass won: true/false
      # - new callers can pass outcome: "win"/"loss"/"draw"
      @outcome =
        outcome.to_s.presence ||
          (won.nil? ? "draw" : (won ? "win" : "loss"))

      @played_at = played_at
      @opponent = opponent
      @score = score
      @hours = hours
      @stats = stats || {}
      @force_new = force_new
      @match = match
    end

    def call
      played_at = @played_at || default_played_at

      Match.transaction do
        match = find_or_init_match(played_at)
        new_record = match.new_record?
        stale = stale_match?(match)
        old_stats = match.persisted? && !stale ? match.stats.to_h : {}
        old_outcome = match.persisted? && !stale ? match.outcome.to_s : nil
        old_hours = match.persisted? && !stale ? match.stats.to_h["hours"] : nil
        old_counted = !stale && MatchResultStatus.counts_for_competitive?(old_stats)

        match.opponent = @opponent
        match.outcome = @outcome
        match.score = @score.to_s.presence
        match.played_at = played_at
        match.surface = surface_for(match)
        match.stats = (match.stats || {}).to_h.merge(@stats.to_h).tap do |stats|
          stats["hours"] = @hours if @hours.present?
          MatchResultStatus.submission_meta(actor: @actor, game: @game, previous: stats).each do |key, value|
            stats[key] = value
          end
        end
        match.save!

        new_counted = MatchResultStatus.counts_for_competitive?(match.stats)
        apply_competitive_and_hours!(
          old_counted: old_counted,
          new_counted: new_counted,
          new_record: new_record || stale,
          old_outcome: old_outcome,
          new_outcome: @outcome,
          old_hours: old_hours,
          new_hours: match.stats.to_h["hours"]
        )
        PlayerStatistic.recalculate_elo_for_mode!(@mode)

        match
      end
    end

    private

    def find_or_init_match(played_at)
      return @match if @match

      played_date = played_at.to_date
      return find_or_init_manual_match(played_date) if @game.nil?
      return Match.new(user: @user, game: @game, mode: @mode) if @force_new

      existing = Match.lock
                      .where(user: @user, game: @game, mode: @mode)
                      .where(played_at: played_date.beginning_of_day..played_date.end_of_day)
                      .first

      existing || Match.new(user: @user, game: @game, mode: @mode)
    end

    def find_or_init_manual_match(played_date)
      scope = Match.lock
                   .where(user: @user, game: nil, mode: @mode)
                   .where(played_at: played_date.beginning_of_day..played_date.end_of_day)

      existing =
        if @mode == "doubles"
          team_a_ids = normalize_ids(@stats["team_a_ids"])
          team_b_ids = normalize_ids(@stats["team_b_ids"])

          scope.to_a.find do |match|
            stats = match.stats.to_h
            normalize_ids(stats["team_a_ids"]) == team_a_ids
              && normalize_ids(stats["team_b_ids"]) == team_b_ids
              && normalize_guest_names(stats["team_a_guest_names"]) == normalize_guest_names(@stats["team_a_guest_names"])
              && normalize_guest_names(stats["team_b_guest_names"]) == normalize_guest_names(@stats["team_b_guest_names"])
          end
        else
          opponent_id = @opponent&.id || normalize_ids(@stats["opponent_ids"]).first
          opponent_guest_names = normalize_guest_names(opponent_guest_names_for_stats(@stats))

          scope.to_a.find do |match|
            stats = match.stats.to_h
            (opponent_id.present? && (match.opponent_id == opponent_id || normalize_ids(stats["opponent_ids"]).first == opponent_id))
              || (opponent_guest_names.any? && normalize_guest_names(opponent_guest_names_for_stats(stats)) == opponent_guest_names)
          end
        end

      existing || Match.new(user: @user, game: nil, mode: @mode)
    end

    # The game already knows where it is played, so the match row takes the
    # surface from it instead of leaving the statistics page with a dash.
    def surface_for(match)
      surface = @game&.surface.presence || sole_court_surface
      return match.surface if surface.blank?
      # A court could start offering a surface a match cannot store; keeping the
      # old value beats failing the whole stats save on a validation error.
      return match.surface unless Match::SURFACES.include?(surface)

      surface
    end

    # A court with a single surface leaves nothing to guess even when the game
    # itself was created without picking one.
    def sole_court_surface
      surfaces = Array(@game&.court&.surfaces)

      surfaces.first if surfaces.size == 1
    end

    def default_played_at
      start = @game.respond_to?(:start_at_for_ui) ? @game.start_at_for_ui : nil
      start || Time.current
    rescue
      Time.current
    end

    def normalize_ids(value)
      Array(value).map(&:to_i).uniq.sort
    end

    def normalize_guest_names(value)
      Array(value).map(&:to_s).map(&:strip).reject(&:blank?).sort
    end

    def opponent_guest_names_for_stats(stats)
      stats = stats.to_h
      user_id = @user.id
      team_a_ids = normalize_ids(stats["team_a_ids"])

      if team_a_ids.include?(user_id)
        stats["team_b_guest_names"]
      else
        stats["team_a_guest_names"]
      end
    end

    def stale_match?(match)
      reset_at = @user.player_statistic&.stats_reset_at
      match.persisted? && reset_at.present? && match.updated_at.present? && match.updated_at < reset_at
    end

    # Competitive W/L/games and match-linked hours only move when confirmed.
    # Pending/disputed rows may store hours on Match#stats but do not inflate
    # PlayerStatistic until confirmation (or open-game auto-confirm).
    def apply_competitive_and_hours!(old_counted:, new_counted:, new_record:, old_outcome:, new_outcome:, old_hours:, new_hours:)
      if new_counted && !old_counted
        apply_counters_delta!(new_record: true, old_outcome: nil, new_outcome: new_outcome, old_hours: 0, new_hours: new_hours, competitive: true)
      elsif old_counted && !new_counted
        apply_counters_delta!(new_record: false, old_outcome: old_outcome, new_outcome: nil, old_hours: old_hours, new_hours: 0, competitive: true, reverse_competitive: true)
      elsif old_counted && new_counted
        apply_counters_delta!(new_record: new_record, old_outcome: old_outcome, new_outcome: new_outcome, old_hours: old_hours, new_hours: new_hours, competitive: true)
      end
      # Pending/disputed: no PlayerStatistic mutation (hours stay on Match#stats only).
    end

    def apply_counters_delta!(new_record:, old_outcome:, new_outcome:, old_hours:, new_hours:, competitive: true, reverse_competitive: false)
      ps = @user.player_statistic || @user.create_player_statistic

      games_key = @mode == "doubles" ? :doubles_games : :singles_games
      hours_key = @mode == "doubles" ? :doubles_hours : :singles_hours
      wins_key = @mode == "doubles" ? :doubles_wins : :singles_wins
      losses_key = @mode == "doubles" ? :doubles_losses : :singles_losses

      training_key = nil
      if @game.respond_to?(:with_coach?) && @game.with_coach?
        if @mode == "doubles"
          training_key = :group_training
        else
          training_key = :individual_training
        end
      end

      activity_counted = if new_record && training_key.present? && competitive
        cycle_start = @game.respond_to?(:current_cycle_start) ? @game.current_cycle_start : nil
        scope = PlayerStatisticEntry.where(user: @user, game: @game)
        scope = scope.where("recorded_at >= ?", cycle_start) if cycle_start.present?
        scope.exists?
      else
        false
      end

      ps.with_lock do
        if competitive
          if reverse_competitive
            reverse_competitive_counters!(ps, games_key:, wins_key:, losses_key:, training_key:, outcome: old_outcome)
          elsif new_record
            unless activity_counted
              if training_key
                ps[training_key] = ps[training_key].to_i + 1
              else
                ps[games_key] = ps[games_key].to_i + 1
              end
            end

            if new_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i + 1
            elsif new_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i + 1
            end
          elsif old_outcome.present? && new_outcome.present? && old_outcome != new_outcome
            if old_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i - 1
            elsif old_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i - 1
            end

            if new_outcome == "win"
              ps[wins_key] = ps[wins_key].to_i + 1
            elsif new_outcome == "loss"
              ps[losses_key] = ps[losses_key].to_i + 1
            end
          end
        end

        ps[games_key] = [ ps[games_key].to_i, 0 ].max
        if training_key
          ps[training_key] = [ ps[training_key].to_i, 0 ].max
        end
        hours_delta = new_hours.to_f - old_hours.to_f
        ps[hours_key] = [ (ps[hours_key] || 0).to_f + hours_delta, 0.0 ].max if hours_delta != 0.0
        ps[wins_key] = [ ps[wins_key].to_i, 0 ].max
        ps[losses_key] = [ ps[losses_key].to_i, 0 ].max

        ps.save!
      end
    end

    def reverse_competitive_counters!(ps, games_key:, wins_key:, losses_key:, training_key:, outcome:)
      if training_key
        ps[training_key] = [ ps[training_key].to_i - 1, 0 ].max
      else
        ps[games_key] = [ ps[games_key].to_i - 1, 0 ].max
      end
      if outcome == "win"
        ps[wins_key] = [ ps[wins_key].to_i - 1, 0 ].max
      elsif outcome == "loss"
        ps[losses_key] = [ ps[losses_key].to_i - 1, 0 ].max
      end
    end

    # Called when a pending peer result is confirmed — credits W/L/games and hours.
    def self.credit_confirmed_match!(match)
      user = match.user
      mode = match.mode.to_s
      game = match.game
      hours = match.stats.to_h["hours"]
      new(user: user, game: game, actor: user, mode: mode, outcome: match.outcome).send(
        :apply_counters_delta!,
        new_record: true,
        old_outcome: nil,
        new_outcome: match.outcome.to_s,
        old_hours: 0,
        new_hours: hours,
        competitive: true
      )
    end
  end
end
