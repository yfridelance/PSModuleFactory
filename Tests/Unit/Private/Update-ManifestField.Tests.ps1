#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'Update-ManifestField.ps1'))

    # Replicate module-scope variables that private functions depend on.
    # When dot-sourced, $Script: refers to THIS file's script scope, not the module scope.
    $Script:DefaultEncoding = [System.Text.UTF8Encoding]::new($true)

    # Temp dir for writable manifests
    $Script:TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSModTest_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $Script:TempDir -ItemType Directory -Force | Out-Null

    # Create a reference manifest in the temp dir with proper @() array syntax
    # This ensures the regex in Update-ManifestField will match correctly.
    $Script:RefManifestPath = Join-Path -Path $Script:TempDir -ChildPath 'RefModule.psd1'
    New-ModuleManifest -Path $Script:RefManifestPath `
        -RootModule 'RefModule.psm1' `
        -ModuleVersion '1.0.0' `
        -Author 'TestAuthor' `
        -Description 'Reference manifest for Update-ManifestField tests' `
        -FunctionsToExport @('Get-RefFunction') `
        -AliasesToExport @('grf')
}

AfterAll {
    if (Test-Path $Script:TempDir) {
        Remove-Item -Path $Script:TempDir -Recurse -Force
    }
}

Describe 'Update-ManifestField' {

    Context 'Array field - FunctionsToExport with 3 or fewer items (single-line)' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'FunctionsToExport' -Value @('Get-One', 'Get-Two', 'Get-Three')
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
        }

        It 'should write FunctionsToExport in single-line format when 3 or fewer items' {
            $Content | Should -Match ([regex]::Escape("@('Get-One', 'Get-Two', 'Get-Three')"))
        }

        It 'should contain all three function names after update' {
            $Data = Import-PowerShellDataFile -Path $ManifestCopy
            $Data.FunctionsToExport | Should -Contain 'Get-One'
            $Data.FunctionsToExport | Should -Contain 'Get-Two'
            $Data.FunctionsToExport | Should -Contain 'Get-Three'
        }
    }

    Context 'Array field - FunctionsToExport with more than 3 items (multi-line)' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            $Functions = @('Get-One', 'Get-Two', 'Get-Three', 'Get-Four')
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'FunctionsToExport' -Value $Functions
            $Content = [System.IO.File]::ReadAllText($ManifestCopy, [System.Text.Encoding]::UTF8)
        }

        It 'should write FunctionsToExport in multi-line format when more than 3 items' {
            # Multi-line: starts with @( on its own and has items on separate lines
            $Content | Should -Match "FunctionsToExport\s*=\s*@\("
            $Content | Should -Match "'Get-One'"
            $Content | Should -Match "'Get-Four'"
        }

        It 'should contain all four function names' {
            $Data = Import-PowerShellDataFile -Path $ManifestCopy
            $Data.FunctionsToExport.Count | Should -Be 4
        }
    }

    Context 'Scalar field - ModuleVersion' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'ModuleVersion' -Value '2.3.4'
            $Data = Import-PowerShellDataFile -Path $ManifestCopy
        }

        It 'should update the ModuleVersion to the specified value' {
            $Data.ModuleVersion | Should -Be '2.3.4'
        }
    }

    Context 'Scalar field - Description' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'Description' -Value 'Updated description for testing'
            $Data = Import-PowerShellDataFile -Path $ManifestCopy
        }

        It 'should update the Description to the specified value' {
            $Data.Description | Should -Be 'Updated description for testing'
        }
    }

    Context 'Preserves other fields unchanged' {
        BeforeAll {
            $ManifestCopy    = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            $OriginalData    = Import-PowerShellDataFile -Path $ManifestCopy
            $OriginalAuthor  = $OriginalData.Author
            $OriginalRootMod = $OriginalData.RootModule

            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'ModuleVersion' -Value '9.9.9'

            $UpdatedData = Import-PowerShellDataFile -Path $ManifestCopy
        }

        It 'should not change the Author field' {
            $UpdatedData.Author | Should -Be $OriginalAuthor
        }

        It 'should not change the RootModule field' {
            $UpdatedData.RootModule | Should -Be $OriginalRootMod
        }
    }

    Context 'UTF-8 BOM encoding' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'ModuleVersion' -Value '1.2.3'
            $Bytes = [System.IO.File]::ReadAllBytes($ManifestCopy)
        }

        It 'should write the file with a UTF-8 BOM (EF BB BF)' {
            $Bytes[0] | Should -Be 0xEF -Because 'UTF-8 BOM first byte should be 0xEF'
            $Bytes[1] | Should -Be 0xBB -Because 'UTF-8 BOM second byte should be 0xBB'
            $Bytes[2] | Should -Be 0xBF -Because 'UTF-8 BOM third byte should be 0xBF'
        }
    }

    Context 'AliasesToExport array field' {
        BeforeAll {
            $ManifestCopy = Join-Path -Path $Script:TempDir -ChildPath ([guid]::NewGuid().ToString('N') + '.psd1')
            Copy-Item -Path $Script:RefManifestPath -Destination $ManifestCopy -Force
            Update-ManifestField -ManifestPath $ManifestCopy -FieldName 'AliasesToExport' -Value @('al1', 'al2')
            $Data = Import-PowerShellDataFile -Path $ManifestCopy
        }

        It 'should update AliasesToExport with the specified aliases' {
            $Data.AliasesToExport | Should -Contain 'al1'
            $Data.AliasesToExport | Should -Contain 'al2'
        }
    }

    Context 'Scalar field - Prerelease (nested in PSData)' {
        BeforeAll {
            $Script:PrereleaseManifestPath = Join-Path -Path $Script:TempDir -ChildPath 'PrereleaseTest.psd1'
        }

        BeforeEach {
            # Create a fresh copy for each test
            Copy-Item -Path $Script:RefManifestPath -Destination $Script:PrereleaseManifestPath -Force
            # Uncomment the Prerelease field so Update-ManifestField can locate and replace it
            $Content = [System.IO.File]::ReadAllText($Script:PrereleaseManifestPath, [System.Text.Encoding]::UTF8)
            $Content = $Content -replace '# Prerelease = ''''', 'Prerelease = '''''
            [System.IO.File]::WriteAllText($Script:PrereleaseManifestPath, $Content, [System.Text.UTF8Encoding]::new($true))
        }

        It 'should set Prerelease to a preview string' {
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'preview1'
            $Data = Import-PowerShellDataFile -Path $Script:PrereleaseManifestPath
            $Data.PrivateData.PSData.Prerelease | Should -Be 'preview1'
        }

        It 'should clear Prerelease by setting to empty string' {
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'preview1'
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value ''
            $Data = Import-PowerShellDataFile -Path $Script:PrereleaseManifestPath
            $Data.PrivateData.PSData.Prerelease | Should -Be ''
        }

        It 'should handle hyphenated prerelease strings' {
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'beta-1'
            $Data = Import-PowerShellDataFile -Path $Script:PrereleaseManifestPath
            $Data.PrivateData.PSData.Prerelease | Should -Be 'beta-1'
        }

        It 'should preserve other manifest fields when updating Prerelease' {
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'preview1'
            $Data = Import-PowerShellDataFile -Path $Script:PrereleaseManifestPath
            # Verify Prerelease was updated
            $Data.PrivateData.PSData.Prerelease | Should -Be 'preview1'
            # Verify top-level fields are preserved
            $Data.ModuleVersion | Should -Be '1.0.0'
            $Data.Author | Should -Be 'TestAuthor'
            $Data.RootModule | Should -Be 'RefModule.psm1'
        }

        It 'should update Prerelease when it already has a value' {
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'alpha1'
            Update-ManifestField -ManifestPath $Script:PrereleaseManifestPath -FieldName 'Prerelease' -Value 'beta2'
            $Data = Import-PowerShellDataFile -Path $Script:PrereleaseManifestPath
            $Data.PrivateData.PSData.Prerelease | Should -Be 'beta2'
        }
    }
}
