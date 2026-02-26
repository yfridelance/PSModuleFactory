# Split-PSModule

## Synopsis

Splits a monolithic `.psm1` file into individual source files organized by type and scope.

## Description

`Split-PSModule` is the inverse of `Build-PSModule`. It takes an existing PowerShell module that
has all its code in a single `.psm1` file and extracts each top-level definition into its own
`.ps1` file in the appropriate subdirectory.

The function uses the PowerShell Abstract Syntax Tree (AST) to identify functions
(`FunctionDefinitionAst`), classes (`TypeDefinitionAst` where `IsClass`), and enums
(`TypeDefinitionAst` where `IsEnum`). Each definition is extracted with its immediately preceding
comment-based help block (if one exists adjacent to the definition).

Public vs. private scope is determined by cross-referencing the module manifest's
`FunctionsToExport` list. Functions listed there are placed under `Public/`; all others go to
`Private/`. Classes and enums always go to `Classes/` and `Enums/` respectively.

After writing the individual files, the original `.psm1` is replaced with a development
dot-source loader (the same format that `Initialize-PSModule` generates). From that point on the
module directory is ready for the PSModuleFactory dev workflow.

By default, `Split-PSModule` does not overwrite existing files — a non-terminating error is
written for each conflict. Use `-Force` to overwrite.

The function supports `-WhatIf` and `-Confirm` via `SupportsShouldProcess` with `ConfirmImpact`
set to `High` because it overwrites the `.psm1` file.

## Syntax

```
Split-PSModule
    [-Path] <String>
    [-Force]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

## Parameters

### -Path

The root directory of the PowerShell module to split. Must be an existing directory and must
contain exactly one `.psd1` manifest file and a matching `.psm1` file (named after the module).

- **Type:** `String`
- **Position:** 0 (positional, mandatory)
- **Default:** None — required
- **Accepts pipeline input:** No

### -Force

When specified, existing `.ps1` files in the target subdirectories are silently overwritten.
Without this switch, any file that already exists at the target path causes a non-terminating
error for that specific file, and the file is skipped. Other files continue to be processed.

- **Type:** `Switch`
- **Position:** Named
- **Default:** Not set (conflicts cause non-terminating errors)
- **Required:** No
- **Accepts pipeline input:** No

## Output

`[PSCustomObject]` with PSTypeName `yvfrii.PS.ModuleFactory.SplitResult`

| Property | Type | Description |
|---|---|---|
| `ModuleName` | `String` | Name of the split module |
| `ModulePath` | `String` | Absolute path of the module directory |
| `PublicFunctions` | `String[]` | Names of functions placed in `Public/` |
| `PrivateFunctions` | `String[]` | Names of functions placed in `Private/` |
| `Classes` | `String[]` | Names of classes placed in `Classes/` |
| `Enums` | `String[]` | Names of enums placed in `Enums/` |
| `FilesCreated` | `Int32` | Total number of `.ps1` files written |
| `Success` | `Boolean` | Always `$true` on a successful split |

## Examples

### Example 1: Split a module, keep existing files

```powershell
Split-PSModule -Path 'C:\Projects\LegacyModule'
```

Extracts all definitions from `LegacyModule.psm1`. Existing files in the subdirectories are
preserved; a non-terminating error is written for each conflict. Inspect `$Error` afterwards to
identify any skipped files.

### Example 2: Split with verbose output

```powershell
Split-PSModule -Path 'C:\Projects\LegacyModule' -Verbose
```

Same as Example 1 but prints a `VERBOSE:` line for each file written, each definition detected,
and each subdirectory created.

### Example 3: Overwrite existing files

```powershell
Split-PSModule -Path 'C:\Projects\LegacyModule' -Force
```

Overwrites any existing `.ps1` files in `Public/`, `Private/`, `Classes/`, and `Enums/`. Use
this when re-splitting after changes to the monolithic `.psm1`.

### Example 4: Preview without writing any files

```powershell
Split-PSModule -Path 'C:\Projects\LegacyModule' -WhatIf
```

Reports all files that would be written (individual source files and the replacement dev `.psm1`)
without creating or modifying anything. Useful for a pre-flight check before committing to the
operation.

## How Splitting Works

1. **Locate the manifest** — The function searches `$Path` for exactly one `.psd1` file. Zero or
   more than one manifest is a terminating error.

2. **Locate the `.psm1`** — The function expects a file named `<ModuleName>.psm1` alongside the
   manifest. If it is missing, a terminating error is thrown.

3. **Read `FunctionsToExport`** — The manifest is read with `Import-PowerShellDataFile` to obtain
   the list of public function names. Wildcard entries (`*`) are ignored. If the manifest cannot
   be parsed, a warning is written and all functions are treated as private.

4. **AST parsing** — `Split-PsFileContent` parses the `.psm1` with the PowerShell language
   parser. It extracts all top-level `function`, `class`, and `enum` definitions. Nested
   definitions (methods, inner functions) are excluded.

5. **Comment-based help inclusion** — If a comment-based help block (`<# ... #>`) immediately
   precedes a definition (separated only by whitespace), it is included in the extracted content.
   This keeps help and code together in the individual file.

6. **Subdirectory creation** — `Public/`, `Private/`, `Classes/`, and `Enums/` are created under
   `$Path` if they do not already exist.

7. **File writing** — Each definition is written to its target file:
   - Functions in `FunctionsToExport` → `Public/<FunctionName>.ps1`
   - Other functions → `Private/<FunctionName>.ps1`
   - Classes → `Classes/<NN_ClassName>.Class.ps1` (numeric prefix assigned by discovery order)
   - Enums → `Enums/<EnumName>.Enum.ps1`

8. **Dev `.psm1` replacement** — The original monolithic `.psm1` is replaced with a development
   dot-source loader generated by `New-DevPsm1Content`. The module is now in the PSModuleFactory
   dev structure.

## Notes

### -Force behavior

`-Force` only applies to the individual `.ps1` files written for each definition. The replacement
of the `.psm1` with the dev loader always occurs (unless `-WhatIf` is passed), regardless of
whether `-Force` is specified.

### File conflicts without -Force

When a target file already exists and `-Force` is not set, a non-terminating error is written via
`Write-Error`. Processing continues with the next definition. To collect all conflicts before
deciding, run with `-WhatIf` first, then use `-Force` to overwrite.

### Class file naming

Classes are written with a numeric prefix that reflects their discovery order in the source file
(e.g., the first class found becomes `01_ClassName.Class.ps1`). This preserves the original load
order when the project is later built with `Build-PSModule`, which sorts class files numerically.

### Git recommendation

Commit or stash any uncommitted changes before running `Split-PSModule`. The operation replaces
the `.psm1` file in place and cannot be undone without Git. After splitting, review the
individual files with `git diff` before committing.
