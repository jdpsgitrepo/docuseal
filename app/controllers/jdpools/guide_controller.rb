# frozen_string_literal: true

module Jdpools
  # "How to use JD e-Sign": the staff guide, EN / TH, with the IT-admin section shown to admins only.
  class GuideController < ApplicationController
    include Jdpools::LanguageChoice

    skip_authorization_check

    def show
      @sections = Array.wrap(I18n.t('jdp_guide.sections', locale: jdp_locale))
      @sections = @sections.reject { |s| s[:admin] } unless current_user.role == User::ADMIN_ROLE
    end
  end
end
