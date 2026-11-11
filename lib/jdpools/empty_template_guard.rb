# frozen_string_literal: true

module Jdpools
  # Upstream lets a template with no document be sent, self-signed or opened from its share link.
  # The signer then gets a blank page and the sender a submission with nothing in it (the NDA,
  # 2026-11-11, sent twice after its Word upload failed). Refuse until a document is uploaded.
  # The API already refuses templates without fields (Api::SubmissionsController).
  module EmptyTemplateGuard
    def self.prepended(base)
      actions = %w[new create update] & base.action_methods.to_a
      base.before_action :jdp_refuse_empty_template, only: actions.map(&:to_sym)
    end

    def self.empty?(template)
      template.present? && Array.wrap(template.schema).empty?
    end

    private

    def jdp_refuse_empty_template
      return unless Jdpools::EmptyTemplateGuard.empty?(@template)

      message = I18n.t('jdp_template_has_no_document')

      if current_user && current_ability.can?(:update, @template)
        redirect_to edit_template_path(@template), alert: message
      else
        render plain: message, status: :unprocessable_content
      end
    end
  end
end
