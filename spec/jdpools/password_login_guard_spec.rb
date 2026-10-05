# frozen_string_literal: true

RSpec.describe 'Password sign-in with Entra on', type: :request do
  let!(:account) { create(:account) }
  let!(:sender) { create(:user, account:, email: 'sender@jdpools.com', password: 'correct horse') }

  before do
    create(:user, account:, email: 'breakglass@jdpools.com', password: 'correct horse')

    allow(Jdpools).to receive_messages(entra_tenant_id: 'tenant', entra_client_id: 'client',
                                       entra_client_secret: 'secret',
                                       password_login_emails: ['breakglass@jdpools.com'])
  end

  def sign_in_with_password(email)
    post '/sign_in', params: { user: { email:, password: 'correct horse' } }
  end

  it 'lets a break-glass account in' do
    sign_in_with_password('BreakGlass@jdpools.com')

    expect(response).to redirect_to(root_path)
  end

  it 'turns everyone else away with a pointer to Microsoft sign-in, even with the right password' do
    sign_in_with_password('sender@jdpools.com')

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq(I18n.t('devise.failure.jdp_use_microsoft'))

    get '/settings/profile'
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'blocks the password-reset door too' do
    token = sender.send_reset_password_instructions

    put '/password', params: { user: { reset_password_token: token, password: 'new password 1',
                                       password_confirmation: 'new password 1' } }

    get '/settings/profile'
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'does not mail a reset link to a non-break-glass address' do
    expect do
      post '/password', params: { user: { email: 'sender@jdpools.com' } }
    end.not_to change(ActionMailer::Base.deliveries, :count)

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'shows the Microsoft button first and folds the password form away' do
    get '/sign_in'

    expect(response.body).to include(I18n.t('sign_in_with_microsoft'))
    expect(response.body).to include('<details')
    expect(response.body).to include(I18n.t('jdp_password_sign_in'))
  end

  context 'with Entra off' do
    before { allow(Jdpools).to receive(:entra_tenant_id).and_return(nil) }

    it 'behaves as upstream' do
      sign_in_with_password('sender@jdpools.com')

      expect(response).to redirect_to(root_path)
    end

    it 'shows the plain upstream login page' do
      get '/sign_in'

      expect(response.body).not_to include(I18n.t('sign_in_with_microsoft'))
      expect(response.body).not_to include('<details')
    end
  end
end
