module PlayerStatistics
  class ConfirmMatchResultService
    def initialize(game:, group_id:, by:, result_updated_at:)
      @game = game
      @group_id = group_id.to_s
      @by = by
      @result_updated_at = result_updated_at
    end

    def call
      raise ArgumentError, "unauthorized" unless @by
      raise ArgumentError, "canceled" if @game.canceled?
      raise ArgumentError, "blank_group" if @group_id.blank?

      mode = nil
      Match.transaction do
        rows = MatchGroups.find(@game, @group_id)
        raise ArgumentError, "not_found" if rows.empty?

        sample = rows.first
        stats = sample.stats.to_h
        raise ArgumentError, "already_confirmed" if stats["result_status"].to_s == "confirmed"
        raise ArgumentError, "not_pending" unless MatchResultStatus.pending?(stats)
        raise ArgumentError, "unauthorized" unless MatchResultStatus.can_confirm_or_dispute?(user: @by, stats: stats)
        raise ArgumentError, "stale_result" unless same_timestamp?(stats["result_updated_at"], @result_updated_at)

        rows.each do |row|
          row.with_lock do
            row.reload
            next unless MatchResultStatus.pending?(row.stats)

            row.stats = row.stats.to_h.merge(
              "result_status" => "confirmed",
              "confirmed_by" => @by.id,
              "disputed_by" => nil,
              "dispute_note" => nil
            )
            row.save!
            UpsertMatchForGameService.credit_confirmed_match!(row)
          end
        end
        mode = sample.mode
      end

      PlayerStatistic.recalculate_elo_for_mode!(mode) if mode
      true
    end

    private

    def same_timestamp?(expected, raw)
      return false if expected.blank? || raw.blank?

      got = Time.zone.parse(raw.to_s)
      return false if got.blank?

      Time.zone.parse(expected.to_s).utc.strftime("%Y-%m-%dT%H:%M:%S.%6N") ==
        got.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N")
    rescue ArgumentError, TypeError
      false
    end
  end
end
