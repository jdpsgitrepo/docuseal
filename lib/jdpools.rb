# frozen_string_literal: true

# JD Pools additions to DocuSeal. See JDPOOLS.md for the design and the list of
# upstream files this fork edits.
module Jdpools
  MEMBER_ROLE = 'member'

  DEPARTMENT_CONFIG_KEY = 'jdp_department'
  ENTRA_OID_CONFIG_KEY = 'jdp_entra_oid'

  ENTRA_ADMIN_APP_ROLE = 'DocuSeal.Admin'
  ENTRA_SENDER_APP_ROLE = 'DocuSeal.Sender'

  module_function

  def entra_enabled?
    entra_tenant_id.present? && entra_client_id.present? && Jdpools::EntraClientAuth.configured?
  end

  def entra_tenant_id
    ENV.fetch('JDP_ENTRA_TENANT_ID', nil)
  end

  def entra_client_id
    ENV.fetch('JDP_ENTRA_CLIENT_ID', nil)
  end

  def entra_client_secret
    ENV.fetch('JDP_ENTRA_CLIENT_SECRET', nil)
  end

  def password_login_emails
    ENV.fetch('JDP_PASSWORD_LOGIN_EMAILS', '').split(',').map { |e| e.strip.downcase }.compact_blank
  end

  # With Entra on, only break-glass addresses may use a password. With Entra off
  # (local development, or before the app registration exists) passwords work as upstream.
  def password_login_allowed?(email)
    return true unless entra_enabled?

    email.to_s.strip.downcase.in?(password_login_emails)
  end

  # Where users can get this modified version's source (AGPLv3 section 13).
  def source_url
    ENV.fetch('JDP_SOURCE_URL', 'https://github.com/jdpsgitrepo/docuseal')
  end

  # EN / TH choice for J.D. Pools pages (lander, guide, signer help, walkthrough), remembered in
  # the jdp_lang cookie. The staff UI itself stays in the account locale.
  def locale_for(cookies)
    cookies[Jdpools::LanguageCookie::COOKIE].to_s == 'th' ? :th : :en
  end

  def member?(user)
    user&.role == MEMBER_ROLE
  end
end
