# frozen_string_literal: true

module Jdpools
  # DocuSign-style routing order. Upstream only enforces order when the account switch "Always enforce
  # signing order" is on (all documents, including ones deliberately sent to everyone at once) or the
  # template prefers it. A document sent with "Preserve order" (the Send dialog default, and HRM's
  # order: "preserved") only held back the next invitation email: the later signer's link still opened
  # and could be signed early. Gate the signing page and form submit by the document's own order.
  module StrictSigningOrder
    def self.prepended(base)
      base.before_action :jdp_enforce_submission_order, only: %i[show update]
    end

    def self.blocked?(submitter)
      return false if submitter.nil? || submitter.completed_at? || submitter.declined_at?

      submission = submitter.submission
      return false unless submission.submitters_order == 'preserved'
      return false if Array.wrap(submission.template_submitters.presence || submission.template&.submitters).size < 2

      !Submitters.current_submitter_order?(submitter)
    end

    private

    def jdp_enforce_submission_order
      return unless Jdpools::StrictSigningOrder.blocked?(@submitter)

      if action_name == 'update'
        render json: { error: I18n.t('awaiting_completion_by_the_other_party') }, status: :unprocessable_content
      else
        render :awaiting
      end
    end
  end
end
