class Integrations::AiTranslate::AccessTokenService
  TOKEN_PATH = '/admin-api/system/oauth2/token'.freeze
  SCOPE = 'ai.translate'.freeze
  TENANT_ID = '1'.freeze
  EXPIRY_BUFFER = 1.minute
  REQUIRED_ENV_VARS = %w[
    AI_TRANSLATE_API_BASE_URL
    AI_TRANSLATE_CLIENT_ID
    AI_TRANSLATE_CLIENT_SECRET
  ].freeze

  def self.configured?
    REQUIRED_ENV_VARS.all? { |key| ENV[key].present? }
  end

  def authorization
    access_token = Redis::Alfred.get(Redis::Alfred::AI_TRANSLATE_ACCESS_TOKEN)
    expires_in = Redis::Alfred.ttl(Redis::Alfred::AI_TRANSLATE_ACCESS_TOKEN)
    return { access_token: access_token, expires_in: expires_in } if access_token.present? && expires_in.positive?

    request_authorization
  end

  def access_token
    authorization.fetch(:access_token)
  end

  def refresh!
    Redis::Alfred.delete(Redis::Alfred::AI_TRANSLATE_ACCESS_TOKEN)
    request_authorization
  end

  private

  def request_authorization
    response = HTTParty.post(
      "#{api_base_url}#{TOKEN_PATH}",
      basic_auth: {
        username: ENV.fetch('AI_TRANSLATE_CLIENT_ID'),
        password: ENV.fetch('AI_TRANSLATE_CLIENT_SECRET')
      },
      headers: {
        'Accept' => 'application/json',
        'Content-Type' => 'application/x-www-form-urlencoded',
        'tenant-id' => TENANT_ID
      },
      body: {
        grant_type: 'client_credentials',
        scope: SCOPE
      }
    )

    raise "AI translate authorization failed with HTTP #{response.code}" unless response.success?

    payload = response.parsed_response
    raise "AI translate authorization failed: #{payload['msg']}" unless payload.fetch('code').zero?

    cache_authorization(payload.fetch('data'))
  end

  def cache_authorization(data)
    expires_in = data.fetch('expires_in').to_i - EXPIRY_BUFFER.to_i
    access_token = data.fetch('access_token')
    Redis::Alfred.set(Redis::Alfred::AI_TRANSLATE_ACCESS_TOKEN, access_token, ex: expires_in)

    { access_token: access_token, expires_in: expires_in }
  end

  def api_base_url
    ENV.fetch('AI_TRANSLATE_API_BASE_URL', 'https://ai-chat-dev.yamie.eu.cc').delete_suffix('/')
  end
end
