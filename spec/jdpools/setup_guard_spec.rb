# frozen_string_literal: true

RSpec.describe Jdpools::SetupGuard, type: :request do
  before { allow(ENV).to receive(:fetch).and_call_original }

  context 'with JDP_SETUP_TOKEN set' do
    before { allow(ENV).to receive(:fetch).with('JDP_SETUP_TOKEN', '').and_return('s3cret-setup') }

    it 'hides setup from anyone without the token' do
      get '/setup'
      expect(response).to have_http_status(:not_found)

      get '/setup', params: { token: 'wrong' }
      expect(response).to have_http_status(:not_found)

      post '/setup', params: { account: { name: 'Mallory' } }
      expect(response).to have_http_status(:not_found)
      expect(Account.count).to eq(0)
    end

    it 'opens setup with the token and keeps it open for the form post' do
      get '/setup', params: { token: 's3cret-setup' }
      expect(response).to have_http_status(:ok)

      get '/setup'
      expect(response).to have_http_status(:ok)
    end
  end

  it 'leaves setup as upstream when no token is configured' do
    get '/setup'

    expect(response).to have_http_status(:ok)
  end
end
