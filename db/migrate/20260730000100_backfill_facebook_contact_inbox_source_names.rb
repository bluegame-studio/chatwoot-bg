class BackfillFacebookContactInboxSourceNames < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE contact_inboxes
      SET source_name = contacts.name
      FROM contacts, inboxes
      WHERE contacts.id = contact_inboxes.contact_id
        AND inboxes.id = contact_inboxes.inbox_id
        AND inboxes.channel_type = 'Channel::FacebookPage'
        AND contact_inboxes.source_name IS NULL
        AND contacts.name IS NOT NULL
        AND contacts.name <> ''
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
