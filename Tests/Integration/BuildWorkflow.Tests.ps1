#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory'))
    Import-Module -Name $ModulePath -Force

    # Temp base for the entire workflow
    $TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModIntBuild_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempBase -ItemType Directory -Force | Out-Null

    # -------------------------------------------------------------------------
    # WORKFLOW: Initialize -> add source files -> Build -> verify output
    # -------------------------------------------------------------------------

    # Step 1: Initialize a new module
    $InitPath   = Join-Path -Path $TempBase -ChildPath 'source'
    New-Item -Path $InitPath -ItemType Directory -Force | Out-Null

    $ModuleName = 'Integration.BuildTest'

    $InitResult = Initialize-PSModule `
        -ModuleName $ModuleName `
        -Path $InitPath `
        -Author 'IntegrationTestUser' `
        -Description 'Integration test module for build workflow' `
        -Version '1.0.0' `
        -License 'None'

    $ModuleRoot = $InitResult.ModulePath

    # Step 2: Add source files to the initialized module
    $PublicDir  = Join-Path -Path $ModuleRoot -ChildPath 'Public'
    $PrivateDir = Join-Path -Path $ModuleRoot -ChildPath 'Private'
    $ClassesDir = Join-Path -Path $ModuleRoot -ChildPath 'Classes'
    $EnumsDir   = Join-Path -Path $ModuleRoot -ChildPath 'Enums'

    Set-Content -Path (Join-Path $EnumsDir 'BuildStatus.Enum.ps1') -Value @'
enum BuildStatus {
    Pending
    Running
    Success
    Failed
}
'@

    Set-Content -Path (Join-Path $ClassesDir '01_BuildItem.Class.ps1') -Value @'
class BuildItem {
    [string]$Name
    [BuildStatus]$Status

    BuildItem([string]$Name) {
        $this.Name   = $Name
        $this.Status = [BuildStatus]::Pending
    }
}
'@

    Set-Content -Path (Join-Path $PrivateDir 'Get-InternalState.ps1') -Value @'
function Get-InternalState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{ Ready = $true }
}
'@

    Set-Content -Path (Join-Path $PublicDir 'Get-BuildItem.ps1') -Value @'
function Get-BuildItem {
    # Alias: gbi
    [CmdletBinding()]
    [OutputType([BuildItem])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    return [BuildItem]::new($Name)
}
'@

    Set-Content -Path (Join-Path $PublicDir 'Start-Build.ps1') -Value @'
function Start-Build {
    # Alias: sb
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Start build')) {
        Write-Verbose "Starting build: $Name"
    }
}
'@

    # Step 3: Build the module
    $OutputPath  = Join-Path -Path $TempBase -ChildPath 'dist'
    $BuildResult = Build-PSModule -Path $ModuleRoot -OutputPath $OutputPath
}

AfterAll {
    if (Test-Path $TempBase) {
        Remove-Item -Path $TempBase -Recurse -Force
    }
}

Describe 'Integration - Build Workflow (Initialize -> add files -> Build)' {

    Context 'Initialize step completed successfully' {
        It 'should have created the module root directory' {
            $ModuleRoot | Should -Exist
        }

        It 'should have created the .psd1 manifest' {
            $InitResult.ManifestPath | Should -Exist
        }

        It 'should have created the dev .psm1 loader' {
            $InitResult.RootModulePath | Should -Exist
        }

        It 'should have all four subdirectories' {
            (Join-Path $ModuleRoot 'Public')  | Should -Exist
            (Join-Path $ModuleRoot 'Private') | Should -Exist
            (Join-Path $ModuleRoot 'Classes') | Should -Exist
            (Join-Path $ModuleRoot 'Enums')   | Should -Exist
        }
    }

    Context 'Build step completed successfully' {
        It 'should return a build result with Success = true' {
            $BuildResult.Success | Should -BeTrue
        }

        It 'should create the output .psm1 file' {
            $BuiltPsm1 = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psm1"
            $BuiltPsm1 | Should -Exist
        }

        It 'should create the output .psd1 file' {
            $BuiltPsd1 = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psd1"
            $BuiltPsd1 | Should -Exist
        }
    }

    Context 'Built manifest has correct exports' {
        BeforeAll {
            $BuiltPsd1    = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psd1"
            $ManifestData = Import-PowerShellDataFile -Path $BuiltPsd1
        }

        It 'should export Get-BuildItem in FunctionsToExport' {
            $ManifestData.FunctionsToExport | Should -Contain 'Get-BuildItem'
        }

        It 'should export Start-Build in FunctionsToExport' {
            $ManifestData.FunctionsToExport | Should -Contain 'Start-Build'
        }

        It 'should NOT export the private function Get-InternalState' {
            $ManifestData.FunctionsToExport | Should -Not -Contain 'Get-InternalState'
        }

        It 'should export alias gbi in AliasesToExport' {
            $ManifestData.AliasesToExport | Should -Contain 'gbi'
        }

        It 'should export alias sb in AliasesToExport' {
            $ManifestData.AliasesToExport | Should -Contain 'sb'
        }
    }

    Context 'Built .psm1 contains all code' {
        BeforeAll {
            $BuiltPsm1  = Join-Path -Path $OutputPath -ChildPath "$ModuleName.psm1"
            $Psm1Content = [System.IO.File]::ReadAllText($BuiltPsm1, [System.Text.Encoding]::UTF8)
        }

        It 'should contain the BuildStatus enum' {
            $Psm1Content | Should -Match 'enum BuildStatus'
        }

        It 'should contain the BuildItem class' {
            $Psm1Content | Should -Match 'class BuildItem'
        }

        It 'should contain the private Get-InternalState function' {
            $Psm1Content | Should -Match 'function Get-InternalState'
        }

        It 'should contain the public Get-BuildItem function' {
            $Psm1Content | Should -Match 'function Get-BuildItem'
        }

        It 'should contain the public Start-Build function' {
            $Psm1Content | Should -Match 'function Start-Build'
        }

        It 'should NOT contain dot-source lines in the built output' {
            $Psm1Content | Should -Not -Match '(?m)^\s*\.\s+.*\.ps1\s*$'
        }

        It 'should have Enums section before Classes section' {
            $EnumsPos   = $Psm1Content.IndexOf('#region ======== Enums ========')
            $ClassesPos = $Psm1Content.IndexOf('#region ======== Classes ========')
            $EnumsPos | Should -BeLessThan $ClassesPos
        }

        It 'should have Classes section before Public section' {
            $ClassesPos = $Psm1Content.IndexOf('#region ======== Classes ========')
            $PublicPos  = $Psm1Content.IndexOf('#region ======== Public ========')
            $ClassesPos | Should -BeLessThan $PublicPos
        }
    }

    Context 'Build result statistics' {
        It 'should report 5 source files merged (1 enum + 1 class + 1 private + 2 public)' {
            $BuildResult.FilesMerged | Should -Be 5
        }

        It 'should report 2 exported functions' {
            $BuildResult.FunctionsExported.Count | Should -Be 2
        }

        It 'should report 2 exported aliases' {
            $BuildResult.AliasesExported.Count | Should -Be 2
        }
    }
}
