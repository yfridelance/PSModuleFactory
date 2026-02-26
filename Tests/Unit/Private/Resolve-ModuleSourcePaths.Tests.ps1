#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    $PrivateFunctionPath = Join-Path -Path $ModulePath -ChildPath (Join-Path -Path 'Private' -ChildPath 'Resolve-ModuleSourcePaths.ps1')
    . $PrivateFunctionPath

    # Replicate the module-scope variable that the private function depends on.
    # When dot-sourced, $Script: refers to THIS file's script scope, not the module scope.
    $Script:LoadOrderFolders = @('Enums', 'Classes', 'Private', 'Public')

    # Fixture path
    $FixturesPath     = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'
}

Describe 'Resolve-ModuleSourcePaths' {

    Context 'Happy path - SampleModule fixture' {
        BeforeAll {
            $Result = Resolve-ModuleSourcePaths -ModuleRoot $SampleModulePath
        }

        It 'should return an ordered dictionary' {
            $Result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        }

        It 'should return an ordered dictionary with four keys' {
            $Result.Count | Should -Be 4
        }

        It 'should contain the key Enums' {
            $Result.Contains('Enums') | Should -BeTrue
        }

        It 'should contain the key Classes' {
            $Result.Contains('Classes') | Should -BeTrue
        }

        It 'should contain the key Private' {
            $Result.Contains('Private') | Should -BeTrue
        }

        It 'should contain the key Public' {
            $Result.Contains('Public') | Should -BeTrue
        }

        It 'should have Enums files as FileInfo objects' {
            $Result['Enums'][0] | Should -BeOfType [System.IO.FileInfo]
        }

        It 'should find exactly one Enum file' {
            $Result['Enums'].Count | Should -Be 1
        }

        It 'should find exactly two Class files' {
            $Result['Classes'].Count | Should -Be 2
        }

        It 'should find exactly one Private file' {
            $Result['Private'].Count | Should -Be 1
        }

        It 'should find exactly two Public files' {
            $Result['Public'].Count | Should -Be 2
        }
    }

    Context 'Enum sorting - numeric prefix order' {
        BeforeAll {
            $Result = Resolve-ModuleSourcePaths -ModuleRoot $SampleModulePath
        }

        It 'should return SampleStatus.Enum.ps1 as the only enum file' {
            $Result['Enums'][0].Name | Should -Be 'SampleStatus.Enum.ps1'
        }
    }

    Context 'Class sorting - numeric prefix order' {
        BeforeAll {
            $Result = Resolve-ModuleSourcePaths -ModuleRoot $SampleModulePath
        }

        It 'should return 01_BaseModel.Class.ps1 before 02_DerivedModel.Class.ps1' {
            $Result['Classes'][0].Name | Should -Be '01_BaseModel.Class.ps1'
            $Result['Classes'][1].Name | Should -Be '02_DerivedModel.Class.ps1'
        }
    }

    Context 'Private and Public - alphabetical sorting' {
        BeforeAll {
            $Result = Resolve-ModuleSourcePaths -ModuleRoot $SampleModulePath
        }

        It 'should return Public files in alphabetical order' {
            $Result['Public'][0].Name | Should -Be 'Get-SampleData.ps1'
            $Result['Public'][1].Name | Should -Be 'Set-SampleData.ps1'
        }

        It 'should return Private files in alphabetical order' {
            $Result['Private'][0].Name | Should -Be 'Invoke-SampleHelper.ps1'
        }
    }

    Context 'Missing directories' {
        BeforeAll {
            # Create a temp dir with no subdirectories
            $TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
            New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null

            # Create only a Public dir, no Enums/Classes/Private
            New-Item -Path (Join-Path $TempRoot 'Public') -ItemType Directory -Force | Out-Null
            $PublicDir = Join-Path -Path $TempRoot -ChildPath 'Public'
            Set-Content -Path (Join-Path -Path $PublicDir -ChildPath 'Test-Func.ps1') -Value 'function Test-Func { }'

            $Result = Resolve-ModuleSourcePaths -ModuleRoot $TempRoot
        }

        AfterAll {
            if (Test-Path $TempRoot) {
                Remove-Item -Path $TempRoot -Recurse -Force
            }
        }

        It 'should return empty array for Enums when directory is missing' {
            $Result['Enums'].Count | Should -Be 0
        }

        It 'should return empty array for Classes when directory is missing' {
            $Result['Classes'].Count | Should -Be 0
        }

        It 'should return empty array for Private when directory is missing' {
            $Result['Private'].Count | Should -Be 0
        }

        It 'should still return files for Public when Public dir exists' {
            $Result['Public'].Count | Should -Be 1
        }
    }

    Context 'Empty directories' {
        BeforeAll {
            $TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
            New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
            foreach ($Dir in @('Enums', 'Classes', 'Private', 'Public')) {
                New-Item -Path (Join-Path $TempRoot $Dir) -ItemType Directory -Force | Out-Null
            }

            $Result = Resolve-ModuleSourcePaths -ModuleRoot $TempRoot
        }

        AfterAll {
            if (Test-Path $TempRoot) {
                Remove-Item -Path $TempRoot -Recurse -Force
            }
        }

        It 'should return empty array for Enums when directory is empty' {
            $Result['Enums'].Count | Should -Be 0
        }

        It 'should return empty array for Classes when directory is empty' {
            $Result['Classes'].Count | Should -Be 0
        }

        It 'should return empty array for Private when directory is empty' {
            $Result['Private'].Count | Should -Be 0
        }

        It 'should return empty array for Public when directory is empty' {
            $Result['Public'].Count | Should -Be 0
        }
    }

    Context 'Non-module directory' {
        BeforeAll {
            $TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
            New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null

            $Result = Resolve-ModuleSourcePaths -ModuleRoot $TempRoot
        }

        AfterAll {
            if (Test-Path $TempRoot) {
                Remove-Item -Path $TempRoot -Recurse -Force
            }
        }

        It 'should return empty arrays for all sections when directory has no module subdirs' {
            $Result['Enums'].Count   | Should -Be 0
            $Result['Classes'].Count | Should -Be 0
            $Result['Private'].Count | Should -Be 0
            $Result['Public'].Count  | Should -Be 0
        }
    }
}
