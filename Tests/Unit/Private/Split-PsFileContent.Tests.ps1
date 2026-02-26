#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # NOTE: Split-PsFileContent.ps1 has comment-based help containing (<# ... #>)
    # which causes parse errors when loaded via dot-source or the module loader.
    # We load it via [Parser]::ParseFile and invoke the resulting AST directly,
    # which is how the PowerShell runtime can handle it correctly.
    $SplitFuncPath = Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'Split-PsFileContent.ps1')
    $ParseErrors = $null
    $Tokens      = $null
    $SplitAst    = [System.Management.Automation.Language.Parser]::ParseFile(
        $SplitFuncPath,
        [ref]$Tokens,
        [ref]$ParseErrors
    )
    # Dot-source the AST scriptblock to define the function in the current scope.
    # Using dot-source (.) rather than .Invoke() ensures the function definition
    # persists in this scope rather than running in a transient child scope.
    . $SplitAst.GetScriptBlock()

    # Fixture path
    $FixturesPath          = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $Script:MonolithicPath = Join-Path -Path $FixturesPath -ChildPath 'MonolithicModule'
    $Script:Psm1Path       = Join-Path -Path $Script:MonolithicPath -ChildPath 'MonolithicModule.psm1'
    $Script:PublicNames    = @('Get-SampleData', 'Set-SampleData')

    # Temp dir for ad-hoc files
    $Script:TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $Script:TempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path $Script:TempDir) {
        Remove-Item -Path $Script:TempDir -Recurse -Force
    }
}

Describe 'Split-PsFileContent' {

    Context 'Return value structure' {
        BeforeAll {
            $Script:Segments = Split-PsFileContent -FilePath $Script:Psm1Path -PublicFunctionNames $Script:PublicNames
        }

        It 'should return an array' {
            $Script:Segments | Should -Not -BeNullOrEmpty
        }

        It 'should return exactly 6 segments from the monolithic file (1 enum + 2 classes + 3 functions)' {
            $Script:Segments.Count | Should -Be 6
        }

        It 'each segment should have a Name property' {
            $Script:Segments | ForEach-Object { $_.Name | Should -Not -BeNullOrEmpty }
        }

        It 'each segment should have a Type property' {
            $Script:Segments | ForEach-Object { $_.Type | Should -Not -BeNullOrEmpty }
        }

        It 'each segment should have a Scope property' {
            $Script:Segments | ForEach-Object { $_.PSObject.Properties.Name | Should -Contain 'Scope' }
        }

        It 'each segment should have a Content property' {
            $Script:Segments | ForEach-Object { $_.Content | Should -Not -BeNullOrEmpty }
        }
    }

    Context 'Function identification - public vs private' {
        BeforeAll {
            $Script:Segments = Split-PsFileContent -FilePath $Script:Psm1Path -PublicFunctionNames $Script:PublicNames
        }

        It 'should mark Get-SampleData as Public' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'Get-SampleData' }
            $Seg.Scope | Should -Be 'Public'
        }

        It 'should mark Set-SampleData as Public' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'Set-SampleData' }
            $Seg.Scope | Should -Be 'Public'
        }

        It 'should mark Invoke-SampleHelper as Private' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'Invoke-SampleHelper' }
            $Seg.Scope | Should -Be 'Private'
        }

        It 'should assign Type=Function to Get-SampleData' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'Get-SampleData' }
            $Seg.Type | Should -Be 'Function'
        }
    }

    Context 'Class identification' {
        BeforeAll {
            $Script:Segments = Split-PsFileContent -FilePath $Script:Psm1Path -PublicFunctionNames $Script:PublicNames
        }

        It 'should extract BaseModel as Type=Class' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'BaseModel' }
            $Seg | Should -Not -BeNullOrEmpty
            $Seg.Type | Should -Be 'Class'
        }

        It 'should extract DerivedModel as Type=Class' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'DerivedModel' }
            $Seg | Should -Not -BeNullOrEmpty
            $Seg.Type | Should -Be 'Class'
        }

        It 'should set Scope=None for classes' {
            $ClassSegs = $Script:Segments | Where-Object { $_.Type -eq 'Class' }
            $ClassSegs | ForEach-Object { $_.Scope | Should -Be 'None' }
        }
    }

    Context 'Enum identification' {
        BeforeAll {
            $Script:Segments = Split-PsFileContent -FilePath $Script:Psm1Path -PublicFunctionNames $Script:PublicNames
        }

        It 'should extract SampleStatus as Type=Enum' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'SampleStatus' }
            $Seg | Should -Not -BeNullOrEmpty
            $Seg.Type | Should -Be 'Enum'
        }

        It 'should set Scope=None for enums' {
            $EnumSegs = $Script:Segments | Where-Object { $_.Type -eq 'Enum' }
            $EnumSegs | ForEach-Object { $_.Scope | Should -Be 'None' }
        }
    }

    Context 'Content extraction' {
        BeforeAll {
            $Script:Segments = Split-PsFileContent -FilePath $Script:Psm1Path -PublicFunctionNames $Script:PublicNames
        }

        It 'should include the function keyword in the extracted content for Get-SampleData' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'Get-SampleData' }
            $Seg.Content | Should -Match 'function Get-SampleData'
        }

        It 'should include the class keyword in the extracted content for BaseModel' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'BaseModel' }
            $Seg.Content | Should -Match 'class BaseModel'
        }

        It 'should include the enum keyword in the extracted content for SampleStatus' {
            $Seg = $Script:Segments | Where-Object { $_.Name -eq 'SampleStatus' }
            $Seg.Content | Should -Match 'enum SampleStatus'
        }
    }

    Context 'Comment-based help preservation' {
        BeforeAll {
            $HelpFile = Join-Path -Path $Script:TempDir -ChildPath 'HelpFunc.ps1'
            Set-Content -Path $HelpFile -Value @'
<#
.SYNOPSIS
    This is the help block.
.DESCRIPTION
    Detailed description here.
#>
function Get-HelpFunction {
    [CmdletBinding()]
    param([string]$X)
    return $X
}
'@
            $Script:HelpSegments = Split-PsFileContent -FilePath $HelpFile -PublicFunctionNames @('Get-HelpFunction')
        }

        It 'should include the comment-based help block in the Content' {
            $Seg = $Script:HelpSegments | Where-Object { $_.Name -eq 'Get-HelpFunction' }
            $Seg.Content | Should -Match '\.SYNOPSIS'
        }
    }

    Context 'All functions private when no PublicFunctionNames specified' {
        BeforeAll {
            $Script:AllPrivate = Split-PsFileContent -FilePath $Script:Psm1Path
        }

        It 'should mark all functions as Private when PublicFunctionNames is empty' {
            $FuncSegs = $Script:AllPrivate | Where-Object { $_.Type -eq 'Function' }
            $FuncSegs | ForEach-Object { $_.Scope | Should -Be 'Private' }
        }
    }
}
