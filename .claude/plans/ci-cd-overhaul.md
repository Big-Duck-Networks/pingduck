# Feature: CI/CD overhaul before launch

The following plan should be complete, but it's important that you validate documentation and codebase patterns and task sanity before you start implementing.

Pay special attention to naming of existing workflows, secrets, paths and tools. Every action version below was current in October 2026; Dependabot keeps them current afterwards.

## Feature Description

Replace PingDuck's two ad-hoc workflows and its hand-run releases with one system on GitHub Actions:

- **Every PR and push** runs the checks for the parts it touches (core, agent, app, database, website).
- **Every push to `main`** also ships *test* builds automatically: Android to Play internal testing, the agent image as `:edge`, a Windows installer artifact, and the website to production.
- **Releasing to users** is a deliberate step: a "Release …" workflow per component (Run workflow button). It checks that the version isn't already released, that the database is migrated, and that `main` is green. Then it **promotes the already-tested build**: Play staged rollout, re-tagging the same agent image, and a signed Windows installer on a public download.
- **The database** is migrated by the pipeline (`supabase db push`), never pasted by hand. Every PR tests the migrations, and every `main` push reports what is pending.
- **Version numbers:** CI stamps build numbers. People only change version names, when they mean to release.

## User Story

As the person shipping PingDuck
I want to push to GitHub and have checks, test builds and (on one click) releases happen by themselves
So that every release is the tested build, nothing ships broken, and launch doesn't depend on manual steps I might get wrong

## Problem Statement

Reviewed in this session (2026-10-10):

- `core.yml` mixes core and agent. It runs macOS and iOS jobs (10× minutes) even for agent-only changes. It publishes the agent image without waiting for the other jobs, and builds arm64 under QEMU with `cargo test` inside, so it is slow and can hit the 60-minute timeout. It has never published, and no Rust agent job has run on GitHub yet.
- `windows-release.yml` has never run.
- **The app has no CI**: 84 tests and `flutter analyze` only run locally.
- **Android release builds are signed with the debug key** (`pingduck_app/android/app/build.gradle.kts:28-33`), which Play rejects.
- Build numbers are bumped by hand (`dart run tools/build_number_gen.dart`) and committed. Build 5 shipped stamped with the wrong commit.
- Supabase migrations are pasted into the SQL editor. `supabase_migrations.schema_migrations` on the project is therefore empty. `supabase/tests/run_tests.sh` exists but never runs in CI.
- The website deploys by `npm run rebuild` from this PC (`pingduck_website/scripts/rebuild.ps1` → SSH → `restart-hetzner.sh --pull`).
- The repo is private, so `releases/latest/download/PingDuckSetup.exe` and the GHCR image are unreachable for users.

**Platform constraints found during research**, which shape the design:

- The org `Big-Duck-Networks` is on **GitHub Free** and `pingduck` is **private**. On Free private repos:
  - no branch protection or rulesets (the API answered 403 "Upgrade to GitHub Pro");
  - no environment secrets, no deployment-branch rules, no required reviewers;
  - **2,000 Actions minutes a month**, with Windows at 2× and macOS at 10×.
- The website repo `Big-Duck-Networks/Pingduck.app` is **public**, so it gets environments, reviewers and unlimited minutes.
- Linux arm64 standard runners (`ubuntu-24.04-arm`) became available in private repos on 2026-01-29 and count against the free minutes. That makes native arm64 builds possible.
- Azure **Artifact Signing** (renamed from Trusted Signing in January 2026) is open to US organizations and US individuals. The 3-year business-history rule was dropped on 2025-10-31.

## Solution Statement

Split CI into one workflow per component with tight path filters. Add the missing checks (app, database, website). Give every component the same three-stage flow:

```
PR / push ──► check (required to stay green)
main push ──► check ──► test build, shipped automatically (internal track, :edge, artifact, website)
Release ──► guard (version not released, DB migrated, main green) ──► promote the tested build
```

On GitHub Free, the gates are built differently:

| Upgrade feature we can't have | What we use instead |
|---|---|
| Required reviewers | **`workflow_dispatch`**. Only people with write access can press Run workflow, which for a one-person org *is* the approval. |
| Branch protection | **A `ci` aggregate job per workflow, and a "main is green" check in every Release workflow.** A release refuses to run on a commit whose checks failed. |
| Environment secrets | **Repository secrets** whose names say what they are for. On a one-person org every workflow is trusted anyway, and fork PRs never receive secrets. |

The plan stays correct after an upgrade to **GitHub Team** ($4/user/month): you'd add branch protection on `main` requiring the `ci` checks, and move release secrets into environments. That's Task 30. A public repo would also get required reviewers and unlimited minutes; see Open Questions.

## Out of Scope / Non-Goals

- Not included:
  - **TestFlight and App Store releases.** There's no Apple Developer account yet. iOS gets a compile-only job, and the TestFlight lane is a follow-up plan.
  - **Splitting the repo.** Cancelled earlier this session.
  - **A staging Supabase project.** Default: one project; the test builds talk to production.
  - **Crash reporting** (Phase 8, separate ticket).
  - **Self-hosted runners.**
  - **Feature flags.**
- Not changing:
  - the C++ core's test matrix (Windows, Linux, sanitizers, fuzz, Android NDK, macOS, iOS xcframework). Same jobs, new triggers.
  - `restart-hetzner.sh`. The Action calls it as is.
  - the Inno Setup script. A signing step is added before it, nothing else.
  - the app's Supabase defaults (`supabase_config.dart`).
- Not doing **expand/contract enforcement in tooling**. It's a written rule in `docs/RELEASING.md` and a checklist item in the PR template.

## Feature Metadata

**Feature Type**: New Capability, plus a refactor of the existing CI
**Estimated Complexity**: High (many workflows and external accounts), but each task is small
**Primary Systems Affected**: `.github/`, `pingduck_app/android/app/build.gradle.kts`, `supabase/`, `agent/Dockerfile`, the website repo's `.github/`, `docs/`
**Dependencies**:
- GitHub Actions
- Google Play Developer API (a service account)
- Supabase CLI (`supabase/setup-cli@v1`)
- Docker buildx
- Sigstore cosign
- Azure Artifact Signing (optional until the account exists)
- fastlane `supply` (Play track promotion)
- `appleboy/ssh-action` (website deploy)

## Related Work

**Implements**: `docs/ROADMAP.md` Phase 8 "Beta" and "TODO at launch: publish /agent"; the CI rows in Phases 1 and 4.

**Back-references:**

- `.claude/plans/windows-desktop-and-rust-agent.md`: Phase 4 defined `windows-release.yml` and the installer, which this plan replaces and extends.
- `.claude/plans/agent-pairing-lan-discovery.md`: the GHCR image and the `/agent` page.

**Forward-references:**

- (to write) `ios-testflight.md`: the App Store lane, once an Apple Developer account exists.

---

## CONTEXT REFERENCES

### Relevant Codebase Files: YOU MUST READ THESE BEFORE IMPLEMENTING

- `.github/workflows/core.yml` (all 182 lines): the core jobs to keep (lines 19-117) and the agent jobs to move (118-182). Mirror its style: `timeout-minutes` on every job, `-LE network` for ctest, comments above non-obvious steps.
- `.github/workflows/windows-release.yml` (all 72 lines): the Windows build steps to keep (Flutter 3.44.0, `cargo build --release`, `choco install innosetup`, `ISCC /DAppVersion=`).
- `agent/Dockerfile` (all): the build stage runs `cargo test` (line ~33). Keep it: with native per-arch runners it's no longer emulated. The runtime stage has `HEALTHCHECK`. The OCI labels say `Apache-2.0` while `agent/Cargo.toml` says `UNLICENSED` (fix in Task 12).
- `agent/Cargo.toml` (`[workspace.package] version = "0.3.0"`): the agent's version source of truth.
- `pingduck_app/pubspec.yaml:19` (`version: 1.0.0+6`): the app's version source of truth. Only the name before `+` matters after this plan.
- `tools/build_number_gen.dart` (lines 1-30, 60-75, 340-350): supports `--git` (build number = `git rev-list --count HEAD`, currently 32) and `--github-output`. It writes `pubspec.yaml` and `lib/core/constants/app_version.dart`. CI runs it without committing.
- `pingduck_app/android/app/build.gradle.kts` (lines 26-33): the `release` build type uses `signingConfigs.getByName("debug")`. `applicationId = "app.webcap.pingduck"`.
- `pingduck_app/android/.gitignore`: already ignores `key.properties`, `*.jks` and `*.keystore`.
- `supabase/tests/run_tests.sh` (all): applies `tests/supabase_stub.sql` and every migration to a throwaway `postgres:15` container, then runs `schema_test.sql`. **Reuse it in CI**: it's faster than `supabase start` and already proven.
- `supabase/migrations/*.sql` (6 files, 20261006120000 to 20261011120000): all applied to production by hand. The email functions skip sending when there is no `resend_api_key` in Vault (`20261008120000_goodbye_email.sql:33-40`), so tests never send email.
- `installer/windows/pingduck.iss`: needs `/DAppVersion=`; the exes it packs are built before it runs.
- `pingduck_website/scripts/restart-hetzner.sh` (all) and `scripts/rebuild.ps1` (lines 1-60): the server path is `/var/www/pingduck_website`, the user `root`, the health check URL `https://pingduck.app`, and settings live in `scripts/.env.deploy`.
- `pingduck_website/src/app/agent/page.tsx` and `src/lib/site.ts` (`agentWindowsUrl: null`): where the public download URL goes at launch.
- `docs/ROADMAP.md` Phase 8 (lines ~184-196): rows to update.

