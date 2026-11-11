# frozen_string_literal: true

module Jdpools
  # Upstream renders signer-facing times (declined on, expired on, signed on) in UTC because no
  # signing controller sets a zone: a decline at 11:32 Bangkok read "04:32 น.". Use the account's
  # time zone (Settings → Account), as the audit log already does.
  module SignerTimeZone
    def self.prepended(base)
      base.prepend_around_action :jdp_with_account_time_zone
    end

    private

    def jdp_with_account_time_zone(&)
      zone = jdp_signer_account&.timezone.presence
      zone && ActiveSupport::TimeZone[zone] ? Time.use_zone(zone, &) : yield
    end

    def jdp_signer_account
      slug = params[:slug] || params[:submit_form_slug] || params[:start_form_slug]
      return if slug.blank?

      if is_a?(StartFormController)
        Template.find_by(slug:)&.account
      else
        Submitter.find_by(slug:)&.account
      end
    end
  end
end
