# frozen_string_literal: true

RSpec.describe Jdpools::EmptyTemplateGuard, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:empty_template) do
    create(:template, account:, author: user).tap { |t| t.documents.destroy_all && t.update!(schema: [], fields: []) }
  end

  before { sign_in(user) }

  it 'sends the sender back to upload a document instead of signing an empty template themselves' do
    expect { put "/start_form_self/#{empty_template.id}" }.not_to change(Submission, :count)

    expect(response).to redirect_to(edit_template_path(empty_template))
    expect(flash[:alert]).to eq(I18n.t('jdp_template_has_no_document'))
  end

  it 'refuses to send an empty template to recipients' do
    expect do
      post "/templates/#{empty_template.id}/submissions",
           params: { submission: { submitters: [{ email: 'signer@example.com' }] } }
    end.not_to change(Submission, :count)

    expect(response).to redirect_to(edit_template_path(empty_template))
  end

  it 'still lets a template with a document be signed' do
    template = create(:template, account:, author: user)

    expect { put "/start_form_self/#{template.id}" }.to change(Submission, :count).by(1)
  end

  it 'gives the editor the Word file types when conversion is available' do
    allow(Jdpools::OfficeUpload).to receive(:available?).and_return(true)

    get "/templates/#{create(:template, account:, author: user).id}/edit"

    expect(response.body).to include('data-accept-file-types="image/*, application/pdf, application/zip, ' \
                                     'application/json, .docx')
  end
end
