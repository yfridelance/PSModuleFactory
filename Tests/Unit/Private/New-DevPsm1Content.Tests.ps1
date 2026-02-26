#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'yvfrii.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'New-DevPsm1Content.ps1'))

    $TestModuleName = 'MyCompany.PS.TestModule'
    $Content        = New-DevPsm1Content -ModuleName $TestModuleName
}

Describe 'New-DevPsm1Content' {

    Context 'Return type and basic structure' {
        It 'should return a non-null string' {
            $Content | Should -Not -BeNullOrEmpty
        }

        It 'should return a string type' {
            $Content | Should -BeOfType [string]
        }
    }

    Context 'Module name in header' {
        It 'should contain the module name in the header comment' {
            $Content | Should -Match ([regex]::Escape($TestModuleName))
        }

        It 'should contain DEVELOPMENT indicator in the header' {
            $Content | Should -Match 'DEVELOPMENT'
        }
    }

    Context 'Dot-sourcing loop present' {
        It 'should contain dot-source syntax' {
            # The generated script should dot-source files
            $Content | Should -Match '\.\s+\$_File\.FullName'
        }

        It 'should contain Get-ChildItem call for file discovery' {
            $Content | Should -Match 'Get-ChildItem'
        }
    }

    Context 'All four folder names in load order' {
        It 'should reference the Enums folder' {
            $Content | Should -Match "'Enums'"
        }

        It 'should reference the Classes folder' {
            $Content | Should -Match "'Classes'"
        }

        It 'should reference the Private folder' {
            $Content | Should -Match "'Private'"
        }

        It 'should reference the Public folder' {
            $Content | Should -Match "'Public'"
        }
    }

    Context 'Correct file filters for each section' {
        It 'should use *.Enum.ps1 filter for Enums section' {
            $Content | Should -Match ([regex]::Escape("'*.Enum.ps1'"))
        }

        It 'should use *.Class.ps1 filter for Classes section' {
            $Content | Should -Match ([regex]::Escape("'*.Class.ps1'"))
        }

        It 'should use *.ps1 filter for Private section' {
            $Content | Should -Match ([regex]::Escape("'*.ps1'"))
        }
    }

    Context 'Load order - Enums before Classes before Private before Public' {
        It 'should reference Enums before Classes' {
            $EnumsPos   = $Content.IndexOf("'Enums'")
            $ClassesPos = $Content.IndexOf("'Classes'")
            $EnumsPos | Should -BeLessThan $ClassesPos -Because 'Enums must be loaded before Classes'
        }

        It 'should reference Classes before Private' {
            $ClassesPos  = $Content.IndexOf("'Classes'")
            $PrivatePos  = $Content.IndexOf("'Private'")
            $ClassesPos | Should -BeLessThan $PrivatePos -Because 'Classes must be loaded before Private'
        }

        It 'should reference Private before Public' {
            $PrivatePos = $Content.IndexOf("'Private'")
            $PublicPos  = $Content.IndexOf("'Public'")
            $PrivatePos | Should -BeLessThan $PublicPos -Because 'Private must be loaded before Public'
        }
    }

    Context 'CRLF line endings' {
        It 'should use CRLF line endings' {
            $Content | Should -Match "`r`n"
        }

        It 'should not contain bare LF line endings' {
            $BareNL = $Content -replace "`r`n", '' | Select-String -Pattern "`n" -SimpleMatch
            $BareNL | Should -BeNullOrEmpty -Because 'all line endings should be CRLF'
        }
    }

    Context 'Test-Path guard for missing directories' {
        It 'should contain Test-Path check before loading each section' {
            $Content | Should -Match 'Test-Path'
        }
    }

    Context 'Different module names produce correct output' {
        It 'should embed the module name correctly for a dotted module name' {
            $AltContent = New-DevPsm1Content -ModuleName 'Acme.PS.Utils'
            $AltContent | Should -Match ([regex]::Escape('Acme.PS.Utils'))
        }
    }
}
