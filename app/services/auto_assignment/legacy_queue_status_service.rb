class AutoAssignment::LegacyQueueStatusService
  pattr_initialize [:conversation!]

  def self.enabled_for?(inbox)
    !inbox.auto_assignment_v2_enabled? &&
      inbox.enable_auto_assignment? &&
      inbox.auto_assignment_config['max_assignment_limit'].to_i.positive?
  end

  def self.waiting_conversations(inbox)
    inbox.conversations.unassigned.open
  end

  def perform
    return unless self.class.enabled_for?(conversation.inbox)
    return { state: 'inactive', position: nil, ahead_count: 0 } unless conversation.open?
    return { state: 'assigned', position: nil, ahead_count: 0 } if conversation.assignee_id.present?

    ahead_count = conversations_ahead.count
    { state: 'waiting', position: ahead_count + 1, ahead_count: ahead_count }
  end

  private

  def conversations_ahead
    self.class.waiting_conversations(conversation.inbox).where(
      'conversations.created_at < :created_at OR (conversations.created_at = :created_at AND conversations.id < :id)',
      created_at: conversation.created_at,
      id: conversation.id
    )
  end
end
