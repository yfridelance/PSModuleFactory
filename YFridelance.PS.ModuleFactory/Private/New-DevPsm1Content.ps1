function New-DevPsm1Content {
    <#
    .SYNOPSIS
        Generates the content for a development .psm1 file that dot-sources all source files dynamically.

    .DESCRIPTION
        Creates a PowerShell module script (.psm1) suitable for use during development. Instead of
        containing merged/compiled code, the generated script dynamically discovers and dot-sources
        all source files at load time, allowing live edits to individual source files without a
        rebuild step.

        The generated script respects the canonical load order:
            1. Enums    (*.Enum.ps1)
            2. Classes  (*.Class.ps1)
            3. Private  (*.ps1)
            4. Public   (*.ps1)

        For each section, the script:
        - Checks whether the folder exists before trying to load from it.
        - Uses Get-ChildItem with the appropriate file filter.
        - Sorts files so that numerically-prefixed files (Enums, Classes) are loaded in numeric order,
          and Private/Public files are sorted alphabetically.
        - Dot-sources each file found.

        All line endings in the returned string are CRLF.

    .PARAMETER ModuleName
        The name of the module, used for comment headers and verbose messages in the generated script.

    .EXAMPLE
        $Content = New-DevPsm1Content -ModuleName 'MyCompany.PS.Utilities'
        [System.IO.File]::WriteAllText(
            'C:\MyModule\MyModule.psm1',
            $Content,
            [System.Text.UTF8Encoding]::new($true)
        )

    .EXAMPLE
        New-DevPsm1Content -ModuleName 'Acme.PS.Tools' -Verbose |
            Out-File -FilePath 'Acme.PS.Tools.psm1' -Encoding utf8BOM
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ModuleName
    )

    Write-Verbose "New-DevPsm1Content: Generating dev .psm1 for module '$ModuleName'"

    # Helper: indents a block of text by a given number of spaces
    # (used to keep the here-string construction readable)

    $Lines = [System.Collections.Generic.List[string]]::new()

    # File header
    $Lines.Add("#Requires -Version 5.1")
    $Lines.Add("# ============================================================")
    $Lines.Add("# $ModuleName  —  DEVELOPMENT .psm1 (auto-generated)")
    $Lines.Add("# This file dot-sources all source files dynamically.")
    $Lines.Add("# Do NOT use this file in production / release builds.")
    $Lines.Add("# ============================================================")
    $Lines.Add("")

    # Section definitions: name, filter, sort strategy
    # Format: @(SectionName, Filter, SortMode)  SortMode: Numeric | Alpha
    $Sections = @(
        @{ Name = 'Enums';   Filter = '*.Enum.ps1';  Sort = 'Numeric' }
        @{ Name = 'Classes'; Filter = '*.Class.ps1'; Sort = 'Numeric' }
        @{ Name = 'Private'; Filter = '*.ps1';        Sort = 'Alpha'   }
        @{ Name = 'Public';  Filter = '*.ps1';        Sort = 'Alpha'   }
    )

    foreach ($Section in $Sections) {
        $SectionName   = $Section.Name
        $FileFilter    = $Section.Filter
        $SortMode      = $Section.Sort

        $Lines.Add("# ---- $SectionName ----")
        $Lines.Add("`$_SectionPath = Join-Path -Path `$PSScriptRoot -ChildPath '$SectionName'")
        $Lines.Add("if (Test-Path -Path `$_SectionPath -PathType Container) {")
        $Lines.Add("    Write-Verbose `"[$ModuleName] Loading $SectionName...`"")
        $Lines.Add("    `$_Files = Get-ChildItem -Path `$_SectionPath -Filter '$FileFilter' -File -Recurse:`$false -ErrorAction SilentlyContinue")
        $Lines.Add("    if (`$null -ne `$_Files -and `$_Files.Count -gt 0) {")

        if ($SortMode -eq 'Numeric') {
            # Sort: numerically-prefixed first, then alpha for the rest
            $Lines.Add("        `$_Prefixed    = `$_Files | Where-Object { `$_.Name -match '^\d+_' } |")
            $Lines.Add("                            Sort-Object -Property { if (`$_.Name -match '^(\d+)_') { [int]`$Matches[1] } }")
            $Lines.Add("        `$_NonPrefixed = `$_Files | Where-Object { `$_.Name -notmatch '^\d+_' } |")
            $Lines.Add("                            Sort-Object -Property Name")
            $Lines.Add("        `$_Sorted = @(`$_Prefixed) + @(`$_NonPrefixed)")
        }
        else {
            # Alpha sort
            $Lines.Add("        `$_Sorted = `$_Files | Sort-Object -Property Name")
        }

        $Lines.Add("        foreach (`$_File in `$_Sorted) {")
        $Lines.Add("            Write-Verbose `"[$ModuleName] Dot-sourcing: `$(`$_File.FullName)`"")
        $Lines.Add("            . `$_File.FullName")
        $Lines.Add("        }")
        $Lines.Add("    }")
        $Lines.Add("}")
        $Lines.Add("")
    }

    $Lines.Add("Write-Verbose `"[$ModuleName] Module loaded (development mode).`"")

    # Join with CRLF
    $Content = $Lines -join "`r`n"

    Write-Verbose "New-DevPsm1Content: Generated $($Lines.Count) lines."
    return $Content
}
