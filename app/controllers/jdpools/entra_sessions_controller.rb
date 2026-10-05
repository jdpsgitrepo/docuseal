# frozen_string_literal: true

module Jdpools
  class EntraSessionsController < ApplicationController
    SESSION_KEY = 'jdp_entra_auth'
    AUTH_TTL = 10.minutes

    skip_before_action :authenticate_user!
    skip_before_action :maybe_redirect_to_setup
    skip_authorization_check

    before_action :require_entra_enabled

    # POST, not GET: a GET start would let another site sign a visitor in to an account of its choosing.
    def create
      state = SecureRandom.urlsafe_base64(32)
      nonce = SecureRandom.urlsafe_base64(32)
      code_verifier = SecureRandom.urlsafe_base64(64)

      session[SESSION_KEY] = {
        'state' => state, 'nonce' => nonce, 'code_verifier' => code_verifier,
        'expires_at' => AUTH_TTL.from_now.to_i
      }

      redirect_to EntraOidc.authorize_url(redirect_uri:, state:, nonce:, code_verifier:), allow_other_host: true
    end

    def callback
      pending = session.delete(SESSION_KEY)

      return fail_sign_in('state') unless valid_state?(pending)
      return fail_sign_in("entra: #{params[:error]} #{params[:error_description]}") if params[:error].present?

      identity = EntraOidc.identity_from_code(code: params[:code].to_s, redirect_uri:,
                                              code_verifier: pending['code_verifier'], nonce: pending['nonce'])
      user = EntraUserSync.call(identity)

      sign_in(:user, user, PasswordLoginGuard::ENTRA_SIGN_IN_OPTION => true)

      redirect_to after_sign_in_path_for(user)
    rescue EntraOidc::Error, EntraUserSync::Denied, ActiveRecord::RecordInvalid => e
      fail_sign_in(e.message)
    end

    private

    def valid_state?(pending)
      pending.is_a?(Hash) &&
        pending['expires_at'].to_i > Time.current.to_i &&
        ActiveSupport::SecurityUtils.secure_compare(pending['state'].to_s, params[:state].to_s)
    end

    def fail_sign_in(reason)
      Rails.logger.warn("[jdpools] Entra sign-in refused: #{reason}")

      redirect_to new_user_session_path, alert: I18n.t('jdp_entra_sign_in_failed')
    end

    def redirect_uri
      jdpools_entra_callback_url
    end

    def require_entra_enabled
      head :not_found unless Jdpools.entra_enabled?
    end
  end
end
