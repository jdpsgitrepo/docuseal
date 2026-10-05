# frozen_string_literal: true

RSpec.describe 'Thai locale', type: :request do
  it 'is available' do
    expect(I18n.available_locales).to include(:th)
  end

  it 'translates every key upstream ships for its signing-only languages' do
    upstream = YAML.load_file(Rails.root.join('config/locales/i18n.yml'), aliases: true)
    signing_keys = upstream['ar'].keys - %w[date time]

    missing = signing_keys.reject { |key| I18n.exists?(key, :th, fallback: false) }

    expect(missing).to be_empty
  end

  it 'gives a Thai phone the Thai signing page' do
    account = create(:account)
    template = create(:template, account:, author: create(:user, account:))
    submission = create(:submission, :with_submitters, template:, created_by_user: template.author)

    get "/s/#{submission.submitters.first.slug}", headers: { 'Accept-Language' => 'th-TH,th;q=0.9,en;q=0.8' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-language="th"')
  end
end
