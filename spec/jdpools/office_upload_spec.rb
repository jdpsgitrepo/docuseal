# frozen_string_literal: true

RSpec.describe Jdpools::OfficeUpload, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:docx) { Rails.root.join('spec/fixtures/jdpools/nda-th.docx') }
  let(:docx_type) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }

  before { sign_in(user) }

  def upload(path, type)
    post '/templates_upload', params: { files: [Rack::Test::UploadedFile.new(path, type)] }
  end

  context 'with LibreOffice installed', if: described_class.available? do
    it 'turns a Thai Word file into a template with its pages, named after the file' do
      expect { upload(docx, docx_type) }.to change(Template, :count).by(1)

      template = Template.last
      expect(response).to redirect_to(edit_template_path(template))
      expect(template.name).to eq('nda-th')
      expect(template.schema.size).to eq(1)

      document = template.documents.first
      expect(document.content_type).to eq('application/pdf')
      expect(document.filename.to_s).to eq('nda-th.pdf')
      expect(document.metadata.dig('pdf', 'number_of_pages')).to eq(1)
      expect(document.preview_images).to be_present
    end

    it 'converts a Word file sent with a generic content type, by its extension' do
      upload(docx, 'application/octet-stream')

      expect(Template.last.documents.first.content_type).to eq('application/pdf')
    end

    it 'offers Word files in the upload pickers' do
      expect(Docuseal.advanced_formats?).to be(true)
    end
  end

  it 'leaves no empty template behind when an upload cannot be read' do
    allow(described_class).to receive(:to_pdf).and_raise(described_class::ConversionFailed, 'boom')
    allow(Rails.env).to receive(:local?).and_return(false)

    expect { upload(docx, docx_type) }.not_to change(Template, :count)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t('unable_to_update_file'))
  end

  it 'leaves no empty template behind for an unsupported file' do
    allow(Rails.env).to receive(:local?).and_return(false)
    txt = Tempfile.new(['notes', '.txt']).tap { |f| f.write('hello') && f.rewind }

    expect { upload(txt.path, 'text/plain') }.not_to change(Template, :count)
    expect(response).to redirect_to(root_path)
  end

  it 'still uploads PDFs untouched' do
    allow(described_class).to receive(:to_pdf)

    upload(Rails.root.join('spec/fixtures/sample-document.pdf'), 'application/pdf')

    expect(described_class).not_to have_received(:to_pdf)
    expect(Template.last.schema.size).to eq(1)
  end

  it 'recognises Word files by extension or content type' do
    file = ->(name, type) { Rack::Test::UploadedFile.new(docx, type, original_filename: name) }

    expect(described_class.office_file?(file.call('a.DOCX', 'application/octet-stream'))).to be(true)
    expect(described_class.office_file?(file.call('a.bin', docx_type))).to be(true)
    expect(described_class.office_file?(file.call('a.pdf', 'application/pdf'))).to be(false)
  end
end
