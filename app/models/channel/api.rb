# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  secret                :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :website_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  store_accessor :additional_attributes, :website_url

  has_secure_token :identifier
  has_secure_token :hmac_token
  include WebhookSecretable
  validate :ensure_valid_agent_reply_time_window
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validates :website_url, length: { maximum: Limits::URL_LENGTH_LIMIT },
                          format: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                          allow_blank: true

  def name
    'API'
  end

  def website_url=(value)
    normalized_value = value.to_s.strip
    normalized_value = "https://#{normalized_value}" if normalized_value.present? && !normalized_value.match?(%r{\Ahttps?://}i)
    super(normalized_value.delete_suffix('/').presence)
  end

  private

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end
end
