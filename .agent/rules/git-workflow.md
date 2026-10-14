---
trigger: always_on
---

# Git workflow

`main` is the only long-lived branch. There is no `dev` branch; don't create one,
branch from it, or open PRs against it.

## Every change

1. Start from an up-to-date `main`:
   `git checkout main && git pull`
2. Create a branch named for the change:
   - `feat/<short-name>` for new behavior
   - `fix/<short-name>` for bugs
   - `docs/<short-name>` for docs and the roadmap
   - `ci/<short-name>` for workflows and build tooling
   - `chore/<short-name>` for everything else
3. Commit with Conventional Commits and a scope:
   `feat(app): …`, `fix(inspector): …`, `feat(agent,db): …`, `docs(roadmap): …`, `ci: …`.
   The subject says what changed in plain words, in lowercase, without a trailing period.
4. Push the branch and open a PR **against `main`**:
   `git push -u origin <branch>` then `gh pr create --base main`.
   Fill in `.github/pull_request_template.md`: what and why, and the checklist.
5. Wait for CI. `main` requires `core ci`, `agent ci`, `app ci`, `database ci`
   and `CodeQL` to pass.
6. Merge only when the user says to. Use a merge commit, not squash or rebase,
   and delete the branch afterward:
   `gh pr merge <n> --merge --delete-branch`.

Never commit or push directly to `main`. It's protected.

## Before pushing

Run the checks for whatever you touched:

- App (`pingduck_app`): `flutter analyze` and `flutter test`
- Core (`core`): build and run the CTest suite
- Agent (`agent`): `cargo test` and `cargo clippy`
- Database (`supabase`): add new migrations as new files and never edit merged
  ones. Keep older app builds working: expand now, contract in a later release
  (see `docs/RELEASING.md`). Update `supabase/tests/schema_test.sql` to match.

## Stacked PRs

When one PR depends on another, base the second on the first's branch. Merge
them in order. Before merging the lower PR, retarget the next one to `main`
(`gh pr edit <next> --base main`). If you delete a base branch while a PR
still points at it, GitHub closes that PR instead of retargeting it.

## Don't

- Don't hand-edit version or build numbers in `pubspec.yaml` or `app_version.dart`.
  The build number is the git commit count, stamped by `tools/build.ps1` and CI.
- Don't upload to Google Play or deploy the database from a branch. CI builds
  the signed AAB on `main`, and the user uploads it and runs the
  Deploy database workflow by hand.
- Don't commit secrets, tokens, real MAC addresses or personal network details.
