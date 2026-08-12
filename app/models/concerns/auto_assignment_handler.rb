module AutoAssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    after_commit :run_auto_assignment, :enqueue_legacy_queue_status_broadcast
  end

  private

  def run_auto_assignment
    if inbox.auto_assignment_v2_enabled?
      return unless v2_assignment_trigger?
    else
      return unless legacy_assignment_trigger?
    end

    AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox.id)
  end

  def v2_assignment_trigger?
    return false unless inbox.enable_auto_assignment?
    return true if conversation_status_changed_to_resolved_or_snoozed?

    conversation_status_changed_to_open? && unassigned_or_ineligible_assignee?
  end

  def legacy_assignment_trigger?
    return false unless legacy_assignment_enabled?
    return true if legacy_capacity_released?

    conversation_status_changed_to_open? && unassigned_or_ineligible_assignee?
  end

  def legacy_assignment_enabled?
    inbox.enable_auto_assignment? && inbox.auto_assignment_config['max_assignment_limit'].to_i.positive?
  end

  def enqueue_legacy_queue_status_broadcast
    return unless legacy_assignment_enabled?
    return if inbox.auto_assignment_v2_enabled?
    return if Current.executed_by.instance_of?(Inbox)

    if destroyed?
      enqueue_queue_status_broadcast(conversation_ids: [], refresh_waiting: open? && assignee_id.nil?)
      return
    end

    waiting_now = open? && assignee_id.nil?
    if previously_new_record?
      enqueue_queue_status_broadcast(conversation_ids: [id], refresh_waiting: false) if waiting_now
      return
    end

    return unless saved_change_to_status? || saved_change_to_assignee_id?

    waiting_before = status_before_last_save == 'open' && assignee_id_before_last_save.nil?
    state_before = if status_before_last_save != 'open'
                     'inactive'
                   elsif assignee_id_before_last_save.present?
                     'assigned'
                   else
                     'waiting'
                   end
    state_now = if !open?
                  'inactive'
                elsif assignee_id.present?
                  'assigned'
                else
                  'waiting'
                end
    return if state_before == state_now

    enqueue_queue_status_broadcast(conversation_ids: [id], refresh_waiting: waiting_before != waiting_now)
  end

  def enqueue_queue_status_broadcast(conversation_ids:, refresh_waiting:)
    AutoAssignment::LegacyQueueStatusBroadcastJob.perform_later(
      inbox_id: inbox.id,
      conversation_ids: conversation_ids,
      refresh_waiting: refresh_waiting
    )
  end

  def legacy_capacity_released?
    open_status_released? || previous_assignee_released?
  end

  def open_status_released?
    saved_change_to_status? && status_before_last_save == 'open' && !open?
  end

  def previous_assignee_released?
    saved_change_to_assignee_id? && assignee_id_before_last_save.present?
  end

  def conversation_status_changed_to_resolved_or_snoozed?
    saved_change_to_status? && (resolved? || snoozed?)
  end

  def unassigned_or_ineligible_assignee?
    assignee.blank? || inbox.members.exclude?(assignee)
  end
end
