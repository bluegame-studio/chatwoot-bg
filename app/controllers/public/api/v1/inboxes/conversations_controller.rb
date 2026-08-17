class Public::Api::V1::Inboxes::ConversationsController < Public::Api::V1::InboxesController
  include Events::Types
  before_action :set_conversation, only: [:toggle_typing, :update_last_seen, :show, :toggle_status]

  def index
    @conversations = @contact_inbox.hmac_verified? ? contact_conversations : @contact_inbox.conversations
  end

  def show; end

  def create
    ActiveRecord::Base.transaction do
      @conversation = create_conversation
      create_initial_message if initial_message?
    end
  end

  def toggle_status
    # Check if the conversation is already resolved to prevent redundant operations
    return if @conversation.resolved?

    # Assign the conversation's contact as the resolver
    # This step attributes the resolution action to the contact involved in the conversation
    # If this assignment is not made, the system implicitly becomes the resolver by default
    Current.contact = @conversation.contact

    # Update the conversation's status to 'resolved' to reflect its closure
    @conversation.status = :resolved
    @conversation.save!
  end

  def toggle_typing
    case params[:typing_status]
    when 'on'
      trigger_typing_event(CONVERSATION_TYPING_ON)
    when 'off'
      trigger_typing_event(CONVERSATION_TYPING_OFF)
    end
    head :ok
  end

  def update_last_seen
    @conversation.contact_last_seen_at = DateTime.now.utc
    @conversation.save!
    ::Conversations::UpdateMessageStatusJob.perform_later(@conversation.id, @conversation.contact_last_seen_at)
    head :ok
  end

  private

  def set_conversation
    @conversation = if @contact_inbox.hmac_verified?
                      @contact_inbox.contact.conversations.find_by!(display_id: params[:id])
                    else
                      @contact_inbox.conversations.find_by!(display_id: params[:id])
                    end
  end

  def create_conversation
    ConversationBuilder.new(params: conversation_params, contact_inbox: @contact_inbox).perform
  end

  def initial_message?
    initial_message_params[:content].present? || params[:attachments].present?
  end

  def create_initial_message
    message = @conversation.messages.new(initial_message_params)
    params[:attachments]&.each do |uploaded_attachment|
      message.attachments.new(
        account_id: message.account_id,
        file_type: helpers.file_type(uploaded_attachment&.content_type),
        file: uploaded_attachment
      )
    end
    message.save!
  end

  def initial_message_params
    {
      account_id: @conversation.account_id,
      sender: @contact_inbox.contact,
      content: params.permit(:content)[:content],
      inbox_id: @conversation.inbox_id,
      message_type: :incoming
    }
  end

  def trigger_typing_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: @conversation, user: @conversation.contact)
  end

  def conversation_params
    params.permit(custom_attributes: {})
  end
end
