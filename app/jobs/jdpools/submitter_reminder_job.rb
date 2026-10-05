# frozen_string_literal: true

module Jdpools
  # Re-sends a signer's invitation email as a reminder. Scheduled by Jdpools::ReminderScheduling.
  class SubmitterReminderJob
    include Sidekiq::Job

    SUBJECT_PREFIX = 'Reminder · แจ้งเตือน: '

    def perform(params = {})
      submitter = Submitter.find_by(id: params['submitter_id'])

      return unless submitter
      return unless due?(submitter, params['send_event_id'])
      return unless Accounts.can_send_invitation_emails?(submitter.account)

      mail = SubmitterMailer.invitation_email(submitter)
      mail.subject = "#{SUBJECT_PREFIX}#{mail.subject}"

      Submitters::ValidateSending.call(submitter, mail)

      mail.deliver_now!

      SubmissionEvent.create!(submitter:, event_type: 'send_reminder_email')
    end

    private

    def due?(submitter, send_event_id)
      return false if submitter.completed_at? || submitter.declined_at?
      return false if submitter.email.blank?
      return false if submitter.submission.archived_at? || submitter.submission.expired?
      return false if submitter.template&.archived_at?

      # The invitation was re-sent after this reminder was scheduled; that send scheduled its own.
      Jdpools::ReminderScheduling.last_send_event_id(submitter.id) == send_event_id
    end
  end
end
