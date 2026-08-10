class Api::V1::Profile::AiTranslationsController < Api::BaseController
  def create
    result = Integrations::AiTranslate::TranslationService.new(
      content: translation_params.fetch(:content),
      source_lang: translation_params.fetch(:sourceLang),
      target_lang: translation_params.fetch(:targetLang)
    ).perform

    render json: { result: result }
  rescue StandardError => e
    Rails.logger.error("AI translation failed: #{e.message}")
    render_could_not_create_error('Unable to translate message')
  end

  private

  def translation_params
    params.permit(:content, :sourceLang, :targetLang)
  end
end
