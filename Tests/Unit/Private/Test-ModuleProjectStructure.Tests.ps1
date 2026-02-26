#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'Test-ModuleProjectStructure.ps1'))

    # Replicate module-scope variables that private functions depend on.
    # When dot-sourced, $Script: refers to THIS file's script scope, not the module scope.
    $Script:LoadOrderFolders = @('Enums', 'Classes', 'Private', 'Public')

    # Fixture path
    $FixturesPath              = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $Script:SampleModulePath   = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'

    # Temp dir for incomplete/invalid module setups
    $Script:TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $Script:TempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $Script:TempDir) {
        Remove-Item -Path $Script:TempDir -Recurse -Force
    }
}

Describe 'Test-ModuleProjectStructure' {

    Context 'Valid module - SampleModule fixture' {
        BeforeAll {
            $Result = Test-ModuleProjectStructure -Path $Script:SampleModulePath
        }

        It 'should return IsValid = true for a valid module structure' {
            $Result.IsValid | Should -BeTrue
        }

        It 'should return the correct ModuleName' {
            $Result.ModuleName | Should -Be 'SampleModule'
        }

        It 'should return a non-null ManifestPath' {
            $Result.ManifestPath | Should -Not -BeNullOrEmpty
        }

        It 'should return a non-null RootModulePath' {
            $Result.RootModulePath | Should -Not -BeNullOrEmpty
        }

        It 'should return an empty Errors array' {
            $Result.Errors.Count | Should -Be 0
        }
    }

    Context 'Missing .psd1 manifest' {
        BeforeAll {
            $NoPsd1Dir = Join-Path -Path $Script:TempDir -ChildPath 'NoPsd1Module'
            New-Item -Path $NoPsd1Dir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $NoPsd1Dir 'NoPsd1Module.psm1') -Value '# empty'

            $Result = Test-ModuleProjectStructure -Path $NoPsd1Dir
        }

        It 'should return IsValid = false when .psd1 is missing' {
            $Result.IsValid | Should -BeFalse
        }

        It 'should include an error message about missing .psd1' {
            $Result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Missing .psm1 root module' {
        BeforeAll {
            $NoPsm1Dir = Join-Path -Path $Script:TempDir -ChildPath 'NoPsm1Module'
            New-Item -Path $NoPsm1Dir -ItemType Directory -Force | Out-Null

            New-ModuleManifest -Path (Join-Path $NoPsm1Dir 'NoPsm1Module.psd1') `
                -RootModule 'NoPsm1Module.psm1' `
                -ModuleVersion '1.0.0' `
                -Author 'Test'
            # Do NOT create the .psm1

            $Result = Test-ModuleProjectStructure -Path $NoPsm1Dir
        }

        It 'should return IsValid = false when .psm1 is missing' {
            $Result.IsValid | Should -BeFalse
        }

        It 'should include an error mentioning the missing root module file' {
            $Result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Multiple .psd1 files' {
        BeforeAll {
            $MultiPsd1Dir = Join-Path -Path $Script:TempDir -ChildPath 'MultiPsd1Module'
            New-Item -Path $MultiPsd1Dir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $MultiPsd1Dir 'Module.psm1')  -Value '# psm1'
            Set-Content -Path (Join-Path $MultiPsd1Dir 'Module1.psd1') -Value '@{ ModuleVersion = "1.0.0" }'
            Set-Content -Path (Join-Path $MultiPsd1Dir 'Module2.psd1') -Value '@{ ModuleVersion = "1.0.0" }'

            $Result = Test-ModuleProjectStructure -Path $MultiPsd1Dir
        }

        It 'should return IsValid = false when multiple .psd1 files are found' {
            $Result.IsValid | Should -BeFalse
        }

        It 'should report an error about multiple manifests' {
            $Result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'No source subdirectories - warning issued' {
        BeforeAll {
            $MinimalName = 'MinimalWarningModule'
            $MinimalDir  = Join-Path -Path $Script:TempDir -ChildPath $MinimalName
            New-Item -Path $MinimalDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $MinimalDir "$MinimalName.psm1") -Value '# empty'
            New-ModuleManifest -Path (Join-Path $MinimalDir "$MinimalName.psd1") `
                -RootModule "$MinimalName.psm1" `
                -ModuleVersion '1.0.0' `
                -Author 'Test'

            $Result = Test-ModuleProjectStructure -Path $MinimalDir
        }

        It 'should return IsValid = true (no subdirectories is a warning, not an error)' {
            $Result.IsValid | Should -BeTrue
        }

        It 'should include a warning about missing source subdirectories' {
            $Result.Warnings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Return object shape' {
        BeforeAll {
            $Result = Test-ModuleProjectStructure -Path $Script:SampleModulePath
        }

        It 'should have an IsValid property' {
            $Result.PSObject.Properties.Name | Should -Contain 'IsValid'
        }

        It 'should have a ModuleName property' {
            $Result.PSObject.Properties.Name | Should -Contain 'ModuleName'
        }

        It 'should have an Errors property' {
            $Result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'should have a Warnings property' {
            $Result.PSObject.Properties.Name | Should -Contain 'Warnings'
        }

        It 'should have a ManifestPath property' {
            $Result.PSObject.Properties.Name | Should -Contain 'ManifestPath'
        }

        It 'should have a RootModulePath property' {
            $Result.PSObject.Properties.Name | Should -Contain 'RootModulePath'
        }
    }
}
