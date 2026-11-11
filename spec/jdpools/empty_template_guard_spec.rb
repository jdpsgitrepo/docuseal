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

  context 'when the template has a document but no fields (template 8, 2026-11-11)' do
    let(:fieldless_template) { create(:template, account:, author: user).tap { |t| t.update!(fields: []) } }

    it 'sends the sender back to add fields instead of opening a page with nothing to sign' do
      expect { put "/start_form_self/#{fieldless_template.id}" }.not_to change(Submission, :count)

      expect(response).to redirect_to(edit_template_path(fieldless_template))
      expect(flash[:alert]).to eq(I18n.t('jdp_template_has_no_fields'))
    end

    it 'refuses to send it to recipients' do
      expect do
        post "/templates/#{fieldless_template.id}/submissions",
             params: { submission: { submitters: [{ email: 'signer@example.com' }] } }
      end.not_to change(Submission, :count)

      expect(response).to redirect_to(edit_template_path(fieldless_template))
      expect(flash[:alert]).to eq(I18n.t('jdp_template_has_no_fields'))
    end

    it 'refuses a signer who opens its share link' do
      fieldless_template.update!(shared_link: true)
      sign_out(user)

      expect do
        put "/d/#{fieldless_template.slug}", params: { submitter: { email: 'signer@example.com' } }
      end.not_to change(Submission, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to eq(I18n.t('jdp_template_has_no_fields'))
    end
  end

  context 'when only the second party has fields' do
    let(:template) do
      create(:template, account:, author: user, submitter_count: 2).tap do |t|
        first_role = t.submitters.first['uuid']
        t.update!(fields: t.fields.reject { |f| f['submitter_uuid'] == first_role })
      end
    end

    it 'refuses Sign it yourself, which starts as the first party' do
      expect { put "/start_form_self/#{template.id}" }.not_to change(Submission, :count)

      expect(response).to redirect_to(edit_template_path(template))
      expect(flash[:alert]).to eq(I18n.t('jdp_template_first_role_has_no_fields'))
    end

    it 'still lets it be sent, with the first party as a view-only recipient' do
      expect do
        post "/templates/#{template.id}/submissions",
             params: { submission: { '1' => { submitters: [
               { uuid: template.submitters.first['uuid'], email: 'viewer@example.com' },
               { uuid: template.submitters.second['uuid'], email: 'signer@example.com' }
             ] } } }
      end.to change(Submission, :count).by(1)
    end
  end

  it 'gives the editor the Word file types when conversion is available' do
    allow(Jdpools::OfficeUpload).to receive(:available?).and_return(true)

    get "/templates/#{create(:template, account:, author: user).id}/edit"

    expect(response.body).to include('data-accept-file-types="image/*, application/pdf, application/zip, ' \
                                     'application/json, .docx')
  end
end
