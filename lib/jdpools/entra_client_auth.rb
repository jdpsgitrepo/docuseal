# frozen_string_literal: true

module Jdpools
  # How this app proves its identity to Entra's token endpoint.
  #
  # Preferred: a certificate (JDP_ENTRA_PRIVATE_KEY + JDP_ENTRA_CERTIFICATE). Only the public
  # certificate is uploaded to Entra, nothing secret is ever copied out of the portal, and it is
  # what Microsoft recommends. A client secret (JDP_ENTRA_CLIENT_SECRET) still works as a fallback.
  module EntraClientAuth
    ASSERTION_TYPE = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
    ASSERTION_TTL = 5.minutes

    module_function

    def configured?
      certificate? || Jdpools.entra_client_secret.present?
    end

    def certificate?
      private_key_pem.present? && certificate_pem.present?
    end

    # Form params to merge into any token request.
    def params(token_url)
      if certificate?
        { client_assertion_type: ASSERTION_TYPE, client_assertion: assertion(token_url) }
      else
        { client_secret: Jdpools.entra_client_secret }
      end
    end

    def assertion(token_url)
      require 'jwt'

      now = Time.current.to_i
      payload = {
        aud: token_url, iss: Jdpools.entra_client_id, sub: Jdpools.entra_client_id,
        jti: SecureRandom.uuid, nbf: now, iat: now, exp: now + ASSERTION_TTL.to_i
      }

      JWT.encode(payload, private_key, 'RS256', { x5t: thumbprint })
    end

    # Base64url SHA-1 of the DER certificate: the key id Entra matches against uploaded certificates.
    def thumbprint
      der = OpenSSL::X509::Certificate.new(certificate_pem).to_der

      Base64.urlsafe_encode64(OpenSSL::Digest::SHA1.digest(der), padding: false)
    end

    def private_key
      OpenSSL::PKey::RSA.new(private_key_pem)
    end

    # Railway stores multi-line values fine, but accept literal "\n" too.
    def private_key_pem
      ENV.fetch('JDP_ENTRA_PRIVATE_KEY', '').gsub('\\n', "\n").presence
    end

    def certificate_pem
      ENV.fetch('JDP_ENTRA_CERTIFICATE', '').gsub('\\n', "\n").presence
    end
  end
end
