# frozen_string_literal: true

module Jdpools
  # Remembers the EN / ไทย toggle on the sign-in lander. Prepended to SessionsController, whose
  # upstream with_browser_locale already honours ?lang=; this only fills it in from the cookie.
  module LanguageCookie
    COOKIE = :jdp_lang
    LANGUAGES = %w[en th].freeze

    private

    def with_browser_locale(&)
      if params[:lang].to_s.in?(LANGUAGES)
        cookies.permanent[COOKIE] = { value: params[:lang], same_site: :lax }
      elsif params[:lang].blank? && cookies[COOKIE].to_s.in?(LANGUAGES)
        params[:lang] = cookies[COOKIE]
      end

      super
    end
  end
end
