class CreateCommunityInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :community_invitations do |t|
      t.references :community, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.references :invitee, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.timestamps
    end

    add_index :community_invitations, [ :community_id, :invitee_id ],
              unique: true,
              where: "status = 'pending'",
              name: "index_community_invitations_pending_unique"
    add_index :community_invitations, :status
    add_check_constraint :community_invitations,
                         "status IN ('pending', 'accepted', 'declined', 'revoked', 'expired')",
                         name: "community_invitations_status_check"
  end
end
