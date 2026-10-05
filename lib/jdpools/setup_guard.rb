# frozen_string_literal: true

module Jdpools
  # Upstream's /setup makes whoever reaches it first the admin, and a new hostname's certificate
  # is public in certificate-transparency logs within minutes. With JDP_SETUP_TOKEN set, setup
  # answers 404 unless opened once with ?token=<value>; the session then carries the form POST.
  module SetupGuard
    SESSION_KEY = 'jdp_setup_token_ok'

    def self.prepended(base)
      base.prepend_before_action :jdp_require_setup_token
    end

    private

    def jdp_require_setup_token
      expected = ENV.fetch('JDP_SETUP_TOKEN', '')

      return if expected.blank?

      if params[:token].present? && ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, expected)
        session[SESSION_KEY] = true
      end

      head :not_found unless session[SESSION_KEY]
    end
  end
end
