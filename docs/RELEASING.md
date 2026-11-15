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
3. Run **release windows** (Actions › release windows › Run workflow). Two optional inputs:
   - **notes**: what's new. The app shows it in its update prompt, and it heads the release notes.
   - **required**: tick it for a fix older builds must not stay without (a security fix, or a server change they can't handle). Older builds then install it on their next daily check without waiting for a click, though Windows still asks for permission. It stays required for every later release, until a newer release is marked required.

   It checks the release guard (tag `desktop-vX.Y.Z`, `windows.yml`, `agent.yml`, `app.yml`, `core.yml`, and database migrations), builds, signs with Azure Artifact Signing (when configured), tags `desktop-vX.Y.Z`, and creates the GitHub release with `PingDuckSetup.exe` and `latest.json` attached, marked as the repo's **latest** release. Last, it records the release in Supabase (`public.app_releases`: version, build, tag, the direct GitHub link, SHA-256, size, notes, minimum build, signed, commit). It refuses to start without the `RELEASE_RECORD_TOKEN` secret.

That release is the whole delivery. Nothing else needs changing:

- **Downloads.** pingduck.app reads the current release from Supabase (`current_app_release('windows')`, cached for about a minute). The `/agent` button links straight to its GitHub download and shows its version and size, and `pingduck.app/download/windows` redirects there. With no release in Supabase (or Supabase unreachable) the button is disabled ("coming soon" before the first release) and `pingduck.app/download/windows` redirects to `/agent`.
- **If recording fails**, the release step fails after the GitHub release exists, and the site keeps offering the previous build. Fix the cause, then record it from the SQL editor: `insert into public.app_releases (platform, version, build, tag, url, sha256, size_bytes, notes, minimum_build, signed) values ('windows', …)`, with the values from the release's `latest.json`.
- **Updates.** The app reads `releases/latest/download/latest.json` about 20 seconds after launch and then daily, and compares its `build` with its own build number. A newer build shows **Update** under App settings › Updates and **Install update** in the tray menu. Installing downloads the installer, checks its size and SHA-256 against `latest.json` (and, once builds are signed, that it's signed by Big Duck Networks), runs it silently through Windows' admin prompt, and the installer reopens the app. Code: `pingduck_app/lib/core/desktop/updates.dart`. The agent service is in the same installer, so it updates with the app.

**Releases/latest belongs to Windows.** `release agent` and `release android` pass `--latest=false`. Never mark another release as latest by hand: the download link and every installed app's update check would go to it and fail.

`latest.json`:

```json
{
  "version": "1.0.1",
  "build": 412,
  "url": "https://github.com/Big-Duck-Networks/pingduck/releases/download/desktop-v1.0.1/PingDuckSetup.exe",
  "sha256": "…",
  "size": 14262784,
  "notes": "Faster scans on large networks.",
  "minimumBuild": 0,
  "signed": true,
  "published": "2026-11-20T15:04:05Z"
}
```

`build` is CI's build number (the commit count on `main`), shown in the app as `v1.0.1 (412)`. `minimumBuild` is the required floor.

If Azure Artifact Signing secrets are configured, `PingDuck.exe`, `pingduck-agent.exe`, and `PingDuckSetup.exe` are digitally signed, avoiding Windows SmartScreen warnings. Otherwise, an unsigned release is produced.

## Rollback

| Component | How |
| --- | --- |
| Android | Play has no real rollback. Halt the staged rollout in Play Console, then release a fix with a higher version. |
| Agent | Point `:latest` back: `docker buildx imagetools create -t ghcr.io/big-duck-networks/pingduck-agent:latest ghcr.io/big-duck-networks/pingduck-agent:<previous version>` |
| Windows | Withdraw it in Supabase (`update public.app_releases set withdrawn_at = now() where tag = 'desktop-v<bad>'`), so the website offers the previous build within a minute or two. Mark the previous release as latest (`gh release edit desktop-v<previous> --latest`) so installed apps stop being offered the bad build, then delete the bad release. Apps that already installed it don't go back, because they only take a higher build: release a fix with a new version instead. |
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
| Windows release token | Repo secret `RELEASE_RECORD_TOKEN`, and its SHA-256 in `private.release_keys` (see `supabase/migrations/20261114130000_app_releases.sql`). It can only record releases. | Pending |
| Windows code signing | Azure Artifact Signing (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_SIGNING_ACCOUNT_NAME`, `AZURE_CERTIFICATE_PROFILE_NAME`, `AZURE_SIGNING_ENDPOINT`) | Workflows wired; Azure account setup pending |

### Rotating a secret

- **Android upload key:** if it leaks or is lost, ask Google for an upload key reset in Play Console (App integrity). Then generate a new key, set the four `ANDROID_*` secrets again, and add the new SHA-1 to the Firebase key's restrictions.
- **Supabase access token:** create a new token in the dashboard (Account › Access tokens), set it on both environments, then revoke the old one.
- **Supabase database password:** reset it in project settings › Database, then set `SUPABASE_DB_PASSWORD` on both environments.

## Actions minutes

The repo is private on GitHub Free: 2,000 minutes a month, with Windows billed at 2× and macOS at 10×. That's why the macOS and iOS jobs run weekly, or on PRs labelled `apple`. Release workflows are short (a few minutes each) because they don't rebuild.