### New Files to Create

**`pingduck` repo:**

| File | Purpose |
|---|---|
| `.github/workflows/agent.yml` | Agent clippy and tests on Windows and Linux; on `main`, native amd64 and arm64 images by digest, merged into `:edge` and `:sha-<sha>`, signed with cosign, with SBOM and provenance. |
| `.github/workflows/app.yml` | `flutter analyze` and `flutter test` on PR and push; on `main`, a signed AAB to Play internal testing. |
| `.github/workflows/database.yml` | `run_tests.sh` on PR and push; on `main`, `supabase db push --dry-run` against production, listing pending migrations in the job summary. |
| `.github/workflows/windows.yml` | Replaces `windows-release.yml`. On `main` and by hand: build `PingDuckSetup.exe` as a 7-day artifact. |
| `.github/workflows/ios.yml` | Weekly and by hand: `flutter build ios --no-codesign`, so iOS keeps compiling. |
| `.github/workflows/release-agent.yml` | Release button: guard, re-tag `:sha-<sha>` → `:X.Y.Z`, `:X.Y`, `:latest`; sign; git tag `agent-vX.Y.Z`; GitHub release notes. |
| `.github/workflows/release-android.yml` | Release button: guard, promote the internal-track build to production at a staged rollout fraction; tag `app-vX.Y.Z`. |
| `.github/workflows/android-rollout.yml` | By hand: raise or halt the production rollout fraction (10% → 50% → 100%). |
| `.github/workflows/release-windows.yml` | Release button: guard, build, sign (when configured), publish to the public `pingduck-releases` repo; tag `desktop-vX.Y.Z`. |
| `.github/workflows/deploy-database.yml` | Button: `supabase db push` to production. |
| `.github/actions/release-guard/action.yml` | Composite action shared by the Release workflows: version not already tagged, required checks green on this commit, no pending migrations. |
| `.github/dependabot.yml` | Weekly grouped updates for Cargo, pub (app and plugin) and GitHub Actions. |
| `.github/pull_request_template.md` | Checklist, including "migration is backward-compatible (expand/contract)". |
| `supabase/config.toml` | Created by `supabase init`; required by `supabase link` and `db push`. |
| `docs/RELEASING.md` | Runbook: how to release each component, roll back, rotate keys, and the one-time setup checklist. |

**`Pingduck.app` (website) repo:**

| File | Purpose |
|---|---|
| `.github/workflows/ci.yml` | `npm ci`, `npm run lint`, `npm run build` on PR and push. |
| `.github/workflows/deploy.yml` | On `main` after CI: SSH to Hetzner, run `restart-hetzner.sh --pull`, health-check `https://pingduck.app`. Uses the `production` environment, which works because the repo is public. |
| `.github/dependabot.yml` | Weekly updates for npm and GitHub Actions. |

**New public repo `Big-Duck-Networks/pingduck-releases`** (created by the user): README only. It holds the Windows installer releases.

### Relevant Documentation: YOU SHOULD READ THESE BEFORE IMPLEMENTING

