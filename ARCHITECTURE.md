# ARCHITECTURE.md -- YFridelance.PS.ModuleFactory

## Table of Contents

1. [Overview](#1-overview)
2. [Project Folder Structure](#2-project-folder-structure)
3. [Public Function Signatures](#3-public-function-signatures)
4. [Private Function Signatures](#4-private-function-signatures)
5. [Data Flow Diagrams](#5-data-flow-diagrams)
6. [Output Object Definitions](#6-output-object-definitions)
7. [Error Handling Conventions](#7-error-handling-conventions)
8. [Configuration Handling](#8-configuration-handling)
9. [Design Decisions and Rationale](#9-design-decisions-and-rationale)
10. [Compatibility Strategy](#10-compatibility-strategy)
11. [Coding Standards Quick Reference](#11-coding-standards-quick-reference)

---

## 1. Overview

**YFridelance.PS.ModuleFactory** is a PowerShell module that helps developers build, package, and
manage other PowerShell modules. It supports four core workflows:

| Feature        | Verb            | Direction                   |
|----------------|-----------------|-----------------------------|
| **Build**      | Build-PSModule          | Dev structure --> distributable .psm1   |
| **Initialize** | Initialize-PSModule     | Nothing --> scaffolded dev structure     |
| **Split**      | Split-PSModule          | Monolithic .psm1 --> dev structure      |
| **Version**    | Update-PSModuleVersion  | Git history --> semantic version bump   |

**Compatibility:** Windows PowerShell 5.1 and PowerShell 7+ (dual compatibility).
Version-specific features use explicit `$PSVersionTable.PSVersion` guards with fallbacks.

**Dependencies:** None at runtime (Git required only for `Update-PSModuleVersion`).
Pester v5 required for tests only.

---

## 2. Project Folder Structure

```
PSModuleFactory/                              # Repository root
|
+-- YFridelance.PS.ModuleFactory/                  # Module root (importable module)
|   +-- YFridelance.PS.ModuleFactory.psd1          # Module manifest
|   +-- YFridelance.PS.ModuleFactory.psm1          # Dev: dot-sources | Build: merged
|   |
|   +-- Public/                               # Exported functions (4 files)
|   |   +-- Build-PSModule.ps1
|   |   +-- Initialize-PSModule.ps1
|   |   +-- Split-PSModule.ps1
|   |   +-- Update-PSModuleVersion.ps1
|   |
|   +-- Private/                              # Internal helper functions
|   |   +-- Resolve-ModuleSourcePaths.ps1
|   |   +-- Get-FunctionNamesFromFile.ps1
|   |   +-- Get-AliasesFromFile.ps1
|   |   +-- Merge-SourceFiles.ps1
|   |   +-- Update-ManifestField.ps1
|   |   +-- New-DevPsm1Content.ps1
|   |   +-- Split-PsFileContent.ps1
|   |   +-- Test-ModuleProjectStructure.ps1
|   |   +-- ConvertTo-SortedClassFileName.ps1
|   |
|   +-- Classes/                              # (reserved, currently empty)
|   +-- Enums/                                # (reserved, currently empty)
|
+-- Tests/                                    # Pester v5 test suite
|   +-- Unit/
|   |   +-- Private/                          # One test file per private function
|   |   |   +-- Resolve-ModuleSourcePaths.Tests.ps1
|   |   |   +-- Get-FunctionNamesFromFile.Tests.ps1
|   |   |   +-- Get-AliasesFromFile.Tests.ps1
|   |   |   +-- Merge-SourceFiles.Tests.ps1
|   |   |   +-- Update-ManifestField.Tests.ps1
|   |   |   +-- New-DevPsm1Content.Tests.ps1
|   |   |   +-- Split-PsFileContent.Tests.ps1
|   |   |   +-- Test-ModuleProjectStructure.Tests.ps1
|   |   |   +-- ConvertTo-SortedClassFileName.Tests.ps1
|   |   +-- Public/                           # One test file per public function
|   |       +-- Build-PSModule.Tests.ps1
|   |       +-- Initialize-PSModule.Tests.ps1
|   |       +-- Split-PSModule.Tests.ps1
|   |       +-- Update-PSModuleVersion.Tests.ps1
|   +-- Integration/
|   |   +-- BuildWorkflow.Tests.ps1           # Scaffold --> add files --> build --> verify
|   |   +-- SplitWorkflow.Tests.ps1           # Build --> split --> rebuild --> compare
|   +-- Fixtures/
|       +-- SampleModule/                     # Pre-built sample module for test input
|       |   +-- SampleModule.psd1
|       |   +-- SampleModule.psm1             # Monolithic version for split tests
|       |   +-- Public/
|       |   |   +-- Get-SampleData.ps1
|       |   |   +-- Set-SampleData.ps1
|       |   +-- Private/
|       |   |   +-- Invoke-SampleHelper.ps1
|       |   +-- Classes/
|       |   |   +-- 01_BaseModel.Class.ps1
|       |   |   +-- 02_DerivedModel.Class.ps1
|       |   +-- Enums/
|       |       +-- SampleStatus.Enum.ps1
|       +-- MonolithicModule/                 # Single-file module for split tests
|           +-- MonolithicModule.psd1
|           +-- MonolithicModule.psm1
|
+-- dist/                                     # Build output (gitignored)
|   +-- YFridelance.PS.ModuleFactory/
|       +-- YFridelance.PS.ModuleFactory.psd1
|       +-- YFridelance.PS.ModuleFactory.psm1
|
+-- build.ps1                                 # Self-build script (dogfooding)
+-- ARCHITECTURE.md                           # This document
+-- AGENTS.md                                 # Multi-agent orchestration prompt
+-- README.md                                 # User-facing documentation
+-- CHANGELOG.md                              # Version history
+-- LICENSE                                   # MIT License
+-- .gitignore                                # Ignores dist/, *.bak, etc.
+-- .github/
    +-- workflows/
        +-- build.yml                         # CI: test --> build --> artifact
```

### Key structural decisions

- The importable module lives in `YFridelance.PS.ModuleFactory/` (one level down from repo root).
  This keeps repo-level files (README, LICENSE, tests, CI) separate from the module itself.
- `Classes/` and `Enums/` directories exist inside the module folder but are reserved for
  future use. The current implementation does not require custom classes or enums.
- `dist/` is the build output directory and is gitignored.
- `build.ps1` at the repo root is a thin wrapper that imports the dev module and calls
  `Build-PSModule` on itself (dogfooding).

---

## 3. Public Function Signatures

### 3.1 Build-PSModule

Merges a dev-structure module into a single distributable .psm1 and updates the manifest.

```powershell
function Build-PSModule {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        # Path to the module root directory containing the .psd1 and source folders.
        # Defaults to the current directory.
        [Parameter(Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        # Path to the output directory where the built module will be placed.
        # Defaults to "../dist/<ModuleName>" relative to $Path.
        [Parameter()]
        [string]$OutputPath,

        # If specified, removes the output directory before building.
        [Parameter()]
        [switch]$Clean
    )
}
```

**Returns:** `[PSCustomObject]` -- see [Section 6.1](#61-build-psmodule-output).

**Behavior:**
1. Validates module structure via `Test-ModuleProjectStructure`.
2. Calls `Resolve-ModuleSourcePaths` to discover source files in load order.
3. Calls `Get-FunctionNamesFromFile` on each Public/*.ps1 to collect exported function names.
4. Calls `Get-AliasesFromFile` on each Public/*.ps1 to collect aliases.
5. Calls `Merge-SourceFiles` to concatenate all source into a single .psm1 body.
6. Writes the merged .psm1 to `$OutputPath`.
7. Copies the .psd1 to `$OutputPath`, then calls `Update-ManifestField` to set
   `FunctionsToExport` and `AliasesToExport`.
8. Returns a build result object.

---

### 3.2 Initialize-PSModule

Scaffolds a new module with the conventional folder structure.

```powershell
function Initialize-PSModule {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        # Name of the module to create. Must follow PowerShell module naming rules.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9._]+$')]
        [string]$ModuleName,

        # Directory where the module folder will be created.
        # Defaults to the current directory.
        [Parameter(Position = 1)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        # Module author name. Defaults to the current user's name.
        [Parameter()]
        [string]$Author = [System.Environment]::UserName,

        # Short description of the module's purpose.
        [Parameter()]
        [string]$Description = '',

        # Initial module version. Defaults to 0.1.0.
        [Parameter()]
        [version]$Version = '0.1.0',

        # Minimum PowerShell version required by the generated module.
        # Defaults to 5.1 for maximum compatibility.
        [Parameter()]
        [version]$PowerShellVersion = '5.1',

        # License type for the generated module manifest.
        # Defaults to MIT.
        [Parameter()]
        [ValidateSet('MIT', 'Apache-2.0', 'GPL-3.0', 'None')]
        [string]$License = 'MIT'
    )
}
```

**Returns:** `[PSCustomObject]` -- see [Section 6.2](#62-initialize-psmodule-output).

**Behavior:**
1. Creates `$Path/$ModuleName/` directory.
2. Creates subdirectories: `Public/`, `Private/`, `Classes/`, `Enums/`.
3. Generates a dev .psm1 via `New-DevPsm1Content` and writes it.
4. Generates a .psd1 manifest using `New-ModuleManifest` with the provided parameters.
5. Returns a scaffold result object.

---

### 3.3 Split-PSModule

Splits a monolithic .psm1 into individual files in the dev folder structure.

```powershell
function Split-PSModule {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        # Path to the module root directory containing the monolithic .psm1 and .psd1.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path,

        # If specified, overwrites existing files in Public/, Private/, Classes/, Enums/.
        # Without this switch, the function will fail if any target files already exist.
        [Parameter()]
        [switch]$Force
    )
}
```

**Returns:** `[PSCustomObject]` -- see [Section 6.3](#63-split-psmodule-output).

**Behavior:**
1. Locates the .psm1 and .psd1 in `$Path`.
2. Reads `FunctionsToExport` from the .psd1 to know which functions are public.
3. Calls `Split-PsFileContent` to parse the .psm1 into individual code blocks
   (functions, classes, enums, loose code).
4. Creates subdirectories (`Public/`, `Private/`, `Classes/`, `Enums/`) if missing.
5. Writes each function to `Public/<Name>.ps1` or `Private/<Name>.ps1`.
6. Writes each class to `Classes/<NN>_<Name>.Class.ps1` (numeric prefix from
   `ConvertTo-SortedClassFileName` preserving inheritance order).
7. Writes each enum to `Enums/<Name>.Enum.ps1`.
8. Generates a new dev .psm1 via `New-DevPsm1Content`.
9. Returns a split result object.

---

### 3.4 Update-PSModuleVersion

Analyzes Conventional Commits in Git history to determine and apply semantic version bumps.

```powershell
function Update-PSModuleVersion {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        # Path to the module root directory containing the .psd1.
        [Parameter(Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        # Override the automatic bump detection with an explicit bump type.
        [Parameter()]
        [ValidateSet('Major', 'Minor', 'Patch')]
        [string]$BumpType,

        # If specified, creates a Git tag (v<Version>) after updating the manifest.
        [Parameter()]
        [switch]$Tag,

        # Optional tag prefix. Defaults to "v" (e.g., v1.2.3).
        [Parameter()]
        [string]$TagPrefix = 'v'
    )
}
```

**Returns:** `[PSCustomObject]` -- see [Section 6.4](#64-update-psmoduleversion-output).

**Notes on -WhatIf:** When `-WhatIf` is active, the function performs all analysis (reads
Git log, determines bump type, computes new version) but does NOT write to the .psd1 or
create a Git tag. The return object is still fully populated so callers can inspect what
*would* happen.

**Behavior:**
1. Verifies Git is available (`Get-Command git`). If not, throws a terminating error.
2. Reads current version from the .psd1.
3. Finds the most recent version tag matching `$TagPrefix*` pattern.
4. Retrieves Git log entries since that tag (or all commits if no tag exists).
5. Parses commit messages for Conventional Commits patterns.
6. Determines bump type: BREAKING CHANGE --> Major, feat --> Minor, fix --> Patch.
   If `$BumpType` is specified, uses that instead of auto-detection.
7. Computes new version.
8. If `-WhatIf` is not active: updates the .psd1 via `Update-ManifestField`.
9. If `-Tag` is specified and `-WhatIf` is not active: creates a Git tag.
10. Returns a version result object.

---

## 4. Private Function Signatures

### 4.1 Resolve-ModuleSourcePaths

Discovers all source files in the correct load order for merging.

```powershell
function Resolve-ModuleSourcePaths {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        # Path to the module root directory.
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ModuleRoot
    )
}
```

**Returns:** An `[ordered]` dictionary with four keys, each containing an array of
`[System.IO.FileInfo]` objects sorted in load order:

```
@{
    Enums   = @( [FileInfo], ... )   # Sorted by file name (numeric prefix)
    Classes = @( [FileInfo], ... )   # Sorted by file name (numeric prefix)
    Private = @( [FileInfo], ... )   # Sorted alphabetically by name
    Public  = @( [FileInfo], ... )   # Sorted alphabetically by name
}
```

**Behavior:**
- Looks for `$ModuleRoot/Enums/*.Enum.ps1`, `$ModuleRoot/Classes/*.Class.ps1`,
  `$ModuleRoot/Private/*.ps1`, `$ModuleRoot/Public/*.ps1`.
- Missing directories are silently skipped (empty array for that key).
- Classes/ and Enums/ are sorted by the numeric prefix (e.g., `01_`, `02_`).
  Files without a numeric prefix are sorted alphabetically after numbered files.
- Private/ and Public/ are sorted alphabetically by file name.

---

### 4.2 Get-FunctionNamesFromFile

Uses PowerShell AST to extract function names from a .ps1 file.

```powershell
function Get-FunctionNamesFromFile {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        # Full path to the .ps1 file to parse.
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath
    )
}
```

**Returns:** `[string[]]` -- Array of function names found in the file. Returns an empty
array if the file contains no function definitions.

**Behavior:**
- Parses the file using `[System.Management.Automation.Language.Parser]::ParseFile()`.
- Extracts all `FunctionDefinitionAst` nodes at the top level (not nested).
- Returns function names only (not method names inside classes).
- If the file has parse errors, writes a non-terminating error and returns an empty array.

---

### 4.3 Get-AliasesFromFile

Extracts alias declarations from `# Alias: <name>` comment lines.

```powershell
function Get-AliasesFromFile {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        # Full path to the .ps1 file to scan.
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath
    )
}
```

**Returns:** `[string[]]` -- Array of alias names. Returns an empty array if none found.

**Behavior:**
- Reads the file content as a string.
- Applies regex: `(?m)^\s*#\s*Alias\s*:\s*(.+)\s*$`
- Supports multiple aliases per file (one `# Alias: name` per line).
- Supports comma-separated aliases on a single line: `# Alias: gs, gsd` --> `@('gs', 'gsd')`.
- Trims whitespace from extracted alias names.

---

### 4.4 Merge-SourceFiles

Concatenates source files with section comment headers.

```powershell
function Merge-SourceFiles {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Ordered dictionary from Resolve-ModuleSourcePaths.
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.Specialized.OrderedDictionary]$SourcePaths
    )
}
```

**Returns:** `[string]` -- The complete merged .psm1 content as a single string.

**Behavior:**
- Iterates through the ordered dictionary keys: Enums, Classes, Private, Public.
- For each non-empty section, writes a section header comment block:
  ```
  #region ======== Enums ========
  ```
- For each file in the section, writes:
  ```
  #region <FileName>
  <file contents>
  #endregion <FileName>
  ```
- Strips any existing dot-source lines (pattern: `^\s*\.\s+.*\.ps1`) from file contents
  to prevent recursive sourcing in the merged output.
- Ensures a single blank line between sections.
- Uses CRLF line endings throughout.
- Closes each section with `#endregion`.

---

### 4.5 Update-ManifestField

Updates specific fields in an existing .psd1 manifest file.

```powershell
function Update-ManifestField {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        # Full path to the .psd1 manifest file.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$ManifestPath,

        # Name of the manifest field to update (e.g., 'FunctionsToExport').
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'FunctionsToExport',
            'AliasesToExport',
            'ModuleVersion',
            'Description',
            'Author'
        )]
        [string]$FieldName,

        # Value to set. Accepts [string], [string[]], or [version].
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
}
```

**Returns:** `[void]` -- Modifies the .psd1 file in place.

**Behavior:**
- Reads the .psd1 as raw text.
- Uses regex replacement to locate the target field and replace its value.
- For array fields (`FunctionsToExport`, `AliasesToExport`): formats as
  `@('Name1', 'Name2', 'Name3')` on a single line if 3 or fewer items, or one item per
  line if more than 3 items.
- For scalar fields (`ModuleVersion`, `Description`, `Author`): formats as `'value'`.
- Preserves the rest of the file content unchanged.
- Writes back with UTF-8 BOM encoding and CRLF line endings.

**Design note:** We intentionally avoid `Update-ModuleManifest` because it reformats the
entire file and can remove comments. Our regex-based approach surgically updates only the
target field.

---

### 4.6 New-DevPsm1Content

Generates the content for a development .psm1 file that dot-sources all individual files.

```powershell
function New-DevPsm1Content {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Name of the module (used for the header comment).
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ModuleName
    )
}
```

**Returns:** `[string]` -- The complete .psm1 file content.

**Generated content structure:**
```powershell
#
# Module: <ModuleName>
# Generated by YFridelance.PS.ModuleFactory
# This file dot-sources all individual function files for development.
# For distribution, use Build-PSModule to merge into a single file.
#

$ModuleRoot = $PSScriptRoot

# Load order: Enums --> Classes --> Private --> Public
$LoadOrder = @('Enums', 'Classes', 'Private', 'Public')

foreach ($Folder in $LoadOrder) {
    $FolderPath = Join-Path -Path $ModuleRoot -ChildPath $Folder
    if (Test-Path -Path $FolderPath) {
        $Files = Get-ChildItem -Path $FolderPath -Filter '*.ps1' -File | Sort-Object Name
        foreach ($File in $Files) {
            . $File.FullName
        }
    }
}
```

---

### 4.7 Split-PsFileContent

Parses a monolithic .psm1 file and splits it into individual code blocks.

```powershell
function Split-PsFileContent {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        # Full path to the monolithic .psm1 file.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath,

        # Array of function names that are considered public (exported).
        # Functions not in this list will be classified as private.
        [Parameter()]
        [string[]]$PublicFunctionNames = @()
    )
}
```

**Returns:** `[PSCustomObject[]]` -- Array of objects, each representing a parsed code block:

```
@{
    Name     = [string]     # 'Get-Something', 'MyClass', 'StatusEnum'
    Type     = [string]     # 'Function', 'Class', 'Enum'
    Scope    = [string]     # 'Public', 'Private', 'None' (classes/enums use 'None')
    Content  = [string]     # The complete source code for this block
}
```

**Behavior:**
- Parses the file using PowerShell AST.
- Extracts top-level `FunctionDefinitionAst` nodes --> Type = 'Function'.
- Extracts `TypeDefinitionAst` nodes where `IsClass` is true --> Type = 'Class'.
- Extracts `TypeDefinitionAst` nodes where `IsEnum` is true --> Type = 'Enum'.
- For functions: checks if the name is in `$PublicFunctionNames` to set Scope.
- For classes: preserves their relative order (important for inheritance).
- For enums: no special ordering needed.
- Extracts the full extent text for each AST node, including any comment-based help
  that immediately precedes a function definition.

---

### 4.8 Test-ModuleProjectStructure

Validates that a directory has the expected module project structure.

```powershell
function Test-ModuleProjectStructure {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Path to the module root directory to validate.
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )
}
```

**Returns:** `[PSCustomObject]` with structure:

```
@{
    IsValid         = [bool]       # $true if minimum requirements are met
    ModuleName      = [string]     # Detected module name (from .psd1 filename)
    ManifestPath    = [string]     # Full path to .psd1 (or $null)
    RootModulePath  = [string]     # Full path to .psm1 (or $null)
    Errors          = [string[]]   # List of validation failures
    Warnings        = [string[]]   # List of non-critical issues
}
```

**Validation rules:**
- Exactly one .psd1 file must exist in `$Path`. (Error if 0 or 2+.)
- A .psm1 file with matching name must exist. (Error if missing.)
- The `RootModule` field in the .psd1 must reference the .psm1. (Warning if mismatch.)
- At least one of `Public/`, `Private/`, `Classes/`, `Enums/` should exist. (Warning if none.)

---

### 4.9 ConvertTo-SortedClassFileName

Generates a filename with numeric prefix for a class, preserving inheritance order.

```powershell
function ConvertTo-SortedClassFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Name of the class.
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ClassName,

        # Zero-based index representing this class's position in the inheritance
        # chain / declaration order.
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$SortIndex
    )
}
```

**Returns:** `[string]` -- Filename like `01_MyClassName.Class.ps1`.

**Behavior:**
- Formats `$SortIndex + 1` as two-digit zero-padded number.
- Returns `"{0:D2}_{1}.Class.ps1" -f ($SortIndex + 1), $ClassName`.

---

## 5. Data Flow Diagrams

### 5.1 Build Flow

```
                              Build-PSModule
                              ==============

  [Module Root]
       |
       v
  Test-ModuleProjectStructure -----> FAIL? --> Throw terminating error
       |
       | (validated)
       v
  Resolve-ModuleSourcePaths
       |
       | Returns OrderedDictionary:
       |   Enums/   --> [FileInfo[]]
       |   Classes/ --> [FileInfo[]]
       |   Private/ --> [FileInfo[]]
       |   Public/  --> [FileInfo[]]
       |
       +---------------------------+
       |                           |
       v                           v
  Get-FunctionNamesFromFile   Get-AliasesFromFile
  (for each Public/*.ps1)     (for each Public/*.ps1)
       |                           |
       | [string[]]                | [string[]]
       | FunctionNames             | AliasNames
       |                           |
       +---------------------------+
       |
       v
  Merge-SourceFiles
       |
       | [string] MergedContent
       v
  +-----------------------------+
  | Write merged .psm1          |
  | Copy .psd1 to OutputPath    |
  +-----------------------------+
       |
       v
  Update-ManifestField (FunctionsToExport)
  Update-ManifestField (AliasesToExport)
       |
       v
  Return [PSCustomObject] BuildResult
```

### 5.2 Initialize Flow

```
                          Initialize-PSModule
                          ===================

  Parameters: ModuleName, Path, Author, Description, Version
       |
       v
  Validate: $Path/$ModuleName does NOT already exist
       |
       v
  Create directory: $Path/$ModuleName/
       |
       +-- Create: Public/
       +-- Create: Private/
       +-- Create: Classes/
       +-- Create: Enums/
       |
       v
  New-DevPsm1Content($ModuleName)
       |
       | [string] Psm1Content
       v
  Write $ModuleName.psm1
       |
       v
  New-ModuleManifest
       |  Parameters:
       |    RootModule        = "$ModuleName.psm1"
       |    ModuleVersion     = $Version
       |    Author            = $Author
       |    Description       = $Description
       |    PowerShellVersion = $PowerShellVersion
       |    FunctionsToExport = @()
       |    AliasesToExport   = @()
       v
  Write $ModuleName.psd1
       |
       v
  Return [PSCustomObject] ScaffoldResult
```

### 5.3 Split Flow

```
                            Split-PSModule
                            ==============

  Parameters: Path, Force
       |
       v
  Locate .psd1 and .psm1 in $Path
       |
       v
  Read FunctionsToExport from .psd1
       |
       | [string[]] PublicFunctionNames
       v
  Split-PsFileContent($Psm1Path, $PublicFunctionNames)
       |
       | [PSCustomObject[]] CodeBlocks:
       |   { Name, Type, Scope, Content }
       |
       +----> Type = 'Enum' --------> Write to Enums/<Name>.Enum.ps1
       |
       +----> Type = 'Class' -------> ConvertTo-SortedClassFileName
       |                                   |
       |                                   v
       |                              Write to Classes/<NN>_<Name>.Class.ps1
       |
       +----> Type = 'Function'
       |      Scope = 'Public' -----> Write to Public/<Name>.ps1
       |
       +----> Type = 'Function'
              Scope = 'Private' ----> Write to Private/<Name>.ps1
              |
              v
  New-DevPsm1Content($ModuleName)
       |
       v
  Write new dev .psm1 (replaces monolithic version)
       |
       v
  Return [PSCustomObject] SplitResult
```

### 5.4 Version Flow

```
                       Update-PSModuleVersion
                       ======================

  Parameters: Path, BumpType, Tag, TagPrefix
       |
       v
  Verify Git is available (Get-Command git)
       |
       | NOT FOUND --> Throw terminating error
       v
  Read current ModuleVersion from .psd1
       |
       v
  Find latest tag: git describe --tags --abbrev=0 --match "$TagPrefix*"
       |
       | (tag found)                     (no tag found)
       v                                      v
  git log $Tag..HEAD --oneline       git log --oneline
       |                                      |
       +--------------------------------------+
       |
       | [string[]] CommitMessages
       v
  Parse Conventional Commits:
       |
       |  Message matches "BREAKING CHANGE:" or "!:" --> Major
       |  Message matches "^feat(\(.+\))?:"          --> Minor
       |  Message matches "^fix(\(.+\))?:"           --> Patch
       |  No recognized pattern                      --> (no bump, warn)
       |
       |  If $BumpType is specified, skip auto-detection
       v
  Compute new version:
       |  Major: ($Current.Major + 1).0.0
       |  Minor: $Current.Major.($Current.Minor + 1).0
       |  Patch: $Current.Major.$Current.Minor.($Current.Build + 1)
       |
       v
  -WhatIf? ----YES----> Return result WITHOUT writing changes
       |
       NO
       |
       v
  Update-ManifestField(ModuleVersion, $NewVersion)
       |
       v
  -Tag? ------YES----> git tag "$TagPrefix$NewVersion"
       |
       NO
       |
       v
  Return [PSCustomObject] VersionResult
```

---

## 6. Output Object Definitions

All public functions return `[PSCustomObject]` instances with a `PSTypeName` property for
identification. This enables downstream formatting and filtering.

### 6.1 Build-PSModule Output

```powershell
[PSCustomObject]@{
    PSTypeName           = 'YFridelance.PS.ModuleFactory.BuildResult'
    ModuleName           = [string]     # e.g., 'MyModule'
    SourcePath           = [string]     # Absolute path to module root
    OutputPath           = [string]     # Absolute path to output directory
    ManifestPath         = [string]     # Absolute path to built .psd1
    RootModulePath       = [string]     # Absolute path to built .psm1
    FunctionsExported    = [string[]]   # List of exported function names
    AliasesExported      = [string[]]   # List of exported alias names
    FilesMerged          = [int]        # Total number of source files merged
    Success              = [bool]       # $true if build completed without errors
}
```

### 6.2 Initialize-PSModule Output

```powershell
[PSCustomObject]@{
    PSTypeName           = 'YFridelance.PS.ModuleFactory.ScaffoldResult'
    ModuleName           = [string]     # e.g., 'MyNewModule'
    ModulePath           = [string]     # Absolute path to created module directory
    ManifestPath         = [string]     # Absolute path to created .psd1
    RootModulePath       = [string]     # Absolute path to created .psm1
    DirectoriesCreated   = [string[]]   # e.g., @('Public', 'Private', 'Classes', 'Enums')
    Success              = [bool]
}
```

### 6.3 Split-PSModule Output

```powershell
[PSCustomObject]@{
    PSTypeName           = 'YFridelance.PS.ModuleFactory.SplitResult'
    ModuleName           = [string]
    ModulePath           = [string]
    PublicFunctions      = [string[]]   # Names of functions written to Public/
    PrivateFunctions     = [string[]]   # Names of functions written to Private/
    Classes              = [string[]]   # Names of classes written to Classes/
    Enums                = [string[]]   # Names of enums written to Enums/
    FilesCreated         = [int]        # Total count of .ps1 files written
    Success              = [bool]
}
```

### 6.4 Update-PSModuleVersion Output

```powershell
[PSCustomObject]@{
    PSTypeName           = 'YFridelance.PS.ModuleFactory.VersionResult'
    ModuleName           = [string]
    ManifestPath         = [string]
    PreviousVersion      = [version]    # e.g., 0.1.0
    NewVersion           = [version]    # e.g., 0.2.0
    BumpType             = [string]     # 'Major', 'Minor', or 'Patch'
    CommitsAnalyzed      = [int]        # Number of commits inspected
    TagCreated           = [string]     # Tag name (e.g., 'v0.2.0') or $null
    IsWhatIf             = [bool]       # $true if -WhatIf was active
    Success              = [bool]
}
```

---

## 7. Error Handling Conventions

### 7.1 Error Classification

| Category | When | Mechanism | Example |
|----------|------|-----------|---------|
| **Terminating** | Precondition failure that makes it impossible to continue | `throw` or `$PSCmdlet.ThrowTerminatingError()` | .psd1 not found, Git not installed |
| **Non-terminating** | A single item in a pipeline fails but others can proceed | `Write-Error` | One .ps1 file has parse errors during build |
| **Warning** | Unexpected but non-fatal condition | `Write-Warning` | Empty Public/ folder, no conventional commits found |
| **Verbose** | Progress/diagnostic information | `Write-Verbose` | "Processing file: Get-Something.ps1" |

### 7.2 Rules

1. **Empty catch blocks are strictly forbidden.** Every `catch` must either re-throw,
   write an error, or write a warning. At minimum, log the exception:
   ```powershell
   catch {
       Write-Error -Message "Failed to parse '$FilePath': $_" -ErrorAction Stop
   }
   ```

2. **Use `-ErrorAction Stop` on all cmdlet calls inside try blocks** to ensure exceptions
   are catchable:
   ```powershell
   try {
       $Content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
   }
   catch {
       Write-Error -Message "Cannot read file '$FilePath': $_"
   }
   ```

3. **Public functions use `$PSCmdlet.ThrowTerminatingError()` for precondition failures.**
   This produces proper PowerShell error records:
   ```powershell
   if (-not (Test-Path -Path $Path)) {
       $Exception = [System.IO.DirectoryNotFoundException]::new(
           "Module path not found: '$Path'"
       )
       $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
           $Exception,
           'ModulePathNotFound',
           [System.Management.Automation.ErrorCategory]::ObjectNotFound,
           $Path
       )
       $PSCmdlet.ThrowTerminatingError($ErrorRecord)
   }
   ```

4. **Private functions use `throw` for unrecoverable errors** since they are internal and
   the calling public function will catch and wrap them.

5. **Validate parameters declaratively** (`[ValidateScript()]`, `[ValidateSet()]`,
   `[ValidatePattern()]`) wherever possible. Prefer parameter validation over manual checks
   in the function body.

6. **All file I/O operations must be wrapped in try/catch.** File system access is
   inherently unreliable (permissions, locks, encoding issues).

### 7.3 Error Messages

Error messages must be:
- **Actionable**: Tell the user what went wrong AND what they can do about it.
- **Contextual**: Include the file path, parameter value, or module name that caused the error.
- **Not generic**: Never "An error occurred." Always specific.

Example:
```
Cannot build module 'MyModule': No .ps1 files found in 'C:\src\MyModule\Public\'.
Ensure that public function files exist in the Public subdirectory.
```

---

## 8. Configuration Handling

### 8.1 Design: No Configuration Files

YFridelance.PS.ModuleFactory does **not** use configuration files (no `.modulefactory.json`, no
YAML, no XML). All behavior is controlled through function parameters with sensible defaults.

**Rationale:**
- Keeps the module simple and dependency-free.
- No config file parsing needed -- avoids a category of bugs entirely.
- PowerShell's `$PSDefaultParameterValues` mechanism already provides user-level defaults:
  ```powershell
  $PSDefaultParameterValues['Build-PSModule:OutputPath'] = 'C:\MyBuilds'
  ```
- Module-level state is avoided to keep functions pure and testable.

### 8.2 Parameter Defaults

| Function | Parameter | Default |
|----------|-----------|---------|
| Build-PSModule | Path | `(Get-Location).Path` |
| Build-PSModule | OutputPath | `"../dist/<ModuleName>"` relative to Path |
| Build-PSModule | Clean | `$false` |
| Initialize-PSModule | Path | `(Get-Location).Path` |
| Initialize-PSModule | Author | `[System.Environment]::UserName` |
| Initialize-PSModule | Version | `0.1.0` |
| Initialize-PSModule | PowerShellVersion | `5.1` |
| Initialize-PSModule | License | `MIT` |
| Split-PSModule | Force | `$false` |
| Update-PSModuleVersion | Path | `(Get-Location).Path` |
| Update-PSModuleVersion | TagPrefix | `v` |

### 8.3 Module-Scope Constants

Defined at the top of the dev .psm1 (or at the top of the merged .psm1 during build):

```powershell
# Module-scope constants (not exported, used by private functions)
$Script:ModuleFactoryVersion = '0.1.0'
$Script:SupportedManifestFields = @(
    'FunctionsToExport'
    'AliasesToExport'
    'ModuleVersion'
    'Description'
    'Author'
)
$Script:DefaultEncoding = [System.Text.UTF8Encoding]::new($true)   # UTF-8 with BOM
$Script:LoadOrderFolders = @('Enums', 'Classes', 'Private', 'Public')
```

These are defined as `$Script:` scoped variables so they are accessible to all functions
within the module but not exported.

---

## 9. Design Decisions and Rationale

### 9.1 Why AST-based function extraction instead of regex?

**Decision:** Use `[System.Management.Automation.Language.Parser]::ParseFile()` to extract
function names and code blocks.

**Rationale:**
- Regex cannot reliably parse PowerShell function definitions (nested braces, here-strings,
  multiline signatures, string interpolation containing `function` keyword).
- The AST parser is built into PowerShell (no external dependency) and handles all edge cases.
- AST provides accurate extent information (start/end positions) for extracting complete
  function bodies including their comment-based help.
- Works identically on PowerShell 5.1 and 7+.

### 9.2 Why regex for alias extraction instead of AST?

**Decision:** Use regex to extract `# Alias: <name>` comments.

**Rationale:**
- These are plain comments, not executable code. The AST does not model comments as
  first-class nodes in a way that is convenient for extraction.
- The format `# Alias: <name>` is a simple, well-defined convention.
- A single regex `(?m)^\s*#\s*Alias\s*:\s*(.+)\s*$` handles all cases reliably.

### 9.3 Why regex-based manifest updates instead of Update-ModuleManifest?

**Decision:** Use `Update-ManifestField` (custom regex-based replacement) instead of the
built-in `Update-ModuleManifest` cmdlet.

**Rationale:**
- `Update-ModuleManifest` rewrites the entire .psd1 file, destroying comments, custom
  formatting, and any hand-edited sections.
- Our approach surgically replaces only the target field, preserving all other content.
- On PowerShell 5.1, `Update-ModuleManifest` has known bugs with certain field types.
- Regex replacement is deterministic -- the output is predictable and testable.

### 9.4 Why ordered dictionary for source paths instead of a custom class?

**Decision:** Return `[ordered]@{}` from `Resolve-ModuleSourcePaths` instead of a custom
class or multiple output objects.

**Rationale:**
- Ordered dictionaries are natively iterable in correct order (Enums, Classes, Private,
  Public) which maps directly to the merge loop.
- No custom class definition needed -- keeps the module simpler.
- `[ordered]@{}` works identically on PowerShell 5.1 and 7+.
- Easy to test: `$Result.Keys | Should -Be @('Enums', 'Classes', 'Private', 'Public')`.

### 9.5 Why no configuration file?

See [Section 8.1](#81-design-no-configuration-files).

### 9.6 Why OutputPath defaults to ../dist/<ModuleName>?

**Decision:** `Build-PSModule` outputs one directory above the module root by default.

**Rationale:**
- The built module cannot be placed inside its own source tree (that would mix dev and
  dist artifacts, confuse `Import-Module`, and risk being picked up by subsequent builds).
- `../dist/<ModuleName>` is a common convention (similar to `dotnet publish`, `npm build`).
- The `dist/` directory sits at repository root, next to `Tests/` and other repo-level
  directories, which is an intuitive location.

### 9.7 Why SupportsShouldProcess on public functions?

**Decision:** All public functions that write to the file system declare
`SupportsShouldProcess = $true`.

**Rationale:**
- PowerShell best practice: any function that modifies system state should support
  `-WhatIf` and `-Confirm`.
- Enables users to preview changes before committing (`Build-PSModule -WhatIf`).
- `Update-PSModuleVersion -WhatIf` is explicitly required (show version bump without
  applying it).
- `ConfirmImpact = 'High'` on `Split-PSModule` because it can overwrite existing files.
- `ConfirmImpact = 'Medium'` on other functions as a balanced default.

### 9.8 Why PSCustomObject return types instead of strings or void?

**Decision:** All public functions return structured `[PSCustomObject]` results with
`PSTypeName` properties.

**Rationale:**
- Pipeline-friendly: results can be piped to `Format-Table`, `Select-Object`, `Where-Object`.
- Testable: assertions can target specific properties (`$Result.Success | Should -Be $true`).
- `PSTypeName` enables custom formatting via `.format.ps1xml` files in the future without
  breaking existing behavior.
- Composable: build results can feed into deployment scripts, version results into CI logic.
- Avoids Write-Host pollution that is uncapturable in pipelines.

### 9.9 Why dual compatibility (5.1 + 7+)?

**Decision:** Support both Windows PowerShell 5.1 and PowerShell 7+.

**Rationale:**
- Many enterprise environments still run Windows PowerShell 5.1 exclusively.
- A module-building tool should not impose a higher runtime requirement than the modules
  it builds (which may target 5.1).
- The AST parser, `[ordered]@{}`, `[System.IO.FileInfo]`, and all core features used in
  this module work identically on both versions.
- Where version-specific behavior exists (e.g., encoding parameter differences on
  `Set-Content`), use `$PSVersionTable.PSVersion.Major` guards.

### 9.10 Why the module folder is nested (repo/YFridelance.PS.ModuleFactory/) instead of at root?

**Decision:** The importable module lives in a subdirectory, not at the repository root.

**Rationale:**
- Separates repo infrastructure (Tests/, .github/, README.md) from module content.
- `Import-Module ./YFridelance.PS.ModuleFactory` works cleanly.
- The build output in `dist/` contains only the module folder -- ready to publish to
  PowerShell Gallery without filtering out repo-level files.
- Standard convention in the PowerShell community for non-trivial modules.

---

## 10. Compatibility Strategy

### 10.1 Version Detection Pattern

```powershell
$IsPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
```

### 10.2 Known Compatibility Points

| Feature | PowerShell 5.1 | PowerShell 7+ | Strategy |
|---------|----------------|---------------|----------|
| File encoding (Set-Content) | `-Encoding UTF8` (no BOM) | `-Encoding utf8BOM` | Version guard: use `[System.IO.File]::WriteAllText()` with `$Script:DefaultEncoding` for consistent BOM behavior |
| Null-coalescing `??` | Not supported | Supported | Do not use. Use `if ($null -eq $X) { $Default } else { $X }` |
| Ternary `? :` | Not supported | Supported | Do not use. Use `if/else` |
| Pipeline chain `&&` | Not supported | Supported | Do not use. Use semicolons or separate statements |
| `Get-Content -AsByteStream` | Not available (use `-Encoding Byte`) | Available | Version guard if needed |
| `Join-Path` with 3+ args | Not supported | Supported | Chain calls: `Join-Path (Join-Path $A $B) $C` |
| AST Parser | Fully supported | Fully supported | No guard needed |
| `[ordered]@{}` | Supported | Supported | No guard needed |
| `New-ModuleManifest` | Supported | Supported | No guard needed |

### 10.3 File Writing Helper Pattern

All file write operations should use this pattern for consistent encoding:

```powershell
# Use .NET method for guaranteed UTF-8 with BOM on both PS versions
[System.IO.File]::WriteAllText($FilePath, $Content, $Script:DefaultEncoding)
```

This avoids the encoding parameter differences between PowerShell 5.1 and 7+.

---

## 11. Coding Standards Quick Reference

This section summarizes the standards that all implementation agents must follow.

### 11.1 Naming

| Element | Convention | Example |
|---------|------------|---------|
| Variables | PascalCase, descriptive | `$ModuleRoot`, `$FunctionNames` |
| Boolean variables | Is/Has/Can prefix | `$IsValid`, `$HasErrors` |
| Collection variables | Plural | `$Files`, `$FunctionNames` |
| Functions (public) | Verb-Noun, approved verbs | `Build-PSModule` |
| Functions (private) | Verb-Noun, approved verbs | `Get-FunctionNamesFromFile` |
| Parameters | PascalCase | `$ModuleName`, `$OutputPath` |
| Script-scope vars | $Script: prefix | `$Script:DefaultEncoding` |

### 11.2 Formatting

- **Indentation:** 4 spaces (no tabs).
- **Line length:** Target ~120 characters maximum.
- **One statement per line.**
- **Braces:** Opening brace on the same line as the statement:
  ```powershell
  if ($Condition) {
      # body
  }
  ```
- **Splatting:** Use when passing 4 or more parameters to a cmdlet:
  ```powershell
  $Params = @{
      Path        = $FilePath
      Value       = $Content
      Encoding    = 'UTF8'
      Force       = $true
      NoNewline   = $true
  }
  Set-Content @Params
  ```

### 11.3 Documentation

Every public function must include comment-based help **inside** the function body:

```powershell
function Build-PSModule {
    <#
    .SYNOPSIS
        Builds a PowerShell module from dev structure into a distributable package.

    .DESCRIPTION
        Merges all source files (Enums, Classes, Private, Public) into a single
        .psm1 file in the correct load order. Updates the module manifest with
        exported function names and aliases.

    .PARAMETER Path
        Path to the module root directory containing the .psd1 and source folders.

    .EXAMPLE
        Build-PSModule -Path 'C:\src\MyModule'

        Builds MyModule and outputs to C:\src\dist\MyModule\.

    .EXAMPLE
        Build-PSModule -Path 'C:\src\MyModule' -OutputPath 'C:\publish\MyModule' -Clean

        Builds MyModule to a custom output path, cleaning the output directory first.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param( ... )
}
```

### 11.4 File Encoding

- All `.ps1` and `.psm1` files: **UTF-8 with BOM** (required for Windows PowerShell
  compatibility with special characters).
- All `.psd1` files: **UTF-8 with BOM** (same reason, plus `New-ModuleManifest` uses this
  by default on Windows).
- Use `$Script:DefaultEncoding` (`[System.Text.UTF8Encoding]::new($true)`) for all write
  operations.

### 11.5 Line Endings

- All source files use **CRLF** (`\r\n`) line endings.
- When generating file content programmatically, use `[System.Environment]::NewLine` or
  explicitly use `` "`r`n" ``.
- Git should be configured with `core.autocrlf = true` or a `.gitattributes` file:
  ```
  *.ps1  text eol=crlf
  *.psm1 text eol=crlf
  *.psd1 text eol=crlf
  ```

---

## Appendix A: File Naming Conventions for Target Modules

These are the conventions that YFridelance.PS.ModuleFactory enforces when creating or splitting
module files:

| File Type | Pattern | Example |
|-----------|---------|---------|
| Public function | `<FunctionName>.ps1` | `Get-Something.ps1` |
| Private function | `<FunctionName>.ps1` | `Invoke-InternalHelper.ps1` |
| Class | `<NN>_<ClassName>.Class.ps1` | `01_BaseClass.Class.ps1` |
| Enum | `<EnumName>.Enum.ps1` | `Status.Enum.ps1` |
| Dev root module | `<ModuleName>.psm1` | `MyModule.psm1` |
| Manifest | `<ModuleName>.psd1` | `MyModule.psd1` |

Where `<NN>` is a two-digit zero-padded number (01-99) representing load order.

---

## Appendix B: Conventional Commits Patterns

`Update-PSModuleVersion` recognizes these patterns when parsing Git commit messages:

| Pattern | Bump | Regex |
|---------|------|-------|
| `fix:` or `fix(scope):` | Patch | `^fix(\(.+\))?!?:` |
| `feat:` or `feat(scope):` | Minor | `^feat(\(.+\))?!?:` |
| `BREAKING CHANGE:` in footer | Major | `BREAKING CHANGE:` (anywhere in message body) |
| `feat!:` or `fix!:` (bang) | Major | `^[a-z]+(\(.+\))?!:` |
| Other types: `docs:`, `chore:`, `refactor:`, `test:`, `style:`, `ci:`, `perf:`, `build:` | None | Recognized but do not trigger a version bump |

The highest bump type wins. If any commit requires Major, the bump is Major regardless of
other commits. Similarly, Minor beats Patch.

Priority: **Major > Minor > Patch > None**.

If no version-bumping commits are found and `$BumpType` is not specified, the function
writes a warning and returns without making changes (unless `-BumpType` is explicitly
provided to force a bump).

---

*End of ARCHITECTURE.md*
