class Api::V1::Accounts::ExclusiveLinksController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    account_user = Current.account.account_users
                          .includes(:user, exclusive_inbox: :channel)
                          .find_by(exclusive_link_token: params[:data])

    return render_invalid_link(:not_found) if account_user.blank? || account_user.exclusive_link.blank?
    return render_invalid_link(:unprocessable_content) unless valid_exclusive_inbox?(account_user)

    render json: exclusive_link_payload(account_user)
  end

  private

  def check_authorization
    authorize(User, :index?)
  end

  def valid_exclusive_inbox?(account_user)
    inbox = account_user.exclusive_inbox
    return false unless inbox&.account_id == Current.account.id
    return false unless inbox.web_widget? || inbox.api?

    inbox.channel.website_url.present? && inbox.inbox_members.exists?(user_id: account_user.user_id)
  end

  def exclusive_link_payload(account_user)
    agent = account_user.user
    inbox = account_user.exclusive_inbox

    {
      valid: true,
      data: account_user.exclusive_link_token,
      exclusive_link: "https://#{account_user.exclusive_link}",
      agent: agent_payload(agent, account_user),
      inbox: inbox_payload(inbox)
    }
  end

  def agent_payload(agent, account_user)
    {
      id: agent.id,
      name: agent.name,
      available_name: agent.available_name,
      availability_status: account_user.availability,
      avatar_url: agent.avatar_url
    }
  end

  def inbox_payload(inbox)
    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      website_url: inbox.channel.website_url,
      website_token: inbox.web_widget? ? inbox.channel.website_token : nil,
      inbox_identifier: inbox.api? ? inbox.channel.identifier : nil
    }.compact
  end

  def render_invalid_link(status)
    render json: { valid: false, error: 'Invalid or unavailable exclusive link' }, status: status
  end
end