- [Docker: multi-platform builds in GitHub Actions](https://docs.docker.com/build/ci/github-actions/multi-platform/). Current majors: `setup-buildx-action@v4`, `build-push-action@v7`, `setup-qemu-action@v4`. Also see the "distribute build across multiple runners" pattern: push by digest per platform, then `docker buildx imagetools create`. The page also documents a reusable `docker/github-builder` workflow (`@v1`); prefer the manual digest pattern unless you verify the reusable workflow's inputs.
- [GitHub: arm64 standard runners in private repositories](https://github.blog/changelog/2026-01-29-arm64-standard-runners-are-now-available-in-private-repositories). `runs-on: ubuntu-24.04-arm`; 2 vCPU, 8 GB in private repos.
- [GitHub: deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments). Confirms that required reviewers are public-only on Free/Pro/Team, and environment secrets need Pro or Team in private repos.
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions). Free: 2,000 minutes a month for private repos; Windows 2×, macOS 10×.
- [Supabase: managing environments](https://supabase.com/docs/guides/deployment/managing-environments): `supabase/setup-cli@v1`, `supabase link --project-ref`, `supabase db push`, with `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`.
- [Supabase: database migrations](https://supabase.com/docs/guides/deployment/database-migrations): `supabase migration repair --status applied <version>` for migrations applied by hand.
- [Flutter: build and release an Android app, signing](https://docs.flutter.dev/deployment/android#sign-the-app): the `key.properties` and `signingConfigs` pattern (adapted here for Kotlin DSL and environment variables).
- [r0adkll/upload-google-play](https://github.com/r0adkll/upload-google-play): `serviceAccountJsonPlainText`, `packageName`, `releaseFiles`, `track: internal`, `status: completed`.
- [fastlane supply](https://docs.fastlane.tools/actions/supply/): `--track internal --track_promote_to production --rollout 0.1`, and `--track production --rollout 0.5` to raise it.
- [Play Console: staged rollouts](https://support.google.com/googleplay/android-developer/answer/6346149).
- [Sigstore cosign keyless signing in GitHub Actions](https://docs.sigstore.dev/cosign/signing/overview/): `sigstore/cosign-installer`, `permissions: id-token: write`, `cosign sign --yes <image>@<digest>`.
- [Azure Artifact Signing GitHub Action](https://github.com/Azure/artifact-signing-action): inputs `endpoint`, `signing-account-name`, `certificate-profile-name`, `files-folder`, `files-folder-filter`. Logs in with `azure/login` (OIDC, federated credential).
- [Azure Artifact Signing eligibility](https://devclass.com/2026/01/14/code-signing-windows-apps-may-be-easier-and-more-secure-with-new-azure-artifact-service/): US/CA/EU/UK organizations, US/CA individuals; the 3-year rule was dropped.
- [appleboy/ssh-action](https://github.com/appleboy/ssh-action): `host`, `username`, `key`, `fingerprint` (pin the host key), `script`.
- [Dependabot configuration](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference): `package-ecosystem: cargo | pub | github-actions | npm`, `groups`.

### Patterns to Follow

**Workflow style** (from `core.yml`):
- a top-level `permissions: contents: read`, widened per job only where needed;
- `concurrency: group: <name>-${{ github.ref }}`, with `cancel-in-progress: true` for checks and **`false` for anything that publishes**;
- `timeout-minutes` on every job;
- a short comment above each non-obvious step;
- job names like `Agent (Windows)`.

**Rust env on Windows runners:** the runner's VS 2022 has its own CMake, so the `CMAKE`/`CMAKE_GENERATOR` workaround in memory `dev-environment.md` is only needed on this PC. Keep `CARGO_INCREMENTAL=0` out of CI (cargo turns incremental off for release builds already).

**Version sources** (single source of truth per component):

| Component | Version name from | Build number | Git tag |
|---|---|---|---|
| Android app | `pingduck_app/pubspec.yaml` name before `+` | `git rev-list --count HEAD` (via `build_number_gen.dart --git`) | `app-vX.Y.Z` |
| Windows desktop | same pubspec name | (not used by Inno) | `desktop-vX.Y.Z` |
| Agent | `agent/Cargo.toml` `[workspace.package] version` | image `:sha-<sha>` | `agent-vX.Y.Z` |
| Core | `pd_version()` (`core/src/core.cpp`) | n/a | not released separately |

**Secrets naming** (repository secrets, since Free has no environment secrets): `PLAY_*`, `ANDROID_*`, `SUPABASE_*`, `AZURE_*`, `RELEASES_TOKEN`. The full list is in Task 1.

**Commit attribution** for any commit the agent makes: end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## IMPLEMENTATION PLAN

### Phase 0: One-time setup (the user, with the executing agent guiding)

Accounts, keys and secrets that no workflow can create. Tasks 1-3. Phases 1-2 need none of them; each later phase names the secrets it needs and **skips cleanly** (a job-summary note, not a failure) while they're missing.

### Phase 1: Checks on everything

**Independent of:** Phase 0.

Split `core.yml`, add the app, database and Dependabot checks, and add the PR template. After this phase every part of the repo is tested on PR and push. Tasks 4-11.

### Phase 2: Agent pipeline

**Depends on:** Phase 1 (`agent.yml` exists).

Native multi-arch images, `:edge` on `main`, signing and SBOM/provenance, and the release workflow that re-tags. Tasks 12-15.

### Phase 3: Android pipeline

**Depends on:** Task 1's Android/Play secrets for the publishing jobs; the build itself doesn't need them.

Real signing, internal track on `main`, staged production release. Tasks 16-19.

### Phase 4: Database pipeline

**Depends on:** Task 2 (migration history repaired) **before** Task 21's deploy is ever run.

Dry-run on `main`, deploy button, guard. Tasks 20-21.

### Phase 5: Windows pipeline

**Independent of:** Phases 3-4. Signing depends on the Azure account; the workflow ships unsigned until the `AZURE_*` secrets exist.

Tasks 22-24.

### Phase 6: Release guard and runbook

**Depends on:** Phases 2-5 (the guard checks their workflows).

The shared guard action, `docs/RELEASING.md`, the roadmap update. Tasks 25-27.

### Phase 7: Website

**Independent of:** all other phases (separate repo).

Tasks 28-29.

### Phase 8: After launch or an upgrade

Task 30, plus the iOS lane in a follow-up plan.

---

## STEP-BY-STEP TASKS

IMPORTANT: Execute every task in order, top to bottom. Each task is atomic and independently testable. Workflow tasks are validated with `actionlint` (install: `go install github.com/rhysd/actionlint/cmd/actionlint@latest`; Go is installed on this PC) and then by a real run on GitHub. The user pushes, or the agent pushes after the user agrees; never push without asking.

### Task 1: SETUP the accounts and secrets (user checklist, written into `docs/RELEASING.md` in Task 26)

- **IMPLEMENT**: Walk the user through it, one item at a time, and record what's done:
  1. **Android upload key:**
     `keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000`.
     Store it in a password manager. Then set the repo secrets:
     - `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload.jks`)
     - `ANDROID_KEYSTORE_PASSWORD`
     - `ANDROID_KEY_ALIAS` = `upload`
     - `ANDROID_KEY_PASSWORD`
  2. **Play Console:**
     - Create the app `app.webcap.pingduck` if it isn't there.
     - Enrol in Play App Signing (the default for new apps).
     - **Upload the first AAB by hand** to Internal testing (the API can't create the first release).
  3. **Play service account:**
     - In Google Cloud, create a service account and enable the Android Publisher API.
     - In Play Console › Users and permissions, invite the service account email with "Release to testing tracks" and "Release to production" for this app.
     - Secret `PLAY_SERVICE_ACCOUNT_JSON` holds the JSON key.
  4. **Supabase:**
     - `SUPABASE_ACCESS_TOKEN`: a personal access token, from dashboard › Account › Access tokens.
     - `SUPABASE_DB_PASSWORD`: from project settings › Database.
     - `SUPABASE_PROJECT_REF` = `rumwtzzyrhzudguolasq`.
  5. **GitHub org settings:**
     - Allow public packages (Settings › Packages).
     - Create the **public** repo `Big-Duck-Networks/pingduck-releases` with a README.
     - Create a fine-grained PAT, scoped only to `pingduck-releases` with Contents: read & write, as secret `RELEASES_TOKEN`.
  6. **Azure Artifact Signing** (optional now):
     - Create a signing account and a public-trust certificate profile; identity validation takes a few days.
     - Create an app registration with a federated credential for `repo:Big-Duck-Networks/pingduck:ref:refs/heads/main`.
     - Secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_CERT_PROFILE`.
  7. **Website repo secrets** (`Pingduck.app`, `production` environment):
     - `HETZNER_HOST`
     - `HETZNER_USER` = `root`
     - `HETZNER_SSH_KEY`: a new deploy key added to the server's `authorized_keys`.
     - `HETZNER_FINGERPRINT`: from `ssh-keyscan <host> | ssh-keygen -lf -`.
- **GOTCHA**: The secrets are set by the user (`gh secret set NAME`). The agent never sees the values; never echo them in workflows. `gh secret set` reads stdin, so suggest `! gh secret set ANDROID_KEYSTORE_PASSWORD` so the value doesn't land in shell history.
- **VALIDATE**: `gh secret list -R Big-Duck-Networks/pingduck` lists the names; `gh secret list -R Big-Duck-Networks/Pingduck.app --env production`.
- **SATISFIES**: AC 6, 7, 8, 10.

### Task 2: SETUP Supabase migration history (one time, before any `db push`)

- **IMPLEMENT**:
  - From the repo root, run `npx supabase init`, accepting the defaults (it creates `supabase/config.toml` and leaves `migrations/` alone; say no to the VS Code settings prompts).
  - Then `npx supabase link --project-ref rumwtzzyrhzudguolasq` (prompts for the DB password; the user runs it with `!`).
  - Then `npx supabase migration list`. It should show all 6 migrations as local-only.
  - The user then runs `npx supabase migration repair --status applied 20261006120000 20261007120000 20261007130000 20261008120000 20261010120000 20261011120000`.
- **GOTCHA**: Only list migrations **actually applied** in production. Ask the user to confirm `20261011120000_agent_instructions_windows.sql` was applied (it was pending earlier this session). Leave any unapplied one out, so `db push` applies it. Repair only writes the history table; it never runs SQL.
- **VALIDATE**: `npx supabase migration list` shows every applied one in both Local and Remote columns; `npx supabase db push --dry-run` prints "Remote database is up to date" (or lists only truly pending ones).
- **SATISFIES**: AC 7.

### Task 3: SETUP the version policy (no code change)

- **IMPLEMENT**:
  - Decide and record in `docs/RELEASING.md` (Task 26) that build numbers are CI-owned from now on, so `dart run tools/build_number_gen.dart` is no longer run by hand.
  - Leave `pubspec.yaml` at `1.0.0+6` and `app_version.dart` as they are: CI overwrites both in the workspace on every build.
- **GOTCHA**: Play `versionCode` must only increase. The commit count is 32 today, above the 6 used so far, and only grows on `main` (releases build only from `main`). Never build a release from a branch.
- **VALIDATE**: `git rev-list --count HEAD` is greater than 6.
- **SATISFIES**: AC 5.

### Task 4: UPDATE `.github/workflows/core.yml`: core only

- **IMPLEMENT**:
  - Delete the `agent-windows` and `agent` jobs (lines 118-182).
  - Change both `paths:` filters to `["core/**", "packages/pingduck_core/**", ".github/workflows/core.yml"]`.
  - Add `schedule: - cron: "0 6 * * 1"` (weekly) so fuzzing and the macOS/iOS builds still run when core is quiet.
  - Restrict the **macOS** and **iOS** jobs (10× minutes) to: `if: github.event_name != 'pull_request' || contains(github.event.pull_request.labels.*.name, 'apple')`, so PRs skip them unless labelled.
  - Add a final `ci` job: `needs: [windows, linux, sanitizers, fuzz, android, macos, ios]`, `if: always()`, which fails if any needed job failed. Skipped counts as success. This one job is what a future branch rule requires.
- **PATTERN**: the existing job layout in `core.yml`.
- **GOTCHA**: The `ci` aggregate needs `if: always()` and an explicit check:
  `run: echo '${{ toJSON(needs) }}' | jq -e 'all(.[]; .result == "success" or .result == "skipped")'`.
- **VALIDATE**: `actionlint .github/workflows/core.yml`
- **SATISFIES**: AC 1, AC 11.

### Task 5: CREATE `.github/workflows/agent.yml`: checks

- **IMPLEMENT**:
  - **Triggers:** `push` to `main` and `pull_request`, both with paths `["agent/**", "core/**", ".dockerignore", ".github/workflows/agent.yml"]`; plus `workflow_dispatch`.
  - **Jobs** (moved from `core.yml`):
    - `test-windows` (windows-latest): `cargo clippy --workspace --all-targets --locked -- -D warnings` and `cargo test --workspace --locked`, in `agent/`.
    - `test-linux` (ubuntu-latest): `apt-get install -y libpcap-dev`, the same clippy and test commands, then `docker build -f agent/Dockerfile -t pingduck-agent .` and the smoke tests:
      - `docker run --rm pingduck-agent --version`;
      - `docker run --rm --entrypoint pingduck pingduck-agent oui 50:c7:bf:00:00:01 --oui /usr/share/pingduck/oui.csv`;
      - **new:** `docker run -d --name a pingduck-agent`, wait 5 s, then `docker exec a pingduck-agent healthcheck`.
- **PATTERN**: `core.yml:118-157` (removed in Task 4).
- **GOTCHA**: On a runner without `--net=host` the agent still serves HTTP on the container's interface, so `healthcheck` (which connects to 127.0.0.1 inside the container) works. Keep `timeout-minutes: 30`.
- **VALIDATE**: `actionlint .github/workflows/agent.yml`
- **SATISFIES**: AC 1.

### Task 6: CREATE `.github/workflows/app.yml`: checks

- **IMPLEMENT**:
  - **Triggers:** `push` to `main` and `pull_request`, with paths `["pingduck_app/**", "packages/pingduck_core/**", "tools/**", ".github/workflows/app.yml"]`; plus `workflow_dispatch`.
  - **Job `test`** (ubuntu-latest, 20 min): `actions/checkout`, then `subosito/flutter-action@v2` (`channel: stable`, `flutter-version: 3.44.0`, `cache: true`). In `pingduck_app/`, run:
    - `flutter pub get`
    - `dart format --output=none --set-exit-if-changed lib test`. **Check first** whether the code is format-clean; if `dart format` would change files, either format them in a separate commit or drop this step.
    - `flutter analyze`
    - `flutter test`
- **PATTERN**: `windows-release.yml:36-50`, the Flutter setup.
- **GOTCHA**:
  - `flutter test` runs `isDesktop` with the `FLUTTER_TEST` env set, so desktop code is off. The FFI plugin is **not** compiled for unit tests (they use `FakeBridge`), so no CMake or NDK is needed.
  - The drift `.g.dart` files are committed, so no `build_runner` step is needed. Confirm with `git ls-files pingduck_app/lib/services/local_storage.g.dart`.
- **VALIDATE**: `actionlint .github/workflows/app.yml`; locally `cd pingduck_app && flutter analyze && flutter test`.
- **SATISFIES**: AC 1.

### Task 7: CREATE `.github/workflows/database.yml`: checks

- **IMPLEMENT**:
  - **Triggers:** `push` to `main` and `pull_request`, with paths `["supabase/**", ".github/workflows/database.yml"]`; plus `workflow_dispatch`.
  - **Job `test`** (ubuntu-latest, 10 min): `sh supabase/tests/run_tests.sh`. It needs Docker and `psql` inside the container, both on the runner image. Then `grep` the output for `ALL SCHEMA TESTS PASSED`.
  - **Job `pending`** (only on `push` to `main`, `needs: test`, skips with a summary note if `SUPABASE_ACCESS_TOKEN` is empty):
    1. `supabase/setup-cli@v1` with `version: latest`;
    2. `supabase link --project-ref "$SUPABASE_PROJECT_REF"`;
    3. `supabase db push --dry-run`, saved to `$GITHUB_STEP_SUMMARY`.
    4. If it lists pending migrations, emit `::warning::N migrations pending; run Deploy database`.
- **PATTERN**: `supabase/tests/run_tests.sh`.
- **GOTCHA**:
  - Check how `run_tests.sh` signals failure. It `set -eu`s and `ON_ERROR_STOP=1`s psql, so a failing check exits non-zero. The grep is a second guard.
  - **Secrets in `if:`**: `secrets` can't be used directly in `if:`. Map them to `env` at job level and test `env.SUPABASE_ACCESS_TOKEN != ''`.
- **VALIDATE**: `actionlint .github/workflows/database.yml`; `sh supabase/tests/run_tests.sh` on `pingduck-vm` (Docker is there; this PC has none).
- **SATISFIES**: AC 1, AC 7.

### Task 8: CREATE `.github/workflows/ios.yml`

- **IMPLEMENT**:
  - **Triggers:** `schedule: cron "0 7 1 * *"` (monthly; see NOTES, Minutes budget) and `workflow_dispatch`.
  - **Job:** macos-latest, 45 min, Flutter 3.44.0. In `pingduck_app/`, run `flutter build ios --release --no-codesign`.
- **GOTCHA**: About 15-20 min at 10×, i.e. ~200 minutes a run. Monthly and by hand only, never on push. The first run may fail on Pod or Xcode settings that have never been built. That's the point: record findings in the plan's AMENDMENTS and fix them there.
- **VALIDATE**: `actionlint .github/workflows/ios.yml`
- **SATISFIES**: AC 1.

### Task 9: CREATE `.github/dependabot.yml`

- **IMPLEMENT**: `version: 2`, with one weekly entry each (`schedule.interval: weekly`, `groups: all: patterns: ["*"]`, `open-pull-requests-limit: 3`) for:
  - `cargo` (`/agent`)
  - `pub` (`/pingduck_app`)
  - `pub` (`/packages/pingduck_core`)
  - `github-actions` (`/`)
- **GOTCHA**: The Dependabot `pub` ecosystem needs `pubspec.lock` committed (it is, for the app). For pub, ignore Flutter-SDK-pinned packages if Dependabot proposes impossible bumps; add `ignore` entries as they appear.
- **VALIDATE**: The file passes GitHub's validation: after the push, the repo's Insights › Dependency graph › Dependabot tab shows no config errors.
- **SATISFIES**: AC 12.

### Task 10: CREATE `.github/pull_request_template.md`

- **IMPLEMENT**: A short checklist:
  - tests added or updated;
  - **migrations are backward-compatible: old app builds keep working (expand now, contract in a later release)**;
  - user-facing strings follow the copy rules;
  - no secrets in the diff.
- **VALIDATE**: The file renders on a test PR.
- **SATISFIES**: AC 7.

### Task 11: REMOVE `.github/workflows/windows-release.yml` (replaced in Tasks 22-23)

- **IMPLEMENT**: `git rm` it in the same commit that adds `windows.yml` (Task 22). Don't remove it earlier, so there's always one Windows workflow.
- **VALIDATE**: `ls .github/workflows` doesn't include it after Task 22.
- **SATISFIES**: AC 9.

### Task 12: UPDATE `agent/Dockerfile` and `agent/Cargo.toml`: labels and version

- **IMPLEMENT**:
  - Make the image's licence label match the crate. **Ask the user** whether the agent is Apache-2.0 (open source) or proprietary. Default: change the Dockerfile label to `LicenseRef-Proprietary` to match `license = "UNLICENSED"`.
  - Add `LABEL org.opencontainers.image.version` from a build arg: `ARG VERSION=dev`, `LABEL org.opencontainers.image.version=$VERSION`.
- **GOTCHA**: `ARG` before `FROM` isn't visible after it; declare `ARG VERSION` in the runtime stage.
- **VALIDATE**: `docker build --build-arg VERSION=0.3.0 -f agent/Dockerfile -t t .` on pingduck-vm, then `docker inspect t --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'` prints `0.3.0`.
- **SATISFIES**: AC 6.

### Task 13: ADD image publishing to `.github/workflows/agent.yml`

- **IMPLEMENT**: New jobs, all with `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`. Use workflow-level `concurrency: { group: agent-publish, cancel-in-progress: false }` for publish jobs, or a separate group for them.
  1. **`image`**:
     - `needs: [test-windows, test-linux]`
     - matrix `include: [{platform: linux/amd64, runner: ubuntu-24.04}, {platform: linux/arm64, runner: ubuntu-24.04-arm}]`; `runs-on: ${{ matrix.runner }}`
     - `permissions: contents: read, packages: write`
     - steps: `docker/setup-buildx-action@v4`; `docker/login-action` (ghcr.io, `github.actor`, `secrets.GITHUB_TOKEN`); then `docker/build-push-action@v7` with:
       - `platforms: ${{ matrix.platform }}`
       - `build-args: VERSION=<from Cargo.toml>`
       - `outputs: type=image,name=ghcr.io/big-duck-networks/pingduck-agent,push-by-digest=true,name-canonical=true,push=true`
       - `cache-from: type=gha,scope=${{ matrix.platform }}`, `cache-to: type=gha,mode=max,scope=…`
     - Write the digest to a file and upload it with `actions/upload-artifact` (name `digest-${{ strategy.job-index }}`).
     - Read the version with: `grep -m1 '^version' agent/Cargo.toml | cut -d'"' -f2`.
  2. **`publish`**:
     - `needs: image`; `permissions: contents: read, packages: write, id-token: write`
     - Download the digests, then `docker buildx imagetools create -t …:edge -t …:sha-${{ github.sha }} <image>@sha256:<d1> <image>@sha256:<d2>`.
     - Install `sigstore/cosign-installer` (latest major) and run `cosign sign --yes ghcr.io/big-duck-networks/pingduck-agent@<index digest>`. Get the digest from `docker buildx imagetools inspect …:sha-${{ github.sha }} --format '{{json .Manifest.Digest}}'`.
     - Write the image reference and digest to `$GITHUB_STEP_SUMMARY`.
  - SBOM and provenance: set `provenance: mode=max` and `sbom: true` on the build-push step, so buildx attaches them per platform.
- **PATTERN**: Docker's multi-platform doc (distribute across runners). The old `core.yml:158-182` publish step is the thing being replaced.
- **GOTCHA**:
  - **Don't publish `:latest` here.** `:latest` only moves in `release-agent.yml`, so users on `:latest` only get released versions. Update the roadmap's Phase 8 Beta row, which says CI publishes `:latest` on every push.
  - **cosign keyless** records the repo and workflow identity in the public Rekor transparency log. The repo name becomes public; that's acceptable, since it's in the image labels anyway. Note it in `RELEASING.md`.
  - The arm64 runner has 2 vCPU in private repos, so the C++ core plus the Rust build plus tests may take ~15 min. Keep `timeout-minutes: 45`.
- **VALIDATE**:
  - `actionlint .github/workflows/agent.yml`.
  - After a push to `main`: `docker buildx imagetools inspect ghcr.io/big-duck-networks/pingduck-agent:edge` lists `linux/amd64` and `linux/arm64`.
  - `cosign verify ghcr.io/big-duck-networks/pingduck-agent:edge --certificate-identity-regexp 'https://github.com/Big-Duck-Networks/pingduck/' --certificate-oidc-issuer https://token.actions.githubusercontent.com` passes.
  - After the user makes the package public: `docker pull` works without logging in.
- **SATISFIES**: AC 2, AC 6.

### Task 14: CREATE `.github/workflows/release-agent.yml`

- **IMPLEMENT**:
  - **Trigger:** `workflow_dispatch` with no inputs. The version comes from `agent/Cargo.toml` at the selected ref, which must be `main`; fail otherwise.
  - **Job** (ubuntu-latest), `permissions: contents: write, packages: write, id-token: write`:
    1. Run `./.github/actions/release-guard` (Task 25) with `tag: agent-v<version>` and `workflow: agent.yml`.
    2. `docker buildx imagetools create -t …:<version> -t …:<major.minor> -t …:latest …:sha-${{ github.sha }}`. This re-tags the **same** image; nothing is rebuilt.
    3. `cosign sign --yes` on the digest. Re-signing is harmless, and it records the release.
    4. `git tag agent-v<version> ${{ github.sha }} && git push origin agent-v<version>`.
    5. `gh release create agent-v<version> --generate-notes --title "PingDuck Agent <version>"` (in this private repo, as a record).
- **GOTCHA**:
  - If `:sha-<sha>` doesn't exist (the `main` publish failed or was skipped), fail with "no tested image for this commit; push or re-run agent.yml".
  - `GITHUB_TOKEN` can push tags (no rulesets on Free).
  - **Rollback:** run with the previous tag's commit selected? No: releases only run from `main`. Document the manual rollback in `RELEASING.md`: `docker buildx imagetools create -t …:latest …:<previous version>`.
- **VALIDATE**: `actionlint`. Then a real run: `docker buildx imagetools inspect …:0.3.0` has the same digest as `…:sha-<sha>`.
- **SATISFIES**: AC 3, AC 6.

### Task 15: UPDATE `agent/Dockerfile` header and `compose.yaml` comments

- **IMPLEMENT**: In the Dockerfile header, say which tags exist: `:latest` is the latest release, `:X.Y.Z` is pinned, `:edge` is every `main` build. In `compose.yaml`, keep `:latest`.
- **VALIDATE**: Read-through.
- **SATISFIES**: AC 6.

### Task 16: UPDATE `pingduck_app/android/app/build.gradle.kts`: release signing

- **IMPLEMENT**:
  - Before `android {`, load the signing values from environment variables (CI) or `key.properties` (local), in this order:
    ```kotlin
    import java.util.Properties

    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun signing(name: String, env: String): String? = System.getenv(env) ?: keyProps.getProperty(name)
    ```
  - Inside `android {}`: `signingConfigs { create("release") { … } }` reading
    - `storeFile` ← `ANDROID_KEYSTORE_PATH` / `storeFile`
    - `storePassword` ← `ANDROID_KEYSTORE_PASSWORD` / `storePassword`
    - `keyAlias` ← `ANDROID_KEY_ALIAS` / `keyAlias`
    - `keyPassword` ← `ANDROID_KEY_PASSWORD` / `keyPassword`
  - In `buildTypes.release`: use `signingConfigs.getByName("release")` **if `storeFile` is set**, else fall back to debug, so `flutter run --release` still works on a dev machine without the key.
  - Remove the two TODO comments that this resolves.
- **PATTERN**: [Flutter: sign the app](https://docs.flutter.dev/deployment/android#sign-the-app), Kotlin DSL variant.
- **GOTCHA**:
  - The fallback to debug must **never** happen in CI: the Task 17 job checks the APK signature (`apksigner verify --print-certs`) and fails if it's the debug cert.
  - `rootProject.file("key.properties")` resolves to `pingduck_app/android/key.properties`, which is gitignored.
- **VALIDATE**:
  - Locally without the key: `cd pingduck_app && flutter build appbundle --release` still succeeds (debug-signed).
  - With a throwaway keystore and env vars set: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` shows the throwaway cert.
- **SATISFIES**: AC 4.

### Task 17: ADD the Android build and internal upload to `.github/workflows/app.yml`

- **IMPLEMENT**: Job `android`:
  - `if: push to main`; `needs: test`; ubuntu-latest; 40 min.
  - Steps:
    1. Checkout with `fetch-depth: 0` (the commit count needs full history).
    2. Java 17: `actions/setup-java` (temurin).
    3. Flutter 3.44.0.
    4. `dart run tools/build_number_gen.dart --git --github-output` from the repo root. It sets the pubspec to `<name>+<count>` and stamps `app_version.dart` with this commit; its outputs give the version. **Verify the output names first**: read the `--github-output` branch at `tools/build_number_gen.dart:70+`.
    5. Decode the keystore: `echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/upload.jks"` and export `ANDROID_KEYSTORE_PATH`.
    6. `flutter build appbundle --release`.
    7. Verify it isn't debug-signed: `keytool -printcert -jarfile app-release.aab | grep -q "CN=Android Debug" && exit 1`.
    8. `r0adkll/upload-google-play@v1` with `serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}`, `packageName: app.webcap.pingduck`, `releaseFiles: pingduck_app/build/app/outputs/bundle/release/app-release.aab`, `track: internal`, `status: completed`.
    9. Upload the AAB as an artifact (7 days).
  - Skip with a summary note when `ANDROID_KEYSTORE_BASE64` or `PLAY_SERVICE_ACCOUNT_JSON` is missing.
- **GOTCHA**:
  - The build compiles `core/` for 3 ABIs through the NDK on the runner. `ANDROID_NDK_LATEST_HOME` exists there, and Flutter picks its own `ndkVersion`, installing it via sdkmanager on demand. Allow 40 min the first time.
  - Never commit the stamped `pubspec.yaml`. It only changes in the workspace.
- **VALIDATE**: `actionlint`. After a push: a new build with versionCode = commit count appears in Play Console › Internal testing.
- **SATISFIES**: AC 2, AC 4, AC 5.

### Task 18: CREATE `.github/workflows/release-android.yml`

- **IMPLEMENT**:
  - **Trigger:** `workflow_dispatch` with input `rollout` (choice: `0.1`, `0.2`, `0.5`, `1.0`; default `0.1`).
  - **Steps:**
    1. Run the release guard (Task 25) with `tag: app-v<pubspec name>`, `workflow: app.yml`, `check_migrations: true`.
    2. Promote with fastlane: set up Ruby (`ruby/setup-ruby@v1`, `ruby-version: 3.3`), `gem install fastlane`, write the service account JSON to `$RUNNER_TEMP/play.json`, then:
       ```
       fastlane supply --package_name app.webcap.pingduck --json_key "$RUNNER_TEMP/play.json" \
         --track internal --track_promote_to production --rollout "$ROLLOUT" \
         --skip_upload_apk --skip_upload_aab --skip_upload_metadata --skip_upload_images --skip_upload_screenshots
       ```
    3. Tag `app-v<name>` at `github.sha` and push it.
    4. `gh release create app-v<name> --generate-notes` (private record).
- **GOTCHA**:
  - **"The tested build":** promotion moves whatever is *latest* on internal testing. That's the build from the most recent `main` push, which is `github.sha` only if nothing landed since. The guard must check that the internal track's top versionCode equals `git rev-list --count ${{ github.sha }}`; fail with "main moved on; release the newer commit or wait". Read it with `fastlane run google_play_track_version_codes track:internal …`.
  - The first production release also needs the store listing, content rating and data-safety forms done in Play Console. Fastlane fails with a clear API error otherwise; `RELEASING.md` says so.
- **VALIDATE**: `actionlint`. A real run shows the production track at 10% in Play Console.
- **SATISFIES**: AC 3.

### Task 19: CREATE `.github/workflows/android-rollout.yml`

- **IMPLEMENT**:
  - **Trigger:** `workflow_dispatch` with input `action` (choice: `0.2`, `0.5`, `1.0`, `halt`).
  - For a fraction: `fastlane supply --track production --rollout <fraction> --skip_upload_*`. For `halt`: `fastlane supply --track production --release_status halted --skip_upload_*`.
- **VALIDATE**: `actionlint`.
- **SATISFIES**: AC 3.

### Task 20: CREATE `.github/workflows/deploy-database.yml`

- **IMPLEMENT**:
  - **Trigger:** `workflow_dispatch`, `main` only (fail otherwise).
  - **Steps:**
    1. `supabase/setup-cli@v1`.
    2. `supabase link --project-ref "$SUPABASE_PROJECT_REF"`.
    3. `supabase db push --dry-run` into the summary.
    4. `supabase db push`.
    5. `supabase migration list` into the summary.
  - Env: `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` from secrets.
  - `concurrency: { group: deploy-database, cancel-in-progress: false }`.
- **GOTCHA**:
  - Must not run before Task 2: an empty history would make `db push` re-run every migration. **Guard:** if the dry-run lists `20261006120000` (the initial schema) as pending, stop with "migration history not repaired; see docs/RELEASING.md".
  - `db push` applies migrations in order, one transaction each. If one fails, the earlier ones stay applied. `RELEASING.md` explains fixing forward with a new migration.
- **VALIDATE**: `actionlint`. A real run with nothing pending prints "Remote database is up to date".
- **SATISFIES**: AC 7.

### Task 21: UPDATE `.github/workflows/database.yml`: the expand/contract reminder

- **IMPLEMENT**: In the `pending` job, when migrations are pending, add to the summary: "Deploy with **Deploy database** before releasing an app build that needs them. Migrations must keep older app builds working."
- **VALIDATE**: `actionlint`.
- **SATISFIES**: AC 7.

### Task 22: CREATE `.github/workflows/windows.yml` (and remove `windows-release.yml`, Task 11)

- **IMPLEMENT**:
  - **Triggers:** `push` to `main` with paths `["pingduck_app/**", "agent/**", "core/**", "packages/**", "installer/**", ".github/workflows/windows.yml"]`; plus `workflow_dispatch`, with `workflow_call` so `release-windows.yml` can reuse it, with inputs `version` (string) and `sign` (boolean).
  - **Job `installer`** (windows-latest, 60 min):
    1. Checkout with `fetch-depth: 0`, then Flutter 3.44.0.
    2. `dart run tools/build_number_gen.dart --git` (About shows the right build and commit).
    3. In `agent/`: `cargo build --release --locked -p pingduck-agent`. No `cargo test`; `agent.yml` covers it.
    4. In `pingduck_app/`: `flutter build windows --release`. No `flutter test`; `app.yml` covers it.
    5. If `inputs.sign` and `AZURE_CLIENT_ID` is set: `azure/login@v2` (OIDC) and `azure/artifact-signing-action` on `PingDuck.exe` and `pingduck-agent.exe` **before** Inno packs them.
    6. `choco install innosetup -y --no-progress`, then ISCC with `/DAppVersion=<version or pubspec name>`.
    7. If signing: sign `PingDuckSetup.exe` too.
    8. Upload the artifact `PingDuckSetup-<version>` (`retention-days: 7`).
  - `permissions: contents: read, id-token: write` (OIDC for Azure).
- **PATTERN**: `windows-release.yml:21-72`.
- **GOTCHA**:
  - Windows minutes are 2×; one build is ~15 min, so ~30 billed. The path filter keeps docs-only pushes from running it, and `concurrency` cancels superseded `main` builds.
  - The artifact-signing action needs .NET 8, which `windows-latest` has.
  - **Verify the action's current inputs at implementation time** (the rename from `trusted-signing-action` changed `trusted-signing-account-name` to `signing-account-name`).
- **VALIDATE**: `actionlint`. A run on `main` produces a downloadable `PingDuckSetup-1.0.0` artifact that installs on a clean Windows VM.
- **SATISFIES**: AC 2, AC 9.

### Task 23: CREATE `.github/workflows/release-windows.yml`

- **IMPLEMENT**:
  - **Trigger:** `workflow_dispatch`.
  - **Job `guard`:** release guard with `tag: desktop-v<pubspec name>`, `workflow: windows.yml`, `check_migrations: true`. It also requires that `agent.yml` and `app.yml` passed on this commit, since the installer contains both.
  - **Job `build`:** `uses: ./.github/workflows/windows.yml` with `version: <name>`, `sign: true`; `secrets: inherit`.
  - **Job `publish`:**
    - Download the artifact.
    - Tag `desktop-v<name>` here and push it.
    - Create a release in the **public** repo with the `RELEASES_TOKEN` secret:
      `gh release create desktop-v<name> PingDuckSetup.exe -R Big-Duck-Networks/pingduck-releases --title "PingDuck for Windows <name>" --notes "<notes>"`.
      The notes say whether the installer is signed.
- **GOTCHA**:
  - This rebuilds at release time instead of promoting the `main` artifact, because signing happens at release and artifacts expire after 7 days. Same commit, same toolchain pins; acceptable. Record it in the NOTES.
  - **The stable public URL** is `https://github.com/Big-Duck-Networks/pingduck-releases/releases/latest/download/PingDuckSetup.exe`. `latest` is the newest non-prerelease.
- **VALIDATE**: `actionlint`. A real run, then `curl -sIL <stable URL>` returns 200 with no auth.
- **SATISFIES**: AC 3, AC 9, AC 10.

### Task 24: UPDATE `pingduck_website/src/lib/site.ts` (prepared, not enabled)

- **IMPLEMENT**:
  - Next to `agentWindowsUrl: null`, add a comment with the stable URL from Task 23.
  - **Do not set it.** `/agent` stays unlinked until launch (user constraint; ROADMAP Phase 8 TODO). Update that TODO row to name `pingduck-releases`.
- **VALIDATE**: `npm run build` in `pingduck_website`.
- **SATISFIES**: AC 10.

### Task 25: CREATE `.github/actions/release-guard/action.yml`

- **IMPLEMENT**: A composite action.
  - **Inputs:** `tag`, `workflows` (comma-separated workflow file names whose latest run on this SHA must have concluded `success`), `check_migrations` (bool).
  - **Steps:**
    1. Fail unless `github.ref == refs/heads/main`.
    2. Fail if `git ls-remote --tags origin "refs/tags/${tag}"` returns anything (version already released; bump the version name).
    3. For each workflow: `gh run list --workflow "$w" --commit "$GITHUB_SHA" --json conclusion,status --limit 1`. Fail unless `status == completed && conclusion == success`. Use `GH_TOKEN: ${{ github.token }}`.
    4. If `check_migrations`: `supabase link`, then `supabase db push --dry-run`. Fail if anything is pending ("deploy the database first").
    5. Write a summary table of all of the above.
- **GOTCHA**: A workflow skipped by its path filter has **no run** on that SHA. Treat "no run" as "look at the newest run on an ancestor commit": `gh run list --workflow w --branch main --status success --limit 1`, then check that commit is an ancestor with `git merge-base --is-ancestor`. That needs `fetch-depth: 0` in the caller.
- **VALIDATE**: `actionlint` on the callers. Run `release-agent.yml` once with the version already tagged: it must stop at step 2.
- **SATISFIES**: AC 3, AC 11.

### Task 26: CREATE `docs/RELEASING.md`

- **IMPLEMENT**: Sections:
  1. **How it works**: the three stages diagram.
  2. **Releasing each component**:
     - Agent: bump the `Cargo.toml` version in a PR or commit, merge, wait for green, press Release agent.
     - Android: bump the pubspec name, merge, wait for internal testing, smoke-test from the Play internal link, press Release Android (10%), then Android rollout to 50% and 100% over a few days, watching Play vitals.
     - Windows: bump, merge, press Release Windows.
     - Database: Deploy database before any app release that needs it.
  3. **Rollback**:
     - agent: re-point `:latest`;
     - Android: halt the rollout and ship a fix (Play has no true rollback);
     - Windows: delete the bad release in `pingduck-releases` so `latest` falls back;
     - database: a fix-forward migration.
  4. **Rules**: expand/contract migrations; never build releases from branches; build numbers are CI-owned.
  5. **One-time setup checklist**: Task 1 and 2 items, with how to rotate each secret.
  6. **Minutes budget**: the table from NOTES.
  7. **Free-plan limits and what an upgrade unlocks.**
- **VALIDATE**: Read-through; every workflow file named in it exists.
- **SATISFIES**: AC 13.

### Task 27: UPDATE `docs/ROADMAP.md`

- **IMPLEMENT**:
  - Phase 8 **Beta** row: the agent image publishes `:edge` per `main` push and `:latest` per release; Android internal testing per `main` push.
  - **TODO at launch** row: the Windows URL is `pingduck-releases`; make the GHCR package public.
  - Add a row **CI/CD** ✅ that links this plan and `docs/RELEASING.md`.
  - Phase 1's CI row: `core.yml` now covers core only, with `agent.yml` beside it.
- **VALIDATE**: `grep -n "RELEASING.md" docs/ROADMAP.md`.
- **SATISFIES**: AC 13.

### Task 28: CREATE `Pingduck.app/.github/workflows/ci.yml` and `dependabot.yml` (website repo)

- **IMPLEMENT**:
  - `ci.yml`: `pull_request` and `push` to `main`. `actions/setup-node@v4` (`node-version: 20`, `cache: npm`), then `npm ci`, `npm run lint`, `npm run build`.
  - `dependabot.yml`: `npm` and `github-actions`, weekly, grouped.
- **GOTCHA**: `AGENTS.md` warns that Next 16 differs from training data. The workflow only runs the repo's own scripts, so nothing Next-specific is needed.
- **VALIDATE**: `actionlint`; locally `npm run lint && npm run build`.
- **SATISFIES**: AC 1, AC 8.

### Task 29: CREATE `Pingduck.app/.github/workflows/deploy.yml`

- **IMPLEMENT**:
  - **Triggers:** `workflow_run` of `ci` on `main` with `conclusion == success`, plus `workflow_dispatch`.
  - `environment: production` (public repo, so add yourself as a required reviewer if you want an approval click; default **none**, auto-deploy).
  - `concurrency: { group: deploy, cancel-in-progress: false }`.
  - **Steps:**
    1. `appleboy/ssh-action@v1` with `host`, `username`, `key` and `fingerprint` from environment secrets, and `script: cd /var/www/pingduck_website && ./scripts/restart-hetzner.sh --pull`.
    2. Health check: `curl -fsS -o /dev/null -w '%{http_code}' https://pingduck.app` retried 10× at 6 s, failing unless 200.
- **PATTERN**: `scripts/rebuild.ps1`, the same remote command and health check.
- **GOTCHA**:
  - `restart-hetzner.sh --pull` does `git reset --hard origin/<branch>` on the server, so the server must be on `main`.
  - `workflow_run` runs the deploy workflow's definition from the default branch. Check that it reads `github.event.workflow_run.head_sha` and deploys only when that equals `main`'s head, so it never deploys an old commit.
  - Keep `npm run rebuild` as a manual fallback.
- **VALIDATE**: `actionlint`. A real run: the job succeeds, and `curl -sI https://pingduck.app` shows the new build (the `last-modified` or `x-nextjs` headers change).
- **SATISFIES**: AC 8.

### Task 30: (after an upgrade to GitHub Team, or making `pingduck` public) ADD branch protection and environments

- **IMPLEMENT**:
  - Branch protection on `main` requiring the `ci` jobs from `core.yml`, `agent.yml` and `app.yml`, plus `database.yml`'s `test`.
  - Create environments `production-android`, `production-agent`, `production-windows` and `production-database` holding the release secrets (moved out of repo secrets), with deployment-branch rule `main`.
  - If the repo is public: add required reviewers to those environments, and drop the guard's "main is green" step in favour of the branch rule.
- **VALIDATE**: `gh api repos/Big-Duck-Networks/pingduck/branches/main/protection` returns 200.
- **SATISFIES**: AC 11.

---

## TESTING STRATEGY

CI configuration is tested in three layers:

1. **Static:** `actionlint` on every workflow, which catches expression, `needs` and context errors, and runs shellcheck on `run:` blocks.
2. **Dry runs:** each publishing job skips cleanly without its secrets. Run every workflow once with `workflow_dispatch` **before** adding secrets and confirm it skips with a note, not a failure.
3. **Real runs**, in a fixed order so a failure is cheap:
   1. `database.yml`
   2. `app.yml`
   3. `agent.yml`, on a PR (checks only)
   4. `agent.yml` on `main` (publishes `:edge`)
   5. `release-agent.yml`
   6. `app.yml` on `main` with secrets (internal track)
   7. `release-android.yml` at 10%
   8. `windows.yml`
   9. `release-windows.yml`
   10. the website `ci` and `deploy`

### Unit tests

No new product code. The existing suites become CI gates: `flutter test` (84), `cargo test` (33 + 5), `ctest`, and `schema_test.sql`. The new code that needs a test is the Android signing fallback (Task 16), checked by building with and without the key.

### Integration tests

- The agent container health check in CI (Task 5).
- The release guard's refusals: an already-released tag, a red workflow on the SHA, pending migrations. Exercise each once by hand (Task 25).

### Edge cases

| Case | Expected |
|---|---|
| A PR from a fork | Gets no secrets; publishing jobs are gated on `push` to `main`, so they never run. |
| A docs-only push to `main` | Triggers no build workflows (path filters). The guard's ancestor logic still finds the last green run. |
| Two quick `main` pushes | Check workflows cancel the older run. Publish jobs (`cancel-in-progress: false`) finish in order. `:edge` ends on the newest. |
| Release pressed while `main` moved on (Android) | The guard compares the internal track's versionCode with the commit count and refuses. |
| `db push` with unrepaired history | `deploy-database.yml` sees the initial schema pending and stops. |
| Missing Azure secrets | The Windows release ships unsigned and says so in the release notes. |
| Play API refusing the first production release (forms incomplete) | Fastlane error surfaced in the job; `RELEASING.md` explains it. |

---

## VALIDATION COMMANDS

### Level 1: Syntax and style

```
actionlint .github/workflows/*.yml
cd ../pingduck_website && actionlint .github/workflows/*.yml
```

(Composite actions aren't linted by actionlint; review `release-guard/action.yml` by hand.)

### Level 2: Unit tests (what CI runs, run locally first)

```
cd pingduck_app && flutter analyze && flutter test
cd agent && cargo clippy --workspace --all-targets --locked -- -D warnings && cargo test --workspace --locked
ssh pingduck-vm 'cd <checkout> && sh supabase/tests/run_tests.sh'
cd ../pingduck_website && npm run lint && npm run build
```

### Level 3: Integration (on GitHub)

```
gh workflow run database.yml && gh run watch
gh workflow run app.yml && gh run watch
gh workflow run agent.yml && gh run watch
docker buildx imagetools inspect ghcr.io/big-duck-networks/pingduck-agent:edge
cosign verify ghcr.io/big-duck-networks/pingduck-agent:edge \
  --certificate-identity-regexp 'https://github.com/Big-Duck-Networks/pingduck/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Level 4: Manual validation

- Play Console: Internal testing shows the build with versionCode = commit count; installing it from the internal link opens the app and About shows the right build and commit.
- `curl -sIL https://github.com/Big-Duck-Networks/pingduck-releases/releases/latest/download/PingDuckSetup.exe` returns 200 with no auth; installing on a clean Windows VM works (signed: no SmartScreen "unknown publisher").
- `docker pull ghcr.io/big-duck-networks/pingduck-agent:latest` with no login, on amd64 and on a Pi (arm64).
- Website: a push to `main` of `Pingduck.app` is live on `https://pingduck.app` within ~5 min.

### Level 5: Additional

- `gh api repos/Big-Duck-Networks/pingduck/actions/cache/usage` and the org billing page after a week: the minutes are inside the budget (see NOTES).

---

## ACCEPTANCE CRITERIA

1. [ ] Every PR and push runs the checks for what it touches: core (`core.yml`), agent (`agent.yml`), app (`app.yml`), database (`database.yml`), website (`ci.yml`); iOS compiles weekly.
2. [ ] Every push to `main` ships test builds without human steps:
   - the agent `:edge` and `:sha-<sha>` (amd64 + arm64);
   - Android on Play internal testing;
   - a Windows installer artifact;
   - the website live.
3. [ ] Releases are one button per component. They refuse already-released versions, red commits and pending migrations, and they promote the tested build: the same image digest for the agent, the same internal-track build for Android.
4. [ ] Android release builds are signed with the upload key in CI, never the debug key; local `flutter run --release` still works without the key.
5. [ ] Build numbers come from CI (commit count); nobody runs `build_number_gen.dart` by hand, and About shows the right build and commit on every CI build.
6. [ ] The agent image is public, multi-arch, signed with cosign (verifiable), carries SBOM and provenance, and `:latest` only moves on releases.
7. [ ] Migrations are tested on every PR, pending ones are reported on `main`, and production is migrated only by Deploy database. Migration history is repaired first.
8. [ ] The website deploys from GitHub on every green `main` push with a health check; `npm run rebuild` remains as a fallback.
9. [ ] `windows-release.yml` is gone; `windows.yml` and `release-windows.yml` replace it.
10. [ ] The Windows installer has a stable public URL that works without auth (`/agent` stays unlinked until launch).
11. [ ] Each workflow has a `ci` aggregate job; the plan documents branch protection for after an upgrade (Task 30).
12. [ ] Dependabot opens grouped weekly PRs for Cargo, pub, npm and GitHub Actions.
13. [ ] `docs/RELEASING.md` exists, and the roadmap reflects the new system.
14. [ ] The monthly Actions minutes stay under 2,000 for a normal month (NOTES budget).

---

## COMPLETION CHECKLIST

- [ ] All tasks completed in order (Task 30 only after an upgrade)
- [ ] Each task's validation passed immediately
- [ ] `actionlint` clean on both repos
- [ ] Every workflow ran once for real and its result is recorded in AMENDMENTS
- [ ] No secret value appears in any file, log or commit
- [ ] Acceptance criteria all met
- [ ] Reviewed with the user before the first push to `main` (it triggers publishing)

---

## OPEN QUESTIONS / ASSUMPTIONS

The user chose the defaults, so these are recorded as assumptions:

- **Assumed:** one Supabase project, so test builds use production data. Confirm before the beta has outside testers.
- **Assumed:** release approval = whoever presses Run workflow (Free plan: no required reviewers on private repos). If the org upgrades to Team, do Task 30; if `pingduck` goes public (open source), required reviewers and unlimited minutes come free, which is worth considering for an agent people run on their home network.
- **Assumed:** the Windows installer is published to a new **public** `pingduck-releases` repo.
- **Assumed:** Azure Artifact Signing as a US organization (Big Duck Networks). If it isn't incorporated, apply as a US individual, also eligible. The Windows pipeline ships unsigned until then.
- **Assumed:** no Apple Developer account yet, so iOS is compile-only (Task 8).
- **Open (Task 12):** is the agent Apache-2.0 or proprietary? The Dockerfile and Cargo.toml disagree.
- **Open (Task 2):** was `20261011120000_agent_instructions_windows.sql` applied to production? It decides the repair list.
- **Assumed:** Play App Signing is on, so the upload key can be reset through Play support if lost.

## NOTES (open canvas)

### Minutes budget (GitHub Free: 2,000 a month; Windows 2×, macOS 10×)

| Workflow | When | Real min | Billed min |
|---|---|---|---|
| core.yml (Linux jobs) | core change | ~25 total | 25 |
| core.yml (Windows) | core change | ~6 | 12 |
| core.yml (macOS + iOS) | core push to main, weekly | ~12 | **120** |
| agent.yml checks | agent/core change | Linux ~10, Windows ~8 | 26 |
| agent.yml images | main push (agent/core) | 2 × ~15 | 30 |
| app.yml test | app change | ~4 | 4 |
| app.yml android | main push (app) | ~15 | 15 |
| windows.yml | main push (app/agent/core) | ~15 | **30** |
| database.yml | supabase change | ~2 | 2 |
| ios.yml | weekly | ~18 | **180 / week ≈ 720 / month** |

**ios.yml weekly is the biggest cost (~720 a month).** Run it **every other week** (cron on days 1-7 and 15-21 of the month) or **by hand only** until the Apple lane exists. **Default: by hand plus monthly**, about 180 a month.

Rough month (20 app pushes to `main`, 8 agent/core, 2 core): app 20×(4+15+30) = 980, agent 8×56 = 450, core 2×157 = 315, iOS 180, so **~1,900**. That's tight. Levers, in order:

1. `windows.yml` on `main` only when `installer/**` or a release-relevant path changes, else by hand.
2. Batch `main` pushes (PRs merged together).
3. GitHub Team ($4/month, 3,000 minutes).
4. Making the repo public (unlimited).

Implement lever 1 if the first two weeks' usage trends over budget. Record actuals in AMENDMENTS.

### Why not Release Please / semantic-release

Considered for automatic versions and changelogs from conventional commits. Rejected for now: this repo's commit messages aren't conventional, and three components with prefixed tags need its monorepo config. `gh release create --generate-notes` gives notes from PRs and commits for free. Revisit if releases get frequent.

### Why rebuild Windows at release instead of promoting

Signing happens at release (it needs the Azure OIDC login), and artifacts expire after 7 days to stay inside the 500 MB Free artifact storage. Same commit, same pinned Flutter and Rust; the risk is low. The agent image and the Android AAB *are* promoted unchanged, which is where "build once" matters most: users run them unattended.

### Why `run_tests.sh` and not `supabase start` in CI

`run_tests.sh` already applies the migrations to plain `postgres:15` with `supabase_stub.sql`, in ~1 min, and it's the suite used so far. `supabase start` would test against the real Supabase images (`auth`, `pg_net`, `vault`, `pg_cron` versions) but takes 3-5 min and pulls ~2 GB. Production parity comes from the `db push --dry-run` against the real project on every `main` push. If a migration ever passes the stub but fails on Supabase, add a `supabase start` job then.

### Sequencing risk

The first push of tonight's 4 unpushed commits runs the **old** `core.yml`, which publishes `:latest` to GHCR (QEMU arm64, may time out). To avoid shipping `:latest` from the old pipeline, push Phase 1 + 2 (Tasks 4-15) together with, or before, those commits. In practice: implement Phases 1-2 locally, commit, then push everything at once.

## AMENDMENTS

- 2026-10-11: **`pingduck` goes public** (user decision). Where this entry conflicts with a task above, this entry wins.
  - **Done before going public:**
    - licences: `LICENSE.md` (FSL-1.1-ALv2) at the root, Apache-2.0 in `agent/LICENSE` and `core/LICENSE`, `agent/Cargo.toml` set to `Apache-2.0`, README "License" section. **Task 12's licence question is answered.**
    - the two real LAN MACs replaced in tests;
    - history rewritten with `git filter-repo`: real MACs gone, author email set to `1407156+Solox312@users.noreply.github.com`. The repo-local `user.email` is set to the same address.
  - **Platform limits that no longer apply:**
    - unlimited standard-runner minutes, including Windows and macOS. **Drop the minutes budget**, AC 14 and lever 1. `ios.yml` runs weekly and on PRs labelled `apple`.
    - `ubuntu-24.04-arm` has 4 vCPU.
    - branch protection and rulesets, environments with environment secrets, deployment-branch rules and **required reviewers** are all available.
  - **Changes to tasks:**
    - **Task 1.5**: no `pingduck-releases` repo and no `RELEASES_TOKEN`. Windows installers are released in `pingduck` itself. The stable URL is `https://github.com/Big-Duck-Networks/pingduck/releases/latest/download/PingDuckSetup.exe`, which is what `windows-release.yml` already documented. Tasks 23 and 24 use it. Agent and app release notes in the same repo become public changelogs.
    - **Task 1**: store release secrets as **environment** secrets.
      - `production-android`: `ANDROID_*`, `PLAY_*`
      - `production-database`: `SUPABASE_*`
      - `production-windows`: `AZURE_*`
      - Give each environment the user as **required reviewer** and a deployment-branch rule of `main`.
      - The Android internal-track upload on `main` (Task 17) uses environment `internal-android` with the same `ANDROID_*`/`PLAY_*` secrets and **no** reviewer.
    - **Task 30 is no longer deferred.** Do it right after Phase 1: a ruleset on `main` requiring the `ci` jobs and `database.yml`'s `test`, PRs required, force-push blocked.
    - Keep the release guard's tag and migration checks. Its "main is green" check becomes a backstop to the ruleset.
    - **Task 13**: add `actions/attest-build-provenance` (free for public repos) on the image digest, besides cosign. Users can then check with `gh attestation verify oci://ghcr.io/big-duck-networks/pingduck-agent:latest -R Big-Duck-Networks/pingduck`.
    - **Task 22/23**: also attest the installer and both exes (`actions/attest-build-provenance` with `subject-path`).
  - **New tasks (public-repo hygiene):**
    - **Task 0a**: Settings › Actions › "Require approval for all external contributors" before workflows run on their PRs.
    - **Task 0b**: enable secret scanning **with push protection**, Dependabot alerts and private vulnerability reporting.
    - **Task 0c**: add `SECURITY.md`: report to `support@pingduck.app` or through GitHub private reporting; the agent is in scope.
    - **Task 0d**: CodeQL (`codeql.yml`, default setup is fine) for C/C++, Rust and GitHub Actions. Dart isn't supported.
    - **Task 0e**: pin every third-party action to a full commit SHA, with the version in a comment; Dependabot updates SHA pins. Never use `pull_request_target` with a checkout of PR code.
    - **Task 0f**: `CODEOWNERS` with `* @Solox312`.
  - **Order of operations:**
    1. Force-push the rewritten history. All hashes changed: `main` is `10763b4`, `dev` is `815aeca`.
    2. Do Tasks 0a, 0b and 0f.
    3. Flip the repo to public.
    4. Continue with Phase 1.

    The GitHub copy still holds the old commits until the force-push. Unreferenced objects on GitHub can stay reachable by direct SHA for a while. With no forks or PRs that risk is small; for certainty, ask GitHub Support to purge cached views after the push, or delete and recreate the repo before pushing.
