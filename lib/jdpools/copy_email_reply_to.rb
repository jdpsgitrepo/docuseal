# frozen_string_literal: true

module Jdpools
  # The "Your document copy" email goes to every signer at once, built for the *last* signer.
  # Upstream leaves Reply-To empty when that last signer is the sender (J.D. countersigning last,
  # the usual order), so an external signer replying to their copy wrote to the it-service mailbox.
  # Keep the sender as Reply-To.
  module CopyEmailReplyTo
    private

    def build_submitter_reply_to(submitter, email_config: nil, documents_copy_email: nil)
      reply_to = super
      return reply_to if reply_to.present? || !documents_copy_email

      sender = submitter.submission.created_by_user || submitter.template&.author
      sender_name = sender&.friendly_name&.sub(/\+\w+@/, '@')
      sender_name unless sender_name.to_s.match?(SubmitterMailer::NO_REPLY_REGEXP)
    end
  end
end
