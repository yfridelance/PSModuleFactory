#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Fixture path
    $FixturesPath     = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'

    # Temp output directory base
    $TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModBuild_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempBase -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $TempBase) {
        Remove-Item -Path $TempBase -Recurse -Force
    }
}

Describe 'Build-PSModule' {

    Context 'Happy path - builds SampleModule to a temp output directory' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_happy'
            $Result    = Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir
        }

        It 'should return a result object with Success = true' {
            $Result.Success | Should -BeTrue
        }

        It 'should create the output .psm1 file' {
            $ExpectedPsm1 = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psm1'
            $ExpectedPsm1 | Should -Exist
        }

        It 'should create the output .psd1 file' {
            $ExpectedPsd1 = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psd1'
            $ExpectedPsd1 | Should -Exist
        }

        It 'should report the correct ModuleName in the result' {
            $Result.ModuleName | Should -Be 'SampleModule'
        }

        It 'should report the correct OutputPath in the result' {
            $Result.OutputPath | Should -Be $OutputDir
        }
    }

    Context 'FunctionsToExport updated in built .psd1' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_functions'
            Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir | Out-Null
            $ManifestPath = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psd1'
            $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
        }

        It 'should export Get-SampleData in the built manifest' {
            $ManifestData.FunctionsToExport | Should -Contain 'Get-SampleData'
        }

        It 'should export Set-SampleData in the built manifest' {
            $ManifestData.FunctionsToExport | Should -Contain 'Set-SampleData'
        }

        It 'should export exactly 2 functions' {
            $ManifestData.FunctionsToExport.Count | Should -Be 2
        }
    }

    Context 'AliasesToExport updated in built .psd1' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_aliases'
            Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir | Out-Null
            $ManifestPath = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psd1'
            $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
        }

        It 'should export alias gsd in the built manifest' {
            $ManifestData.AliasesToExport | Should -Contain 'gsd'
        }

        It 'should export alias ssd in the built manifest' {
            $ManifestData.AliasesToExport | Should -Contain 'ssd'
        }

        It 'should export alias setsd in the built manifest' {
            $ManifestData.AliasesToExport | Should -Contain 'setsd'
        }
    }

    Context 'Merged .psm1 contains all function code' {
        BeforeAll {
            $OutputDir  = Join-Path -Path $TempBase -ChildPath 'build_content'
            Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir | Out-Null
            $Psm1Path   = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psm1'
            $Psm1Content = [System.IO.File]::ReadAllText($Psm1Path, [System.Text.Encoding]::UTF8)
        }

        It 'should contain the Get-SampleData function in the merged psm1' {
            $Psm1Content | Should -Match 'function Get-SampleData'
        }

        It 'should contain the Set-SampleData function in the merged psm1' {
            $Psm1Content | Should -Match 'function Set-SampleData'
        }

        It 'should contain the Invoke-SampleHelper function in the merged psm1' {
            $Psm1Content | Should -Match 'function Invoke-SampleHelper'
        }

        It 'should contain the BaseModel class in the merged psm1' {
            $Psm1Content | Should -Match 'class BaseModel'
        }

        It 'should contain the SampleStatus enum in the merged psm1' {
            $Psm1Content | Should -Match 'enum SampleStatus'
        }
    }

    Context '-Clean removes existing output before building' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_clean'
            New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

            # Create a stale file that should be removed by -Clean
            $StaleFile = Join-Path -Path $OutputDir -ChildPath 'stale_artifact.txt'
            Set-Content -Path $StaleFile -Value 'old content'

            Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir -Clean -Confirm:$false | Out-Null
        }

        It 'should remove the stale file when -Clean is specified' {
            $StaleFile = Join-Path -Path $OutputDir -ChildPath 'stale_artifact.txt'
            $StaleFile | Should -Not -Exist
        }

        It 'should still produce the built .psm1 after clean' {
            $BuiltPsm1 = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psm1'
            $BuiltPsm1 | Should -Exist
        }
    }

    Context '-WhatIf does NOT create output files' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_whatif'
            Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir -WhatIf | Out-Null
        }

        It 'should not create the output .psm1 when -WhatIf is used' {
            $ExpectedPsm1 = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psm1'
            $ExpectedPsm1 | Should -Not -Exist
        }

        It 'should not create the output .psd1 when -WhatIf is used' {
            $ExpectedPsd1 = Join-Path -Path $OutputDir -ChildPath 'SampleModule.psd1'
            $ExpectedPsd1 | Should -Not -Exist
        }
    }

    Context 'Invalid path produces terminating error' {
        It 'should throw a terminating error when given a non-existent path' {
            {
                Build-PSModule -Path 'C:\DoesNotExist\NotAModule' -OutputPath (Join-Path $TempBase 'err_out')
            } | Should -Throw
        }
    }

    Context 'Result object shape' {
        BeforeAll {
            $OutputDir = Join-Path -Path $TempBase -ChildPath 'build_shape'
            $Result    = Build-PSModule -Path $SampleModulePath -OutputPath $OutputDir
        }

        It 'should include ModuleName in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'ModuleName'
        }

        It 'should include SourcePath in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'SourcePath'
        }

        It 'should include FunctionsExported in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'FunctionsExported'
        }

        It 'should include AliasesExported in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'AliasesExported'
        }

        It 'should include FilesMerged in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'FilesMerged'
        }
    }
}
