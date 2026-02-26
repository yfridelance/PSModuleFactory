function Update-PSModuleVersion {
    <#
    .SYNOPSIS
        Bumps the ModuleVersion in a module manifest based on Conventional Commits analysis or an
        explicit bump type.

    .DESCRIPTION
        Update-PSModuleVersion reads the current ModuleVersion from the module manifest (.psd1),
        analyzes Git commit messages since the last matching version tag using the Conventional
        Commits specification, and determines the appropriate semantic version bump (Major, Minor,
        or Patch).

        Commit analysis rules:
        - A commit with 'BREAKING CHANGE:' in its body, or a type suffix '!' (e.g. 'feat!:'),
          triggers a Major bump.
        - A commit starting with 'feat' triggers a Minor bump.
        - A commit starting with 'fix' triggers a Patch bump.
        - Other commit types (docs, chore, refactor, test, style, ci, perf, build) do not
          trigger a bump.

        The highest bump type found wins. If -BumpType is explicitly provided, it overrides the
        automatic analysis result.

        Requires Git to be available on the system PATH.

    .PARAMETER Path
        The root directory of the PowerShell module project. Must contain at least one .psd1
        manifest file. Defaults to the current working directory.

    .PARAMETER BumpType
        When specified, overrides the automatic Conventional Commits analysis. Valid values are
        'Major', 'Minor', and 'Patch'.

    .PARAMETER Tag
        When specified, creates a new Git tag in the format '<TagPrefix><NewVersion>' after
        updating the manifest.

    .PARAMETER TagPrefix
        The prefix string prepended to the version number when reading and creating Git tags.
        Defaults to 'v'.

    .EXAMPLE
        Update-PSModuleVersion -Path 'C:\Projects\MyModule'

        Analyzes commits since the last matching Git tag and bumps the version automatically based
        on Conventional Commits. Writes the new version to the manifest.

    .EXAMPLE
        Update-PSModuleVersion -Path 'C:\Projects\MyModule' -BumpType Minor -Tag -TagPrefix 'release/' -Verbose

        Forces a Minor version bump, updates the manifest, creates a Git tag with the 'release/'
        prefix, and prints verbose progress.

    .OUTPUTS
        [PSCustomObject] with PSTypeName 'yvfrii.PS.ModuleFactory.VersionResult'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('Major', 'Minor', 'Patch')]
        [string]$BumpType,

        [Parameter()]
        [switch]$Tag,

        [Parameter()]
        [string]$TagPrefix = 'v'
    )

    # -------------------------------------------------------------------------
    # Step 1: Verify Git availability
    # -------------------------------------------------------------------------
    Write-Verbose "Verifying Git availability..."
    $GitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
    if (-not $GitCommand) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.CommandNotFoundException]::new(
                "Git executable not found on PATH. Git is required to analyze commit history."
            ),
            'GitNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            'git'
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    Write-Verbose "Git found at: $($GitCommand.Source)"

    # -------------------------------------------------------------------------
    # Step 2: Find .psd1 and read current ModuleVersion
    # -------------------------------------------------------------------------
    Write-Verbose "Searching for module manifest in: $Path"
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

    $ManifestFile = $ManifestFiles[0]
    $ManifestPath = $ManifestFile.FullName
    $ModuleName = [System.IO.Path]::GetFileNameWithoutExtension($ManifestFile.Name)
    Write-Verbose "Found manifest: $ManifestPath"

    Write-Verbose "Reading ModuleVersion from manifest..."
    $CurrentVersion = $null
    try {
        $ManifestData = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
        $CurrentVersion = [version]$ManifestData.ModuleVersion
        Write-Verbose "Current version: $CurrentVersion"
    }
    catch {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "Failed to read ModuleVersion from '$ManifestPath': $($_.Exception.Message)"
            ),
            'ManifestReadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $ManifestPath
        )
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    # -------------------------------------------------------------------------
    # Step 3: Find latest matching Git tag
    # -------------------------------------------------------------------------
    Write-Verbose "Searching for latest Git tag matching prefix: $TagPrefix*"
    $LatestTag = $null
    try {
        $GitDescribeOutput = & git -C $Path describe --tags --abbrev=0 "--match=$TagPrefix*" 2>&1
        if ($LASTEXITCODE -eq 0 -and $GitDescribeOutput) {
            $LatestTag = ($GitDescribeOutput | Out-String).Trim()
            Write-Verbose "Latest matching tag: $LatestTag"
        }
        else {
            Write-Verbose "No matching tag found; will analyze all commits."
        }
    }
    catch {
        Write-Verbose "Git describe failed: $($_.Exception.Message). Analyzing all commits."
    }

    # -------------------------------------------------------------------------
    # Step 4: Get commits since tag (or all commits if no tag found)
    # -------------------------------------------------------------------------
    Write-Verbose "Retrieving commit log..."
    $CommitLines = @()
    try {
        if ($LatestTag) {
            $GitLogOutput = & git -C $Path log "$LatestTag..HEAD" '--oneline' '--no-merges' 2>&1
        }
        else {
            $GitLogOutput = & git -C $Path log '--oneline' '--no-merges' 2>&1
        }

        if ($LASTEXITCODE -eq 0 -and $GitLogOutput) {
            $CommitLines = @($GitLogOutput | ForEach-Object { ($_ | Out-String).Trim() } |
                Where-Object { $_ -ne '' })
            Write-Verbose "Commits found: $($CommitLines.Count)"
        }
        else {
            Write-Verbose "No commits found in log output."
        }
    }
    catch {
        Write-Warning "Failed to retrieve git log: $($_.Exception.Message)"
    }

    $CommitsAnalyzed = $CommitLines.Count

    # -------------------------------------------------------------------------
    # Step 5: Parse commits for Conventional Commits bump signals
    # -------------------------------------------------------------------------
    Write-Verbose "Analyzing $CommitsAnalyzed commit(s) for Conventional Commits signals..."

    # Bump priority: Major=3, Minor=2, Patch=1, None=0
    $HighestBumpPriority = 0
    $DetectedBumpType = 'None'

    # Patterns (compatible with PowerShell 5.1 — no ternary, no ??)
    $BreakingPattern = '^[a-z]+(\(.+\))?!:'
    $FeatPattern = '^feat(\(.+\))?:'
    $FixPattern = '^fix(\(.+\))?:'

    foreach ($CommitLine in $CommitLines) {
        # Strip the short hash prefix: "abc1234 feat: add thing" -> "feat: add thing"
        $CommitMessage = $CommitLine -replace '^[0-9a-f]+\s+', ''

        # Check for breaking change (type! or BREAKING CHANGE in body — oneline shows subject only,
        # so we check the '!' suffix indicator in the subject)
        if ($CommitMessage -match $BreakingPattern -or $CommitMessage -match 'BREAKING CHANGE') {
            Write-Verbose "BREAKING CHANGE detected: $CommitMessage"
            if ($HighestBumpPriority -lt 3) {
                $HighestBumpPriority = 3
                $DetectedBumpType = 'Major'
            }
        }
        elseif ($CommitMessage -match $FeatPattern) {
            Write-Verbose "Minor (feat) detected: $CommitMessage"
            if ($HighestBumpPriority -lt 2) {
                $HighestBumpPriority = 2
                $DetectedBumpType = 'Minor'
            }
        }
        elseif ($CommitMessage -match $FixPattern) {
            Write-Verbose "Patch (fix) detected: $CommitMessage"
            if ($HighestBumpPriority -lt 1) {
                $HighestBumpPriority = 1
                $DetectedBumpType = 'Patch'
            }
        }
        else {
            Write-Verbose "No bump signal: $CommitMessage"
        }
    }

    Write-Verbose "Highest detected bump type: $DetectedBumpType"

    # -------------------------------------------------------------------------
    # Step 6: Determine effective bump type
    # -------------------------------------------------------------------------
    $EffectiveBumpType = $null

    if ($BumpType) {
        # Explicit override wins
        $EffectiveBumpType = $BumpType
        Write-Verbose "Using explicit -BumpType override: $EffectiveBumpType"
    }
    elseif ($DetectedBumpType -ne 'None') {
        $EffectiveBumpType = $DetectedBumpType
        Write-Verbose "Using detected bump type: $EffectiveBumpType"
    }

    if (-not $EffectiveBumpType) {
        Write-Warning "No version bump detected from commit analysis and -BumpType not specified. No version change will be made."
        $VersionResult = [PSCustomObject]@{
            PSTypeName      = 'yvfrii.PS.ModuleFactory.VersionResult'
            ModuleName      = $ModuleName
            ManifestPath    = $ManifestPath
            PreviousVersion = $CurrentVersion
            NewVersion      = $CurrentVersion
            BumpType        = 'None'
            CommitsAnalyzed = $CommitsAnalyzed
            TagCreated      = $null
            IsWhatIf        = $WhatIfPreference
            Success         = $false
        }
        return $VersionResult
    }

    # -------------------------------------------------------------------------
    # Step 7: Compute new version
    # -------------------------------------------------------------------------
    $MajorPart = $CurrentVersion.Major
    $MinorPart = $CurrentVersion.Minor
    $PatchPart = $CurrentVersion.Build

    # Ensure Build component is non-negative (version 1.0 has Build=-1)
    if ($PatchPart -lt 0) {
        $PatchPart = 0
    }

    if ($EffectiveBumpType -eq 'Major') {
        $NewVersion = [version]"$($MajorPart + 1).0.0"
    }
    elseif ($EffectiveBumpType -eq 'Minor') {
        $NewVersion = [version]"$MajorPart.$($MinorPart + 1).0"
    }
    else {
        # Patch
        $NewVersion = [version]"$MajorPart.$MinorPart.$($PatchPart + 1)"
    }

    Write-Verbose "Version bump: $CurrentVersion -> $NewVersion ($EffectiveBumpType)"

    # -------------------------------------------------------------------------
    # Step 8: Update manifest if not WhatIf
    # -------------------------------------------------------------------------
    $TagCreated = $null
    $IsWhatIf = $false

    if ($PSCmdlet.ShouldProcess(
            "Manifest '$ManifestPath'",
            "Update ModuleVersion from $CurrentVersion to $NewVersion ($EffectiveBumpType bump)")) {
        Write-Verbose "Updating ModuleVersion in manifest to: $NewVersion"
        try {
            Update-ManifestField -ManifestPath $ManifestPath -FieldName 'ModuleVersion' `
                -Value $NewVersion.ToString() -ErrorAction Stop
            Write-Verbose "Manifest updated successfully."
        }
        catch {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Failed to update ModuleVersion in '$ManifestPath': $($_.Exception.Message)"
                ),
                'ManifestUpdateFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $ManifestPath
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        # -------------------------------------------------------------------------
        # Step 9: Create Git tag if -Tag specified
        # -------------------------------------------------------------------------
        if ($Tag) {
            $NewTagName = "$TagPrefix$NewVersion"
            Write-Verbose "Creating Git tag: $NewTagName"
            if ($PSCmdlet.ShouldProcess($NewTagName, 'Create Git tag')) {
                try {
                    $GitTagOutput = & git -C $Path tag $NewTagName 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Git tag creation failed for '$NewTagName': $GitTagOutput"
                    }
                    else {
                        $TagCreated = $NewTagName
                        Write-Verbose "Git tag created: $TagCreated"
                    }
                }
                catch {
                    Write-Warning "Exception creating Git tag '$NewTagName': $($_.Exception.Message)"
                }
            }
        }
    }
    else {
        # WhatIf mode — report what would happen but do not modify
        $IsWhatIf = $true
        Write-Verbose "WhatIf: Would update ModuleVersion from $CurrentVersion to $NewVersion"
        if ($Tag) {
            Write-Verbose "WhatIf: Would create Git tag '$TagPrefix$NewVersion'"
        }
    }

    # -------------------------------------------------------------------------
    # Step 10: Return VersionResult
    # -------------------------------------------------------------------------
    $VersionResult = [PSCustomObject]@{
        PSTypeName      = 'yvfrii.PS.ModuleFactory.VersionResult'
        ModuleName      = $ModuleName
        ManifestPath    = $ManifestPath
        PreviousVersion = $CurrentVersion
        NewVersion      = $NewVersion
        BumpType        = $EffectiveBumpType
        CommitsAnalyzed = $CommitsAnalyzed
        TagCreated      = $TagCreated
        IsWhatIf        = $IsWhatIf
        Success         = $true
    }

    Write-Verbose "Version update completed: $ModuleName $CurrentVersion -> $NewVersion"
    return $VersionResult
}
