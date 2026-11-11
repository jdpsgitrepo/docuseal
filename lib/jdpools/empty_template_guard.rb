# frozen_string_literal: true

module Jdpools
  # Upstream lets a template be sent, self-signed or opened from its share link before it is ready.
  # The signer then gets a page with nothing to fill and the sender a submission that can never be
  # signed. Two ways this happened on 2026-11-11:
  #
  # - no document: the NDA was sent twice after its Word upload failed (blank page);
  # - a document but no fields: the re-uploaded NDA (template 8) was self-signed before anyone placed
  #   a Signature field. Upstream marks every role with no fields as a viewer, so the signer could
  #   only look at it.
  #
  # Refuse until the template is ready. Sending refuses only a template with no fields at all: a role
  # with no fields next to roles that sign is upstream's view-only recipient, which is legitimate.
  # Sign it yourself and the share link start as the first role, so that role must have a field.
  # The API already refuses templates without fields (Api::SubmissionsController).
  module EmptyTemplateGuard
    FIRST_ROLE_CONTROLLERS = %w[StartFormSelfController StartFormController].freeze

    def self.prepended(base)
      actions = %w[new create update] & base.action_methods.to_a
      base.before_action :jdp_refuse_empty_template, only: actions.map(&:to_sym)
    end

    # The locale key explaining why the template can't be used yet, or nil when it can.
    def self.problem(template, starts_as_first_role: false)
      return if template.blank?
      return 'jdp_template_has_no_document' if Array.wrap(template.schema).empty?

      field_roles = Array.wrap(template.fields).filter_map { |f| f['submitter_uuid'] }
      return 'jdp_template_has_no_fields' if field_roles.empty?

      return unless starts_as_first_role

      first_role = Submitters::StartForm.first_submitter_uuid(template)

      'jdp_template_first_role_has_no_fields' if field_roles.exclude?(first_role)
    end

    def self.empty?(template)
      problem(template).present?
    end

    private

    def jdp_refuse_empty_template
      key = Jdpools::EmptyTemplateGuard.problem(
        @template, starts_as_first_role: FIRST_ROLE_CONTROLLERS.include?(self.class.name)
      )
      return unless key

      message = I18n.t(key)

      if current_user && current_ability.can?(:update, @template)
        redirect_to edit_template_path(@template), alert: message
      else
        render plain: message, status: :unprocessable_content
      end
    end
  end
end
