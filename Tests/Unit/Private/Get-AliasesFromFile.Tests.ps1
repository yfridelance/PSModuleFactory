#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    $PrivateFunctionPath = Join-Path -Path $ModulePath -ChildPath (Join-Path -Path 'Private' -ChildPath 'Get-AliasesFromFile.ps1')
    . $PrivateFunctionPath

    # Fixture path
    $FixturesPath     = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'

    # Temp dir for ad-hoc files
    $TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
}

Describe 'Get-AliasesFromFile' {

    Context 'Extracting a single alias' {
        It 'should extract gsd from Get-SampleData.ps1' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = Get-AliasesFromFile -FilePath $FilePath
            $Result   | Should -Contain 'gsd'
        }

        It 'should return exactly one alias for Get-SampleData.ps1' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = Get-AliasesFromFile -FilePath $FilePath
            $Result.Count | Should -Be 1
        }
    }

    Context 'Extracting comma-separated aliases from one annotation line' {
        It 'should extract all aliases from Set-SampleData.ps1' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Set-SampleData.ps1')
            $Result   = Get-AliasesFromFile -FilePath $FilePath
            $Result   | Should -Contain 'ssd'
            $Result   | Should -Contain 'setsd'
        }

        It 'should return exactly two aliases for Set-SampleData.ps1' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Set-SampleData.ps1')
            $Result   = Get-AliasesFromFile -FilePath $FilePath
            $Result.Count | Should -Be 2
        }
    }

    Context 'Extracting multiple Alias annotation lines' {
        BeforeAll {
            $MultiAliasFile = Join-Path -Path $TempDir -ChildPath 'MultiAlias-Func.ps1'
            Set-Content -Path $MultiAliasFile -Value @'
function Get-MultiAlias {
    # Alias: gma
    # Alias: GetMA, g-ma
    [CmdletBinding()]
    param()
    return 'result'
}
'@
        }

        It 'should extract all aliases from multiple annotation lines' {
            $Result = Get-AliasesFromFile -FilePath $MultiAliasFile
            $Result | Should -Contain 'gma'
            $Result | Should -Contain 'GetMA'
            $Result | Should -Contain 'g-ma'
        }

        It 'should return three aliases total' {
            $Result = Get-AliasesFromFile -FilePath $MultiAliasFile
            $Result.Count | Should -Be 3
        }
    }

    Context 'No alias annotations' {
        It 'should return empty array for Invoke-SampleHelper.ps1 which has no aliases' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Private' 'Invoke-SampleHelper.ps1')
            $Result   = Get-AliasesFromFile -FilePath $FilePath
            $Result.Count | Should -Be 0
        }

        It 'should return empty array for a file with no alias annotation' {
            $NoAliasFile = Join-Path -Path $TempDir -ChildPath 'NoAlias-Func.ps1'
            Set-Content -Path $NoAliasFile -Value @'
function Get-NoAlias {
    [CmdletBinding()]
    param([string]$X)
    return $X
}
'@
            $Result = Get-AliasesFromFile -FilePath $NoAliasFile
            $Result.Count | Should -Be 0
        }
    }

    Context 'Whitespace variations in annotation' {
        BeforeAll {
            $WhitespaceFile = Join-Path -Path $TempDir -ChildPath 'Whitespace-Func.ps1'
            Set-Content -Path $WhitespaceFile -Value @'
function Get-WhitespaceTest {
    #Alias:ws1
    # Alias  :   ws2  ,  ws3
    [CmdletBinding()]
    param()
}
'@
        }

        It 'should handle no space after hash' {
            $Result = Get-AliasesFromFile -FilePath $WhitespaceFile
            $Result | Should -Contain 'ws1'
        }

        It 'should trim alias names with extra spaces' {
            $Result = Get-AliasesFromFile -FilePath $WhitespaceFile
            $Result | Should -Contain 'ws2'
            $Result | Should -Contain 'ws3'
        }
    }

    Context 'Pipeline input' {
        It 'should accept file path from pipeline' {
            $FilePath = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $Result   = $FilePath | Get-AliasesFromFile
            $Result   | Should -Contain 'gsd'
        }
    }
}
