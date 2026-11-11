# frozen_string_literal: true

RSpec.describe 'Signer-facing pages', type: :request do
  let(:account) { create(:account, timezone: 'Bangkok') }
  let(:sender) { create(:user, account:, first_name: 'Rollie', last_name: 'Parame', email: 'rollie@example.com') }
  let(:template) { create(:template, account:, author: sender) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: sender) }
  let(:submitter) { submission.submitters.first }
  let(:thai_phone) { { 'Accept-Language' => 'th-TH,th;q=0.9' } }

  it 'shows a decline in the account time zone, with Thai month names, to a Thai phone' do
    submitter.update!(declined_at: Time.utc(2026, 11, 11, 4, 32))

    get "/s/#{submitter.slug}", headers: thai_phone

    expect(response.body).to include('11 พฤศจิกายน 2026 เวลา 11:32 น.')
    expect(response.body).not_to include('November')
  end

  it 'keeps the logo inside a phone screen' do
    template.update!(shared_link: true)

    get "/d/#{template.slug}", headers: thai_phone

    expect(response.body).to include('height: 50px; width: auto; max-width: 100%;')
    expect(response.body).not_to include('pxpx')
  end

  it 'opens the signing help in Thai for a Thai phone that has never chosen a language' do
    get '/help/signing', headers: thai_phone
    expect(response.body).to include('<html lang="th"')

    get '/help/signing', headers: { 'Accept-Language' => 'en-GB,en;q=0.9' }
    expect(response.body).to include('<html lang="en"')
  end

  describe 'document copy email' do
    let(:external) { submission.submitters.first.tap { |s| s.update!(email: 'signer@external.example') } }

    it 'keeps the sender as Reply-To when the sender signed last' do
      sender_as_signer = create(:submitter, submission:, email: sender.email, uuid: SecureRandom.uuid,
                                            completed_at: Time.current)
      external.update!(completed_at: 1.minute.ago)

      reply_to = SubmitterMailer.new.send(:build_submitter_reply_to, sender_as_signer, documents_copy_email: true)

      expect(reply_to).to include('rollie@example.com')
    end
  end

  it 'gives the signing help link full contrast and a 44px tap area' do
    get "/s/#{submitter.slug}", headers: thai_phone

    link = Nokogiri::HTML(response.body).at_css('a[href*="/help/signing"]')
    expect(link['class']).not_to include('opacity-70')
    expect(link['style']).to include('min-height: 44px')
  end

  it 'starts the invitation email with a hidden preview line instead of the greeting' do
    account.update!(name: 'J.D. Pools')
    submission.update!(name: 'NDA')

    message = SubmitterMailer.invitation_email(submitter).message
    html = (message.html_part || message).body.decoded.force_encoding(Encoding::UTF_8)

    expect(html).to match(/display: none.*J\.D\. Pools invites you to sign &quot;NDA&quot;/m)
    expect(html.index('invites you to sign')).to be < html.index('</div>')
  end
end
