#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Fixture path
    $FixturesPath          = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $Script:MonolithicFixture = Join-Path -Path $FixturesPath -ChildPath 'MonolithicModule'

    # Temp base for all split tests (we work on copies, never modify the fixture)
    $Script:TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModSplit_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $Script:TempBase -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $Script:TempBase) {
        Remove-Item -Path $Script:TempBase -Recurse -Force
    }
}

Describe 'Split-PSModule' {

    Context 'Splits MonolithicModule into individual files' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_basic'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            $Result  = Split-PSModule -Path $WorkDir -Force -Confirm:$false
        }

        It 'should return a result object with Success = true' {
            $Result.Success | Should -BeTrue
        }

        It 'should report the correct ModuleName' {
            $Result.ModuleName | Should -Be 'MonolithicModule'
        }

        It 'should create files (FilesCreated > 0)' {
            $Result.FilesCreated | Should -BeGreaterThan 0
        }
    }

    Context 'Public functions go into the Public directory' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_public'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            Split-PSModule -Path $WorkDir -Force -Confirm:$false | Out-Null
        }

        It 'should create Get-SampleData.ps1 in the Public directory' {
            $Expected = Join-Path -Path $WorkDir -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Expected | Should -Exist
        }

        It 'should create Set-SampleData.ps1 in the Public directory' {
            $Expected = Join-Path -Path $WorkDir -ChildPath (Join-Path 'Public' 'Set-SampleData.ps1')
            $Expected | Should -Exist
        }
    }

    Context 'Private functions go into the Private directory' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_private'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            Split-PSModule -Path $WorkDir -Force -Confirm:$false | Out-Null
        }

        It 'should create Invoke-SampleHelper.ps1 in the Private directory' {
            $Expected = Join-Path -Path $WorkDir -ChildPath (Join-Path 'Private' 'Invoke-SampleHelper.ps1')
            $Expected | Should -Exist
        }
    }

    Context 'Classes go into the Classes directory with numeric prefix' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_classes'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            $Result  = Split-PSModule -Path $WorkDir -Force -Confirm:$false
        }

        It 'should report BaseModel and DerivedModel in the Classes list' {
            $Result.Classes | Should -Contain 'BaseModel'
            $Result.Classes | Should -Contain 'DerivedModel'
        }

        It 'should create a Class file for BaseModel in the Classes directory' {
            $ClassDir   = Join-Path -Path $WorkDir -ChildPath 'Classes'
            $ClassFiles = Get-ChildItem -Path $ClassDir -Filter '*BaseModel*' -File -ErrorAction SilentlyContinue
            $ClassFiles.Count | Should -BeGreaterThan 0
        }

        It 'should create a Class file for DerivedModel in the Classes directory' {
            $ClassDir   = Join-Path -Path $WorkDir -ChildPath 'Classes'
            $ClassFiles = Get-ChildItem -Path $ClassDir -Filter '*DerivedModel*' -File -ErrorAction SilentlyContinue
            $ClassFiles.Count | Should -BeGreaterThan 0
        }

        It 'should use numerically prefixed filenames for class files' {
            $ClassDir   = Join-Path -Path $WorkDir -ChildPath 'Classes'
            $ClassFiles = Get-ChildItem -Path $ClassDir -Filter '*.Class.ps1' -File -ErrorAction SilentlyContinue
            $ClassFiles | ForEach-Object {
                $_.Name | Should -Match '^\d{2}_'
            }
        }
    }

    Context 'Enums go into the Enums directory' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_enums'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            $Result  = Split-PSModule -Path $WorkDir -Force -Confirm:$false
        }

        It 'should report SampleStatus in the Enums list' {
            $Result.Enums | Should -Contain 'SampleStatus'
        }

        It 'should create SampleStatus.Enum.ps1 in the Enums directory' {
            $Expected = Join-Path -Path $WorkDir -ChildPath (Join-Path 'Enums' 'SampleStatus.Enum.ps1')
            $Expected | Should -Exist
        }
    }

    Context 'Dev .psm1 regenerated after split' {
        BeforeAll {
            $WorkDir     = Join-Path -Path $Script:TempBase -ChildPath 'split_devpsm1'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force
            Split-PSModule -Path $WorkDir -Force -Confirm:$false | Out-Null
            $Psm1Path    = Join-Path -Path $WorkDir -ChildPath 'MonolithicModule.psm1'
            $Psm1Content = [System.IO.File]::ReadAllText($Psm1Path, [System.Text.Encoding]::UTF8)
        }

        It 'should replace the monolithic .psm1 with a dev dot-source loader' {
            # The monolithic content had enum/class/function definitions directly
            # The new dev loader should use Get-ChildItem and dot-sourcing
            $Psm1Content | Should -Match 'Get-ChildItem'
        }

        It 'should reference the Public folder in the dev loader' {
            $Psm1Content | Should -Match "'Public'"
        }

        It 'should reference the Private folder in the dev loader' {
            $Psm1Content | Should -Match "'Private'"
        }
    }

    Context '-Force overwrites existing files' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_force'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $WorkDir -Recurse -Force

            # First split
            Split-PSModule -Path $WorkDir -Force -Confirm:$false | Out-Null

            # Corrupt the output to verify -Force overwrites
            $PublicDir     = Join-Path -Path $WorkDir -ChildPath 'Public'
            $GetSampleFile = Join-Path -Path $PublicDir -ChildPath 'Get-SampleData.ps1'
            Set-Content -Path $GetSampleFile -Value '# CORRUPTED'

            # Second split with -Force; need to restore monolithic psm1 first
            Copy-Item -Path (Join-Path $Script:MonolithicFixture 'MonolithicModule.psm1') -Destination (Join-Path $WorkDir 'MonolithicModule.psm1') -Force
            Split-PSModule -Path $WorkDir -Force -Confirm:$false | Out-Null

            $Script:ForceTestContent = Get-Content -Path $GetSampleFile -Raw
        }

        It 'should overwrite the existing file when -Force is specified' {
            $Script:ForceTestContent | Should -Not -Match '# CORRUPTED'
        }

        It 'should write valid function content when overwriting' {
            $Script:ForceTestContent | Should -Match 'function Get-SampleData'
        }
    }

    Context 'Without -Force, existing files cause a non-terminating error' {
        BeforeAll {
            $Script:NoForceWorkDir = Join-Path -Path $Script:TempBase -ChildPath 'split_noforce'
            New-Item -Path $Script:NoForceWorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:MonolithicFixture '*') -Destination $Script:NoForceWorkDir -Recurse -Force

            # First split to create the files
            Split-PSModule -Path $Script:NoForceWorkDir -Force -Confirm:$false | Out-Null

            # Restore the monolithic psm1 so we can split again
            Copy-Item -Path (Join-Path $Script:MonolithicFixture 'MonolithicModule.psm1') -Destination (Join-Path $Script:NoForceWorkDir 'MonolithicModule.psm1') -Force
        }

        It 'should write a non-terminating error when a file already exists and -Force is not specified' {
            $Errors = $null
            Split-PSModule -Path $Script:NoForceWorkDir -Confirm:$false -ErrorVariable Errors -ErrorAction SilentlyContinue | Out-Null
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'should NOT throw a terminating error when a file already exists and -Force is not specified' {
            {
                # Restore psm1 again for a clean attempt
                Copy-Item -Path (Join-Path $Script:MonolithicFixture 'MonolithicModule.psm1') -Destination (Join-Path $Script:NoForceWorkDir 'MonolithicModule.psm1') -Force
                Split-PSModule -Path $Script:NoForceWorkDir -Confirm:$false -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }
    }
}
