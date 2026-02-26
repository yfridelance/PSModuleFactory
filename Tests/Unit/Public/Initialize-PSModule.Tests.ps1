#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Temp base directory for all scaffold tests
    $TempBase = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModInit_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempBase -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $TempBase) {
        Remove-Item -Path $TempBase -Recurse -Force
    }
}

Describe 'Initialize-PSModule' {

    Context 'Happy path - creates module structure in temp dir' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'happy'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName = 'TestModule.Happy'
            $Result = Initialize-PSModule -ModuleName $ModuleName -Path $ScaffoldPath -Author 'TestUser' -Description 'Test module' -Version '1.0.0' -License 'None'
        }

        It 'should return a result object with Success = true' {
            $Result.Success | Should -BeTrue
        }

        It 'should return the correct ModuleName in the result' {
            $Result.ModuleName | Should -Be $ModuleName
        }

        It 'should create the module root directory' {
            $Result.ModulePath | Should -Exist
        }
    }

    Context 'All four subdirectories are created' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'subdirs'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName = 'TestModule.SubDirs'
            $Result     = Initialize-PSModule -ModuleName $ModuleName -Path $ScaffoldPath -License 'None'
            $ModuleRoot = $Result.ModulePath
        }

        It 'should create the Public subdirectory' {
            (Join-Path -Path $ModuleRoot -ChildPath 'Public') | Should -Exist
        }

        It 'should create the Private subdirectory' {
            (Join-Path -Path $ModuleRoot -ChildPath 'Private') | Should -Exist
        }

        It 'should create the Classes subdirectory' {
            (Join-Path -Path $ModuleRoot -ChildPath 'Classes') | Should -Exist
        }

        It 'should create the Enums subdirectory' {
            (Join-Path -Path $ModuleRoot -ChildPath 'Enums') | Should -Exist
        }
    }

    Context '.psm1 and .psd1 are created' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'files'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName = 'TestModule.Files'
            $Result     = Initialize-PSModule -ModuleName $ModuleName -Path $ScaffoldPath -License 'None'
            $ModuleRoot = $Result.ModulePath
        }

        It 'should create the .psm1 file' {
            $Result.RootModulePath | Should -Exist
        }

        It 'should create the .psd1 manifest file' {
            $Result.ManifestPath | Should -Exist
        }

        It 'should name the .psm1 correctly' {
            [System.IO.Path]::GetFileName($Result.RootModulePath) | Should -Be "$ModuleName.psm1"
        }

        It 'should name the .psd1 correctly' {
            [System.IO.Path]::GetFileName($Result.ManifestPath) | Should -Be "$ModuleName.psd1"
        }
    }

    Context '.psd1 has correct metadata' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'metadata'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName = 'TestModule.Meta'
            $Result     = Initialize-PSModule -ModuleName $ModuleName `
                -Path $ScaffoldPath `
                -Author 'JohnDoe' `
                -Description 'My test description' `
                -Version '2.1.0' `
                -License 'None'

            $ManifestData = Import-PowerShellDataFile -Path $Result.ManifestPath
        }

        It 'should set the correct ModuleVersion' {
            $ManifestData.ModuleVersion | Should -Be '2.1.0'
        }

        It 'should set the correct Author' {
            $ManifestData.Author | Should -Be 'JohnDoe'
        }

        It 'should set the correct Description' {
            $ManifestData.Description | Should -Be 'My test description'
        }

        It 'should set RootModule to the .psm1 filename' {
            $ManifestData.RootModule | Should -Be "$ModuleName.psm1"
        }

        It 'should start with FunctionsToExport as empty array' {
            # New module has no functions yet
            ($ManifestData.FunctionsToExport | Where-Object { $_ -and $_ -ne '*' }).Count | Should -Be 0
        }
    }

    Context '-WhatIf does NOT create anything' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'whatif'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName  = 'TestModule.WhatIf'
            $ExpectedDir = Join-Path -Path $ScaffoldPath -ChildPath $ModuleName

            Initialize-PSModule -ModuleName $ModuleName -Path $ScaffoldPath -License 'None' -WhatIf | Out-Null
        }

        It 'should not create the module directory when -WhatIf is specified' {
            $ExpectedDir | Should -Not -Exist
        }
    }

    Context 'Already-existing path produces terminating error' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'exists'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $ModuleName   = 'TestModule.Exists'
            $ExistingPath = Join-Path -Path $ScaffoldPath -ChildPath $ModuleName
            New-Item -Path $ExistingPath -ItemType Directory -Force | Out-Null
        }

        It 'should throw a terminating error when the module directory already exists' {
            {
                Initialize-PSModule -ModuleName $ModuleName -Path $ScaffoldPath -License 'None'
            } | Should -Throw
        }
    }

    Context 'Result object shape' {
        BeforeAll {
            $ScaffoldPath = Join-Path -Path $TempBase -ChildPath 'shape'
            New-Item -Path $ScaffoldPath -ItemType Directory -Force | Out-Null

            $Result = Initialize-PSModule -ModuleName 'TestModule.Shape' -Path $ScaffoldPath -License 'None'
        }

        It 'should include ModuleName in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'ModuleName'
        }

        It 'should include ModulePath in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'ModulePath'
        }

        It 'should include ManifestPath in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'ManifestPath'
        }

        It 'should include RootModulePath in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'RootModulePath'
        }

        It 'should include DirectoriesCreated in the result' {
            $Result.PSObject.Properties.Name | Should -Contain 'DirectoriesCreated'
        }
    }
}
