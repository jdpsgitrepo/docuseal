# JD Pools fork of DocuSeal

This is `jdpsgitrepo/docuseal`, JD Pools' fork of [docusealco/docuseal](https://github.com/docusealco/docuseal).
It replaces Adobe Acrobat seats and print–sign–scan for company paperwork. It is not wired into the
jdpoolstech apps.

Our changes live on the `jdpools` branch. `master` tracks upstream untouched.

## Licence obligations (AGPLv3 + section 7(b)) — do not regress

DocuSeal is AGPLv3 with one additional term. Modifying, rebranding, self-hosting and re-implementing
Pro features in our own code are all allowed. Two obligations must hold on every deploy, and
`spec/jdpools/licence_requirements_spec.rb` fails if either breaks:

1. **Attribution (7(b)).** The original DocuSeal attribution stays in every interactive UI. It is
   `shared/_powered_by` ("Powered by DocuSeal"): on signing and completion pages, the sign-in lander,
   and (our addition) a footer on every staff page in `layouts/application`. Emails keep
   "Sent using DocuSeal". Replacing the DocuSeal logo/name in headers with J.D. Pools branding is fine;
   removing the "Powered by" line is not.
2. **Source offer (section 13).** Everyone who uses the service over the network, external signers
   included, must be offered this modified version's source. The "Source code" link in
   `shared/_powered_by` points at `Jdpools.source_url` (`JDP_SOURCE_URL`, default
   `https://github.com/jdpsgitrepo/docuseal`). Railway deploys from that repo, so the published source
   is what runs.

The repo is public. It could be private only if the source were served some other way (e.g. a
download from the app), and anyone who receives it may redistribute it, so private would not mean
confidential. Never commit secrets: credentials and IDs live in Railway variables.

## What we added

| Feature | Upstream status | Ours |
|---|---|---|
| Microsoft Entra sign-in (OIDC) | Pro only (SAML) | `lib/jdpools/entra_*`, `app/controllers/jdpools/entra_sessions_controller.rb` |
| Roles + department visibility | Pro only (every user is admin upstream) | `lib/jdpools/ability_scoping.rb` |
| Password login restricted to break-glass accounts | — | `lib/jdpools/password_login_guard.rb` |
| Thai signing page (follows the signer's phone language) | Not available (14 languages, no Thai) | `config/locales/th.yml`, `config/locales/jdpools.yml`, `app/javascript/submission_form/i18n_th.js` |
| Automatic email reminders | Pro only (settings form saves, nothing sends) | `app/jobs/jdpools/submitter_reminder_job.rb` |
| Thai in generated PDFs (tone marks stacked correctly; audit trail no longer drops Thai) | HexaPDF does no shaping; audit trail's Helvetica has no Thai | `lib/jdpools/thai_pdf_text.rb`, `config/jdpools/fonts/` (Laksaman, TLWG, GPLv2+ with font exception) |
| Sign-in lander at `/`: the jdpoolstech front-door design (collab's sign-in) with Admin Sign In in the card, feature cards below, EN / TH toggle (remembered in `jdp_lang` cookie) | DocuSeal marketing page | `lib/jdpools/{landing_redirect,language_cookie,sign_in_layout}.rb`, `app/views/jdpools/_sign_in.html.erb`, `app/views/layouts/jdpools_signin.html.erb`, `public/jdpools/` |
| Onboarding: staff guide `/guide` (EN/TH, admin section for admins), JD walkthrough (DocuSeal's tour reworded + Thai), first-steps panel for senders with no documents, public signer help `/help/signing` linked from invitation emails and the signing page | DocuSeal tour, English only, shown only once a template exists | `config/locales/jdpools_onboarding.{en,th}.yml`, `app/controllers/jdpools/{guide,signer_help}_controller.rb`, `app/views/jdpools/` |
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

## Sign-in lander assets

`public/jdpools/signin.css` is a **verbatim copy** of jdpoolstech `apps/collab/src/app/signin/signin.css`
(the shared front-door stylesheet; the monorepo keeps its copies byte-identical). Re-copy it when that
file changes; put e-Sign-only rules in `signin-extras.css`. `water.js` is collab's `WaterCanvas.tsx`
shader ported to plain JS. Fonts (Prompt, DM Sans, SIL OFL) are self-hosted in `public/jdpools/fonts/`
because upstream's CSP blocks the Google Fonts stylesheet.

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
| `app/views/devise/sessions/new.html.erb` | With SSO on, renders `jdpools/_sign_in` (the lander: Microsoft button, signer note, folded IT-admin password form); upstream markup kept in the else branch |
| `app/views/shared/_navbar.html.erb` | "Guide" link next to Settings |
| `app/views/templates_dashboard/index.html.erb` | Welcome card + tour text in the EN/TH choice; members' tour ends on the guide; first-steps panel when no documents |
| `app/views/shared/_app_tour.html.erb` | Tour text in the EN/TH choice |
| `app/views/submitter_mailer/invitation_email.html.erb` | "How to sign" help line |
| `app/views/shared/_powered_by.html.erb` | "Source code" link to our fork (AGPL section 13) |
| `app/views/layouts/application.html.erb` | Attribution + source footer on staff pages (7(b), section 13) |
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
