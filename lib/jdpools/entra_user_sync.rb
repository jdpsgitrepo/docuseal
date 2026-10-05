# frozen_string_literal: true

module Jdpools
  # Turns a verified Entra identity into a DocuSeal user. Entra is the source of truth: role, name
  # and department are overwritten on every sign-in, and the account is created on first sign-in.
  module EntraUserSync
    class Denied < StandardError; end

    module_function

    def call(identity)
      role = role_for(identity.app_roles)

      raise Denied, 'no DocuSeal app role assigned in Entra' if role.nil?

      user = find_user(identity) || build_user(identity)

      raise Denied, 'user is archived in DocuSeal' if user.archived_at?

      User.transaction do
        user.assign_attributes(
          email: identity.email,
          first_name: identity.first_name.presence || user.first_name,
          last_name: identity.last_name.presence || user.last_name,
          role:
        )
        user.save!

        UserConfig.find_or_initialize_by(user:, key: ENTRA_OID_CONFIG_KEY).update!(value: identity.oid)

        # nil means Graph could not be read: keep the department we already have.
        Jdpools::Departments.assign(user, identity.department) unless identity.department.nil?
      end

      user
    end

    def role_for(app_roles)
      return User::ADMIN_ROLE if app_roles.include?(ENTRA_ADMIN_APP_ROLE)

      MEMBER_ROLE if app_roles.include?(ENTRA_SENDER_APP_ROLE)
    end

    # The Entra object id is stable across renames; email is the fallback for users created before
    # their first Microsoft sign-in (the setup admin, or someone an admin added by hand).
    def find_user(identity)
      user_id = UserConfig.where(key: ENTRA_OID_CONFIG_KEY, value: identity.oid).pick(:user_id)

      return User.find(user_id) if user_id

      User.where('lower(email) = ?', identity.email.downcase).first
    end

    def build_user(identity)
      account = Account.where(archived_at: nil).order(:id).first

      raise Denied, 'DocuSeal has no account yet; finish setup first' unless account

      account.users.new(email: identity.email, password: SecureRandom.base58(48))
    end
  end
end
