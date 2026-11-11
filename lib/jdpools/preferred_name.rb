# frozen_string_literal: true

module Jdpools
  # The name people see for a sender (signing-page header "ส่งโดย …", email Reply-To) is the Entra display
  # name, re-synced on every sign-in. A preferred first name stored in e-Sign (user_configs) wins for
  # display without changing Entra, which would rename the person everywhere.
  # Set: UserConfig.create!(user:, key: Jdpools::PreferredName::KEY, value: 'Rollie')
  module PreferredName
    KEY = 'jdp_preferred_first_name'

    def full_name
      preferred = jdp_preferred_first_name
      preferred ? [preferred, last_name].compact_blank.join(' ') : super
    end

    private

    def jdp_preferred_first_name
      return @jdp_preferred_first_name if defined?(@jdp_preferred_first_name)

      @jdp_preferred_first_name = persisted? ? user_configs.find_by(key: KEY)&.value.to_s.strip.presence : nil
    end
  end
end
