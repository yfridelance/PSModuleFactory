#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private functions we need
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'Resolve-ModuleSourcePaths.ps1'))
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'Merge-SourceFiles.ps1'))

    # Replicate module-scope variables that private functions depend on.
    # When dot-sourced, $Script: refers to THIS file's script scope, not the module scope.
    $Script:LoadOrderFolders = @('Enums', 'Classes', 'Private', 'Public')

    # Fixture path
    $FixturesPath     = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'Fixtures'))
    $SampleModulePath = Join-Path -Path $FixturesPath -ChildPath 'SampleModule'

    # Resolve source paths for SampleModule and merge
    $SourcePaths  = Resolve-ModuleSourcePaths -ModuleRoot $SampleModulePath
    $MergedOutput = Merge-SourceFiles -SourcePaths $SourcePaths
}

Describe 'Merge-SourceFiles' {

    Context 'Section order - Enums before Classes before Private before Public' {
        It 'should place Enums content before Classes content' {
            $EnumsPos   = $MergedOutput.IndexOf('#region ======== Enums ========')
            $ClassesPos = $MergedOutput.IndexOf('#region ======== Classes ========')
            $EnumsPos | Should -BeLessThan $ClassesPos -Because 'Enums must appear before Classes in the merge output'
        }

        It 'should place Classes content before Private content' {
            $ClassesPos  = $MergedOutput.IndexOf('#region ======== Classes ========')
            $PrivatePos  = $MergedOutput.IndexOf('#region ======== Private ========')
            $ClassesPos | Should -BeLessThan $PrivatePos -Because 'Classes must appear before Private in the merge output'
        }

        It 'should place Private content before Public content' {
            $PrivatePos = $MergedOutput.IndexOf('#region ======== Private ========')
            $PublicPos  = $MergedOutput.IndexOf('#region ======== Public ========')
            $PrivatePos | Should -BeLessThan $PublicPos -Because 'Private must appear before Public in the merge output'
        }
    }

    Context 'Section headers - #region markers' {
        It 'should include a section header for Enums' {
            $MergedOutput | Should -Match ([regex]::Escape('#region ======== Enums ========'))
        }

        It 'should include a section header for Classes' {
            $MergedOutput | Should -Match ([regex]::Escape('#region ======== Classes ========'))
        }

        It 'should include a section header for Private' {
            $MergedOutput | Should -Match ([regex]::Escape('#region ======== Private ========'))
        }

        It 'should include a section header for Public' {
            $MergedOutput | Should -Match ([regex]::Escape('#region ======== Public ========'))
        }

        It 'should include matching endregion markers for Enums' {
            $MergedOutput | Should -Match ([regex]::Escape('#endregion ======== Enums ========'))
        }

        It 'should include matching endregion markers for Public' {
            $MergedOutput | Should -Match ([regex]::Escape('#endregion ======== Public ========'))
        }
    }

    Context 'Per-file region markers' {
        It 'should include a per-file region for SampleStatus.Enum.ps1' {
            $MergedOutput | Should -Match ([regex]::Escape('#region SampleStatus.Enum.ps1'))
        }

        It 'should include a per-file endregion for SampleStatus.Enum.ps1' {
            $MergedOutput | Should -Match ([regex]::Escape('#endregion SampleStatus.Enum.ps1'))
        }

        It 'should include a per-file region for Get-SampleData.ps1' {
            $MergedOutput | Should -Match ([regex]::Escape('#region Get-SampleData.ps1'))
        }

        It 'should include a per-file region for Invoke-SampleHelper.ps1' {
            $MergedOutput | Should -Match ([regex]::Escape('#region Invoke-SampleHelper.ps1'))
        }
    }

    Context 'Dot-source line stripping' {
        It 'should not contain dot-source lines starting with . and a .ps1 path' {
            # The dev psm1 uses ". $File.FullName" — after merge, no such lines should remain
            $MergedOutput | Should -Not -Match '(?m)^\s*\.\s+.*\.ps1\s*$'
        }
    }

    Context 'Function content present' {
        It 'should contain the Get-SampleData function body' {
            $MergedOutput | Should -Match 'function Get-SampleData'
        }

        It 'should contain the Set-SampleData function body' {
            $MergedOutput | Should -Match 'function Set-SampleData'
        }

        It 'should contain the Invoke-SampleHelper function body' {
            $MergedOutput | Should -Match 'function Invoke-SampleHelper'
        }

        It 'should contain the BaseModel class definition' {
            $MergedOutput | Should -Match 'class BaseModel'
        }

        It 'should contain the SampleStatus enum definition' {
            $MergedOutput | Should -Match 'enum SampleStatus'
        }
    }

    Context 'CRLF line endings' {
        It 'should use CRLF line endings throughout the merged output' {
            $MergedOutput | Should -Match "`r`n"
        }

        It 'should not contain bare LF-only line endings' {
            # After normalisation there should be no lone LF (every LF should be preceded by CR)
            $BareNL = $MergedOutput -replace "`r`n", '' | Select-String -Pattern "`n" -SimpleMatch
            $BareNL | Should -BeNullOrEmpty -Because 'all line endings should be CRLF, not bare LF'
        }
    }

    Context 'Empty sections are skipped' {
        BeforeAll {
            # Build a minimal source dict with only Public populated
            $EmptyDict = [System.Collections.Specialized.OrderedDictionary]::new()
            $EmptyDict['Enums']   = [System.IO.FileInfo[]]@()
            $EmptyDict['Classes'] = [System.IO.FileInfo[]]@()
            $EmptyDict['Private'] = [System.IO.FileInfo[]]@()

            $PublicFile = Join-Path -Path $SampleModulePath -ChildPath (Join-Path 'Public' 'Get-SampleData.ps1')
            $EmptyDict['Public'] = [System.IO.FileInfo[]]@([System.IO.FileInfo]::new($PublicFile))

            $OutputPartial = Merge-SourceFiles -SourcePaths $EmptyDict
        }

        It 'should not include section header for empty Enums section' {
            $OutputPartial | Should -Not -Match ([regex]::Escape('#region ======== Enums ========'))
        }

        It 'should still include section header for populated Public section' {
            $OutputPartial | Should -Match ([regex]::Escape('#region ======== Public ========'))
        }
    }
}
