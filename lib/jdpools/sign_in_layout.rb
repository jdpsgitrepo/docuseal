# frozen_string_literal: true

module Jdpools
  # The sign-in lander uses its own full-screen layout (layouts/jdpools_signin) once Microsoft
  # sign-in is on. Every other Sessions action keeps upstream's application layout.
  module SignInLayout
    module_function

    def install(controller)
      controller.layout ->(c) { Jdpools::SignInLayout.layout_for(c) }
    end

    def layout_for(controller)
      return 'application' unless Jdpools.entra_enabled?

      controller.action_name.in?(%w[new create]) ? 'jdpools_signin' : 'application'
    end
  end
end
