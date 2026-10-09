class CreateEmailLoginChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :email_login_challenges do |t|
      t.string :email, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :consumed_at
      t.string :request_ip
      t.string :locale
      t.string :telegram_locale

      t.timestamps
    end

    add_index :email_login_challenges, :email
    add_index :email_login_challenges, :expires_at
    add_index :email_login_challenges, [ :email, :consumed_at ]
  end
end
