# Releasing PingDuck

How a change gets from `main` to users, for each component. Plan: `.claude/plans/ci-cd-overhaul.md`.

## How it works

1. **Every PR** runs the checks for the parts it touches (`core ci`, `agent ci`, `app ci`, `database ci`, CodeQL). `main` only takes PRs that pass.
2. **Every push to `main`** builds test builds by itself: the agent image as `:edge` and `:sha-<commit>`, and a signed Android AAB kept as a workflow artifact for 30 days. Nothing reaches users at this stage.
3. **A release is a button.** Each component has a workflow you run by hand from `main` (Actions › the workflow › Run workflow). It runs the **release guard** first, then promotes the build that was already tested. It never rebuilds.

The release guard (`.github/actions/release-guard`) stops a release unless:

- it runs from `main`;
- the release's tag doesn't exist yet (so a version name ships once);
- the component's workflows passed on this commit, or on the newest `main` commit that touched them;
- production has every migration (`supabase db push --dry-run` reports nothing pending).

Each run's summary shows a table of these checks.

## Releasing each component

### Database (first, when a release needs it)

1. Merge the migration. On `main`, `database.yml` lists what production still lacks.
2. Run **Deploy database**. It needs your approval (the `production-database` environment), shows a dry run, then runs `supabase db push`.

Migrations must keep older app and agent builds working: add first, remove only once no released build uses the old shape (expand, then contract). Users update slowly, and Play rollouts are gradual.

### Android app

1. Change `version:` in `pingduck_app/pubspec.yaml` (the name only, e.g. `1.0.0` to `1.0.1`; leave the `+N`, CI stamps the build number). Merge.
2. Wait for `app.yml` on `main` to go green. Its summary links the signed AAB.
3. Run **release android**. It checks the guard (with `app.yml` and `core.yml`), makes sure `core/` hasn't changed since the AAB was built, tags `app-vX.Y.Z` on the AAB's commit and attaches the AAB to a GitHub release.
4. Upload that AAB to Play by hand. **CI never uploads to Play.**
   - Internal testing first. Install it from the internal link and smoke-test: scan, sign in, Plan panel, an agent's devices.
   - Then promote it in Play Console to closed testing (the beta) or production. For production, use a staged rollout (for example 10%, then 50%, then 100% over a few days) and watch Android vitals between steps.

For a quick internal test without a release, download the AAB from any green `app.yml` run on `main` and upload it. Releases are for builds that go to testers or users.

### Agent (Docker image)

1. Bump `version` in `agent/Cargo.toml`. Merge, and wait for `agent.yml` on `main`.
2. Run **release agent**. After the guard, it re-tags the tested `:sha-<commit>` image as `:X.Y.Z`, `:X.Y` and `:latest`, signs it with cosign, tags `agent-vX.Y.Z` and creates a GitHub release.

Users on `:latest` only get released versions; `:edge` follows `main`.

### Windows (desktop app and agent service)

1. Change `version:` in `pingduck_app/pubspec.yaml` (e.g. `1.0.0` to `1.0.1`; CI stamps the build number). Merge.
2. Wait for `windows.yml` on `main` to build the installer artifact and ensure `agent.yml` and `app.yml` are green.
3. Run **release windows** (Actions › release windows › Run workflow). It checks the release guard (tag `desktop-vX.Y.Z`, `windows.yml`, `agent.yml`, `app.yml`, `core.yml`, and database migrations), builds, signs with Azure Artifact Signing (when configured), tags `desktop-vX.Y.Z`, and creates the GitHub release with `PingDuckSetup.exe` attached.

If Azure Artifact Signing secrets are configured, `PingDuck.exe`, `pingduck-agent.exe`, and `PingDuckSetup.exe` are digitally signed, avoiding Windows SmartScreen warnings. Otherwise, an unsigned release is produced.

## Rollback

| Component | How |
| --- | --- |
| Android | Play has no real rollback. Halt the staged rollout in Play Console, then release a fix with a higher version. |
| Agent | Point `:latest` back: `docker buildx imagetools create -t ghcr.io/big-duck-networks/pingduck-agent:latest ghcr.io/big-duck-networks/pingduck-agent:<previous version>` |
| Windows | Delete the bad GitHub release, so `releases/latest` falls back to the one before. |
| Database | Fix forward with a new migration. Each migration runs in its own transaction, so a failed `db push` leaves the earlier ones applied. |

## Rules

- **Release only from `main`.** The guard enforces it. Play's `versionCode` must only go up, and it's the commit count on `main`.
- **Build numbers belong to CI.** People only change version names, and only to release. `tools/build.ps1` stamps local builds the same way and puts the files back.
- **Migrations are expand, then contract** (see Database above). The PR template asks about it.
- **Never put secret values in workflow logs.** Set secrets with `gh secret set NAME`, which reads the value from stdin.

## One-time setup

| Item | Where | State |
| --- | --- | --- |
| Android upload key | Repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Set (2026-10-12) |
| Play App Signing | Play Console › App integrity | Should be on (the default for new apps), so Google holds the app signing key and ours is only the upload key. Not confirmed here; check once |
| Supabase | `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF` on both the `database-check` (no reviewer, dry runs only) and `production-database` (your approval) environments | Set (2026-10-12) |
| Migration history | `supabase migration repair` so production's history matches `supabase/migrations` | Done; Deploy database refuses to run if the first migration shows as pending |
| GHCR package | GitHub org › Packages › `pingduck-agent` | Private until launch, then make it public |
| Windows code signing | Azure Artifact Signing (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_SIGNING_ACCOUNT_NAME`, `AZURE_CERTIFICATE_PROFILE_NAME`, `AZURE_SIGNING_ENDPOINT`) | Workflows wired; Azure account setup pending |

### Rotating a secret

- **Android upload key:** if it leaks or is lost, ask Google for an upload key reset in Play Console (App integrity). Then generate a new key, set the four `ANDROID_*` secrets again, and add the new SHA-1 to the Firebase key's restrictions.
- **Supabase access token:** create a new token in the dashboard (Account › Access tokens), set it on both environments, then revoke the old one.
- **Supabase database password:** reset it in project settings › Database, then set `SUPABASE_DB_PASSWORD` on both environments.

## Actions minutes

The repo is private on GitHub Free: 2,000 minutes a month, with Windows billed at 2× and macOS at 10×. That's why the macOS and iOS jobs run weekly, or on PRs labelled `apple`. Release workflows are short (a few minutes each) because they don't rebuild.
