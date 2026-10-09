class CreateMatchInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :match_invitations do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.references :invitee, null: false, foreign_key: { to_table: :users }
      t.references :game, null: true, foreign_key: true
      t.references :court, null: true, foreign_key: true
      t.string :play_format, null: false, default: "singles"
      t.datetime :proposed_at
      t.string :message, limit: 500
      t.string :status, null: false, default: "pending"
      t.datetime :responded_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :match_invitations, :status
    add_index :match_invitations, :expires_at
    add_index :match_invitations, [ :inviter_id, :invitee_id ],
              unique: true,
              where: "status = 'pending'",
              name: "index_match_invitations_unique_pending_pair"
    add_check_constraint :match_invitations,
                         "status IN ('pending', 'accepted', 'declined', 'canceled', 'expired')",
                         name: "match_invitations_status_check"
    add_check_constraint :match_invitations,
                         "play_format IN ('singles', 'doubles')",
                         name: "match_invitations_play_format_check"
    add_check_constraint :match_invitations,
                         "inviter_id <> invitee_id",
                         name: "match_invitations_not_self_check"
  end
end
