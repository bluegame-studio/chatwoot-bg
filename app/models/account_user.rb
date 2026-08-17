# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  exclusive_link           :string
#  exclusive_link_token     :string
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  custom_role_id           :bigint
#  exclusive_inbox_id       :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_and_exclusive_token  (account_id,exclusive_link_token) UNIQUE WHERE (exclusive_link_token IS NOT NULL)
#  index_account_users_on_account_id                   (account_id)
#  index_account_users_on_agent_capacity_policy_id     (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id               (custom_role_id)
#  index_account_users_on_exclusive_inbox_id           (exclusive_inbox_id)
#  index_account_users_on_exclusive_link               (exclusive_link) UNIQUE
#  index_account_users_on_user_id                      (user_id)
#  uniq_user_id_per_account_id                         (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (exclusive_inbox_id => inboxes.id) ON DELETE => nullify
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :exclusive_inbox, class_name: 'Inbox', optional: true

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account

  before_validation :normalize_exclusive_link, if: :exclusive_configuration_changed?

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?
  after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_visibility_changed?

  validates :user_id, uniqueness: { scope: :account_id }
  validates :exclusive_link, uniqueness: true, allow_blank: true
  validates :exclusive_link_token, uniqueness: { scope: :account_id }, allow_blank: true
  validate :validate_exclusive_configuration, if: :exclusive_configuration_changed?

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account, user)
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  def normalize_exclusive_link
    self.exclusive_link = exclusive_link.to_s.strip.sub(%r{\Ahttps?://}i, '').presence
    self.exclusive_link_token = exclusive_link.to_s[%r{/exclusive/([A-Za-z0-9_-]+)\z}, 1]
    self.exclusive_inbox = nil if exclusive_link.blank?
  end

  def validate_exclusive_configuration
    return if exclusive_link.blank? && exclusive_inbox.blank?

    errors.add(:exclusive_link, :invalid) if exclusive_link_token.blank?
    errors.add(:exclusive_inbox, :invalid) unless valid_exclusive_inbox?
  end

  def valid_exclusive_inbox?
    return false unless exclusive_inbox&.account_id == account_id
    return false unless exclusive_inbox.web_widget? || exclusive_inbox.api?

    exclusive_inbox.channel.website_url.present? && exclusive_inbox.inbox_members.exists?(user_id: user_id)
  end

  def exclusive_configuration_changed?
    will_save_change_to_exclusive_link? || will_save_change_to_exclusive_inbox_id?
  end

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end

  def filtered_unread_count_visibility_changed?
    previous_changes.key?('role') || previous_changes.key?('custom_role_id')
  end

  def invalidate_filtered_unread_count_visibility
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    dispatch_account_cache_invalidated if invalidate_filtered_unread_count_visibility
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
