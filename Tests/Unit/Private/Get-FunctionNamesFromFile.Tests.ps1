#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    $PrivateFunctionPath = Join-Path -Path $ModulePath -ChildPath (Join-Path -Path 'Private' -ChildPath 'Get-FunctionNamesFromFile.ps1')
    . $PrivateFunctionPath

    # Fixture path
    $FixturesPath     = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'
    $MonolithicPath   = Join-Path -Path $FixturesPath -ChildPath 'MonolithicModule'

    # Temp dir for ad-hoc files
    $TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
}

Describe 'Get-FunctionNamesFromFile' {

    Context 'Extracting a single function name' {
        It 'should extract Get-SampleData from Get-SampleData.ps1' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = Get-FunctionNamesFromFile -FilePath $FilePath
            $Result   | Should -Contain 'Get-SampleData'
        }

        It 'should return exactly one name from a single-function file' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = Get-FunctionNamesFromFile -FilePath $FilePath
            $Result.Count | Should -Be 1
        }

        It 'should extract Invoke-SampleHelper from a private file' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Private' 'Invoke-SampleHelper.ps1')
            $Result   = Get-FunctionNamesFromFile -FilePath $FilePath
            $Result   | Should -Contain 'Invoke-SampleHelper'
        }
    }

    Context 'Extracting multiple function names from one file' {
        BeforeAll {
            $MultiFunc = Join-Path -Path $TempDir -ChildPath 'Multi-Func.ps1'
            Set-Content -Path $MultiFunc -Value @'
function Get-Alpha {
    param([string]$X)
    return $X
}

function Get-Beta {
    param([string]$Y)
    return $Y
}

function Set-Gamma {
    param([string]$Z)
    $Z
}
'@
        }

        It 'should return all three function names' {
            $Result = Get-FunctionNamesFromFile -FilePath $MultiFunc
            $Result.Count | Should -Be 3
        }

        It 'should include Get-Alpha' {
            $Result = Get-FunctionNamesFromFile -FilePath $MultiFunc
            $Result | Should -Contain 'Get-Alpha'
        }

        It 'should include Get-Beta' {
            $Result = Get-FunctionNamesFromFile -FilePath $MultiFunc
            $Result | Should -Contain 'Get-Beta'
        }

        It 'should include Set-Gamma' {
            $Result = Get-FunctionNamesFromFile -FilePath $MultiFunc
            $Result | Should -Contain 'Set-Gamma'
        }
    }

    Context 'Extracting from the monolithic module file' {
        BeforeAll {
            $Psm1Path = Join-Path -Path $MonolithicPath -ChildPath 'MonolithicModule.psm1'
            $Result   = Get-FunctionNamesFromFile -FilePath $Psm1Path
        }

        It 'should find three top-level functions in the monolithic file' {
            $Result.Count | Should -Be 3
        }

        It 'should include Get-SampleData' {
            $Result | Should -Contain 'Get-SampleData'
        }

        It 'should include Set-SampleData' {
            $Result | Should -Contain 'Set-SampleData'
        }

        It 'should include Invoke-SampleHelper' {
            $Result | Should -Contain 'Invoke-SampleHelper'
        }
    }

    Context 'File with no functions' {
        BeforeAll {
            $NoFuncFile = Join-Path -Path $TempDir -ChildPath 'NoFunctions.ps1'
            Set-Content -Path $NoFuncFile -Value @'
# This file contains no function definitions
$Script:SomeVariable = 42
Write-Verbose "Loaded"
'@
        }

        It 'should return an empty array for a file with no functions' {
            $Result = Get-FunctionNamesFromFile -FilePath $NoFuncFile
            $Result.Count | Should -Be 0
        }
    }

    Context 'File with nested functions' {
        BeforeAll {
            $NestedFile = Join-Path -Path $TempDir -ChildPath 'Nested-Func.ps1'
            Set-Content -Path $NestedFile -Value @'
function Outer-Function {
    param([string]$X)

    function Inner-Function {
        param([string]$Y)
        return $Y
    }

    return Inner-Function -Y $X
}
'@
        }

        It 'should return only the top-level outer function' {
            $Result = Get-FunctionNamesFromFile -FilePath $NestedFile
            $Result | Should -Contain 'Outer-Function'
        }

        It 'should NOT return the nested inner function' {
            $Result = Get-FunctionNamesFromFile -FilePath $NestedFile
            $Result | Should -Not -Contain 'Inner-Function'
        }

        It 'should return exactly one name' {
            $Result = Get-FunctionNamesFromFile -FilePath $NestedFile
            $Result.Count | Should -Be 1
        }
    }

    Context 'File with class methods' {
        BeforeAll {
            $ClassFile = Join-Path -Path $TempDir -ChildPath 'ClassMethod.ps1'
            Set-Content -Path $ClassFile -Value @'
class MyClass {
    [string]$Name

    [string] GetName() {
        return $this.Name
    }

    [void] SetName([string]$Name) {
        $this.Name = $Name
    }
}
'@
        }

        It 'should not extract class methods as functions' {
            $Result = Get-FunctionNamesFromFile -FilePath $ClassFile
            $Result.Count | Should -Be 0
        }
    }

    Context 'Pipeline input' {
        It 'should accept file path from pipeline' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = $FilePath | Get-FunctionNamesFromFile
            $Result   | Should -Contain 'Get-SampleData'
        }
    }
}
