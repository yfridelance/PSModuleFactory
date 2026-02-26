#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory'))
    Import-Module -Name $ModulePath -Force

    # Fixture path
    $FixturesPath   = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures')
    $MonolithicFixture = Join-Path -Path $FixturesPath -ChildPath 'MonolithicModule'

    # Temp base for the entire workflow
    $TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModIntSplit_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempBase -ItemType Directory -Force | Out-Null

    # -------------------------------------------------------------------------
    # WORKFLOW: Copy MonolithicModule -> Split -> verify files -> Build -> verify round-trip
    # -------------------------------------------------------------------------

    # Step 1: Copy the monolithic fixture to a work directory
    $WorkDir = Join-Path -Path $TempBase -ChildPath 'work'
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $MonolithicFixture '*') -Destination $WorkDir -Recurse -Force

    # Step 2: Split the module
    $SplitResult = Split-PSModule -Path $WorkDir -Force -Confirm:$false

    # Step 3: Build the split module (round-trip check)
    $BuildOutputDir = Join-Path -Path $TempBase -ChildPath 'dist'
    $BuildResult    = Build-PSModule -Path $WorkDir -OutputPath $BuildOutputDir
}

AfterAll {
    if (Test-Path $TempBase) {
        Remove-Item -Path $TempBase -Recurse -Force
    }
}

