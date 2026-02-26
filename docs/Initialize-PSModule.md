# Initialize-PSModule

## Synopsis

Scaffolds a new PowerShell module project with the standard directory structure.

## Description

`Initialize-PSModule` creates a complete PowerShell module project under the specified parent
directory. A single call generates everything needed to start developing a module immediately:
the module root folder, the four canonical source subdirectories, a development `.psm1` that
dot-sources all source files dynamically, and a pre-configured `.psd1` manifest.

The generated `.psm1` is a development loader — it uses `Get-ChildItem` at import time to
discover and dot-source all files in each section. This means you can add, rename, or delete
individual source files without editing the `.psm1`. When you are ready to distribute the
module, run `Build-PSModule` to compile everything into a single merged `.psm1`.

The function refuses to overwrite an existing directory with the same module name. If a directory
already exists at the target path a terminating error is thrown.

The function supports `-WhatIf` and `-Confirm` via `SupportsShouldProcess`.

## Syntax

```
Initialize-PSModule
    [-ModuleName] <String>
    [[-Path] <String>]
    [-Author <String>]
    [-Description <String>]
    [-Version <Version>]
    [-PowerShellVersion <Version>]
    [-License <String>]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

## Parameters

### -ModuleName

The name of the new module. Used as the folder name and as the base name for the `.psm1` and
`.psd1` files. Must start with a letter and contain only letters, digits, dots (`.`), and
underscores (`_`).

- **Type:** `String`
- **Position:** 0 (positional, mandatory)
- **Default:** None — required
- **Accepts pipeline input:** No
- **Validation:** `^[A-Za-z][A-Za-z0-9._]+$`

### -Path

The parent directory in which the module project folder will be created. Must be an existing
directory. The module is created at `<Path>\<ModuleName>`.

- **Type:** `String`
- **Position:** 1 (positional)
- **Default:** Current working directory (`Get-Location`)
- **Required:** No
- **Accepts pipeline input:** No

### -Author

The author name written to the `Author` field of the module manifest. Defaults to the current
OS user name (`[System.Environment]::UserName`).

- **Type:** `String`
- **Position:** Named
- **Default:** Current OS user name
- **Required:** No

### -Description

A short description of the module written to the `Description` field of the manifest. Defaults
to an empty string, which you can fill in later by editing the `.psd1`.

- **Type:** `String`
- **Position:** Named
- **Default:** `''` (empty string)
- **Required:** No

### -Version

The initial `ModuleVersion` written to the manifest. Accepts any value that can be parsed as a
`[version]` (e.g., `'1.0.0'`, `'0.1.0'`).

- **Type:** `Version`
- **Position:** Named
- **Default:** `0.1.0`
- **Required:** No

### -PowerShellVersion

The minimum PowerShell version written to the `PowerShellVersion` field of the manifest.

- **Type:** `Version`
- **Position:** Named
- **Default:** `5.1`
- **Required:** No

### -License

The SPDX license identifier used to set `LicenseUri` in the `PSData` section of the manifest.
Specify `'None'` to omit `LicenseUri` entirely.

- **Type:** `String`
- **Position:** Named
- **Default:** `'MIT'`
- **Required:** No
- **Accepted values:** `MIT`, `Apache-2.0`, `GPL-3.0`, `None`

| Value | LicenseUri written to manifest |
|---|---|
| `MIT` | `https://opensource.org/licenses/MIT` |
| `Apache-2.0` | `https://www.apache.org/licenses/LICENSE-2.0` |
| `GPL-3.0` | `https://www.gnu.org/licenses/gpl-3.0.html` |
| `None` | Field omitted |

## Output

`[PSCustomObject]` with PSTypeName `YFridelance.PS.ModuleFactory.ScaffoldResult`

| Property | Type | Description |
|---|---|---|
| `ModuleName` | `String` | Name of the scaffolded module |
| `ModulePath` | `String` | Absolute path of the created module root directory |
| `ManifestPath` | `String` | Full path to the generated `.psd1` file |
| `RootModulePath` | `String` | Full path to the generated `.psm1` file |
| `DirectoriesCreated` | `String[]` | All directories created (root + four subdirectories) |
| `Success` | `Boolean` | Always `$true` on a successful scaffold |

## Examples

### Example 1: Scaffold with defaults in the current directory

```powershell
Initialize-PSModule -ModuleName 'MyCompany.PS.Utilities'
```

Creates `.\MyCompany.PS.Utilities\` with the default author (current user), version `0.1.0`,
and an MIT license URI.

### Example 2: Scaffold with all options specified

```powershell
Initialize-PSModule -ModuleName 'Acme.PS.Tools' -Path 'C:\Projects' `
    -Author 'Jane Doe' -Description 'Acme internal toolset' `
    -Version '1.0.0' -PowerShellVersion '7.2' -License 'Apache-2.0'
```

Creates `C:\Projects\Acme.PS.Tools\` with a manifest configured for PowerShell 7.2+ and an
Apache-2.0 license URI.

### Example 3: Scaffold without a license URI

```powershell
Initialize-PSModule -ModuleName 'Internal.Tools' -License 'None'
```

Creates the module project without a `LicenseUri` field in the manifest. Suitable for internal
or proprietary modules where the license does not have a public URI.

### Example 4: Preview what would be created without writing any files

```powershell
Initialize-PSModule -ModuleName 'MyModule' -Path 'C:\Projects' -WhatIf
```

Reports all directories and files that would be created without actually creating anything.

## What Gets Created

After running `Initialize-PSModule -ModuleName 'MyModule' -Path 'C:\Projects'`, the following
structure is created:

```
C:\Projects\
+-- MyModule\
    +-- MyModule.psd1          # Module manifest
    +-- MyModule.psm1          # Development dot-source loader
    +-- Public\                # Place exported functions here (*.ps1)
    +-- Private\               # Place internal helpers here (*.ps1)
    +-- Classes\               # Place class definitions here (*.Class.ps1)
    +-- Enums\                 # Place enum definitions here (*.Enum.ps1)
```

## Notes

### Generated .psm1

The generated `.psm1` is a development loader that should not be shipped as-is. At import time
it performs the following steps in order:

1. Checks if the `Enums` directory exists; if so, loads all `*.Enum.ps1` files sorted
   numerically then alphabetically.
2. Checks if the `Classes` directory exists; if so, loads all `*.Class.ps1` files in the same
   order.
3. Loads all `*.ps1` files from `Private`, sorted alphabetically.
4. Loads all `*.ps1` files from `Public`, sorted alphabetically.

This approach means you never need to edit the `.psm1` while developing — just add files to the
appropriate subdirectory.

### Generated .psd1

The generated manifest sets `FunctionsToExport`, `AliasesToExport`, `CmdletsToExport`, and
`VariablesToExport` to empty arrays. When you run `Build-PSModule`, these fields are overwritten
with the names discovered by AST analysis of your `Public` files. Do not manually list exports in
the dev manifest — the build step owns those fields.

### Encoding

Both generated files are written as UTF-8 with BOM. Edit them with any editor that respects
BOM-aware UTF-8 (all modern editors do).
