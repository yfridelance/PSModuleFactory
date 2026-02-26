# Update-PSModuleVersion

## Synopsis

Bumps the `ModuleVersion` in a module manifest based on Conventional Commits analysis or an
explicit bump type.

## Description

`Update-PSModuleVersion` automates semantic versioning for PowerShell modules. It reads the
current `ModuleVersion` from the `.psd1` manifest, analyzes Git commit messages since the last
matching version tag, and determines the appropriate version bump — Major, Minor, or Patch —
according to the Conventional Commits specification.

The highest bump type found in the commit range wins. If commits contain both `fix:` and `feat:`
entries, the result is a Minor bump. If any commit contains `BREAKING CHANGE` in its body or
uses the bang notation (`feat!:`), the result is a Major bump regardless of other commit types.

When `-BumpType` is supplied explicitly, the commit analysis is still performed but the explicit
value overrides the detected result.

After computing the new version, the function updates the `ModuleVersion` field in the manifest
file in place. If `-Tag` is specified, a new Git tag is created in the format
`<TagPrefix><NewVersion>` (default: `v0.2.0`).

The function requires Git to be available on the system `PATH`. It supports `-WhatIf` through
`SupportsShouldProcess` — when `-WhatIf` is passed, the manifest is not modified and no tag is
created, but the function reports what it would do.

## Syntax

```
Update-PSModuleVersion
    [[-Path] <String>]
    [-BumpType <String>]
    [-Tag]
    [-TagPrefix <String>]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

## Parameters

### -Path

The root directory of the PowerShell module project. Must contain at least one `.psd1` manifest
file. If multiple manifests exist in the directory, the first one found is used.

- **Type:** `String`
- **Position:** 0 (positional)
- **Default:** Current working directory (`Get-Location`)
- **Required:** No
- **Accepts pipeline input:** No

### -BumpType

When specified, overrides the automatic Conventional Commits analysis. The new version is
computed from the current version using this bump type regardless of what the commit history
contains.

- **Type:** `String`
- **Position:** Named
- **Default:** None (automatic analysis is used)
- **Required:** No
- **Accepted values:** `Major`, `Minor`, `Patch`

### -Tag

When specified, creates a new Git tag after updating the manifest. The tag name is
`<TagPrefix><NewVersion>`. The tag is a lightweight tag (not annotated).

- **Type:** `Switch`
- **Position:** Named
- **Default:** Not set
- **Required:** No

### -TagPrefix

The prefix string prepended to the version number for both reading existing tags (to find the
baseline for commit analysis) and creating new tags.

- **Type:** `String`
- **Position:** Named
- **Default:** `'v'`
- **Required:** No

## Output

`[PSCustomObject]` with PSTypeName `YFridelance.PS.ModuleFactory.VersionResult`

| Property | Type | Description |
|---|---|---|
| `ModuleName` | `String` | Name of the module |
| `ManifestPath` | `String` | Full path to the `.psd1` file |
| `PreviousVersion` | `Version` | Version before the update |
| `NewVersion` | `Version` | Version after the update |
| `BumpType` | `String` | Effective bump type (`Major`, `Minor`, `Patch`, or `None`) |
| `CommitsAnalyzed` | `Int32` | Number of commits inspected |
| `TagCreated` | `String` | Name of the Git tag created, or `$null` if none |
| `IsWhatIf` | `Boolean` | `$true` when the run was in `-WhatIf` mode |
| `Success` | `Boolean` | `$true` if a version change was made; `$false` if no bump was detected |

## Examples

### Example 1: Automatic version bump from commit history

```powershell
Update-PSModuleVersion -Path 'C:\Projects\MyModule'
```

Analyzes all commits since the last Git tag matching `v*`. If a `feat:` commit is found, bumps
the minor version. Updates the manifest in place.

### Example 2: Force a specific bump type

```powershell
Update-PSModuleVersion -Path 'C:\Projects\MyModule' -BumpType Major
```

Ignores commit history and unconditionally increments the major version. Resets minor and patch
to zero (e.g., `1.2.3` becomes `2.0.0`).

### Example 3: Bump version and create a Git tag

```powershell
Update-PSModuleVersion -Path 'C:\Projects\MyModule' -Tag -Verbose
```

Analyzes commits, bumps the version in the manifest, and creates a tag such as `v0.2.0`. The
`-Verbose` switch prints the detected bump type and each commit message inspected.

### Example 4: Dry run — see what would happen

```powershell
Update-PSModuleVersion -Path 'C:\Projects\MyModule' -WhatIf
```

Runs the full analysis and reports the detected bump type and new version without modifying the
manifest or creating a tag. Use this to verify the result before applying the change.

## Conventional Commits Bump Rules

The function parses one-line Git log output (`git log --oneline --no-merges`). The short commit
hash prefix is stripped before pattern matching.

| Commit pattern | Example | Bump triggered |
|---|---|---|
| Type with `!` suffix | `feat!: remove legacy API` | Major |
| `BREAKING CHANGE` anywhere in subject | `fix: patch BREAKING CHANGE noted` | Major |
| `feat` type | `feat(auth): add OAuth2 support` | Minor |
| `fix` type | `fix(parser): handle empty input` | Patch |
| `docs`, `chore`, `refactor`, `test`, `style`, `ci`, `perf`, `build` | `docs: update readme` | None |
| Merge commits | _(filtered out by `--no-merges`)_ | None |

The **highest** bump type found in the analyzed commit range wins. A range containing both `fix:`
and `feat!:` commits results in a Major bump.

If no bump-triggering commits are found and `-BumpType` is not specified, the function writes a
warning and returns a `VersionResult` with `BumpType = 'None'` and `Success = $false`. The
manifest is not modified.

## -WhatIf Dry-Run Explanation

`-WhatIf` is fully supported. When passed:

- Git tag discovery and commit analysis run normally.
- The new version is computed and reported.
- The manifest file is **not** modified.
- No Git tag is created.
- The returned `VersionResult` has `IsWhatIf = $true` and contains the computed `NewVersion`.

This allows you to inspect the result of the analysis before committing to the change:

```powershell
$Result = Update-PSModuleVersion -Path 'C:\Projects\MyModule' -WhatIf
Write-Host "Would bump from $($Result.PreviousVersion) to $($Result.NewVersion) ($($Result.BumpType))"
```

## Git Requirements

- Git must be installed and available on the system `PATH`. The function calls `git` directly
  using the call operator (`& git`).
- The module directory must be inside a Git repository. The function passes `-C $Path` to all
  Git commands so the working directory does not affect the result.
- If no tag matching `<TagPrefix>*` exists, all commits in the repository's history are analyzed
  (equivalent to `git log --oneline --no-merges`).
- The function uses `git describe --tags --abbrev=0 --match=<TagPrefix>*` to find the most
  recent tag. Annotated and lightweight tags are both supported.
- Tag creation (when `-Tag` is specified) uses `git tag <TagName>`. The tag is lightweight.
  Push the tag to a remote with `git push origin <TagName>` after the function completes.
