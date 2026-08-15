class AddExclusiveLinkToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :exclusive_link, :string
    add_index :account_users, :exclusive_link, unique: true
  end
end
