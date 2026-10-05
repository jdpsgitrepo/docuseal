# frozen_string_literal: true

module Jdpools
  # With Entra on, a password may only sign in the break-glass accounts in JDP_PASSWORD_LOGIN_EMAILS.
  #
  # Enforced in one Warden hook (config/initializers/jdpools.rb) rather than per controller, because
  # a password reaches a session through several doors: the sign-in form, a password reset, an
  # invitation link and first-run setup all end in Devise#sign_in.
  module PasswordLoginGuard
    ENTRA_SIGN_IN_OPTION = :jdp_entra
    FAILURE_MESSAGE = :jdp_use_microsoft

    module_function

    def allowed?(user, warden, options)
      return true unless user.is_a?(User)
      return true if options[ENTRA_SIGN_IN_OPTION]
      # A remember-me cookie was minted by an earlier sign-in that already passed this check.
      return true if warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)

      Jdpools.password_login_allowed?(user.email)
    end

    # Stops "forgot password" mailing a reset link that could never be used.
    module PasswordsControllerPatch
      def create
        email = params.dig(resource_name, :email)

        return super if Jdpools.password_login_allowed?(email)

        redirect_to new_session_path(resource_name), notice: I18n.t('devise.passwords.send_paranoid_instructions')
      end
    end
  end
end
