class Api::V1::Profile::AiTranslationAuthorizationsController < Api::BaseController
  def create
    authorization = Integrations::AiTranslate::AccessTokenService.new.authorization
    render json: { expires_in: authorization.fetch(:expires_in) }
  rescue StandardError => e
    Rails.logger.error("AI translate authorization failed: #{e.message}")
    render_could_not_create_error('Unable to authorize AI translation service')
  end
end
