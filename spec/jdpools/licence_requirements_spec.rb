# frozen_string_literal: true

# DocuSeal is AGPLv3 with a section 7(b) term. These guard the two obligations a rebrand can quietly
# break (JDPOOLS.md, "Licence obligations"):
#   - 7(b): the original DocuSeal attribution stays in every interactive UI;
#   - section 13: every network user is offered this modified version's source.
RSpec.describe 'Licence requirements', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }

  def expect_attribution_and_source(body)
    expect(body).to include(Docuseal::PRODUCT_URL, Jdpools.source_url)
  end

  it 'keeps attribution and the source link on staff pages' do
    sign_in(user)

    get '/settings/profile'

    expect_attribution_and_source(response.body)
  end

  it 'keeps attribution and the source link on the signing page' do
    template = create(:template, account:, author: user)
    submission = create(:submission, :with_submitters, template:, created_by_user: user)

    get "/s/#{submission.submitters.first.slug}"

    expect_attribution_and_source(response.body)
  end

  it 'keeps attribution and the source link on the sign-in lander' do
    user
    allow(Jdpools).to receive_messages(entra_tenant_id: 'tenant', entra_client_id: 'client',
                                       entra_client_secret: 'secret')

    get '/sign_in'

    expect_attribution_and_source(response.body)
  end

  it 'points the source link at the public fork' do
    expect(Jdpools.source_url).to eq('https://github.com/jdpsgitrepo/docuseal')
  end
end
