function Build-PSModule {
    <#
    .SYNOPSIS
        Builds a PowerShell module by merging source files into a distributable package.

    .DESCRIPTION
        Build-PSModule compiles a structured PowerShell module project into a single distributable
        package. It merges all source files (Enums, Classes, Private, and Public functions) into a
        single .psm1 file, copies and updates the module manifest (.psd1) with exported functions
        and aliases, and writes the output to a distribution directory.

        The function validates the module project structure before building and provides detailed
        progress output via Write-Verbose.

    .PARAMETER Path
        The root directory of the PowerShell module project to build. Must be an existing directory.
        Defaults to the current working directory.

    .PARAMETER OutputPath
        The directory where the built module will be written. If not specified, defaults to a
        'dist/<ModuleName>' folder located one level above the module root (sibling of the module
        root directory).

    .PARAMETER Clean
        When specified, removes the existing output directory before building. Requires confirmation
        unless -Confirm:$false or -Force is used.

    .EXAMPLE
        Build-PSModule -Path 'C:\Projects\MyModule'

        Builds the module located at C:\Projects\MyModule and writes output to
        C:\Projects\dist\MyModule.

    .EXAMPLE
        Build-PSModule -Path 'C:\Projects\MyModule' -OutputPath 'C:\Artifacts\MyModule' -Clean -Verbose

        Builds the module located at C:\Projects\MyModule, removes any existing output at
        C:\Artifacts\MyModule first, then writes the build result there with verbose progress output.

    .OUTPUTS
        [PSCustomObject] with PSTypeName 'yvfrii.PS.ModuleFactory.BuildResult'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Clean
    )

    # -------------------------------------------------------------------------
    # Step 1: Validate module project structure
    # -------------------------------------------------------------------------
    Write-Verbose "Validating module structure at: $Path"
    $ValidationResult = Test-ModuleProjectStructure -Path $Path

    if (-not $ValidationResult.IsValid) {
        $ErrorMessages = $ValidationResult.Errors -join '; '
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Module structure validation failed for '$Path'. Errors: $ErrorMessages"
            ),
            'InvalidModuleStructure',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $ModuleName = $ValidationResult.ModuleName
    Write-Verbose "Module name resolved: $ModuleName"

    # -------------------------------------------------------------------------
    # Step 2: Resolve output path
    # -------------------------------------------------------------------------
    if (-not $OutputPath) {
        $ParentPath = Split-Path -Path $Path -Parent
        $DistPath = Join-Path -Path $ParentPath -ChildPath 'dist'
        $OutputPath = Join-Path -Path $DistPath -ChildPath $ModuleName
        Write-Verbose "OutputPath not specified; defaulting to: $OutputPath"
    }

    $AbsSourcePath = (Resolve-Path -Path $Path).Path
    Write-Verbose "Absolute source path: $AbsSourcePath"

    # -------------------------------------------------------------------------
    # Step 3: Clean output directory if requested
    # -------------------------------------------------------------------------
    if ($Clean -and (Test-Path -Path $OutputPath -PathType Container)) {
        Write-Verbose "Clean switch specified; removing existing output directory: $OutputPath"
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Remove existing output directory')) {
            try {
                Remove-Item -Path $OutputPath -Recurse -Force -ErrorAction Stop
                Write-Verbose "Removed output directory: $OutputPath"
            }
            catch {
                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.IOException]::new(
                        "Failed to remove existing output directory '$OutputPath': $($_.Exception.Message)"
                    ),
                    'OutputDirectoryRemovalFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $OutputPath
                )
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 4: Create output directory if it does not exist
    # -------------------------------------------------------------------------
    if (-not (Test-Path -Path $OutputPath -PathType Container)) {
        Write-Verbose "Creating output directory: $OutputPath"
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Create output directory')) {
            try {
                New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Verbose "Created output directory: $OutputPath"
            }
            catch {
                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.IOException]::new(
                        "Failed to create output directory '$OutputPath': $($_.Exception.Message)"
                    ),
                    'OutputDirectoryCreationFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $OutputPath
                )
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 5: Resolve source paths
    # -------------------------------------------------------------------------
    Write-Verbose "Resolving module source paths..."
    try {
        $SourcePaths = Resolve-ModuleSourcePaths -ModuleRoot $Path -ErrorAction Stop
    }
    catch {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Failed to resolve module source paths: $($_.Exception.Message)"
            ),
            'SourcePathResolutionFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    # -------------------------------------------------------------------------
    # Step 6 & 7: Collect function names and alias names from Public files
    # -------------------------------------------------------------------------
    $FunctionNames = @()
    $AliasNames = @()

    if ($SourcePaths.Contains('Public') -and $SourcePaths['Public'].Count -gt 0) {
        foreach ($PublicFile in $SourcePaths['Public']) {
            Write-Verbose "Extracting function names from: $($PublicFile.FullName)"
            try {
                $FileFunctions = Get-FunctionNamesFromFile -FilePath $PublicFile.FullName -ErrorAction Stop
                if ($FileFunctions) {
                    $FunctionNames += $FileFunctions
                }
            }
            catch {
                Write-Warning "Could not extract function names from '$($PublicFile.FullName)': $($_.Exception.Message)"
            }

            Write-Verbose "Extracting alias names from: $($PublicFile.FullName)"
            try {
                $FileAliases = Get-AliasesFromFile -FilePath $PublicFile.FullName -ErrorAction Stop
                if ($FileAliases) {
                    $AliasNames += $FileAliases
                }
            }
            catch {
                Write-Warning "Could not extract alias names from '$($PublicFile.FullName)': $($_.Exception.Message)"
            }
        }
    }

    Write-Verbose "Functions to export: $($FunctionNames.Count) ($($FunctionNames -join ', '))"
    Write-Verbose "Aliases to export: $($AliasNames.Count) ($($AliasNames -join ', '))"

    # -------------------------------------------------------------------------
    # Step 8: Merge source files
    # -------------------------------------------------------------------------
    Write-Verbose "Merging source files..."
    try {
        $MergedContent = Merge-SourceFiles -SourcePaths $SourcePaths -ErrorAction Stop
    }
    catch {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Failed to merge source files: $($_.Exception.Message)"
            ),
            'SourceFileMergeFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $SourcePaths
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    # -------------------------------------------------------------------------
    # Step 9: Write merged .psm1 to output
    # -------------------------------------------------------------------------
    $OutputPsm1Path = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psm1"
    Write-Verbose "Writing merged .psm1 to: $OutputPsm1Path"

    if ($PSCmdlet.ShouldProcess($OutputPsm1Path, 'Write merged .psm1 content')) {
        try {
            [System.IO.File]::WriteAllText($OutputPsm1Path, $MergedContent, $Script:DefaultEncoding)
            Write-Verbose "Written .psm1: $OutputPsm1Path"
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new(
                    "Failed to write .psm1 to '$OutputPsm1Path': $($_.Exception.Message)"
                ),
                'Psm1WriteFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $OutputPsm1Path
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # -------------------------------------------------------------------------
    # Step 10: Copy .psd1 to output directory
    # -------------------------------------------------------------------------
    $SourceManifestPath = $ValidationResult.ManifestPath
    $OutputManifestPath = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psd1"
    Write-Verbose "Copying manifest from '$SourceManifestPath' to '$OutputManifestPath'"

    if ($PSCmdlet.ShouldProcess($OutputManifestPath, 'Copy module manifest (.psd1)')) {
        try {
            Copy-Item -Path $SourceManifestPath -Destination $OutputManifestPath -Force -ErrorAction Stop
            Write-Verbose "Copied manifest to: $OutputManifestPath"
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new(
                    "Failed to copy manifest from '$SourceManifestPath' to '$OutputManifestPath': $($_.Exception.Message)"
                ),
                'ManifestCopyFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $OutputManifestPath
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # -------------------------------------------------------------------------
    # Step 11: Update FunctionsToExport and AliasesToExport in the copied manifest
    # -------------------------------------------------------------------------
    Write-Verbose "Updating FunctionsToExport in copied manifest..."
    try {
        Update-ManifestField -ManifestPath $OutputManifestPath -FieldName 'FunctionsToExport' `
            -Value $FunctionNames -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to update FunctionsToExport in manifest: $($_.Exception.Message)"
    }

    Write-Verbose "Updating AliasesToExport in copied manifest..."
    try {
        Update-ManifestField -ManifestPath $OutputManifestPath -FieldName 'AliasesToExport' `
            -Value $AliasNames -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to update AliasesToExport in manifest: $($_.Exception.Message)"
    }

    # -------------------------------------------------------------------------
    # Step 12: Count total files merged
    # -------------------------------------------------------------------------
    $FilesMerged = 0
    foreach ($Key in $SourcePaths.Keys) {
        if ($SourcePaths[$Key]) {
            $FilesMerged += $SourcePaths[$Key].Count
        }
    }
    Write-Verbose "Total files merged: $FilesMerged"

    # -------------------------------------------------------------------------
    # Step 13: Return BuildResult
    # -------------------------------------------------------------------------
    $BuildResult = [PSCustomObject]@{
        PSTypeName        = 'yvfrii.PS.ModuleFactory.BuildResult'
        ModuleName        = $ModuleName
        SourcePath        = $AbsSourcePath
        OutputPath        = $OutputPath
        ManifestPath      = $OutputManifestPath
        RootModulePath    = $OutputPsm1Path
        FunctionsExported = [string[]]$FunctionNames
        AliasesExported   = [string[]]$AliasNames
        FilesMerged       = $FilesMerged
        Success           = $true
    }

    Write-Verbose "Build completed successfully for module: $ModuleName"
    return $BuildResult
}
