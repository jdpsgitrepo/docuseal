# frozen_string_literal: true

module Jdpools
  # EN / TH for J.D. Pools' own pages: ?lang= sets the jdp_lang cookie (shared with the sign-in
  # lander), otherwise the cookie decides.
  module LanguageChoice
    extend ActiveSupport::Concern

    included do
      before_action :jdp_remember_language
      helper_method :jdp_locale
    end

    private

    def jdp_remember_language
      return unless params[:lang].to_s.in?(Jdpools::LanguageCookie::LANGUAGES)

      cookies.permanent[Jdpools::LanguageCookie::COOKIE] = { value: params[:lang], same_site: :lax }
    end

    def jdp_locale
      return params[:lang].to_sym if params[:lang].to_s.in?(Jdpools::LanguageCookie::LANGUAGES)

      Jdpools.locale_for(cookies)
    end
  end
end
