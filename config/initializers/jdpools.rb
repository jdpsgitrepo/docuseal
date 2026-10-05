# frozen_string_literal: true

# JD Pools fork wiring. Everything is attached from here so upstream files stay untouched;
# see JDPOOLS.md.

Rails.application.config.i18n.available_locales += %i[th]

Rails.application.config.to_prepare do
  Ability.prepend(Jdpools::AbilityScoping) unless Ability <= Jdpools::AbilityScoping

  unless PasswordsController <= Jdpools::PasswordLoginGuard::PasswordsControllerPatch
    PasswordsController.prepend(Jdpools::PasswordLoginGuard::PasswordsControllerPatch)
  end

  unless HexaPDF::Layout::TextFragment.singleton_class <= Jdpools::ThaiPdfText::TextFragmentPatch
    HexaPDF::Layout::TextFragment.singleton_class.prepend(Jdpools::ThaiPdfText::TextFragmentPatch)
  end

  DashboardController.prepend(Jdpools::LandingRedirect) unless DashboardController <= Jdpools::LandingRedirect
  SessionsController.prepend(Jdpools::LanguageCookie) unless SessionsController <= Jdpools::LanguageCookie
  Jdpools::SignInLayout.install(SessionsController)

  SetupController.prepend(Jdpools::SetupGuard) unless SetupController <= Jdpools::SetupGuard

  Accounts.singleton_class.prepend(Jdpools::AccountsPatch) unless Accounts.singleton_class <= Jdpools::AccountsPatch

  unless SendSubmitterInvitationEmailJob <= Jdpools::ReminderScheduling
    SendSubmitterInvitationEmailJob.prepend(Jdpools::ReminderScheduling)
  end
end

# Registered once (not in to_prepare, which re-runs on every code reload in development). The hook
# body resolves Jdpools::PasswordLoginGuard at call time, so it always sees the reloaded module.
Warden::Manager.after_set_user except: :fetch do |user, warden, options|
  next if Jdpools::PasswordLoginGuard.allowed?(user, warden, options)

  scope = options[:scope]
  warden.logout(scope)
  throw :warden, scope:, message: Jdpools::PasswordLoginGuard::FAILURE_MESSAGE
end

# Mail through Microsoft Graph instead of SMTP (see Jdpools::GraphMailDelivery). Upstream's
# ActionMailerConfigsInterceptor rewrites From to SMTP_FROM whenever a delivery method is configured,
# so point that at the Graph mailbox too.
# Checked on ENV rather than the class so boot does not autoload reloadable code.
if Rails.env.production? && ENV['JDP_GRAPH_MAIL_FROM'].present? && ENV['SMTP_ADDRESS'].blank?
  ENV['SMTP_FROM'] ||= ENV.fetch('JDP_GRAPH_MAIL_FROM').strip.downcase
  Rails.application.config.action_mailer.delivery_method = :jdp_graph

  ActiveSupport.on_load(:action_mailer) do
    ActionMailer::Base.add_delivery_method(:jdp_graph, Jdpools::GraphMailDelivery)
  end
end

# Upstream's routes.rb ends with run_load_hooks(:routes), so these append without editing it.
ActiveSupport.on_load(:routes) do
  post '/auth/entra' => 'jdpools/entra_sessions#create', as: :jdpools_entra_sign_in
  get '/auth/entra/callback' => 'jdpools/entra_sessions#callback', as: :jdpools_entra_callback
  get '/guide' => 'jdpools/guide#show', as: :jdpools_guide
  get '/help/signing' => 'jdpools/signer_help#show', as: :jdpools_signer_help
end
