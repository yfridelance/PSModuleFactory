# yvfrii.PS.ModuleFactory

A PowerShell module that helps developers build, package, and manage other PowerShell modules.
PSModuleFactory covers the full module lifecycle: scaffold a new module from scratch, develop with
individual source files, build a distributable single-file package, and automate semantic versioning
from Git commit history.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/yvfrii.PS.ModuleFactory?label=PSGallery)](https://www.powershellgallery.com/packages/yvfrii.PS.ModuleFactory)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/yfridelance/PSModuleFactory/actions/workflows/build.yml/badge.svg)](https://github.com/yfridelance/PSModuleFactory/actions/workflows/build.yml)

---

## Quick Start

### Install

```powershell
Install-Module -Name yvfrii.PS.ModuleFactory -Scope CurrentUser
Import-Module yvfrii.PS.ModuleFactory
```

### Initialize a new module

```powershell
Initialize-PSModule -ModuleName 'Acme.PS.Tools' -Path 'C:\Projects' -Author 'Jane Doe' `
    -Description 'Acme internal toolset' -Version '0.1.0'
```

### Develop — add functions, classes, and enums to the generated folders, then build

```powershell
# Build from the module root directory
Build-PSModule -Path 'C:\Projects\Acme.PS.Tools' -Clean -Verbose

# Output lands in C:\Projects\dist\Acme.PS.Tools\
```

### Bump the version before publishing

```powershell
Update-PSModuleVersion -Path 'C:\Projects\Acme.PS.Tools' -Tag -Verbose
```

---

## Features

### Build — merge a dev structure into a distributable package

During development, each function lives in its own `.ps1` file. `Build-PSModule` merges all source
files into a single `.psm1`, updates `FunctionsToExport` and `AliasesToExport` in the copied
manifest, and writes everything to the output directory.

```powershell
# Build to the default dist/ folder
Build-PSModule -Path 'C:\Projects\MyModule'

# Build to a custom path with a clean run
Build-PSModule -Path 'C:\Projects\MyModule' -OutputPath 'C:\Artifacts\MyModule' -Clean
```

### Initialize — scaffold a new module with the standard folder layout

Creates the module directory, subdirectories (`Public`, `Private`, `Classes`, `Enums`), a
development `.psm1` that dot-sources all source files, and a pre-configured `.psd1` manifest.

```powershell
Initialize-PSModule -ModuleName 'Company.PS.Utilities' -Path 'C:\Projects' `
    -Description 'Utility functions' -License 'MIT'
```

### Split — convert a monolithic .psm1 into individual source files

If you have an existing module with all code in a single `.psm1`, `Split-PSModule` extracts each
function, class, and enum into its own file under the appropriate subdirectory and replaces the
original `.psm1` with a development dot-source loader.

```powershell
# Preview what would happen without writing any files
Split-PSModule -Path 'C:\Projects\LegacyModule' -WhatIf

# Execute the split; overwrite existing files if present
Split-PSModule -Path 'C:\Projects\LegacyModule' -Force
```

### Version — semantic versioning from Conventional Commits

Reads the current `ModuleVersion` from the manifest, analyzes Git commits since the last version
tag using the Conventional Commits specification, and bumps the version accordingly. Optionally
creates a Git tag.

```powershell
# Automatic analysis from commit history
Update-PSModuleVersion -Path 'C:\Projects\MyModule'

# Force a specific bump and tag
Update-PSModuleVersion -Path 'C:\Projects\MyModule' -BumpType Minor -Tag

# Dry run — see what would change without modifying anything
Update-PSModuleVersion -Path 'C:\Projects\MyModule' -WhatIf
```

---

## Module Structure (managed module)

A module managed by PSModuleFactory uses the following layout:

```
MyModule/                        # Module root (equals the module name)
|
+-- MyModule.psd1                # Module manifest
+-- MyModule.psm1                # Dev: dot-source loader | Build: merged output
|
+-- Public/                      # Exported functions — one file per function
|   +-- Get-Something.ps1
|   +-- Set-Something.ps1
|
+-- Private/                     # Internal helpers — one file per function
|   +-- Invoke-Helper.ps1
|   +-- ConvertTo-Internal.ps1
|
+-- Classes/                     # PowerShell classes — numerically prefixed for load order
|   +-- 01_BaseModel.Class.ps1
|   +-- 02_DerivedModel.Class.ps1
|
+-- Enums/                       # Enum definitions — numerically prefixed for load order
    +-- 01_StatusEnum.Enum.ps1
```

File naming conventions:
- Public and Private functions: `FunctionName.ps1`
- Classes: `NN_ClassName.Class.ps1` (numeric prefix controls load order)
- Enums: `NN_EnumName.Enum.ps1` (numeric prefix controls load order)

---

## PSModuleFactory Repository Structure

```
PSModuleFactory/                              # Repository root
|
+-- yvfrii.PS.ModuleFactory/                  # Module source
|   +-- yvfrii.PS.ModuleFactory.psd1          # Module manifest
|   +-- yvfrii.PS.ModuleFactory.psm1          # Dev dot-source loader
|   +-- Public/                               # Four exported functions
|   |   +-- Build-PSModule.ps1
|   |   +-- Initialize-PSModule.ps1
|   |   +-- Split-PSModule.ps1
|   |   +-- Update-PSModuleVersion.ps1
|   +-- Private/                              # Nine internal helper functions
|   |   +-- ConvertTo-SortedClassFileName.ps1
|   |   +-- Get-AliasesFromFile.ps1
|   |   +-- Get-FunctionNamesFromFile.ps1
|   |   +-- Merge-SourceFiles.ps1
|   |   +-- New-DevPsm1Content.ps1
|   |   +-- Resolve-ModuleSourcePaths.ps1
|   |   +-- Split-PsFileContent.ps1
|   |   +-- Test-ModuleProjectStructure.ps1
|   |   +-- Update-ManifestField.ps1
|   +-- Classes/                              # (reserved)
|   +-- Enums/                                # (reserved)
|
+-- Tests/                                    # Pester v5 test suite
|   +-- Unit/
|   |   +-- Public/
|   |   +-- Private/
|   +-- Integration/
|   +-- Fixtures/
|
+-- dist/                                     # Build output (gitignored)
+-- build.ps1                                 # Self-build script (dogfooding)
+-- .github/
|   +-- workflows/
|       +-- build.yml                         # CI pipeline
+-- ARCHITECTURE.md
+-- CHANGELOG.md
+-- LICENSE
+-- README.md
```

---

## Requirements

| Requirement | Minimum version | Notes |
|---|---|---|
| PowerShell | 5.1 | Windows PowerShell 5.1 and PowerShell 7+ both supported |
| Pester | 5.0 | Required only for running tests |
| Git | Any recent version | Required only for `Update-PSModuleVersion` |

No external PowerShell module dependencies are required at runtime.

---

## Documentation

| Topic | File |
|---|---|
| Build-PSModule | [docs/Build-PSModule.md](docs/Build-PSModule.md) |
| Initialize-PSModule | [docs/Initialize-PSModule.md](docs/Initialize-PSModule.md) |
| Split-PSModule | [docs/Split-PSModule.md](docs/Split-PSModule.md) |
| Update-PSModuleVersion | [docs/Update-PSModuleVersion.md](docs/Update-PSModuleVersion.md) |
| Conventional Commits guide | [docs/ConventionalCommits.md](docs/ConventionalCommits.md) |

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow the existing code style: PascalCase variables, comment-based help on every function,
   `SupportsShouldProcess` on state-modifying functions.
3. Write Pester v5 tests for any new or changed behavior. Place unit tests under
   `Tests/Unit/Public/` or `Tests/Unit/Private/` to match the source layout.
4. Use Conventional Commits for all commit messages so that `Update-PSModuleVersion` can
   determine the correct version bump automatically. See
   [docs/ConventionalCommits.md](docs/ConventionalCommits.md) for the format.
5. Open a pull request against `main`. The CI pipeline must pass before merge.

---

## License

MIT License. Copyright (c) 2026 Yves Fridelance. See [LICENSE](LICENSE) for the full text.
