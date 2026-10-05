# frozen_string_literal: true

RSpec.describe Jdpools::ReminderScheduling do
  let(:account) { create(:account) }
  let(:template) { create(:template, account:, author: create(:user, account:)) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: template.author) }
  let(:submitter) { submission.submitters.first.tap { |s| s.update!(email: 'signer@example.com') } }

  def configure_reminders(value)
    AccountConfig.create!(account:, key: AccountConfig::SUBMITTER_REMINDERS, value:)
  end

  def send_invitation
    SendSubmitterInvitationEmailJob.new.perform('submitter_id' => submitter.id)
  end

  def scheduled_reminders
    Jdpools::SubmitterReminderJob.jobs
  end

  it 'schedules one reminder per configured duration, counted from the invitation' do
    configure_reminders('first_duration' => 'two_days', 'second_duration' => 'five_days')

    freeze_time do
      send_invitation

      expect(scheduled_reminders.size).to eq(2)
      expect(scheduled_reminders.pluck('at')).to eq([2.days.from_now.to_f, 5.days.from_now.to_f])
    end
  end

  it 'ignores a duration that is not later than the one before it' do
    configure_reminders('first_duration' => 'five_days', 'second_duration' => 'two_days', 'third_duration' => '')

    send_invitation

    expect(scheduled_reminders.size).to eq(1)
  end

  it 'schedules nothing when reminders are not configured' do
    send_invitation

    expect(scheduled_reminders).to be_empty
  end

  it 'schedules nothing when upstream skipped the invitation' do
    configure_reminders('first_duration' => 'two_days')
    submitter.update!(completed_at: Time.current)

    send_invitation

    expect(scheduled_reminders).to be_empty
  end

  describe Jdpools::SubmitterReminderJob do
    before do
      configure_reminders('first_duration' => 'two_days')
      send_invitation
      ActionMailer::Base.deliveries.clear
    end

    let(:job_args) { scheduled_reminders.first['args'].first }

    it 'emails the signer again, marked as a reminder, and logs it' do
      described_class.new.perform(job_args)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(['signer@example.com'])
      expect(mail.subject).to start_with(described_class::SUBJECT_PREFIX)
      expect(SubmissionEvent.where(submitter:, event_type: 'send_reminder_email').count).to eq(1)
    end

    it 'stays quiet once the signer has completed' do
      submitter.update!(completed_at: Time.current)

      described_class.new.perform(job_args)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'stays quiet once the signer has declined' do
      submitter.update!(declined_at: Time.current)

      described_class.new.perform(job_args)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'stays quiet when the invitation was re-sent after it was scheduled' do
      send_invitation
      ActionMailer::Base.deliveries.clear

      described_class.new.perform(job_args)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'stays quiet when the submission is archived' do
      submission.update!(archived_at: Time.current)

      described_class.new.perform(job_args)

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
