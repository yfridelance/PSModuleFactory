#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Fixture path
    $FixturesPath            = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $Script:SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'
    $Script:SourceManifest   = Join-Path -Path $Script:SampleModulePath -ChildPath 'SampleModule.psd1'

    # Temp base for version update tests
    $Script:TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModVer_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $Script:TempBase -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $Script:TempBase) {
        Remove-Item -Path $Script:TempBase -Recurse -Force
    }
}

Describe 'Update-PSModuleVersion' {

    Context 'feat commit -> Minor bump (mocked git)' {
        BeforeAll {
            # Create a copy of SampleModule with version 1.0.0
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_feat'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            # Ensure version is 1.0.0
            $ManifestCopy = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($ManifestCopy, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('abc1234 feat: add new feature')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            $Result = Update-PSModuleVersion -Path $WorkDir -Confirm:$false
        }

        It 'should detect Minor bump from feat commit' {
            $Result.BumpType | Should -Be 'Minor'
        }

        It 'should increment Minor version from 1.0.0 to 1.1.0' {
            $Result.NewVersion.ToString() | Should -Be '1.1.0'
        }

        It 'should set PreviousVersion to 1.0.0' {
            $Result.PreviousVersion.ToString() | Should -Be '1.0.0'
        }
    }

    Context 'fix commit -> Patch bump (mocked git)' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_fix'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            $ManifestCopy = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($ManifestCopy, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('def5678 fix: correct null reference issue')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            $Result = Update-PSModuleVersion -Path $WorkDir -Confirm:$false
        }

        It 'should detect Patch bump from fix commit' {
            $Result.BumpType | Should -Be 'Patch'
        }

        It 'should increment Patch version from 1.0.0 to 1.0.1' {
            $Result.NewVersion.ToString() | Should -Be '1.0.1'
        }
    }

    Context 'BREAKING CHANGE commit -> Major bump (mocked git)' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_breaking'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            $ManifestCopy = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($ManifestCopy, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('a1b2c3d feat!: remove legacy API')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            $Result = Update-PSModuleVersion -Path $WorkDir -Confirm:$false
        }

        It 'should detect Major bump from breaking change commit' {
            $Result.BumpType | Should -Be 'Major'
        }

        It 'should increment Major version from 1.0.0 to 2.0.0' {
            $Result.NewVersion.ToString() | Should -Be '2.0.0'
        }

        It 'should reset Minor and Patch to 0 on Major bump' {
            $Result.NewVersion.Minor | Should -Be 0
            $Result.NewVersion.Build | Should -Be 0
        }
    }

    Context '-BumpType overrides auto-detection' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_override'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            $ManifestCopy = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($ManifestCopy, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('e4f5a6b fix: small patch')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            # Override: force Major even though commits only warrant Patch
            $Result = Update-PSModuleVersion -Path $WorkDir -BumpType Major -Confirm:$false
        }

        It 'should use the explicit -BumpType value regardless of commit analysis' {
            $Result.BumpType | Should -Be 'Major'
        }

        It 'should produce a Major bump (2.0.0) even when commits only warrant Patch' {
            $Result.NewVersion.ToString() | Should -Be '2.0.0'
        }
    }

    Context '-WhatIf returns result but does NOT modify manifest' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_whatif'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            $Script:WhatIfManifest = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($Script:WhatIfManifest, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($Script:WhatIfManifest, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('c7d8e9f feat: new feature')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            $Result = Update-PSModuleVersion -Path $WorkDir -WhatIf
        }

        It 'should return a result object' {
            $Result | Should -Not -BeNullOrEmpty
        }

        It 'should report the computed NewVersion in the result' {
            $Result.NewVersion | Should -Not -BeNullOrEmpty
        }

        It 'should mark IsWhatIf = true in the result' {
            $Result.IsWhatIf | Should -BeTrue
        }

        It 'should NOT modify the .psd1 manifest version' {
            $ManifestData = Import-PowerShellDataFile -Path $Script:WhatIfManifest
            $ManifestData.ModuleVersion | Should -Be '1.0.0'
        }
    }

    Context 'No git available -> terminating error' {
        It 'should throw when git is not available on PATH' {
            Mock -CommandName 'Get-Command' -ParameterFilter { $Name -eq 'git' } -MockWith {
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            {
                Update-PSModuleVersion -Path $Script:SampleModulePath -Confirm:$false -ErrorAction Stop
            } | Should -Throw
        }
    }

    Context 'Result object shape' {
        BeforeAll {
            $WorkDir = Join-Path -Path $Script:TempBase -ChildPath 'ver_shape'
            New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $Script:SampleModulePath '*') -Destination $WorkDir -Recurse -Force
            $ManifestCopy = Join-Path -Path $WorkDir -ChildPath 'SampleModule.psd1'
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '1.0.0'"
            [System.IO.File]::WriteAllText($ManifestCopy, $Content, [System.Text.UTF8Encoding]::new($true))

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'describe' } -MockWith {
                $global:LASTEXITCODE = 1
                return $null
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            Mock -CommandName 'git' -ParameterFilter { $args -contains 'log' } -MockWith {
                $global:LASTEXITCODE = 0
                return @('f1a2b3c fix: test fix')
            } -ModuleName 'yvfrii.PS.ModuleFactory'

            $Result = Update-PSModuleVersion -Path $WorkDir -Confirm:$false
        }

        It 'should include ModuleName in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'ModuleName'
        }

        It 'should include PreviousVersion in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'PreviousVersion'
        }

        It 'should include NewVersion in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'NewVersion'
        }

        It 'should include BumpType in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'BumpType'
        }

        It 'should include CommitsAnalyzed in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'CommitsAnalyzed'
        }

        It 'should include Success in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'Success'
        }
    }
}
