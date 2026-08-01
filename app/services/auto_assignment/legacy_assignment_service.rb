class AutoAssignment::LegacyAssignmentService
  DEFAULT_BATCH_SIZE = 100

  pattr_initialize [:inbox!]

  def perform_bulk_assignment(limit: DEFAULT_BATCH_SIZE)
    return 0 if inbox.auto_assignment_v2_enabled?
    return 0 unless inbox.enable_auto_assignment?
    return 0 unless inbox.auto_assignment_config['max_assignment_limit'].to_i.positive?

    unassigned_conversations(limit).count { |conversation| perform_for_conversation(conversation) }
  end

  private

  def unassigned_conversations(limit)
    inbox.conversations
         .unassigned
         .open
         .reorder(created_at: :asc, id: :asc)
         .limit(limit)
         .to_a
  end

  def perform_for_conversation(conversation)
    conversation.reload
    return false unless conversation.open? && conversation.assignee_id.nil?

    allowed_agent_ids = allowed_agent_ids_for(conversation)
    return false if allowed_agent_ids.empty?

    AutoAssignment::AgentAssignmentService.new(
      conversation: conversation,
      allowed_agent_ids: allowed_agent_ids
    ).perform
  end

  def allowed_agent_ids_for(conversation)
    member_ids_with_capacity = inbox.member_ids_with_assignment_capacity
    return member_ids_with_capacity if conversation.team_id.blank?
    return [] if conversation.team.blank? || !conversation.team.allow_auto_assign?

    member_ids_with_capacity & conversation.team.members.ids
  end
end
