class AddSchedulingToMatchInvitations < ActiveRecord::Migration[8.1]
  def change
    change_table :match_invitations, bulk: true do |t|
      t.string :scheduling_status, null: false, default: "none"
      t.references :proposed_by, foreign_key: { to_table: :users }, null: true
      t.string :proposal_note, limit: 500
      t.datetime :proposal_updated_at
      t.datetime :scheduling_reminded_at
    end

    add_index :match_invitations, :scheduling_status
    add_check_constraint :match_invitations,
                         "scheduling_status IN ('none', 'needed', 'proposed', 'scheduled')",
                         name: "match_invitations_scheduling_status_check"
  end
end
