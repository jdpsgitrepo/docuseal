# frozen_string_literal: true

RSpec.describe Jdpools::AbilityScoping do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }

  let(:hr_sender) { create(:user, account:, role: Jdpools::MEMBER_ROLE) }
  let(:hr_colleague) { create(:user, account:, role: Jdpools::MEMBER_ROLE) }
  let(:purchasing_sender) { create(:user, account:, role: Jdpools::MEMBER_ROLE) }
  let(:no_department_sender) { create(:user, account:, role: Jdpools::MEMBER_ROLE) }

  let(:hr_template) { create(:template, account:, author: hr_sender) }
  let(:purchasing_template) { create(:template, account:, author: purchasing_sender) }

  let!(:hr_submission) { create(:submission, :with_submitters, template: hr_template, created_by_user: hr_sender) }
  let!(:purchasing_submission) do
    create(:submission, :with_submitters, template: purchasing_template, created_by_user: purchasing_sender)
  end

  before do
    Jdpools::Departments.assign(hr_sender, 'Human Resources')
    Jdpools::Departments.assign(hr_colleague, 'Human Resources')
    Jdpools::Departments.assign(purchasing_sender, 'Purchasing')
  end

  def accessible(model, user)
    model.accessible_by(Ability.new(user)).to_a
  end

  it 'lets a member see their own department and nothing else' do
    expect(accessible(Submission, hr_colleague)).to contain_exactly(hr_submission)
    expect(accessible(Template, hr_colleague)).to contain_exactly(hr_template)
    expect(accessible(Submitter, hr_colleague)).to match_array(hr_submission.submitters)
  end

  it 'keeps departments apart' do
    expect(accessible(Submission, purchasing_sender)).to contain_exactly(purchasing_submission)
    expect(Ability.new(purchasing_sender).can?(:read, hr_submission)).to be(false)
    expect(Ability.new(purchasing_sender).can?(:update, hr_template)).to be(false)
  end

  it 'shows a member with no department only their own work' do
    own = create(:submission, template: create(:template, account:, author: no_department_sender),
                              created_by_user: no_department_sender)

    expect(accessible(Submission, no_department_sender)).to contain_exactly(own)
  end

  it 'covers submissions started from a public link, which have no creating user' do
    linked = create(:submission, template: hr_template, created_by_user: nil)

    expect(accessible(Submission, hr_colleague)).to include(linked)
    expect(accessible(Submission, purchasing_sender)).not_to include(linked)
  end

  it 'gives admins the upstream full access' do
    expect(accessible(Submission, admin)).to contain_exactly(hr_submission, purchasing_submission)
  end

  it 'keeps members out of account settings and other users' do
    ability = Ability.new(hr_sender)

    expect(ability.can?(:manage, hr_sender)).to be(true)
    expect(ability.can?(:read, hr_colleague)).to be(false)
    expect(ability.can?(:create, account.users.new)).to be(false)
    expect(ability.can?(:read, AccountConfig.new(account:))).to be(false)
    expect(ability.can?(:read, EncryptedConfig.new(account:, key: EncryptedConfig::ESIGN_CERTS_KEY))).to be(false)
    expect(ability.can?(:read, WebhookUrl.new(account:))).to be(false)
    expect(ability.can?(:manage, :mcp)).to be(false)
  end

  it 'never leaks across accounts' do
    other_account = create(:account)
    stranger = create(:user, account: other_account, role: Jdpools::MEMBER_ROLE)
    Jdpools::Departments.assign(stranger, 'Human Resources')

    expect(accessible(Submission, stranger)).to be_empty
    expect(Jdpools::Departments.visible_user_ids(stranger)).to eq([stranger.id])
  end
end
