# frozen_string_literal: true

module Jdpools
  # Upstream decides whether email can be sent by looking for SMTP settings. Graph mail counts too.
  module AccountsPatch
    def can_send_emails?(account, **)
      Jdpools::GraphMailDelivery.enabled? || super
    end
  end
end
