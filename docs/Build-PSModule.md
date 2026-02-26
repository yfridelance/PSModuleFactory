# Build-PSModule

## Synopsis

Builds a PowerShell module by merging source files into a distributable package.

## Description

`Build-PSModule` compiles a structured PowerShell module project into a single distributable
package. It reads source files from the four canonical subdirectories (`Enums`, `Classes`,
`Private`, `Public`), merges them in the correct load order into one `.psm1` file, copies and
updates the module manifest (`.psd1`) with the detected exported functions and aliases, and writes
all output to the specified distribution directory.

The function validates the module project structure before doing any work, so a clear error is
produced if required files are missing. All progress steps are reported through `Write-Verbose`.
The function supports `-WhatIf` and `-Confirm` through `SupportsShouldProcess`.

Merging is done with `#region` / `#endregion` markers so that the built `.psm1` remains readable
and navigable in an editor. Dot-source lines from the dev `.psm1` are stripped automatically so
the built file does not attempt to load individual source files at runtime.

## Syntax

```
Build-PSModule
    [[-Path] <String>]
    [-OutputPath <String>]
    [-Clean]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

## Parameters

### -Path

The root directory of the PowerShell module project to build. Must be an existing directory and
must contain a `.psd1` manifest file. The module name is derived from the manifest file name.

- **Type:** `String`
- **Position:** 0 (positional)
- **Default:** Current working directory (`Get-Location`)
- **Required:** No
- **Accepts pipeline input:** No

### -OutputPath

The directory where the built module will be written. If the directory does not exist it is
created. If not specified, the output path defaults to `../dist/<ModuleName>` relative to
`-Path` (i.e., a `dist` folder one level above the module root, then a subfolder named after
the module).

- **Type:** `String`
- **Position:** Named
- **Default:** `<parent of Path>/dist/<ModuleName>`
- **Required:** No
- **Accepts pipeline input:** No

### -Clean

When specified, removes the existing output directory before building. A confirmation prompt is
shown unless `-Confirm:$false` is also passed. Useful in CI pipelines to ensure no stale files
remain from a previous build.

- **Type:** `Switch`
- **Position:** Named
- **Default:** Not set
- **Required:** No
- **Accepts pipeline input:** No

## Output

`[PSCustomObject]` with PSTypeName `YFridelance.PS.ModuleFactory.BuildResult`

| Property | Type | Description |
|---|---|---|
| `ModuleName` | `String` | Name of the built module |
| `SourcePath` | `String` | Absolute path of the module source root |
| `OutputPath` | `String` | Directory where the built module was written |
| `ManifestPath` | `String` | Full path to the output `.psd1` file |
| `RootModulePath` | `String` | Full path to the output `.psm1` file |
| `FunctionsExported` | `String[]` | Function names written to `FunctionsToExport` |
| `AliasesExported` | `String[]` | Alias names written to `AliasesToExport` |
| `FilesMerged` | `Int32` | Total number of source files merged |
| `Success` | `Boolean` | Always `$true` on a successful build |

## Examples

### Example 1: Build from the current directory

```powershell
Set-Location 'C:\Projects\MyModule'
Build-PSModule
```

Builds the module in the current directory. Output is written to `C:\Projects\dist\MyModule\`.

### Example 2: Build from an explicit path

```powershell
Build-PSModule -Path 'C:\Projects\MyModule'
```

Equivalent to Example 1 but using an explicit path rather than relying on the current directory.

### Example 3: Build to a custom output path with verbose output

```powershell
Build-PSModule -Path 'C:\Projects\MyModule' -OutputPath 'C:\CI\Artifacts\MyModule' -Verbose
```

Writes the built module to `C:\CI\Artifacts\MyModule`. Prints one `VERBOSE:` line per operation
so progress is visible in a CI log.

### Example 4: Clean build with confirmation suppressed

```powershell
Build-PSModule -Path 'C:\Projects\MyModule' -Clean -Confirm:$false
```

Removes the existing output directory without prompting, then rebuilds. Useful in automated
pipelines where interactive prompts would block execution.

## How the Build Process Works

1. **Structure validation** — `Test-ModuleProjectStructure` checks that the module root contains
   exactly one `.psd1` and a matching `.psm1`. A terminating error is thrown if validation fails.

2. **Output path resolution** — If `-OutputPath` was not supplied, the default path
   `<parent>/dist/<ModuleName>` is computed.

3. **Clean** — If `-Clean` was specified and the output directory exists, it is removed.

4. **Output directory creation** — The output directory is created if it does not exist.

5. **Source path resolution** — `Resolve-ModuleSourcePaths` discovers all source files in the
   four sections, applying the correct sort order:
   - `Enums/*.Enum.ps1` — numerically prefixed files first (`01_`, `02_`, ...), then alphabetical
   - `Classes/*.Class.ps1` — same numeric-then-alpha ordering
   - `Private/*.ps1` — strict alphabetical
   - `Public/*.ps1` — strict alphabetical

6. **Function and alias extraction** — `Get-FunctionNamesFromFile` and `Get-AliasesFromFile` use
   the PowerShell AST to extract the names of all top-level functions and `Set-Alias` calls from
   each `Public` file.

7. **Merge** — `Merge-SourceFiles` concatenates all source files into a single string, wrapping
   each section and each file in `#region` / `#endregion` markers and stripping dot-source lines.

8. **Write `.psm1`** — The merged content is written to `<OutputPath>/<ModuleName>.psm1` using
   UTF-8 with BOM encoding.

9. **Copy `.psd1`** — The source manifest is copied to the output directory.

10. **Update manifest** — `FunctionsToExport` and `AliasesToExport` fields in the copied manifest
    are replaced with the lists collected in step 6.

11. **Return result** — A `BuildResult` object is returned summarizing the operation.

## Notes

- **Encoding:** All output files are written as UTF-8 with BOM (`utf8BOM`). This matches the
  encoding expected by Windows PowerShell 5.1 and is safe for PowerShell 7+.

- **Line endings:** The merged `.psm1` uses CRLF line endings throughout, regardless of the host
  OS. This ensures consistent behavior when the built module is distributed to Windows systems.

- **Dot-source stripping:** Any line matching `^\s*\.\s+.*\.ps1` in a source file is removed
  during merge. This means the dev `.psm1` dot-source loader is automatically excluded from the
  built output without manual intervention.

- **WhatIf support:** When `-WhatIf` is passed, no files are written or deleted. The function
  reports what it would do via standard `WhatIf:` output.
