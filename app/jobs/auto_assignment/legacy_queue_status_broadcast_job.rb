class AutoAssignment::LegacyQueueStatusBroadcastJob < ApplicationJob
  include Events::Types

  BATCH_SIZE = 100

  queue_as :default

  def perform(inbox_id:, conversation_ids: [], refresh_waiting: false)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox
    return unless AutoAssignment::LegacyQueueStatusService.enabled_for?(inbox)

    changed_ids = Array(conversation_ids).map(&:to_i).index_with(true)
    broadcast_changed_conversations(inbox, changed_ids.keys)
    broadcast_waiting_conversations(inbox, changed_ids) if refresh_waiting
  end

  private

  def broadcast_changed_conversations(inbox, conversation_ids)
    inbox.conversations.where(id: conversation_ids).includes(:contact_inbox).find_each do |conversation|
      queue_status = AutoAssignment::LegacyQueueStatusService.new(conversation: conversation).perform
      broadcast_status(conversation, queue_status) if queue_status
    end
  end

  def broadcast_waiting_conversations(inbox, changed_ids)
    position = 0
    last_conversation = nil

    loop do
      conversations = waiting_batch(inbox, last_conversation)
      break if conversations.empty?

      conversations.each do |conversation|
        position += 1
        next if changed_ids[conversation.id]

        broadcast_status(
          conversation,
          state: 'waiting',
          position: position,
          ahead_count: position - 1
        )
      end
      last_conversation = conversations.last
    end
  end

  def waiting_batch(inbox, last_conversation)
    scope = AutoAssignment::LegacyQueueStatusService.waiting_conversations(inbox)
    if last_conversation
      scope = scope.where(
        'conversations.created_at > :created_at OR (conversations.created_at = :created_at AND conversations.id > :id)',
        created_at: last_conversation.created_at,
        id: last_conversation.id
      )
    end

    scope.reorder(created_at: :asc, id: :asc).includes(:contact_inbox).limit(BATCH_SIZE).to_a
  end

  def broadcast_status(conversation, queue_status)
    token = conversation.contact_inbox&.pubsub_token
    return if token.blank?

    ActionCableBroadcastJob.perform_later(
      [token],
      CONVERSATION_QUEUE_POSITION_CHANGED,
      {
        account_id: conversation.account_id,
        conversation_id: conversation.display_id,
        queue_status: queue_status
      }
    )
  end
end
