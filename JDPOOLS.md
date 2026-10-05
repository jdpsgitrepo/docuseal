# JD Pools fork of DocuSeal

This is `jdpsgitrepo/docuseal`, JD Pools' fork of [docusealco/docuseal](https://github.com/docusealco/docuseal).
It replaces Adobe Acrobat seats and print–sign–scan for company paperwork. It is not wired into the
jdpoolstech apps.

Our changes live on the `jdpools` branch. `master` tracks upstream untouched.

## Licence obligations (AGPLv3 + section 7(b))

- This repository stays **public**. Anyone who uses the running service (staff and external signers)
  is entitled to the modified source; the public fork is how we meet that.
- The "Powered by DocuSeal" attribution stays in the UI. Do not remove it.

## What we added

| Feature | Upstream status | Ours |
|---|---|---|
| Microsoft Entra sign-in (OIDC) | Pro only (SAML) | `lib/jdpools/entra_*`, `app/controllers/jdpools/entra_sessions_controller.rb` |
| Roles + department visibility | Pro only (every user is admin upstream) | `lib/jdpools/ability_scoping.rb` |
| Password login restricted to break-glass accounts | — | `lib/jdpools/password_login_guard.rb` |
| Thai signing page (follows the signer's phone language) | Not available (14 languages, no Thai) | `config/locales/th.yml`, `config/locales/jdpools.yml`, `app/javascript/submission_form/i18n_th.js` |
| Automatic email reminders | Pro only (settings form saves, nothing sends) | `app/jobs/jdpools/submitter_reminder_job.rb` |
| Thai in generated PDFs (tone marks stacked correctly; audit trail no longer drops Thai) | HexaPDF does no shaping; audit trail's Helvetica has no Thai | `lib/jdpools/thai_pdf_text.rb`, `config/jdpools/fonts/` (Laksaman, TLWG, GPLv2+ with font exception) |
| J.D. Pools branding (colours, logo, favicon, titles) | Pro only (custom logo) | DaisyUI theme in `tailwind.config.js`, `public/jdpools-logo.png`, favicons |
| Email through Microsoft Graph | SMTP only (Exchange Online retired SMTP basic auth) | `lib/jdpools/graph_mail_delivery.rb` |
| Certificate client auth to Entra | — | `lib/jdpools/entra_client_auth.rb` |

Thai or bilingual email wording needs no code: Settings → Personalization edits the invitation and
completion emails in the open-source build.

## Design decisions (2026-10-05)

**Sign-in.** Everyone signs in with Microsoft. The Entra enterprise app has *assignment required* on,
so only users or groups assigned to it can sign in at all. Two app roles decide the DocuSeal role:

| Entra app role value | DocuSeal role | Can |
|---|---|---|
| `DocuSeal.Admin` | `admin` | Everything (upstream behaviour) |
| `DocuSeal.Sender` | `member` | Send and track documents for their own department |

A user with neither role is refused, even if assignment-required is switched off by mistake. Entra
is the source of truth: role, name and department are re-synced on every sign-in, and an account
is created on first sign-in. Emails are matched lowercased.

**Visibility.** A member sees templates and submissions created by anyone in the same Entra
`department`. With a blank department they see only their own. Admins see everything. Members
get no settings, users, webhooks, API-wide config or MCP access.

Department is stored in `user_configs` (key `jdp_department`), not a new column, so we carry no
schema migration and `db/schema.rb` never conflicts on upstream merges.

**Break-glass.** Email + password login works only for addresses listed in
`JDP_PASSWORD_LOGIN_EMAILS`. The login page shows the Microsoft button first and folds the
password form into an "IT admin password sign-in" section (opened by `?password=1`).

**Sessions.** Upstream remembers a login for 730 days. Set `SESSION_REMEMBER_DAYS=1` so a user
disabled in Entra loses access within a day; Microsoft SSO makes re-login one click.

**Reminders.** When an invitation email is sent, reminders are scheduled at the durations set in
Settings → Notifications. A reminder is skipped if the signer has completed or declined, the
submission is archived or expired, or the invitation was re-sent since it was scheduled.

## Configuration

| Variable | Purpose |
|---|---|
| `JDP_ENTRA_TENANT_ID` | Directory (tenant) ID. SSO is off when unset. |
| `JDP_ENTRA_CLIENT_ID` | App registration client ID |
| `JDP_ENTRA_PRIVATE_KEY` / `JDP_ENTRA_CERTIFICATE` | PEM key pair; the certificate (public half only) is uploaded to the app registration. Preferred. |
| `JDP_ENTRA_CLIENT_SECRET` | Fallback when no certificate is set |
| `JDP_GRAPH_MAIL_FROM` | Mailbox all email is sent from through Microsoft Graph (`it-service@jdpools.com`). Needs the `Mail.Send` application permission. |
| `S3_ATTACHMENTS_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_ENDPOINT` | Railway bucket for documents (upstream's S3 settings) |
| `JDP_PASSWORD_LOGIN_EMAILS` | Comma-separated break-glass emails allowed to use a password |
| `SESSION_REMEMBER_DAYS` | Set to `1` |
| `JDP_SETUP_TOKEN` | First-run `/setup` answers 404 unless opened once with `?token=<value>`. Remove after setup. |
| `SECRET_KEY_BASE` | Set explicitly. Upstream otherwise writes one to `/data/docuseal/.env`, which a redeploy without a volume loses, logging everyone out and breaking encrypted settings. |
| `APP_URL` | Public URL, e.g. `https://sign.jdpools.com`. Builds the Entra redirect URI and every emailed link. |

Entra app registration: redirect URI `https://<host>/auth/entra/callback` (Web platform), delegated
Graph permission `User.Read`, app roles `DocuSeal.Admin` and `DocuSeal.Sender`, enterprise app
"Assignment required" = Yes.

## Known gaps

- Members still see the **Account** and **Users** links in Settings (upstream shows them to every
  user). Account refuses them; Users lists only themselves.

## Keeping the fork mergeable

Upstream lands several commits a day. Rules that keep merges cheap:

1. New behaviour goes in new files under `lib/jdpools/`, `app/controllers/jdpools/`,
   `app/jobs/jdpools/`, `config/initializers/jdpools.rb`. Hook into upstream with `prepend`,
   `ActiveSupport.on_load(:routes)`, and empty partials upstream already ships for Pro.
2. Every edit to an upstream file is listed below, and kept to a few lines.
3. No schema migrations unless unavoidable.

### Upstream files we edit

| File | Change |
|---|---|
| `app/views/devise/sessions/_omniauthable.html.erb` | Empty upstream; renders the Microsoft button |
| `app/views/devise/sessions/new.html.erb` | Microsoft button first; password form folded into a `<details>` when SSO is on |
| `app/views/notifications_settings/_reminder_banner.html.erb` | Drops the "Unlock with Pro" banner |
| `app/views/users/_role_select.html.erb` | Role shown read-only: it is managed in Entra |
| `app/javascript/submission_form/i18n.js` | Registers the `th` strings |
| `tailwind.config.js`, `tailwind.dynamic.config.js` | Theme colours/radii from jdpoolstech `design-system/brand-tokens.css` |
| `app/javascript/application.js`, `app/views/shared/_meta.html.erb` | Background / theme-color hex; page titles, og:site_name |
| `app/views/shared/_logo.html.erb`, `app/javascript/template_builder/logo.vue` | J.D. Pools logo image in place of the DocuSeal mark |
| `app/views/shared/_title.html.erb`, `app/views/shared/_html_title.html.erb`, `app/views/layouts/_head_tags.html.erb`, `app/views/{submit,start}_form/_docuseal_logo.html.erb` | "e-Sign" / "J.D. Pools e-Sign" in headers and titles |
| `public/favicon*`, `public/apple-*` | J.D. Pools favicons (from design-system/favicon) |

The "Powered by DocuSeal" footers (`shared/_powered_by`, `shared/_attribution`, `shared/_email_attribution`) are
deliberately untouched: section 7(b) of the licence requires that attribution to stay.

### Syncing upstream

```sh
git fetch upstream
git checkout master && git merge --ff-only upstream/master && git push origin master
git checkout jdpools && git merge master
bundle exec rspec spec/jdpools   # our specs
```

## Running locally (macOS, Apple Silicon)

Needs Ruby 4.0.5, arm64 Homebrew `vips redis leptonica onnxruntime libpq`, Postgres, and DocuSeal's
own PDFium build (`gh release download <tag> -R docusealco/pdfium-binaries -p pdfium-mac-arm64.zip`,
the tag the Dockerfile pins). Put `libpdfium.dylib` on `DYLD_FALLBACK_LIBRARY_PATH` and invoke the
Ruby binary directly (`ruby $(which bundle) exec rspec`): macOS strips `DYLD_*` from anything
started through `/usr/bin/env`, which every Ruby binstub's shebang is. Build assets with Node 22
(`bin/shakapacker`) before request specs that render pages.
