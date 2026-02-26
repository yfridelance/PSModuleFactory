function Split-PSModule {
    <#
    .SYNOPSIS
        Splits a monolithic .psm1 file into individual source files organized by type and scope.

    .DESCRIPTION
        Split-PSModule analyzes an existing PowerShell module's .psm1 file and extracts each
        function, class, and enum into its own individual .ps1 file under the appropriate
        subdirectory (Public, Private, Classes, or Enums). The function uses AST-based parsing
        to identify code blocks and cross-references the module manifest's FunctionsToExport list
        to determine public vs. private scope.

        After splitting, a new development-mode .psm1 is generated that dot-sources all the
        individual files, replacing the original monolithic .psm1.

        Existing files are skipped (with a non-terminating error) unless -Force is specified.

    .PARAMETER Path
        The root directory of the PowerShell module to split. Must contain exactly one .psd1
        manifest file and a matching .psm1 file.

    .PARAMETER Force
        When specified, overwrites existing .ps1 files in the target subdirectories. Without this
        switch, existing files are skipped and a non-terminating error is written for each conflict.

    .EXAMPLE
        Split-PSModule -Path 'C:\Projects\MyModule'

        Splits the monolithic MyModule.psm1 into individual files. Existing files are preserved
        (a warning is written for each conflict).

    .EXAMPLE
        Split-PSModule -Path 'C:\Projects\MyModule' -Force -Verbose

        Splits the module and overwrites any existing individual source files, with verbose
        progress output for each operation.

    .OUTPUTS
        [PSCustomObject] with PSTypeName 'yvfrii.PS.ModuleFactory.SplitResult'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path,

        [Parameter()]
        [switch]$Force
    )

    # -------------------------------------------------------------------------
    # Step 1: Locate exactly one .psd1 in $Path
    # -------------------------------------------------------------------------
    Write-Verbose "Searching for module manifest (.psd1) in: $Path"
    $ManifestFiles = @(Get-ChildItem -Path $Path -Filter '*.psd1' -File -ErrorAction SilentlyContinue)

    if ($ManifestFiles.Count -eq 0) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new(
                "No module manifest (.psd1) found in '$Path'."
            ),
            'ManifestNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    if ($ManifestFiles.Count -gt 1) {
        $Names = ($ManifestFiles | ForEach-Object { $_.Name }) -join ', '
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Multiple module manifests found in '$Path': $Names. Exactly one .psd1 is required."
            ),
            'MultipleManifestsFound',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $ManifestFile = $ManifestFiles[0]
    $ModuleName = [System.IO.Path]::GetFileNameWithoutExtension($ManifestFile.Name)
    $ManifestPath = $ManifestFile.FullName
    Write-Verbose "Found manifest: $ManifestPath (module name: $ModuleName)"

    # -------------------------------------------------------------------------
    # Step 2: Locate matching .psm1
    # -------------------------------------------------------------------------
    $Psm1Path = Join-Path -Path $Path -ChildPath "$ModuleName.psm1"
    Write-Verbose "Looking for .psm1 at: $Psm1Path"

    if (-not (Test-Path -Path $Psm1Path -PathType Leaf)) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new(
                "Module root file '$Psm1Path' not found. Expected '$ModuleName.psm1' alongside the manifest."
            ),
            'RootModuleNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Psm1Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    Write-Verbose "Found .psm1: $Psm1Path"

    # -------------------------------------------------------------------------
    # Step 3: Read FunctionsToExport from manifest
    # -------------------------------------------------------------------------
    Write-Verbose "Reading FunctionsToExport from manifest..."
    $ExportedFunctions = @()
    try {
        $ManifestData = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
        if ($ManifestData.FunctionsToExport) {
            $ExportedFunctions = @($ManifestData.FunctionsToExport | Where-Object { $_ -and $_ -ne '*' })
        }
        Write-Verbose "Exported functions from manifest: $($ExportedFunctions -join ', ')"
    }
    catch {
        Write-Warning "Could not read FunctionsToExport from manifest; all functions will be treated as Private. Error: $($_.Exception.Message)"
    }

    # -------------------------------------------------------------------------
    # Step 4: Split .psm1 into code blocks
    # -------------------------------------------------------------------------
    Write-Verbose "Splitting .psm1 content into code blocks..."
    try {
        $CodeBlocks = Split-PsFileContent -FilePath $Psm1Path -PublicFunctionNames $ExportedFunctions -ErrorAction Stop
    }
    catch {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Failed to split .psm1 content: $($_.Exception.Message)"
            ),
            'PsFileContentSplitFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Psm1Path
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    Write-Verbose "Code blocks found: $($CodeBlocks.Count)"

    # -------------------------------------------------------------------------
    # Step 5: Create subdirectories if needed
    # -------------------------------------------------------------------------
    $SubDirectories = @('Public', 'Private', 'Classes', 'Enums')
    foreach ($SubDir in $SubDirectories) {
        $SubDirPath = Join-Path -Path $Path -ChildPath $SubDir
        if (-not (Test-Path -Path $SubDirPath -PathType Container)) {
            Write-Verbose "Creating subdirectory: $SubDirPath"
            if ($PSCmdlet.ShouldProcess($SubDirPath, 'Create subdirectory')) {
                try {
                    New-Item -Path $SubDirPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Created: $SubDirPath"
                }
                catch {
                    Write-Warning "Failed to create subdirectory '$SubDirPath': $($_.Exception.Message)"
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 6: Write individual code block files
    # -------------------------------------------------------------------------
    $PublicFunctions = @()
    $PrivateFunctions = @()
    $Classes = @()
    $Enums = @()
    $FilesCreated = 0

    # Track class index for sorting
    $ClassIndex = 0

    foreach ($Block in $CodeBlocks) {
        $BlockName = $Block.Name
        $BlockType = $Block.Type
        $BlockScope = $Block.Scope
        $BlockContent = $Block.Content

        # Determine target path based on type and scope
        $TargetDir = $null
        $FileName = $null

        if ($BlockType -eq 'Enum') {
            $TargetDir = Join-Path -Path $Path -ChildPath 'Enums'
            $FileName = "$BlockName.Enum.ps1"
            $Enums += $BlockName
        }
        elseif ($BlockType -eq 'Class') {
            $TargetDir = Join-Path -Path $Path -ChildPath 'Classes'
            $FileName = ConvertTo-SortedClassFileName -ClassName $BlockName -SortIndex $ClassIndex
            $ClassIndex++
            $Classes += $BlockName
        }
        elseif ($BlockType -eq 'Function') {
            if ($BlockScope -eq 'Public') {
                $TargetDir = Join-Path -Path $Path -ChildPath 'Public'
                $FileName = "$BlockName.ps1"
                $PublicFunctions += $BlockName
            }
            else {
                $TargetDir = Join-Path -Path $Path -ChildPath 'Private'
                $FileName = "$BlockName.ps1"
                $PrivateFunctions += $BlockName
            }
        }
        else {
            Write-Warning "Unknown block type '$BlockType' for '$BlockName'; skipping."
            continue
        }

        $TargetFilePath = Join-Path -Path $TargetDir -ChildPath $FileName

        # Check for existing file
        if (Test-Path -Path $TargetFilePath -PathType Leaf) {
            if (-not $Force) {
                Write-Error "File already exists at '$TargetFilePath'. Use -Force to overwrite."
                continue
            }
            Write-Verbose "Overwriting existing file (Force): $TargetFilePath"
        }

        Write-Verbose "Writing $BlockType '$BlockName' to: $TargetFilePath"
        if ($PSCmdlet.ShouldProcess($TargetFilePath, "Write $BlockType source file '$BlockName'")) {
            try {
                [System.IO.File]::WriteAllText($TargetFilePath, $BlockContent, $Script:DefaultEncoding)
                $FilesCreated++
                Write-Verbose "Written: $TargetFilePath"
            }
            catch {
                Write-Error "Failed to write '$TargetFilePath': $($_.Exception.Message)"
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 7: Generate new dev .psm1 and overwrite existing
    # -------------------------------------------------------------------------
    Write-Verbose "Generating new dev .psm1 to replace monolithic file..."
    try {
        $NewDevContent = New-DevPsm1Content -ModuleName $ModuleName -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to generate dev .psm1 content: $($_.Exception.Message)"
        $NewDevContent = $null
    }

    if ($NewDevContent) {
        Write-Verbose "Overwriting .psm1 with dev loader: $Psm1Path"
        if ($PSCmdlet.ShouldProcess($Psm1Path, 'Overwrite .psm1 with dev dot-source loader')) {
            try {
                [System.IO.File]::WriteAllText($Psm1Path, $NewDevContent, $Script:DefaultEncoding)
                Write-Verbose "Written dev .psm1: $Psm1Path"
            }
            catch {
                Write-Warning "Failed to overwrite .psm1 at '$Psm1Path': $($_.Exception.Message)"
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 8: Return SplitResult
    # -------------------------------------------------------------------------
    $SplitResult = [PSCustomObject]@{
        PSTypeName       = 'yvfrii.PS.ModuleFactory.SplitResult'
        ModuleName       = $ModuleName
        ModulePath       = $Path
        PublicFunctions  = [string[]]$PublicFunctions
        PrivateFunctions = [string[]]$PrivateFunctions
        Classes          = [string[]]$Classes
        Enums            = [string[]]$Enums
        FilesCreated     = $FilesCreated
        Success          = $true
    }

    Write-Verbose "Split completed. Files created: $FilesCreated"
    return $SplitResult
}
