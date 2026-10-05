# frozen_string_literal: true

module Jdpools
  # Upstream shows a DocuSeal marketing page at / to signed-out visitors. With Microsoft sign-in on,
  # the sign-in page is the lander instead. Prepended to DashboardController.
  module LandingRedirect
    private

    def maybe_render_landing
      return super unless Jdpools.entra_enabled?
      return if signed_in?

      redirect_to new_user_session_path(request.query_parameters.slice('lang'))
    end
  end
end
