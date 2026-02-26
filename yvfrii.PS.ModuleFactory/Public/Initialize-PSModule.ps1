function Initialize-PSModule {
    <#
    .SYNOPSIS
        Scaffolds a new PowerShell module project with the standard directory structure.

    .DESCRIPTION
        Initialize-PSModule creates a new PowerShell module project directory under the specified
        base path. It generates the standard folder layout (Public, Private, Classes, Enums), a
        development .psm1 file that dot-sources all source files, and a module manifest (.psd1)
        pre-configured with the provided metadata.

        The function refuses to overwrite an existing directory with the same module name and
        provides detailed progress output via Write-Verbose.

    .PARAMETER ModuleName
        The name of the new module. Must start with a letter and contain only letters, digits,
        dots, and underscores. This name is used as the folder name and the base name for the
        .psm1 and .psd1 files.

    .PARAMETER Path
        The parent directory in which the module project folder will be created. Must be an
        existing directory. Defaults to the current working directory.

    .PARAMETER Author
        The author name to embed in the module manifest. Defaults to the current OS user name.

    .PARAMETER Description
        A short description of the module written into the manifest. Defaults to an empty string.

    .PARAMETER Version
        The initial module version. Defaults to '0.1.0'.

    .PARAMETER PowerShellVersion
        The minimum PowerShell version required by the module. Defaults to '5.1'.

    .PARAMETER License
        The SPDX license identifier to embed as LicenseUri in the manifest. Use 'None' to omit
        the LicenseUri field. Supported values: MIT, Apache-2.0, GPL-3.0, None.

    .EXAMPLE
        Initialize-PSModule -ModuleName 'MyCompany.PS.Utilities' -Path 'C:\Projects'

        Creates a new module project at C:\Projects\MyCompany.PS.Utilities with default settings.

    .EXAMPLE
        Initialize-PSModule -ModuleName 'Acme.Tools' -Author 'Jane Doe' -Description 'Acme toolset' `
            -Version '1.0.0' -License 'Apache-2.0' -Verbose

        Creates Acme.Tools with custom author, description, version, and Apache-2.0 license URI.

    .OUTPUTS
        [PSCustomObject] with PSTypeName 'yvfrii.PS.ModuleFactory.ScaffoldResult'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9._]+$')]
        [string]$ModuleName,

        [Parameter(Position = 1)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [string]$Author = [System.Environment]::UserName,

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [version]$Version = '0.1.0',

        [Parameter()]
        [version]$PowerShellVersion = '5.1',

        [Parameter()]
        [ValidateSet('MIT', 'Apache-2.0', 'GPL-3.0', 'None')]
        [string]$License = 'MIT'
    )

    # -------------------------------------------------------------------------
    # Step 1: Compute and validate module path
    # -------------------------------------------------------------------------
    $ModulePath = Join-Path -Path $Path -ChildPath $ModuleName
    Write-Verbose "Target module path: $ModulePath"

    if (Test-Path -Path $ModulePath) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.IOException]::new(
                "Module directory already exists at '$ModulePath'. Choose a different name or path."
            ),
            'ModuleDirectoryAlreadyExists',
            [System.Management.Automation.ErrorCategory]::ResourceExists,
            $ModulePath
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    # -------------------------------------------------------------------------
    # Step 2: Create module root directory
    # -------------------------------------------------------------------------
    Write-Verbose "Creating module root directory: $ModulePath"
    if ($PSCmdlet.ShouldProcess($ModulePath, 'Create module root directory')) {
        try {
            New-Item -Path $ModulePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created: $ModulePath"
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new(
                    "Failed to create module root directory '$ModulePath': $($_.Exception.Message)"
                ),
                'ModuleDirectoryCreationFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $ModulePath
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # -------------------------------------------------------------------------
    # Step 3: Create subdirectories
    # -------------------------------------------------------------------------
    $SubDirectories = @('Public', 'Private', 'Classes', 'Enums')
    $DirectoriesCreated = @($ModulePath)

    foreach ($SubDir in $SubDirectories) {
        $SubDirPath = Join-Path -Path $ModulePath -ChildPath $SubDir
        Write-Verbose "Creating subdirectory: $SubDirPath"
        if ($PSCmdlet.ShouldProcess($SubDirPath, 'Create subdirectory')) {
            try {
                New-Item -Path $SubDirPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $DirectoriesCreated += $SubDirPath
                Write-Verbose "Created: $SubDirPath"
            }
            catch {
                Write-Warning "Failed to create subdirectory '$SubDirPath': $($_.Exception.Message)"
            }
        }
    }

    # -------------------------------------------------------------------------
    # Step 4: Generate and write dev .psm1
    # -------------------------------------------------------------------------
    $Psm1Path = Join-Path -Path $ModulePath -ChildPath "$ModuleName.psm1"
    Write-Verbose "Generating dev .psm1 content for module: $ModuleName"

    try {
        $DevPsm1Content = New-DevPsm1Content -ModuleName $ModuleName -ErrorAction Stop
    }
    catch {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Failed to generate dev .psm1 content: $($_.Exception.Message)"
            ),
            'DevPsm1GenerationFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $ModuleName
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    Write-Verbose "Writing dev .psm1 to: $Psm1Path"
    if ($PSCmdlet.ShouldProcess($Psm1Path, 'Write dev .psm1 file')) {
        try {
            [System.IO.File]::WriteAllText($Psm1Path, $DevPsm1Content, $Script:DefaultEncoding)
            Write-Verbose "Written: $Psm1Path"
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new(
                    "Failed to write dev .psm1 to '$Psm1Path': $($_.Exception.Message)"
                ),
                'Psm1WriteFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $Psm1Path
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # -------------------------------------------------------------------------
    # Step 5: Build manifest parameters and create .psd1
    # -------------------------------------------------------------------------
    $ManifestPath = Join-Path -Path $ModulePath -ChildPath "$ModuleName.psd1"
    Write-Verbose "Generating module manifest at: $ManifestPath"

    # Resolve LicenseUri based on selected license
    $LicenseUriMap = @{
        'MIT'        = 'https://opensource.org/licenses/MIT'
        'Apache-2.0' = 'https://www.apache.org/licenses/LICENSE-2.0'
        'GPL-3.0'    = 'https://www.gnu.org/licenses/gpl-3.0.html'
    }

    $ManifestParams = @{
        Path                 = $ManifestPath
        RootModule           = "$ModuleName.psm1"
        ModuleVersion        = $Version.ToString()
        Author               = $Author
        Description          = $Description
        PowerShellVersion    = $PowerShellVersion.ToString()
        FunctionsToExport    = @()
        AliasesToExport      = @()
        CmdletsToExport      = @()
        VariablesToExport    = @()
    }

    if ($License -ne 'None' -and $LicenseUriMap.ContainsKey($License)) {
        $ManifestParams['LicenseUri'] = $LicenseUriMap[$License]
        Write-Verbose "Setting LicenseUri to: $($ManifestParams['LicenseUri'])"
    }

    if ($PSCmdlet.ShouldProcess($ManifestPath, 'Create module manifest (.psd1)')) {
        try {
            New-ModuleManifest @ManifestParams -ErrorAction Stop
            Write-Verbose "Created manifest: $ManifestPath"
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Failed to create module manifest at '$ManifestPath': $($_.Exception.Message)"
                ),
                'ManifestCreationFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $ManifestPath
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # -------------------------------------------------------------------------
    # Step 6: Return ScaffoldResult
    # -------------------------------------------------------------------------
    $ScaffoldResult = [PSCustomObject]@{
        PSTypeName         = 'yvfrii.PS.ModuleFactory.ScaffoldResult'
        ModuleName         = $ModuleName
        ModulePath         = $ModulePath
        ManifestPath       = $ManifestPath
        RootModulePath     = $Psm1Path
        DirectoriesCreated = [string[]]$DirectoriesCreated
        Success            = $true
    }

    Write-Verbose "Module '$ModuleName' scaffolded successfully at: $ModulePath"
    return $ScaffoldResult
}
