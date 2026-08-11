class Integrations::AiTranslate::TranslationService
  TRANSLATE_PATH = '/admin-api/ai/open/translate'.freeze
  TENANT_ID = '1'.freeze

  pattr_initialize [:content!, :source_lang!, :target_lang!]

  def perform
    token_service = Integrations::AiTranslate::AccessTokenService.new
    response = request_translation(token_service.access_token)
    response = request_translation(token_service.refresh!.fetch(:access_token)) if response.code == 401

    raise "AI translation failed with HTTP #{response.code}" unless response.success?

    payload = response.parsed_response
    raise "AI translation failed: #{payload['msg']}" unless payload.fetch('code').zero?

    payload.fetch('data').fetch('translatedContent')
  end

  private

  def request_translation(access_token)
    HTTParty.post(
      "#{api_base_url}#{TRANSLATE_PATH}",
      headers: {
        'Authorization' => "Bearer #{access_token}",
        'Content-Type' => 'application/json',
        'tenant-id' => TENANT_ID
      },
      body: {
        content: content,
        sourceLang: source_lang,
        targetLang: target_lang
      }.to_json
    )
  end

  def api_base_url
    ENV.fetch('AI_TRANSLATE_API_BASE_URL', 'https://ai-chat-dev.yamie.eu.cc').delete_suffix('/')
  end
end
