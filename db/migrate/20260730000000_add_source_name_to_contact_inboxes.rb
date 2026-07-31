class AddSourceNameToContactInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :contact_inboxes, :source_name, :string
  end
end
