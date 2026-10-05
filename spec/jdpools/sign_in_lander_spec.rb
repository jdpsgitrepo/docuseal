# frozen_string_literal: true

RSpec.describe 'Sign-in lander', type: :request do
  before do
    create(:user, account: create(:account))
    allow(Jdpools).to receive_messages(entra_tenant_id: 'tenant', entra_client_id: 'client',
                                       entra_client_secret: 'secret')
  end

  it 'sends signed-out visitors from / to the sign-in page instead of the DocuSeal marketing page' do
    get '/'

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'carries a language choice through that redirect' do
    get '/', params: { lang: 'th' }

    expect(response).to redirect_to(new_user_session_path(lang: 'th'))
  end

  it 'shows the Microsoft button, the signer note and an EN / ไทย toggle' do
    get '/sign_in'

    expect(response.body).to include(I18n.t('sign_in_with_microsoft'), ERB::Util.html_escape(I18n.t('jdp_landing_signer_note')))
    expect(response.body).to include('lang="th"', 'lang="en"')
    expect(response.body).to include(I18n.t('powered_by'))
  end

  it 'switches to Thai and remembers it' do
    get '/sign_in', params: { lang: 'th' }

    expect(response.body).to include(I18n.t('jdp_landing_subtitle', locale: :th))
    expect(cookies[:jdp_lang]).to eq('th')

    get '/sign_in'

    expect(response.body).to include(I18n.t('jdp_landing_subtitle', locale: :th))

    get '/sign_in', params: { lang: 'en' }

    expect(response.body).to include(I18n.t('jdp_landing_subtitle', locale: :en))
  end

  it 'ignores languages other than EN and TH' do
    get '/sign_in', params: { lang: 'xx' }

    expect(cookies[:jdp_lang]).to be_blank
  end

  context 'with Microsoft sign-in off' do
    before { allow(Jdpools).to receive(:entra_tenant_id).and_return(nil) }

    it 'keeps the upstream landing page' do
      get '/'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t('jdp_landing_signer_note')))
    end
  end
end
