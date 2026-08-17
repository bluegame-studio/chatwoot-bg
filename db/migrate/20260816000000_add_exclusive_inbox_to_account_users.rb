class AddExclusiveInboxToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_reference :account_users, :exclusive_inbox, foreign_key: { to_table: :inboxes, on_delete: :nullify }
    add_column :account_users, :exclusive_link_token, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE account_users
          SET exclusive_link_token = substring(exclusive_link FROM '/exclusive/([A-Za-z0-9_-]+)$')
          WHERE exclusive_link IS NOT NULL
        SQL
      end
    end

    add_index :account_users, [:account_id, :exclusive_link_token],
              unique: true,
              where: 'exclusive_link_token IS NOT NULL',
              name: 'index_account_users_on_account_and_exclusive_token'
  end
end
