function Resolve-ModuleSourcePaths {
    <#
    .SYNOPSIS
        Resolves and returns ordered source file paths for a PowerShell module project.

    .DESCRIPTION
        Scans the given module root directory for the four canonical source subdirectories
        (Enums, Classes, Private, Public) and returns an ordered dictionary mapping each
        section name to a sorted array of [System.IO.FileInfo] objects.

        Enums/*.Enum.ps1 and Classes/*.Class.ps1 files are sorted by numeric prefix
        (e.g. 01_, 02_). Files without a numeric prefix are appended after prefixed files,
        sorted alphabetically. Private and Public files are sorted strictly alphabetically.

        Directories that do not exist are silently skipped; their corresponding value in the
        returned dictionary will be an empty [System.IO.FileInfo[]] array.

    .PARAMETER ModuleRoot
        The root directory of the PowerShell module project to inspect.

    .EXAMPLE
        $Paths = Resolve-ModuleSourcePaths -ModuleRoot 'C:\MyModule'
        $Paths['Public']  # Returns [System.IO.FileInfo[]] for Public/*.ps1

    .EXAMPLE
        $Paths = Resolve-ModuleSourcePaths -ModuleRoot $PSScriptRoot
        foreach ($Section in $Paths.Keys) {
            Write-Host "$Section : $($Paths[$Section].Count) file(s)"
        }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ModuleRoot
    )

    Write-Verbose "Resolve-ModuleSourcePaths: ModuleRoot='$ModuleRoot'"

    $Result = [System.Collections.Specialized.OrderedDictionary]::new()
    $EmptyFileInfoArray = [System.IO.FileInfo[]]@()

    foreach ($Section in $Script:LoadOrderFolders) {
        $Result[$Section] = $EmptyFileInfoArray
    }

    # Determine file pattern per section
    $SectionPatterns = @{
        Enums   = '*.Enum.ps1'
        Classes = '*.Class.ps1'
        Private = '*.ps1'
        Public  = '*.ps1'
    }

    foreach ($Section in $Script:LoadOrderFolders) {
        $SectionDir = Join-Path -Path $ModuleRoot -ChildPath $Section

        if (-not (Test-Path -Path $SectionDir -PathType Container)) {
            Write-Verbose "  [$Section] Directory not found, skipping: '$SectionDir'"
            continue
        }

        $Pattern = $SectionPatterns[$Section]
        Write-Verbose "  [$Section] Scanning '$SectionDir' for pattern '$Pattern'"

        try {
            $GetChildItemParams = @{
                Path    = $SectionDir
                Filter  = $Pattern
                File    = $true
                Recurse = $false
            }
            $RawFiles = Get-ChildItem @GetChildItemParams -ErrorAction Stop
        }
        catch {
            Write-Error "Resolve-ModuleSourcePaths: Failed to enumerate '$SectionDir': $_"
            continue
        }

        if ($null -eq $RawFiles -or $RawFiles.Count -eq 0) {
            Write-Verbose "  [$Section] No files found."
            continue
        }

        if ($Section -eq 'Enums' -or $Section -eq 'Classes') {
            # Sort by numeric prefix (01_, 02_, ...), then non-prefixed alphabetically after
            $Prefixed    = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            $NonPrefixed = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

            foreach ($File in $RawFiles) {
                if ($File.Name -match '^(\d+)_') {
                    $Prefixed.Add($File)
                }
                else {
                    $NonPrefixed.Add($File)
                }
            }

            $SortedPrefixed    = $Prefixed    | Sort-Object -Property { if ($_.Name -match '^(\d+)_') { [int]$Matches[1] } else { [int]::MaxValue } }
            $SortedNonPrefixed = $NonPrefixed | Sort-Object -Property Name

            $Sorted = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            foreach ($F in $SortedPrefixed)    { $Sorted.Add($F) }
            foreach ($F in $SortedNonPrefixed) { $Sorted.Add($F) }

            $Result[$Section] = $Sorted.ToArray()
        }
        else {
            # Private / Public: strict alphabetical
            $Result[$Section] = ($RawFiles | Sort-Object -Property Name)
        }

        Write-Verbose "  [$Section] Resolved $($Result[$Section].Count) file(s)."
    }

    return $Result
}
