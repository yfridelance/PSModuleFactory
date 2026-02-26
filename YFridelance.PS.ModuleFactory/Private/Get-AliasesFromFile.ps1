function Get-AliasesFromFile {
    <#
    .SYNOPSIS
        Extracts alias declarations from a PowerShell script file using comment annotations.

    .DESCRIPTION
        Reads the given file as plain text and applies a regular expression to locate lines
        that follow the annotation convention:

            # Alias: AliasName
            # Alias: gs, gsd, Get-StuffAlias

        Each matching line may contain one or more comma-separated alias names. All names
        are trimmed of surrounding whitespace before being returned.

        The function returns a flat [string[]] array of all alias names found in the file.
        If no alias annotations are present, an empty array is returned. The function
        accepts pipeline input for the file path.

    .PARAMETER FilePath
        Full path to the .ps1 file to scan. The file must exist.

    .EXAMPLE
        Get-AliasesFromFile -FilePath 'C:\MyModule\Public\Get-Thing.ps1'
        # File contains: # Alias: gt, Get-ThingAlias
        # Returns: @('gt', 'Get-ThingAlias')

    .EXAMPLE
        Get-ChildItem -Path 'C:\MyModule\Public' -Filter '*.ps1' |
            Select-Object -ExpandProperty FullName |
            Get-AliasesFromFile
        # Returns all declared aliases from all Public .ps1 files
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath
    )

    process {
        Write-Verbose "Get-AliasesFromFile: Reading '$FilePath'"

        try {
            $FileContent = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Error "Get-AliasesFromFile: Could not read file '$FilePath': $_"
            return [string[]]@()
        }

        # Pattern: optional leading whitespace, # Alias: <values>
        $AliasPattern = '(?m)^\s*#\s*Alias\s*:\s*(.+)\s*$'
        $Matches      = [System.Text.RegularExpressions.Regex]::Matches($FileContent, $AliasPattern)

        if ($Matches.Count -eq 0) {
            Write-Verbose "Get-AliasesFromFile: No alias annotations found in '$FilePath'."
            return [string[]]@()
        }

        $AliasNames = [System.Collections.Generic.List[string]]::new()

        foreach ($Match in $Matches) {
            $RawValue = $Match.Groups[1].Value.Trim()
            Write-Verbose "  Found alias annotation value: '$RawValue'"

            # Support comma-separated list on a single annotation line
            $Parts = $RawValue -split ','
            foreach ($Part in $Parts) {
                $Trimmed = $Part.Trim()
                if ($Trimmed.Length -gt 0) {
                    Write-Verbose "    Alias: '$Trimmed'"
                    $AliasNames.Add($Trimmed)
                }
            }
        }

        Write-Verbose "Get-AliasesFromFile: Found $($AliasNames.Count) alias(es) in '$FilePath'."
        return [string[]]$AliasNames.ToArray()
    }
}
