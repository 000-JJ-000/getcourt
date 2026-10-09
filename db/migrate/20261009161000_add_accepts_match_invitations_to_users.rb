class AddAcceptsMatchInvitationsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :accepts_match_invitations, :boolean, default: true, null: false
  end
end
