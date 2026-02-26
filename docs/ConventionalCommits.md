# Conventional Commits Guide

This guide explains the Conventional Commits specification and how `Update-PSModuleVersion` uses
commit messages to determine automatic semantic version bumps.

## What Are Conventional Commits

Conventional Commits is a lightweight specification for commit messages that makes the meaning
of each commit machine-readable. By following a simple format, tools can analyze commit history
to determine the appropriate version bump, generate changelogs, and communicate intent clearly
to other developers.

Specification: https://www.conventionalcommits.org/en/v1.0.0/

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Every line has a defined purpose:

- **type** — A short keyword that categorizes the change (see the table below).
- **scope** — An optional noun in parentheses that names the part of the codebase affected.
- **description** — A concise, imperative-mood summary of the change in lowercase.
- **body** — Optional extended explanation. Can include `BREAKING CHANGE:` footer lines.
- **footer** — One or more trailers in the format `Token: value` or `Token #value`. The
  `BREAKING CHANGE:` footer triggers a major version bump.

### Examples of well-formed commit messages

```
feat(auth): add OAuth2 login flow
```

```
fix(parser): handle empty input strings gracefully
```

```
refactor: extract helper function from Build-PSModule
```

```
feat!: remove -LegacyMode parameter from Build-PSModule

BREAKING CHANGE: The -LegacyMode switch has been removed. Update callers
to use -OutputFormat instead.
```

```
fix(manifest): correct FunctionsToExport regex

Resolves an edge case where function names containing digits in the first
character were not matched.
```

## Commit Types and Their Meaning

| Type | Description | Version bump |
|---|---|---|
| `feat` | A new feature visible to the user | Minor |
| `fix` | A bug fix | Patch |
| `docs` | Documentation changes only | None |
| `style` | Formatting, whitespace — no logic change | None |
| `refactor` | Code restructuring with no feature or fix | None |
| `perf` | A change that improves performance | None |
| `test` | Adding or correcting tests | None |
| `build` | Changes to the build system or external dependencies | None |
| `ci` | Changes to CI/CD configuration files and scripts | None |
| `chore` | Routine tasks, dependency updates, etc. | None |
| `revert` | Reverts a previous commit | None |

## Which Types Trigger Version Bumps

`Update-PSModuleVersion` inspects the subject line of each commit using the following rules
applied in priority order (highest wins):

### Major bump — breaking change

A commit triggers a Major bump when either:

1. The type is followed immediately by `!` before the colon:

   ```
   feat!: redesign module manifest update logic
   fix!: change return type of Build-PSModule
   ```

2. The subject line itself contains the text `BREAKING CHANGE` (note: because `git log --oneline`
   shows only the subject, breaking changes documented only in the body/footer are not detected
   automatically in this mode — use the `!` notation to ensure detection):

   ```
   feat: new API BREAKING CHANGE in output object
   ```

A Major bump resets Minor and Patch to zero: `1.3.2` becomes `2.0.0`.

### Minor bump — new feature

A commit triggers a Minor bump when the type is `feat` (without `!`):

```
feat: add -Clean parameter to Build-PSModule
feat(split): support classes with generic type constraints
```

A Minor bump resets Patch to zero: `1.3.2` becomes `1.4.0`.

### Patch bump — bug fix

A commit triggers a Patch bump when the type is `fix` (without `!`):

```
fix: prevent crash when Enums directory is missing
fix(manifest): handle version strings with two components
```

A Patch bump increments only the last component: `1.3.2` becomes `1.3.3`.

### No bump — all other types

Commits with types `docs`, `chore`, `refactor`, `test`, `style`, `ci`, `perf`, `build`, and
any non-standard type do not trigger a version bump. Merge commits are also excluded (the
function passes `--no-merges` to `git log`).

## BREAKING CHANGE in the Footer

The Conventional Commits specification places breaking change notices in the commit footer:

```
refactor!: rewrite Initialize-PSModule output object

The ScaffoldResult object no longer includes a FilesCreated property.
Callers that inspect FilesCreated must be updated.

BREAKING CHANGE: ScaffoldResult.FilesCreated removed.
```

Because `Update-PSModuleVersion` uses `git log --oneline`, only the subject line is visible to
the parser. The footer-only form of `BREAKING CHANGE` is therefore not detected unless the
subject also contains `BREAKING CHANGE` or uses the `!` notation.

**Recommendation:** Always use the `!` notation on the type when a commit introduces a breaking
change. This guarantees correct detection regardless of the log format:

```
refactor!: rewrite Initialize-PSModule output object
```

## Bang Notation (feat!:)

The `!` suffix can be applied to any type, not just `feat`. All of the following trigger a
Major bump:

```
feat!: ...
fix!: ...
refactor!: ...
chore!: ...
```

This is useful when a routine maintenance change (such as a `chore` or `refactor`) happens to
introduce an incompatible change.

## How Update-PSModuleVersion Uses Commits

The analysis follows these steps:

1. Find the most recent Git tag matching `<TagPrefix>*` (default: `v*`) using
   `git describe --tags --abbrev=0`.
2. Run `git log <tag>..HEAD --oneline --no-merges` to get all commits since that tag.
   If no tag exists, all commits are analyzed.
3. Strip the short hash prefix from each line (`abc1234 feat: add thing` becomes
   `feat: add thing`).
4. Match each subject line against three patterns in priority order:
   - Breaking: `^[a-z]+(\(.+\))?!:` or subject contains `BREAKING CHANGE`
   - Minor: `^feat(\(.+\))?:`
   - Patch: `^fix(\(.+\))?:`
5. The highest bump type found across all commits is used.
6. The new version is computed and written to the manifest.

## Practical Workflow

Use this commit discipline consistently and version management becomes fully automatic:

```powershell
# Day-to-day development
git commit -m "feat(build): add -OutputFormat parameter"
git commit -m "fix: handle empty Private directory"
git commit -m "test: add unit tests for Merge-SourceFiles"
git commit -m "docs: improve Build-PSModule examples"

# When ready to release
Update-PSModuleVersion -Path .\MyModule -Tag -Verbose
# Detects feat and fix commits => Minor bump (e.g. 0.1.0 -> 0.2.0)
# Creates tag v0.2.0
git push origin v0.2.0
```

For a patch-only release:

```powershell
git commit -m "fix(parser): handle null manifest gracefully"
Update-PSModuleVersion -Path .\MyModule -Tag
# 0.2.0 -> 0.2.1, tag v0.2.1
```

To force a specific bump regardless of commit content:

```powershell
Update-PSModuleVersion -Path .\MyModule -BumpType Major -Tag
# 0.2.1 -> 1.0.0, tag v1.0.0
```
