# frozen_string_literal: true

module Jdpools
  # "How to sign a document": public, for people who received a document and have never signed online.
  class SignerHelpController < ApplicationController
    include Jdpools::LanguageChoice

    skip_before_action :authenticate_user!
    skip_before_action :maybe_redirect_to_setup
    skip_authorization_check

    layout 'jdpools_signin'

    around_action :jdp_with_locale

    def show; end

    private

    def jdp_with_locale(&)
      I18n.with_locale(jdp_locale, &)
    end
  end
end
