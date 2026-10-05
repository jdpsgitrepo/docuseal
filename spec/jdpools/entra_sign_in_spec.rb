# frozen_string_literal: true

require 'jwt'

RSpec.describe 'Microsoft Entra sign-in', type: :request do
  let(:tenant_id) { 'a1b2c3d4-0000-4000-8000-000000000001' }
  let(:client_id) { 'c1d2e3f4-0000-4000-8000-000000000002' }
  let(:signing_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:jwk) { JWT::JWK.new(signing_key, kid: 'test-key') }
  let(:login_url) { "https://login.microsoftonline.com/#{tenant_id}" }

  let!(:account) { create(:account) }
  let!(:setup_admin) { create(:user, account:, email: 'it.admin@jdpools.com') }

  let(:claims) do
    {
      'oid' => 'entra-oid-1',
      'tid' => tenant_id,
      'email' => 'Somchai.K@JDPools.com',
      'given_name' => 'Somchai',
      'family_name' => 'K',
      'roles' => [Jdpools::ENTRA_SENDER_APP_ROLE]
    }
  end
  let(:graph_profile) { { 'department' => 'Human Resources', 'givenName' => 'Somchai', 'surname' => 'Kaewmanee' } }

  before do
    allow(Jdpools).to receive_messages(entra_tenant_id: tenant_id, entra_client_id: client_id,
                                       entra_client_secret: 'secret')

    stub_request(:get, "#{login_url}/discovery/v2.0/keys")
      .to_return(body: JWT::JWK::Set.new(jwk).export.to_json)
    stub_request(:get, %r{\Ahttps://graph\.microsoft\.com/v1\.0/me})
      .to_return(body: graph_profile.to_json)
  end

  def start_sign_in
    post '/auth/entra'

    expect(response).to have_http_status(:redirect)
    location = URI.parse(response.location)
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq("#{login_url}/oauth2/v2.0/authorize")

    Rack::Utils.parse_query(location.query)
  end

  def id_token(nonce, overrides = {})
    payload = claims.merge(
      'iss' => "#{login_url}/v2.0", 'aud' => client_id, 'nonce' => nonce,
      'iat' => Time.current.to_i, 'exp' => 1.hour.from_now.to_i
    ).merge(overrides)

    JWT.encode(payload, signing_key, 'RS256', kid: 'test-key')
  end

  def complete_sign_in(query, token_overrides = {})
    stub_request(:post, "#{login_url}/oauth2/v2.0/token")
      .with(body: hash_including('code' => 'auth-code', 'code_verifier' => anything, 'client_secret' => 'secret'))
      .to_return(body: { id_token: id_token(query['nonce'], token_overrides), access_token: 'graph-token' }.to_json)

    get '/auth/entra/callback', params: { code: 'auth-code', state: query['state'] }
  end

  it 'creates the sender on first sign-in, from Entra, and signs them in' do
    query = start_sign_in

    expect(query).to include('client_id' => client_id, 'code_challenge_method' => 'S256', 'response_type' => 'code')

    complete_sign_in(query)

    user = User.find_by(email: 'somchai.k@jdpools.com')

    expect(response).to redirect_to(root_path)
    expect(user).to have_attributes(role: Jdpools::MEMBER_ROLE, first_name: 'Somchai', last_name: 'Kaewmanee')
    expect(Jdpools::Departments.for(user)).to eq('Human Resources')

    get '/settings/profile'
    expect(response).to have_http_status(:ok)
  end

  it 're-syncs role and department on a later sign-in' do
    complete_sign_in(start_sign_in)
    delete '/sign_out'

    claims['roles'] = [Jdpools::ENTRA_ADMIN_APP_ROLE]
    stub_request(:get, %r{\Ahttps://graph\.microsoft\.com/v1\.0/me})
      .to_return(body: graph_profile.merge('department' => 'Information Technology').to_json)
    complete_sign_in(start_sign_in)

    user = User.find_by(email: 'somchai.k@jdpools.com')
    expect(user.role).to eq(User::ADMIN_ROLE)
    expect(Jdpools::Departments.for(user)).to eq('Information Technology')
    expect(User.where('lower(email) = ?', 'somchai.k@jdpools.com').count).to eq(1)
  end

  it 'matches an existing user by email case-insensitively' do
    complete_sign_in(start_sign_in, 'email' => 'IT.Admin@jdpools.com', 'oid' => 'admin-oid',
                                    'roles' => [Jdpools::ENTRA_ADMIN_APP_ROLE])

    expect(response).to redirect_to(root_path)
    expect(User.count).to eq(1)
    expect(setup_admin.reload.role).to eq(User::ADMIN_ROLE)
  end

  it 'keeps the stored department when Graph cannot be read' do
    complete_sign_in(start_sign_in)
    delete '/sign_out'

    stub_request(:get, %r{\Ahttps://graph\.microsoft\.com/v1\.0/me}).to_return(status: 503)
    complete_sign_in(start_sign_in)

    expect(Jdpools::Departments.for(User.find_by(email: 'somchai.k@jdpools.com'))).to eq('Human Resources')
  end

  shared_examples 'a refused sign-in' do
    it 'does not sign anyone in' do
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq(I18n.t('jdp_entra_sign_in_failed'))
      expect(User.find_by(email: 'somchai.k@jdpools.com')).to be_nil

      get '/settings/profile'
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context 'when the user has no DocuSeal app role' do
    before { complete_sign_in(start_sign_in, 'roles' => []) }

    it_behaves_like 'a refused sign-in'
  end

  context 'when the token is for another tenant' do
    before { complete_sign_in(start_sign_in, 'tid' => 'some-other-tenant') }

    it_behaves_like 'a refused sign-in'
  end

  context 'when the nonce does not match' do
    before do
      query = start_sign_in
      complete_sign_in(query.merge('nonce' => 'forged'))
    end

    it_behaves_like 'a refused sign-in'
  end

  context 'when the token is signed by a key Entra does not publish' do
    before do
      query = start_sign_in
      forged = JWT.encode({ 'nonce' => query['nonce'] }, OpenSSL::PKey::RSA.new(2048), 'RS256', kid: 'test-key')
      stub_request(:post, "#{login_url}/oauth2/v2.0/token").to_return(body: { id_token: forged }.to_json)
      get '/auth/entra/callback', params: { code: 'auth-code', state: query['state'] }
    end

    it_behaves_like 'a refused sign-in'
  end

  context 'when the state does not match' do
    before do
      query = start_sign_in
      complete_sign_in(query.merge('state' => 'tampered'))
    end

    it_behaves_like 'a refused sign-in'
  end

  it 'refuses an archived user' do
    archived = create(:user, account:, email: 'somchai.k@jdpools.com', archived_at: Time.current)

    complete_sign_in(start_sign_in)

    expect(response).to redirect_to(new_user_session_path)
    expect(archived.reload.role).to eq(User::ADMIN_ROLE)
  end

  it 'is not routable when Entra is not configured' do
    allow(Jdpools).to receive(:entra_tenant_id).and_return(nil)

    post '/auth/entra'

    expect(response).to have_http_status(:not_found)
  end
end
