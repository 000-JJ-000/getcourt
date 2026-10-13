module PlayerStatistics
  class DisputeMatchResultService
    def initialize(game:, group_id:, by:, result_updated_at:, note: nil)
      @game = game
      @group_id = group_id.to_s
      @by = by
      @result_updated_at = result_updated_at
      @note = note.to_s.strip.presence
    end

    def call
      raise ArgumentError, "unauthorized" unless @by
      raise ArgumentError, "canceled" if @game.canceled?
      raise ArgumentError, "blank_group" if @group_id.blank?
      raise ArgumentError, "note_too_long" if @note && @note.length > MatchResultStatus::DISPUTE_NOTE_MAX

      Match.transaction do
        rows = MatchGroups.find(@game, @group_id)
        raise ArgumentError, "not_found" if rows.empty?

        stats = rows.first.stats.to_h
        raise ArgumentError, "not_pending" unless MatchResultStatus.pending?(stats)
        raise ArgumentError, "unauthorized" unless MatchResultStatus.can_confirm_or_dispute?(user: @by, stats: stats)
        raise ArgumentError, "stale_result" unless same_timestamp?(stats["result_updated_at"], @result_updated_at)

        rows.each do |row|
          row.with_lock do
            row.reload
            next unless MatchResultStatus.pending?(row.stats)

            row.stats = row.stats.to_h.merge(
              "result_status" => "disputed",
              "disputed_by" => @by.id,
              "dispute_note" => @note,
              "confirmed_by" => nil
            )
            row.save!
          end
        end
      end

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
