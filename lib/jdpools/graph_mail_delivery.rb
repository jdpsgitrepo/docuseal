# frozen_string_literal: true

module Jdpools
  # ActionMailer delivery method that sends through Microsoft Graph as one fixed mailbox
  # (JDP_GRAPH_MAIL_FROM), the way the jdpoolstech apps already send. Exchange Online retired SMTP
  # basic auth, so a mailbox password over SMTP is not an option.
  #
  # Sends the full MIME message (POST /users/{mailbox}/sendMail, base64 MIME body), so attachments,
  # HTML and headers arrive exactly as DocuSeal built them. Needs the Mail.Send application
  # permission on the Entra app, ideally scoped to the one mailbox with RBAC for Applications.
  class GraphMailDelivery
    TOKEN_CACHE_KEY = 'jdpools:graph:mail_token'
    GRAPH_SCOPE = 'https://graph.microsoft.com/.default'

    class DeliveryError < StandardError; end

    def self.enabled?
      mailbox.present? && Jdpools.entra_tenant_id.present? && Jdpools.entra_client_id.present? &&
        EntraClientAuth.configured?
    end

    def self.mailbox
      ENV.fetch('JDP_GRAPH_MAIL_FROM', '').strip.downcase.presence
    end

    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      url = "https://graph.microsoft.com/v1.0/users/#{ERB::Util.url_encode(self.class.mailbox)}/sendMail"

      response = http.post(url) do |req|
        req.headers['Authorization'] = "Bearer #{access_token}"
        req.headers['Content-Type'] = 'text/plain'
        req.body = Base64.strict_encode64(mail.encoded)
      end

      return response if response.status == 202

      Rails.cache.delete(TOKEN_CACHE_KEY) if response.status == 401

      raise DeliveryError, "Graph sendMail returned #{response.status}: #{response.body.to_s.first(300)}"
    end

    private

    def access_token
      Rails.cache.fetch(TOKEN_CACHE_KEY, expires_in: 45.minutes) do
        token_url = "#{EntraOidc.tenant_url}/oauth2/v2.0/token"

        response = http.post(token_url) do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(
            { client_id: Jdpools.entra_client_id, grant_type: 'client_credentials', scope: GRAPH_SCOPE }
              .merge(EntraClientAuth.params(token_url))
          )
        end

        raise DeliveryError, "Graph token request returned #{response.status}" unless response.success?

        JSON.parse(response.body).fetch('access_token')
      end
    end

    def http
      Faraday.new do |f|
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end
  end
end
