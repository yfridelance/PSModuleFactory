function Merge-SourceFiles {
    <#
    .SYNOPSIS
        Merges ordered PowerShell source files into a single monolithic script string.

    .DESCRIPTION
        Accepts an ordered dictionary (as produced by Resolve-ModuleSourcePaths) whose keys
        are section names (Enums, Classes, Private, Public) and whose values are arrays of
        [System.IO.FileInfo] objects.

        For each non-empty section a region header comment is emitted:
            #region ======== SectionName ========

        For each file within a section, a per-file region is emitted:
            #region FileName
            <file content, with dot-source lines stripped>
            #endregion FileName

        A closing region comment for the section is appended after all its files:
            #endregion ======== SectionName ========

        Dot-source lines (matching ^\s*\.\s+.*\.ps1) are removed from the merged output so
        that the resulting .psm1 does not attempt to dot-source files at runtime.

        All line endings in the output are normalised to CRLF.

    .PARAMETER SourcePaths
        An ordered dictionary whose keys are section names and whose values are
        [System.IO.FileInfo[]] arrays, as returned by Resolve-ModuleSourcePaths.

    .EXAMPLE
        $Paths  = Resolve-ModuleSourcePaths -ModuleRoot 'C:\MyModule'
        $Merged = Merge-SourceFiles -SourcePaths $Paths
        [System.IO.File]::WriteAllText('C:\MyModule\MyModule.psm1', $Merged, $Script:DefaultEncoding)

    .EXAMPLE
        $Paths  = Resolve-ModuleSourcePaths -ModuleRoot $PSScriptRoot
        Merge-SourceFiles -SourcePaths $Paths | Out-File -FilePath 'merged.psm1' -Encoding utf8
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.Specialized.OrderedDictionary]$SourcePaths
    )

    Write-Verbose "Merge-SourceFiles: Beginning merge of source sections."

    $DotSourcePattern = '(?m)^\s*\.\s+.*\.ps1\s*$'
    $Builder          = [System.Text.StringBuilder]::new()

    foreach ($Section in $SourcePaths.Keys) {
        $Files = $SourcePaths[$Section]

        if ($null -eq $Files -or $Files.Count -eq 0) {
            Write-Verbose "  [$Section] No files — skipping section."
            continue
        }

        Write-Verbose "  [$Section] Merging $($Files.Count) file(s)."

        [void]$Builder.Append("#region ======== $Section ========`r`n")

        foreach ($File in $Files) {
            $FileName = $File.Name
            Write-Verbose "    Merging file: '$($File.FullName)'"

            [void]$Builder.Append("#region $FileName`r`n")

            try {
                $RawContent = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)
            }
            catch {
                Write-Error "Merge-SourceFiles: Failed to read '$($File.FullName)': $_"
                [void]$Builder.Append("# ERROR: Could not read file '$FileName'`r`n")
                [void]$Builder.Append("#endregion $FileName`r`n")
                continue
            }

            # Strip dot-source lines
            $Cleaned = [System.Text.RegularExpressions.Regex]::Replace(
                $RawContent,
                $DotSourcePattern,
                '',
                [System.Text.RegularExpressions.RegexOptions]::Multiline
            )

            # Normalise line endings to CRLF
            # First collapse any existing CRLF to LF, then replace LF with CRLF
            $Cleaned = $Cleaned -replace "`r`n", "`n"
            $Cleaned = $Cleaned -replace "`n", "`r`n"

            # Ensure content ends with exactly one CRLF before the endregion
            $Cleaned = $Cleaned.TrimEnd("`r", "`n")

            [void]$Builder.Append($Cleaned)
            [void]$Builder.Append("`r`n")
            [void]$Builder.Append("#endregion $FileName`r`n")
        }

        [void]$Builder.Append("#endregion ======== $Section ========`r`n")
        [void]$Builder.Append("`r`n")
    }

    $Result = $Builder.ToString()
    Write-Verbose "Merge-SourceFiles: Merge complete. Total length: $($Result.Length) chars."
    return $Result
}
