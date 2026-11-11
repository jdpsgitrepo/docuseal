# frozen_string_literal: true

RSpec.describe Jdpools::StrictSigningOrder, type: :request do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, submitter_count: 2) }

  def submission_with(order)
    create(:submission, :with_submitters, template:, created_by_user: author, submitters_order: order)
  end

  def parties(submission)
    uuids = submission.template_submitters.pluck('uuid')
    submission.submitters.sort_by { |s| uuids.index(s.uuid) }
  end

  it 'shows the second signer a waiting page until the first has signed' do
    first, second = parties(submission_with('preserved'))

    get "/s/#{second.slug}"
    expect(response.body).to include(I18n.t('awaiting_completion_by_the_other_party'))

    first.update!(completed_at: Time.current)
    get "/s/#{second.slug}"
    expect(response.body).not_to include(I18n.t('awaiting_completion_by_the_other_party'))
  end

  it 'refuses a form submit from a signer whose turn has not come' do
    _, second = parties(submission_with('preserved'))

    put "/s/#{second.slug}", params: { values: {} }

    expect(response).to have_http_status(:unprocessable_content)
    expect(second.reload.completed_at).to be_nil
  end

  it 'lets everyone sign at once when the document was sent without signing order' do
    _, second = parties(submission_with('random'))

    get "/s/#{second.slug}"

    expect(response.body).not_to include(I18n.t('awaiting_completion_by_the_other_party'))
  end

  it 'never blocks the first signer' do
    first, = parties(submission_with('preserved'))

    get "/s/#{first.slug}"

    expect(response.body).not_to include(I18n.t('awaiting_completion_by_the_other_party'))
  end
end
