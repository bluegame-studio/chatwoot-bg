class Public::Api::V1::CsatSurveyController < PublicController
  before_action :set_message
  before_action :set_conversation

  def show; end

  def update
    render json: { error: 'You cannot update the CSAT survey after 14 days' }, status: :unprocessable_entity and return if check_csat_locked

    @message.update!(message_update_params[:message])
  end

  private

  def set_conversation
    @conversation ||= @message.conversation
  end

  def set_message
    @message = find_message_by_survey_uuid(params[:id]) if params[:id].present?
    return if @message

    @conversation = Conversation.find_by!(uuid: params[:id])
    @message ||= @conversation.messages.find_by!(content_type: 'input_csat')
  end

  def find_message_by_survey_uuid(survey_uuid)
    sanitized_uuid = ActiveRecord::Base.sanitize_sql_like(survey_uuid)
    Message.input_csat
           .where('content_attributes::text LIKE ?', "%#{sanitized_uuid}%")
           .detect { |message| message.csat_survey_uuid == survey_uuid }
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }] }])
  end

  def check_csat_locked
    (Time.zone.now.to_date - @message.created_at.to_date).to_i > 14
  end
end