Describe 'Integration - Split Workflow (MonolithicModule -> Split -> Build round-trip)' {

    Context 'Split step completed successfully' {
        It 'should return a split result with Success = true' {
            $SplitResult.Success | Should -BeTrue
        }

        It 'should report the correct module name' {
            $SplitResult.ModuleName | Should -Be 'MonolithicModule'
        }

        It 'should report files were created' {
            $SplitResult.FilesCreated | Should -BeGreaterThan 0
        }
    }

    Context 'Individual files created correctly after split' {
        It 'should create Public/Get-SampleData.ps1' {
            (Join-Path $WorkDir (Join-Path 'Public' 'Get-SampleData.ps1')) | Should -Exist
        }

        It 'should create Public/Set-SampleData.ps1' {
            (Join-Path $WorkDir (Join-Path 'Public' 'Set-SampleData.ps1')) | Should -Exist
        }

        It 'should create Private/Invoke-SampleHelper.ps1' {
            (Join-Path $WorkDir (Join-Path 'Private' 'Invoke-SampleHelper.ps1')) | Should -Exist
        }

        It 'should create Enums/SampleStatus.Enum.ps1' {
            (Join-Path $WorkDir (Join-Path 'Enums' 'SampleStatus.Enum.ps1')) | Should -Exist
        }

        It 'should create at least one Class file in Classes/' {
            $ClassDir   = Join-Path $WorkDir 'Classes'
            $ClassFiles = Get-ChildItem -Path $ClassDir -Filter '*.Class.ps1' -File -ErrorAction SilentlyContinue
            $ClassFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Split files have valid content' {
        It 'should write a valid function definition to Public/Get-SampleData.ps1' {
            $FilePath = Join-Path $WorkDir (Join-Path 'Public' 'Get-SampleData.ps1')
            $Content  = Get-Content -Path $FilePath -Raw
            $Content  | Should -Match 'function Get-SampleData'
        }

        It 'should write a valid enum definition to Enums/SampleStatus.Enum.ps1' {
            $FilePath = Join-Path $WorkDir (Join-Path 'Enums' 'SampleStatus.Enum.ps1')
            $Content  = Get-Content -Path $FilePath -Raw
            $Content  | Should -Match 'enum SampleStatus'
        }

        It 'should write a valid class definition to a Classes file' {
            $ClassDir  = Join-Path $WorkDir 'Classes'
            $BaseFile  = Get-ChildItem -Path $ClassDir -Filter '*BaseModel*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $BaseFile | Should -Not -BeNullOrEmpty
            $Content  = Get-Content -Path $BaseFile.FullName -Raw
            $Content  | Should -Match 'class BaseModel'
        }
    }

    Context 'Dev .psm1 regenerated after split' {
        BeforeAll {
            $Psm1Path    = Join-Path $WorkDir 'MonolithicModule.psm1'
            $Psm1Content = [System.IO.File]::ReadAllText($Psm1Path, [System.Text.Encoding]::UTF8)
        }

        It 'should replace the monolithic .psm1 with a dev loader' {
            # Original monolithic file had enum/class/function bodies directly
            # Dev loader should have Get-ChildItem and dot-source pattern
            $Psm1Content | Should -Match 'Get-ChildItem'
        }

        It 'should reference Public in the dev loader' {
            $Psm1Content | Should -Match "'Public'"
        }

        It 'should reference Private in the dev loader' {
            $Psm1Content | Should -Match "'Private'"
        }

        It 'should reference Enums in the dev loader' {
            $Psm1Content | Should -Match "'Enums'"
        }

        It 'should reference Classes in the dev loader' {
            $Psm1Content | Should -Match "'Classes'"
        }
    }

    Context 'Build round-trip after split' {
        It 'should build successfully after splitting' {
            $BuildResult.Success | Should -BeTrue
        }

        It 'should create the built .psm1 file' {
            $BuiltPsm1 = Join-Path $BuildOutputDir 'MonolithicModule.psm1'
            $BuiltPsm1 | Should -Exist
        }

        It 'should create the built .psd1 file' {
            $BuiltPsd1 = Join-Path $BuildOutputDir 'MonolithicModule.psd1'
            $BuiltPsd1 | Should -Exist
        }
    }

    Context 'Built manifest exports after round-trip' {
        BeforeAll {
            $BuiltPsd1    = Join-Path $BuildOutputDir 'MonolithicModule.psd1'
            $ManifestData = Import-PowerShellDataFile -Path $BuiltPsd1
        }

        It 'should export Get-SampleData' {
            $ManifestData.FunctionsToExport | Should -Contain 'Get-SampleData'
        }

        It 'should export Set-SampleData' {
            $ManifestData.FunctionsToExport | Should -Contain 'Set-SampleData'
        }

        It 'should NOT export the private Invoke-SampleHelper' {
            $ManifestData.FunctionsToExport | Should -Not -Contain 'Invoke-SampleHelper'
        }

        It 'should export alias gsd' {
            $ManifestData.AliasesToExport | Should -Contain 'gsd'
        }
    }

    Context 'Built .psm1 content after round-trip' {
        BeforeAll {
            $BuiltPsm1  = Join-Path $BuildOutputDir 'MonolithicModule.psm1'
            $Psm1Content = [System.IO.File]::ReadAllText($BuiltPsm1, [System.Text.Encoding]::UTF8)
        }

        It 'should contain the SampleStatus enum in the built output' {
            $Psm1Content | Should -Match 'enum SampleStatus'
        }

        It 'should contain the BaseModel class in the built output' {
            $Psm1Content | Should -Match 'class BaseModel'
        }

        It 'should contain the DerivedModel class in the built output' {
            $Psm1Content | Should -Match 'class DerivedModel'
        }

        It 'should contain all three functions in the built output' {
            $Psm1Content | Should -Match 'function Get-SampleData'
            $Psm1Content | Should -Match 'function Set-SampleData'
            $Psm1Content | Should -Match 'function Invoke-SampleHelper'
        }

        It 'should NOT contain dot-source lines in the built output' {
            $Psm1Content | Should -Not -Match '(?m)^\s*\.\s+.*\.ps1\s*$'
        }

        It 'should have Enums section appearing before Functions sections' {
            $EnumsPos   = $Psm1Content.IndexOf('#region ======== Enums ========')
            $PublicPos  = $Psm1Content.IndexOf('#region ======== Public ========')
            $EnumsPos | Should -BeLessThan $PublicPos
        }
    }

    Context 'Split result classification' {
        It 'should classify Get-SampleData as a public function' {
            $SplitResult.PublicFunctions | Should -Contain 'Get-SampleData'
        }

        It 'should classify Set-SampleData as a public function' {
            $SplitResult.PublicFunctions | Should -Contain 'Set-SampleData'
        }

        It 'should classify Invoke-SampleHelper as a private function' {
            $SplitResult.PrivateFunctions | Should -Contain 'Invoke-SampleHelper'
        }

        It 'should classify BaseModel as a class' {
            $SplitResult.Classes | Should -Contain 'BaseModel'
        }

        It 'should classify DerivedModel as a class' {
            $SplitResult.Classes | Should -Contain 'DerivedModel'
        }

        It 'should classify SampleStatus as an enum' {
            $SplitResult.Enums | Should -Contain 'SampleStatus'
        }
    }
}
