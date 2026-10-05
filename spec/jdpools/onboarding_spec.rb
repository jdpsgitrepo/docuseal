# frozen_string_literal: true

RSpec.describe 'Onboarding', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:member) { create(:user, account:, role: Jdpools::MEMBER_ROLE) }

  def section_titles(locale)
    I18n.t('jdp_guide.sections', locale:).pluck(:title)
  end

  describe 'staff guide' do
    it 'needs a signed-in user' do
      admin

      get '/guide'

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'shows senders every section except the IT-admin one' do
      sign_in(member)

      get '/guide'

      expect(response.body).to include(*section_titles(:en)[0..-2].map { |t| ERB::Util.html_escape(t) })
      expect(response.body).not_to include(section_titles(:en).last)
    end

    it 'shows IT admins the admin section too' do
      sign_in(admin)

      get '/guide'

      expect(response.body).to include(section_titles(:en).last, I18n.t('jdp_guide.admin_badge'))
    end

    it 'switches to Thai and remembers it for the walkthrough' do
      sign_in(member)

      get '/guide', params: { lang: 'th' }

      expect(response.body).to include(I18n.t('jdp_guide.title', locale: :th))
      expect(cookies[:jdp_lang]).to eq('th')

      get '/'

      # A sender with no documents yet gets the first-steps panel, in the language they chose.
      expect(response.body).to include(I18n.t('jdp_welcome_title', locale: :th),
                                       I18n.t('jdp_first_steps.guide', locale: :th))

      get '/', params: { tour: true }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t('app_tour.upload_a_pdf_file_description',
                                                                    locale: :th)))
    end

    it 'links from the navbar' do
      sign_in(member)

      get '/settings/profile'

      expect(response.body).to include('href="/guide"')
    end
  end

  describe 'signer help' do
    it 'is public and in English by default' do
      get '/help/signing'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('jdp_signer_help.title'))
      expect(response.body).to include(Jdpools.source_url)
    end

    it 'is available in Thai' do
      get '/help/signing', params: { lang: 'th' }

      expect(response.body).to include(I18n.t('jdp_signer_help.title', locale: :th))
    end

    it 'is linked from the signing page and the invitation email' do
      template = create(:template, account:, author: admin)
      submission = create(:submission, :with_submitters, template:, created_by_user: admin)
      submitter = submission.submitters.first
      submitter.update!(email: 'signer@example.com')

      get "/s/#{submitter.slug}"
      expect(response.body).to include('/help/signing')

      mail = SubmitterMailer.invitation_email(submitter)
      expect(mail.html_part&.body.to_s.presence || mail.body.to_s).to include('/help/signing')
    end
  end

  it 'has every English onboarding string in Thai' do
    %w[jdp_guide jdp_signer_help jdp_first_steps app_tour].each do |key|
      en = I18n.t(key, locale: :en)
      th = I18n.t(key, locale: :th)

      expect(en.keys - th.keys).to be_empty, "#{key} missing in th: #{en.keys - th.keys}" if en.is_a?(Hash)
    end

    expect(section_titles(:th).size).to eq(section_titles(:en).size)
  end
end
