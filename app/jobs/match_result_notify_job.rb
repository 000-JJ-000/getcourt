class MatchResultNotifyJob < ApplicationJob
  queue_as :default

  EVENTS = {
    "submitted" => :submitted,
    "confirmed" => :confirmed,
    "disputed" => :disputed,
    "peer_canceled" => :peer_canceled
  }.freeze

  def perform(game_id, group_id_or_nil, event)
    game = Game.find_by(id: game_id)
    return unless game

    method = EVENTS[event.to_s]
    return unless method

    MatchResults::Notifier.public_send(method, game, group_id_or_nil)
  end
end
