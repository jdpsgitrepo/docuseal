# frozen_string_literal: true

module Jdpools
  # Word uploads. Open-source DocuSeal takes only PDFs and images; converting Word files is a
  # DocuSeal Pro/cloud feature, so a .docx raised InvalidFileType, the upload controller swallowed
  # it ("Unable to upload file."), and the template it had already saved stayed behind with no
  # document. Staff then sent that empty template (2026-11-11, the NDA).
  #
  # Here the formats upstream's cloud accepts (Word, Excel, OpenDocument text, RTF) are converted
  # to PDF with headless LibreOffice before upstream's normal PDF path, so every upload route
  # (dashboard, builder, API) gets them.
  module OfficeUpload
    EXTENSIONS = Templates::CreateAttachments::DOCUMENT_EXTENSIONS
    CONTENT_TYPES = (Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES + %w[text/rtf]).freeze

    TIMEOUT = 90
    BINARIES = %w[soffice libreoffice].freeze
    ConversionFailed = Class.new(StandardError)

    module_function

    def office_file?(file)
      return false unless file.respond_to?(:original_filename)

      EXTENSIONS.include?(File.extname(file.original_filename.to_s).downcase) ||
        CONTENT_TYPES.include?(file.content_type.to_s)
    end

    # Looked up once: advanced_formats? asks on every page that shows an upload button.
    def soffice
      return @soffice if defined?(@soffice)

      @soffice = ENV.fetch('JDP_SOFFICE_PATH') do
        candidates = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).flat_map do |dir|
          BINARIES.map { |name| File.join(dir, name) }
        end
        (candidates + ['/Applications/LibreOffice.app/Contents/MacOS/soffice']).find { |f| File.executable?(f) }
      end
    end

    def available?
      soffice.present?
    end

    # Returns the PDF as an uploaded file named after the original, so the template keeps its name.
    def to_pdf(file)
      raise ConversionFailed, 'LibreOffice is not installed' unless available?

      Dir.mktmpdir('jdp-office') do |dir|
        ext = File.extname(file.original_filename.to_s).downcase.presence || '.docx'
        input = File.join(dir, "input#{ext}")
        File.binwrite(input, read(file))

        run_soffice(dir, input)

        output = File.join(dir, 'input.pdf')
        raise ConversionFailed, 'LibreOffice produced no PDF' unless File.size?(output)

        pdf = Tempfile.new(['jdp-office', '.pdf'])
        pdf.binmode
        pdf.write(File.binread(output))
        pdf.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: pdf,
          filename: "#{File.basename(file.original_filename.to_s, '.*').tr('/', '-')}.pdf",
          type: Templates::CreateAttachments::PDF_CONTENT_TYPE
        )
      end
    end

    def read(file)
      io = file.respond_to?(:tempfile) ? file.tempfile : file
      io.rewind if io.respond_to?(:rewind)
      data = io.read
      io.rewind if io.respond_to?(:rewind)
      data
    end

    # A private profile per run: two conversions sharing LibreOffice's default profile lock each other out.
    # Plain "pdf" lets LibreOffice pick the Writer or Calc export filter for the file.
    def run_soffice(dir, input)
      cmd = [soffice, "-env:UserInstallation=file://#{dir}/profile", '--headless', '--norestore',
             '--convert-to', 'pdf', '--outdir', dir, input]

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        $stdin.reopen(File::NULL)
        $stdout.reopen(writer)
        $stderr.reopen(writer)
        Process.setpgid(0, 0)
        drop_to_effective_user
        exec(*cmd)
      end
      writer.close
      log = Thread.new { reader.read }

      status = wait_for(pid)
      raise ConversionFailed, "LibreOffice failed: #{log.value.to_s.last(500)}" unless status.success?
    ensure
      reader&.close
    end

    def wait_for(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT

      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          Process.kill('KILL', -pid)
          Process.waitpid(pid)
          raise ConversionFailed, 'LibreOffice timed out'
        end

        sleep 0.1
      end
    end

    # Upstream's config/dotenv.rb runs the app as root with only the *effective* user switched to
    # docuseal (2000). A child started like that runs in the loader's secure mode, which ignores
    # LibreOffice's $ORIGIN library path, so soffice died with "Error loading shared library
    # libuno_sal.so.3". In the forked child, become the effective user for real before exec.
    def drop_to_effective_user
      uid = Process.euid
      gid = Process.egid
      return if Process.uid == uid && Process.gid == gid

      Process::Sys.seteuid(0)
      Process.groups = [gid]
      Process::Sys.setregid(gid, gid)
      Process::Sys.setreuid(uid, uid)
    end

    # Prepended to Templates::CreateAttachments' singleton (upstream uses module_function).
    module CreateAttachmentsPatch
      def handle_file_types(template, file, params, **)
        return super unless Jdpools::OfficeUpload.office_file?(file)

        super(template, Jdpools::OfficeUpload.to_pdf(file), params, **)
      end
    end

    # Prepended to TemplatesUploadsController.
    module UploadsControllerPatch
      def create
        super
      ensure
        jdp_discard_empty_template
      end

      private

      # Upstream saves the template before reading the file, so a failed upload (or a password
      # prompt, which re-uploads into a new template) leaves a nameable, sendable empty template.
      def jdp_discard_empty_template
        template = @template
        return unless template&.persisted? && Array.wrap(template.schema).empty?
        return if template.documents.reload.any? || template.submissions.exists?

        template.destroy
      rescue StandardError => e
        Rails.logger.warn("[jdpools] could not discard empty template #{template&.id}: #{e.message}")
      end
    end

    # Upstream shows .docx in the file pickers only on DocuSeal cloud.
    module AdvancedFormatsPatch
      def advanced_formats?
        Jdpools::OfficeUpload.available? || super
      end
    end
  end
end
