# frozen_string_literal: true

module Jdpools
  # Upstream's open-source Ability gives every user full control of the account. Members (Entra
  # app role DocuSeal.Sender) get department-scoped access instead; every other role keeps the
  # upstream rules unchanged.
  #
  # Rules are hash conditions so CanCanCan can turn them into SQL: upstream controllers load lists
  # with load_and_authorize_resource / accessible_by, so the same rules filter every index page.
  module AbilityScoping
    def initialize(user)
      if Jdpools.member?(user)
        member_rules(user)
      else
        super
      end
    end

    private

    def member_rules(user)
      account_id = user.account_id
      user_ids = Jdpools::Departments.visible_user_ids(user)

      can :manage, Template, account_id:, author_id: user_ids

      # Folders are shared by name across the account (TemplateFolders.find_or_create_by_name), and
      # the dashboard only lists folders holding templates this user can see, so reading every
      # folder exposes no documents. Renaming or deleting stays with the folder's department.
      can(:read, TemplateFolder, account_id:)
      can :manage, TemplateFolder, account_id:, author_id: user_ids

      can :manage, Submission, account_id:, created_by_user_id: user_ids
      # Submissions started from a template's public link have no creating user.
      can :manage, Submission, account_id:, created_by_user_id: nil, template: { author_id: user_ids }

      can :manage, Submitter, account_id:, submission: { created_by_user_id: user_ids }
      can :manage, Submitter, account_id:, submission: { created_by_user_id: nil, template: { author_id: user_ids } }

      # Own profile only; creating or managing other users is denied by the id condition.
      can(:manage, User, id: user.id, account_id:)
      can :manage, UserConfig, user_id: user.id
      can :manage, EncryptedUserConfig, user_id: user.id
      can :manage, AccessToken, user_id: user.id
    end
  end
end
