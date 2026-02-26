function Test-ModuleProjectStructure {
    <#
    .SYNOPSIS
        Validates the structure of a PowerShell module project directory.

    .DESCRIPTION
        Inspects the given path for the required artefacts of a well-formed PowerShell module
        project and returns a structured result object describing whether the project is valid,
        along with any errors or warnings found.

        Validation rules (errors — cause IsValid = $false):
        - The directory must exist.
        - Exactly one .psd1 manifest file must be present at the root.
        - A .psm1 file whose base name matches the manifest's base name must exist.
        - The RootModule field inside the manifest must reference a file that exists.

        Warnings (non-fatal, collected into Warnings[]):
        - No source subdirectories (Enums, Classes, Private, Public) were found.
        - The RootModule field value does not match the name of the .psm1 file found
          (e.g. it points to a compiled .psm1 in a different location).

    .PARAMETER Path
        The root directory of the module project to inspect.

    .EXAMPLE
        $Result = Test-ModuleProjectStructure -Path 'C:\MyModule'
        if ($Result.IsValid) {
            Write-Host "Module '$($Result.ModuleName)' looks good."
        } else {
            $Result.Errors | ForEach-Object { Write-Warning $_ }
        }

    .EXAMPLE
        Test-ModuleProjectStructure -Path $PSScriptRoot -Verbose |
            Select-Object IsValid, ModuleName, Errors, Warnings
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    Write-Verbose "Test-ModuleProjectStructure: Validating '$Path'"

    $Errors   = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()

    # Resolve to absolute path
    try {
        $ResolvedPath = (Resolve-Path -Path $Path -ErrorAction Stop).Path
    }
    catch {
        $Errors.Add("Directory '$Path' does not exist or cannot be resolved.")
        return [PSCustomObject]@{
            IsValid        = $false
            ModuleName     = $null
            ManifestPath   = $null
            RootModulePath = $null
            Errors         = [string[]]$Errors.ToArray()
            Warnings       = [string[]]$Warnings.ToArray()
        }
    }

    if (-not (Test-Path -Path $ResolvedPath -PathType Container)) {
        $Errors.Add("'$ResolvedPath' exists but is not a directory.")
        return [PSCustomObject]@{
            IsValid        = $false
            ModuleName     = $null
            ManifestPath   = $null
            RootModulePath = $null
            Errors         = [string[]]$Errors.ToArray()
            Warnings       = [string[]]$Warnings.ToArray()
        }
    }

    # Find .psd1 files at the root level
    try {
        $ManifestFiles = Get-ChildItem -Path $ResolvedPath -Filter '*.psd1' -File -Recurse:$false -ErrorAction Stop
    }
    catch {
        $Errors.Add("Failed to enumerate .psd1 files in '$ResolvedPath': $_")
        $ManifestFiles = @()
    }

    if ($null -eq $ManifestFiles -or $ManifestFiles.Count -eq 0) {
        $Errors.Add("No .psd1 manifest file found in '$ResolvedPath'.")
    }
    elseif ($ManifestFiles.Count -gt 1) {
        $Names = ($ManifestFiles | ForEach-Object { $_.Name }) -join ', '
        $Errors.Add("Multiple .psd1 manifest files found in '$ResolvedPath': $Names. Expected exactly one.")
    }

    # If we have errors so far we cannot determine module name reliably
    if ($Errors.Count -gt 0) {
        return [PSCustomObject]@{
            IsValid        = $false
            ModuleName     = $null
            ManifestPath   = $null
            RootModulePath = $null
            Errors         = [string[]]$Errors.ToArray()
            Warnings       = [string[]]$Warnings.ToArray()
        }
    }

    $ManifestFile = $ManifestFiles[0]
    $ModuleName   = $ManifestFile.BaseName
    $ManifestPath = $ManifestFile.FullName

    Write-Verbose "  Manifest found: '$ManifestPath' (ModuleName='$ModuleName')"

    # Check for matching .psm1
    $ExpectedPsm1Name = "$ModuleName.psm1"
    $ExpectedPsm1Path = Join-Path -Path $ResolvedPath -ChildPath $ExpectedPsm1Name

    $HasPsm1 = Test-Path -Path $ExpectedPsm1Path -PathType Leaf

    if (-not $HasPsm1) {
        $Errors.Add("Expected root module file '$ExpectedPsm1Path' does not exist.")
    }
    else {
        Write-Verbose "  Root module file found: '$ExpectedPsm1Path'"
    }

    # Read manifest and validate RootModule field
    $RootModuleValue = $null
    $RootModulePath  = $null

    try {
        $ManifestText = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)

        # Extract RootModule value via regex (handles 'value' or "value")
        $RmMatch = [System.Text.RegularExpressions.Regex]::Match(
            $ManifestText,
            "(?m)^\s*RootModule\s*=\s*['""]([^'""]+)['""]"
        )

        if ($RmMatch.Success) {
            $RootModuleValue = $RmMatch.Groups[1].Value.Trim()
            Write-Verbose "  RootModule field value: '$RootModuleValue'"

            # Resolve RootModule path (may be relative to manifest directory)
            if ([System.IO.Path]::IsPathRooted($RootModuleValue)) {
                $RootModulePath = $RootModuleValue
            }
            else {
                $RootModulePath = Join-Path -Path $ResolvedPath -ChildPath $RootModuleValue
            }

            if (-not (Test-Path -Path $RootModulePath -PathType Leaf)) {
                $Errors.Add("RootModule '$RootModuleValue' specified in manifest does not exist at '$RootModulePath'.")
                $RootModulePath = $null
            }
            else {
                # Warning if RootModule doesn't match the expected .psm1 name
                $RootModuleBaseName = [System.IO.Path]::GetFileName($RootModulePath)
                if ($RootModuleBaseName -ne $ExpectedPsm1Name) {
                    $Warnings.Add(
                        "RootModule '$RootModuleValue' does not match the expected file '$ExpectedPsm1Name'. " +
                        "Ensure this is intentional."
                    )
                }
            }
        }
        else {
            $Warnings.Add("RootModule field not found or could not be parsed in '$ManifestPath'.")
        }
    }
    catch {
        $Errors.Add("Failed to read or parse manifest '$ManifestPath': $_")
    }

    # Check for source subdirectories (warning only)
    $SourceSubdirs      = $Script:LoadOrderFolders
    $HasSourceSubdirs   = $false

    foreach ($SubDir in $SourceSubdirs) {
        $SubDirPath = Join-Path -Path $ResolvedPath -ChildPath $SubDir
        if (Test-Path -Path $SubDirPath -PathType Container) {
            $HasSourceSubdirs = $true
            break
        }
    }

    if (-not $HasSourceSubdirs) {
        $Warnings.Add(
            "No source subdirectories (Enums, Classes, Private, Public) found under '$ResolvedPath'. " +
            "This may be intentional for a single-file module."
        )
    }

    $IsValid = $Errors.Count -eq 0

    Write-Verbose "Test-ModuleProjectStructure: Validation complete. IsValid=$IsValid, Errors=$($Errors.Count), Warnings=$($Warnings.Count)"

    return [PSCustomObject]@{
        IsValid        = $IsValid
        ModuleName     = $ModuleName
        ManifestPath   = $ManifestPath
        RootModulePath = $RootModulePath
        Errors         = [string[]]$Errors.ToArray()
        Warnings       = [string[]]$Warnings.ToArray()
    }
}
