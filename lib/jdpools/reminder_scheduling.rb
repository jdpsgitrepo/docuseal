# frozen_string_literal: true

module Jdpools
  # Upstream's open-source build saves reminder durations (Settings → Notifications) but never sends
  # a reminder. Prepended to SendSubmitterInvitationEmailJob: once an invitation email has gone out,
  # schedule a reminder at each configured duration, counted from that send ("first reminder in
  # 2 days, second in 5 days"). A duration not later than the one before it is ignored.
  module ReminderScheduling
    def perform(params = {})
      submitter_id = params['submitter_id']
      last_event_id = Jdpools::ReminderScheduling.last_send_event_id(submitter_id)

      result = super

      send_event_id = Jdpools::ReminderScheduling.last_send_event_id(submitter_id)

      # No new send_email event means upstream skipped the send (completed, declined, archived...).
      if send_event_id && send_event_id != last_event_id
        Jdpools::ReminderScheduling.schedule(Submitter.find(submitter_id), send_event_id)
      end

      result
    end

    module_function

    def last_send_event_id(submitter_id)
      SubmissionEvent.where(submitter_id:, event_type: 'send_email').maximum(:id)
    end

    def schedule(submitter, send_event_id)
      return if submitter.viewer?

      previous = 0.seconds

      durations(submitter.account).each do |duration|
        next if duration <= previous

        previous = duration

        Jdpools::SubmitterReminderJob.perform_in(duration, 'submitter_id' => submitter.id,
                                                           'send_event_id' => send_event_id)
      end
    end

    # AccountConfig value: { 'first_duration' => 'two_days', 'second_duration' => 'four_days', ... }
    def durations(account)
      value = AccountConfig.find_by(account:, key: AccountConfig::SUBMITTER_REMINDERS)&.value

      return [] unless value.is_a?(Hash)

      value.values_at('first_duration', 'second_duration', 'third_duration').filter_map do |key|
        parse_duration(AccountConfigs::REMINDER_DURATIONS[key])
      end
    end

    # '2 days' -> 2.days. Unknown or blank keys are skipped.
    def parse_duration(text)
      count, unit = text.to_s.split
      return if count.to_i <= 0 || unit.blank?

      count.to_i.public_send(unit.pluralize)
    rescue NoMethodError
      nil
    end
  end
end
