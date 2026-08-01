# frozen_string_literal: true

INBOX_IDENTIFIER = ENV.fetch('INBOX_IDENTIFIER')
ASSIGNMENT_LIMIT = ENV.fetch('MAX_ASSIGNMENT_LIMIT', 2).to_i
WAIT_TIMEOUT = ENV.fetch('FIFO_MOCK_TIMEOUT', 75).to_i
POLL_INTERVAL = 0.5

def wait_until(description)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_TIMEOUT

  loop do
    return if yield
    raise "Timed out waiting for #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep POLL_INTERVAL
  end
end

def print_conversations(conversations)
  puts 'position | conversation_id | status   | assignee_id | created_at'
  conversations.each_with_index do |conversation, index|
    conversation.reload
    puts format(
      '%<position>8d | %<id>15d | %<status>-8s | %<assignee>11s | %<created_at>s',
      position: index + 1,
      id: conversation.id,
      status: conversation.status,
      assignee: conversation.assignee_id || 'unassigned',
      created_at: conversation.created_at.iso8601
    )
  end
end

channel = Channel::Api.find_by!(identifier: INBOX_IDENTIFIER)
inbox = channel.inbox
account = inbox.account

if ENV.fetch('FIFO_MOCK_ACTION', 'run') == 'cleanup'
  run_id = ENV.fetch('FIFO_MOCK_RUN_ID')
  conversations = inbox.conversations.where("additional_attributes ->> 'fifo_mock_run_id' = ?", run_id)
  contact_ids = conversations.distinct.pluck(:contact_id)
  conversation_count = conversations.count

  conversations.destroy_all
  Contact.where(id: contact_ids).destroy_all
  puts "Removed #{conversation_count} FIFO mock conversations for run #{run_id}"
  exit
end

raise 'Assignment V2 must be disabled for the account' if account.feature_enabled?('assignment_v2')
raise 'MAX_ASSIGNMENT_LIMIT must be greater than 0' unless ASSIGNMENT_LIMIT.positive?

member_ids = inbox.members.ids
agent_id = ENV['AGENT_ID']&.to_i
agent_id ||= member_ids.one? ? member_ids.first : nil
raise 'Set AGENT_ID when the inbox does not have exactly one member' if agent_id.blank?

agent = inbox.members.find(agent_id)
account_user = account.account_users.find_by!(user_id: agent.id)
existing_open_count = inbox.conversations.open.count
raise "Inbox already has #{existing_open_count} open conversations; use an empty mock inbox" if existing_open_count.positive?

run_id = "#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
original_auto_assignment = inbox.enable_auto_assignment?
original_availability = account_user.availability
original_auto_offline = account_user.auto_offline

begin
  inbox.update!(
    enable_auto_assignment: false,
    auto_assignment_config: inbox.auto_assignment_config.merge('max_assignment_limit' => ASSIGNMENT_LIMIT)
  )
  account_user.update!(availability: :offline, auto_offline: false)
  OnlineStatusTracker.set_status(account.id, agent.id, 'offline')

  mock_conversation_count = ASSIGNMENT_LIMIT + 2
  conversations = mock_conversation_count.times.map do |index|
    position = index + 1
    contact = Contact.create!(account: account, name: "FIFO Mock #{run_id} ##{position}")
    contact_inbox = ContactInbox.create!(
      contact: contact,
      inbox: inbox,
      source_id: "fifo-mock-#{run_id}-#{position}"
    )

    Conversation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      identifier: "fifo-mock-#{run_id}-#{position}",
      created_at: (mock_conversation_count + 1 - position).minutes.ago,
      additional_attributes: {
        'fifo_mock_run_id' => run_id,
        'fifo_mock_position' => position
      }
    )
  end

  inbox.update!(enable_auto_assignment: true)
  account_user.update!(availability: :online, auto_offline: false)
  OnlineStatusTracker.set_status(account.id, agent.id, 'online')

  AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox.id)
  wait_until('the first FIFO assignment') do
    conversations.count { |conversation| conversation.reload.assignee_id == agent.id } == ASSIGNMENT_LIMIT
  end

  expected_assignee_ids = Array.new(ASSIGNMENT_LIMIT, agent.id) + Array.new(2)
  actual_assignee_ids = conversations.map { |conversation| conversation.reload.assignee_id }
  raise "FIFO assertion failed: expected #{expected_assignee_ids.inspect}, got #{actual_assignee_ids.inspect}" unless actual_assignee_ids == expected_assignee_ids

  puts "\nInitial FIFO assignment passed for run #{run_id}:"
  print_conversations(conversations)

  in_flight_key = format(Redis::Alfred::AUTO_ASSIGNMENT_IN_FLIGHT_KEY, inbox_id: inbox.id)
  wait_until('the inbox assignment gate to be released') { Redis::Alfred.get(in_flight_key).nil? }

  conversations.first.update!(status: :resolved)
  next_waiting_conversation = conversations.fetch(ASSIGNMENT_LIMIT)
  newest_waiting_conversation = conversations.fetch(ASSIGNMENT_LIMIT + 1)
  wait_until('the oldest waiting conversation to receive released capacity') do
    next_waiting_conversation.reload.assignee_id == agent.id
  end

  raise 'FIFO assertion failed: the newest waiting conversation was assigned first' if newest_waiting_conversation.reload.assignee_id.present?

  open_assigned_count = inbox.conversations.open.where(assignee_id: agent.id).count
  raise "Capacity assertion failed: expected #{ASSIGNMENT_LIMIT} open conversations, got #{open_assigned_count}" unless open_assigned_count == ASSIGNMENT_LIMIT

  puts "\nFirst capacity release passed; the older backlog was assigned before the newest conversation:"
  print_conversations(conversations)

  wait_until('the inbox assignment gate to be released again') { Redis::Alfred.get(in_flight_key).nil? }

  second_assigned_conversation = conversations.find do |conversation|
    conversation.reload.open? && conversation.assignee_id == agent.id
  end
  second_assigned_conversation.update!(status: :resolved)
  wait_until('the newest waiting conversation to receive the next released capacity') do
    newest_waiting_conversation.reload.assignee_id == agent.id
  end

  puts "\nSecond capacity release passed; the newest conversation was assigned last:"
  print_conversations(conversations)
  puts "\nFIFO mock completed successfully. Run ID: #{run_id}"
  puts 'Use FIFO_MOCK_ACTION=cleanup and FIFO_MOCK_RUN_ID with this script to remove the mock records.'
ensure
  inbox.update!(enable_auto_assignment: original_auto_assignment)
  account_user.update!(availability: original_availability, auto_offline: original_auto_offline)
  OnlineStatusTracker.set_status(account.id, agent.id, original_availability)
end
