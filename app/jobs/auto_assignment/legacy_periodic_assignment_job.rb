class AutoAssignment::LegacyPeriodicAssignmentJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_in_batches do |accounts|
      accounts.each do |account|
        next if account.feature_enabled?('assignment_v2')

        account.inboxes.where(enable_auto_assignment: true).find_each do |inbox|
          next unless inbox.auto_assignment_config['max_assignment_limit'].to_i.positive?

          AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox.id)
        end
      end
    end
  end
end
