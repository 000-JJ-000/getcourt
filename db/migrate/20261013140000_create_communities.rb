class CreateCommunities < ActiveRecord::Migration[8.1]
  def change
    create_table :communities do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.references :city, foreign_key: true
      t.string :city_name
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :visibility, null: false, default: "public"
      t.string :membership_policy, null: false, default: "open"
      t.decimal :ntrp_min, precision: 3, scale: 1
      t.decimal :ntrp_max, precision: 3, scale: 1
      t.string :play_focus
      t.timestamps
    end

    add_index :communities, :slug, unique: true
    add_index :communities, :visibility
    add_index :communities, :city_name
    add_check_constraint :communities,
                         "visibility IN ('public', 'private')",
                         name: "communities_visibility_check"
    add_check_constraint :communities,
                         "membership_policy IN ('open', 'approval')",
                         name: "communities_membership_policy_check"
    add_check_constraint :communities,
                         "play_focus IS NULL OR play_focus IN ('singles', 'doubles', 'both')",
                         name: "communities_play_focus_check"

    create_table :community_memberships do |t|
      t.references :community, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "pending"
      t.datetime :responded_at
      t.timestamps
    end

    add_index :community_memberships, [ :community_id, :user_id ], unique: true, name: "index_community_memberships_on_community_and_user"
    add_index :community_memberships, :status
    add_check_constraint :community_memberships,
                         "role IN ('owner', 'moderator', 'member')",
                         name: "community_memberships_role_check"
    add_check_constraint :community_memberships,
                         "status IN ('active', 'pending', 'removed')",
                         name: "community_memberships_status_check"

    add_reference :games, :community, foreign_key: true, null: true
  end
end
