# frozen_string_literal: true

module Jdpools
  # Microsoft Entra sign-in: OpenID Connect authorization-code flow with PKCE.
  #
  # Written on faraday + jwt (both already in upstream's Gemfile) rather than an omniauth gem, so the
  # fork adds nothing to Gemfile.lock, the file most likely to conflict on upstream merges.
  module EntraOidc
    LOGIN_HOST = 'https://login.microsoftonline.com'
    GRAPH_ME_URL = 'https://graph.microsoft.com/v1.0/me'
    SCOPE = 'openid profile email User.Read'
    JWKS_CACHE_KEY = 'jdpools:entra:jwks'
    JWKS_CACHE_TTL = 12.hours

    class Error < StandardError; end

    Identity = Struct.new(:oid, :email, :first_name, :last_name, :app_roles, :department)

    module_function

    def authorize_url(redirect_uri:, state:, nonce:, code_verifier:)
      query = {
        client_id: Jdpools.entra_client_id,
        response_type: 'code',
        response_mode: 'query',
        redirect_uri:,
        scope: SCOPE,
        state:,
        nonce:,
        code_challenge: code_challenge(code_verifier),
        code_challenge_method: 'S256',
        prompt: 'select_account'
      }

      "#{tenant_url}/oauth2/v2.0/authorize?#{query.to_query}"
    end

    def code_challenge(code_verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    end

    # Exchanges the code, verifies the ID token and reads the Graph profile. Raises Error on any
    # failure; the caller shows one generic message.
    def identity_from_code(code:, redirect_uri:, code_verifier:, nonce:)
      tokens = exchange_code(code:, redirect_uri:, code_verifier:)
      claims = verify_id_token(tokens.fetch('id_token'), nonce:)
      profile = fetch_profile(tokens['access_token'])

      email = (claims['email'].presence || claims['preferred_username'].presence || profile['mail']).to_s.downcase

      raise Error, 'id token carries no email' if email.blank?

      Identity.new(
        oid: claims.fetch('oid'),
        email:,
        first_name: profile['givenName'].presence || claims['given_name'],
        last_name: profile['surname'].presence || claims['family_name'],
        app_roles: Array.wrap(claims['roles']),
        department: profile.key?('department') ? profile['department'].to_s : nil
      )
    end

    def exchange_code(code:, redirect_uri:, code_verifier:)
      response = http.post("#{tenant_url}/oauth2/v2.0/token") do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(
          client_id: Jdpools.entra_client_id,
          client_secret: Jdpools.entra_client_secret,
          grant_type: 'authorization_code',
          code:,
          redirect_uri:,
          code_verifier:,
          scope: SCOPE
        )
      end

      unless response.success?
        raise Error,
              "token endpoint returned #{response.status}: #{response.body.to_s.first(300)}"
      end

      JSON.parse(response.body)
    end

    def verify_id_token(id_token, nonce:)
      require 'jwt'

      claims, = JWT.decode(
        id_token, nil, true,
        algorithms: ['RS256'],
        jwks: jwks_loader,
        iss: "#{tenant_url}/v2.0", verify_iss: true,
        aud: Jdpools.entra_client_id, verify_aud: true,
        verify_expiration: true, verify_iat: true,
        leeway: 60
      )

      raise Error, 'id token is for another tenant' if claims['tid'] != Jdpools.entra_tenant_id

      nonce_matches = ActiveSupport::SecurityUtils.secure_compare(claims['nonce'].to_s, nonce.to_s)

      raise Error, 'id token nonce mismatch' unless nonce_matches

      claims
    rescue JWT::DecodeError => e
      raise Error, "id token rejected: #{e.message}"
    end

    # Department comes from Graph because Entra does not put it in the ID token. A Graph failure
    # returns {} and the caller keeps the department it already had.
    def fetch_profile(access_token)
      return {} if access_token.blank?

      response = http.get(GRAPH_ME_URL, { '$select' => 'department,givenName,surname,mail' },
                          { 'Authorization' => "Bearer #{access_token}" })

      return {} unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError
      {}
    end

    # Re-fetches the key set once when a token names a key we have not seen (Entra rotates keys).
    def jwks_loader
      lambda do |options|
        Rails.cache.delete(JWKS_CACHE_KEY) if options[:kid_not_found]

        keys = Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: JWKS_CACHE_TTL) do
          response = http.get("#{tenant_url}/discovery/v2.0/keys")

          raise Error, "jwks endpoint returned #{response.status}" unless response.success?

          JSON.parse(response.body)
        end

        JWT::JWK::Set.new(keys)
      end
    end

    def tenant_url
      "#{LOGIN_HOST}/#{Jdpools.entra_tenant_id}"
    end

    def http
      Faraday.new do |f|
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
