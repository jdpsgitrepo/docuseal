# frozen_string_literal: true

require 'jwt'

RSpec.describe Jdpools::GraphMailDelivery do
  let(:tenant_id) { 'tenant-1' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:send_url) { 'https://graph.microsoft.com/v1.0/users/it-service%40jdpools.com/sendMail' }
  let(:key) { OpenSSL::PKey::RSA.new(2048) }
  let(:certificate) do
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=jdpools-docuseal')
      cert.public_key = key.public_key
      cert.not_before = 1.day.ago
      cert.not_after = 1.year.from_now
      cert.sign(key, OpenSSL::Digest.new('SHA256'))
    end
  end

  let(:mail) do
    Mail.new(from: 'Somchai <it-service@jdpools.com>', to: 'signer@example.com',
             subject: 'กรุณาลงนาม', body: 'Please sign')
  end

  before do
    # Test env uses :null_store; production uses :memory_store, which is what token reuse relies on.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Jdpools).to receive_messages(entra_tenant_id: tenant_id, entra_client_id: 'client-1')
    allow(Jdpools::EntraClientAuth).to receive_messages(private_key_pem: key.to_pem,
                                                        certificate_pem: certificate.to_pem)
    allow(described_class).to receive(:mailbox).and_return('it-service@jdpools.com')

    stub_request(:post, token_url).to_return(body: { access_token: 'graph-token', expires_in: 3599 }.to_json)
    stub_request(:post, send_url).to_return(status: 202)
  end

  it 'authenticates with a signed certificate assertion, never a secret' do
    described_class.new.deliver!(mail)

    expect(WebMock).to(have_requested(:post, token_url).with do |req|
      form = Rack::Utils.parse_query(req.body)
      claims, header = JWT.decode(form['client_assertion'], key.public_key, true, algorithm: 'RS256')

      form['grant_type'] == 'client_credentials' &&
        form['client_secret'].nil? &&
        form['client_assertion_type'] == Jdpools::EntraClientAuth::ASSERTION_TYPE &&
        claims.values_at('aud', 'iss', 'sub') == [token_url, 'client-1', 'client-1'] &&
        header['x5t'] == Base64.urlsafe_encode64(OpenSSL::Digest::SHA1.digest(certificate.to_der), padding: false)
    end)
  end

  it 'posts the full MIME message as the configured mailbox' do
    described_class.new.deliver!(mail)

    expect(WebMock).to(have_requested(:post, send_url).with do |req|
      req.headers['Authorization'] == 'Bearer graph-token' &&
        Mail.new(Base64.strict_decode64(req.body)).subject == 'กรุณาลงนาม'
    end)
  end

  it 'reuses the access token across sends' do
    2.times { described_class.new.deliver!(mail) }

    expect(WebMock).to have_requested(:post, token_url).once
  end

  it 'raises on a Graph failure and drops a rejected token' do
    stub_request(:post, send_url).to_return(status: 401, body: 'InvalidAuthenticationToken')

    expect { described_class.new.deliver!(mail) }.to raise_error(described_class::DeliveryError, /401/)

    stub_request(:post, send_url).to_return(status: 202)
    described_class.new.deliver!(mail)

    expect(WebMock).to have_requested(:post, token_url).twice
  end

  it 'tells upstream that email can be sent' do
    allow(described_class).to receive(:enabled?).and_return(true)

    expect(Accounts.can_send_emails?(nil)).to be(true)
  end
end
