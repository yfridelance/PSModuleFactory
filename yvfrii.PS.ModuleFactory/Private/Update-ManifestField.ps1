function Update-ManifestField {
    <#
    .SYNOPSIS
        Updates a single field in a PowerShell module manifest (.psd1) file in place.

    .DESCRIPTION
        Reads the target .psd1 file as raw text and uses a regular expression to locate and
        replace the value of the specified field. The rest of the file content is preserved
        exactly as-is.

        Array fields (FunctionsToExport, AliasesToExport):
        - 3 or fewer items  → single-line:  @('Name1', 'Name2', 'Name3')
        - More than 3 items → multi-line:
              @(
                  'Name1',
                  'Name2',
                  ...
              )

        Scalar fields (ModuleVersion, Description, Author):
        - Written as 'value' (single-quoted string).

        The file is written back with UTF-8 BOM encoding and CRLF line endings.

    .PARAMETER ManifestPath
        Full path to the .psd1 module manifest file. The file must exist.

    .PARAMETER FieldName
        The manifest field to update. Must be one of:
        FunctionsToExport, AliasesToExport, ModuleVersion, Description, Author.

    .PARAMETER Value
        The new value for the field. For array fields, pass a [string[]] or [object[]].
        For scalar fields, pass a scalar value (string, version, etc.).

    .EXAMPLE
        Update-ManifestField -ManifestPath 'C:\MyModule\MyModule.psd1' `
                             -FieldName 'ModuleVersion' `
                             -Value '2.0.0'

    .EXAMPLE
        $Functions = @('Get-Thing', 'Set-Thing', 'Remove-Thing', 'New-Thing')
        Update-ManifestField -ManifestPath 'C:\MyModule\MyModule.psd1' `
                             -FieldName 'FunctionsToExport' `
                             -Value $Functions
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('FunctionsToExport', 'AliasesToExport', 'ModuleVersion', 'Description', 'Author')]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    Write-Verbose "Update-ManifestField: Updating '$FieldName' in '$ManifestPath'"

    # Read manifest as raw text
    try {
        $ManifestText = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Error "Update-ManifestField: Could not read manifest '$ManifestPath': $_"
        return
    }

    # Determine if this is an array field or a scalar field
    $ArrayFields = @('FunctionsToExport', 'AliasesToExport')
    $IsArrayField = $ArrayFields -contains $FieldName

    # Build replacement value string
    if ($IsArrayField) {
        $Items = @()
        if ($null -ne $Value) {
            foreach ($Item in @($Value)) {
                $Items += [string]$Item
            }
        }

        if ($Items.Count -le 3) {
            # Single-line format
            if ($Items.Count -eq 0) {
                $ValueString = "@()"
            }
            else {
                $QuotedItems = foreach ($Item in $Items) { "'$Item'" }
                $ValueString = "@(" + ($QuotedItems -join ', ') + ")"
            }
        }
        else {
            # Multi-line format — use 4-space indent inside the array
            $Lines = [System.Collections.Generic.List[string]]::new()
            $Lines.Add("@(")
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $Comma = if ($i -lt $Items.Count - 1) { "," } else { "" }
                $Lines.Add("        '$($Items[$i])'$Comma")
            }
            $Lines.Add("    )")
            $ValueString = $Lines -join "`r`n"
        }
    }
    else {
        # Scalar: single-quoted string
        $ScalarValue  = [string]$Value
        # Escape any single quotes inside the value
        $ScalarValue  = $ScalarValue -replace "'", "''"
        $ValueString  = "'$ScalarValue'"
    }

    Write-Verbose "  New value string: $ValueString"

    # Regex pattern to match the field and its current value in the .psd1
    # Handles:
    #   FieldName = 'value'
    #   FieldName = @(...)     single-line
    #   FieldName = @(         multi-line
    #       ...
    #   )
    #   FieldName = @()
    #
    # Strategy: match the key, then consume everything up to the end of the value.
    # For @(...) multi-line, we need to match across lines.

    # Pattern explanation:
    #   (?m)                  multiline
    #   ^(\s*FieldName\s*=\s*) capture the key prefix incl. whitespace and =
    #   (                      capture the value block:
    #     @\([^)]*\)           single-line @(...)  OR  @()
    #     |
    #     @\(\s*\r?\n          multi-line @( followed by newline
    #     (?:[^)]*\r?\n)*      any number of content lines
    #     \s*\)                closing paren (possibly indented)
    #     |
    #     '[^']*'              single-quoted scalar
    #   )

    $EscapedField   = [System.Text.RegularExpressions.Regex]::Escape($FieldName)

    # Pattern must handle all formats New-ModuleManifest can produce:
    #   FieldName = @('item1', 'item2')        — @() array syntax
    #   FieldName = @(                         — multi-line @() array
    #       'item1',
    #       'item2'
    #   )
    #   FieldName = 'item1', 'item2'           — bare comma-separated (New-ModuleManifest default)
    #   FieldName = 'value'                    — single scalar
    #   FieldName = "value"                    — double-quoted scalar
    #   FieldName = '*'                        — wildcard
    $Pattern = "(?m)^(\s*$EscapedField\s*=\s*)(@\([\s\S]*?\)|'[^']*'(?:\s*,\s*'[^']*')*|`"[^`"]*`")"

    $RegexOptions = [System.Text.RegularExpressions.RegexOptions]::Multiline

    $Replacement = { param($m) $m.Groups[1].Value + $ValueString }

    try {
        $UpdatedText = [System.Text.RegularExpressions.Regex]::Replace(
            $ManifestText,
            $Pattern,
            $Replacement,
            $RegexOptions
        )
    }
    catch {
        Write-Error "Update-ManifestField: Regex replacement failed for field '$FieldName': $_"
        return
    }

    # Verify that the field was found by trying to match it
    $RegexMatch = [System.Text.RegularExpressions.Regex]::Match($ManifestText, $Pattern, $RegexOptions)
    if (-not $RegexMatch.Success) {
        Write-Error ("Update-ManifestField: Field '$FieldName' was not found in '$ManifestPath'. " +
                     "Ensure the field exists and its current value format is supported.")
        return
    }

    # If the text is unchanged, the field already has the desired value — nothing to write
    if ($UpdatedText -eq $ManifestText) {
        Write-Verbose "Update-ManifestField: '$FieldName' already has the desired value. No changes needed."
        return
    }

    # Normalise line endings to CRLF
    $UpdatedText = $UpdatedText -replace "`r`n", "`n"
    $UpdatedText = $UpdatedText -replace "`n", "`r`n"

    # Write back with UTF-8 BOM
    try {
        [System.IO.File]::WriteAllText($ManifestPath, $UpdatedText, $Script:DefaultEncoding)
    }
    catch {
        Write-Error "Update-ManifestField: Failed to write updated manifest '$ManifestPath': $_"
        return
    }

    Write-Verbose "Update-ManifestField: '$FieldName' updated successfully."
}
