#Requires -Version 5.1
BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath (Join-Path -Path '..' -ChildPath 'YFridelance.PS.ModuleFactory')))
    Import-Module -Name $ModulePath -Force

    # Dot-source the private function
    . (Join-Path -Path $ModulePath -ChildPath (Join-Path 'Private' 'ConvertTo-SortedClassFileName.ps1'))
}

Describe 'ConvertTo-SortedClassFileName' {

    Context 'Index 0 - first class' {
        It 'should produce 01_ prefix for SortIndex 0' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'BaseModel' -SortIndex 0
            $Result | Should -Be '01_BaseModel.Class.ps1'
        }

        It 'should include the .Class.ps1 suffix' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'BaseModel' -SortIndex 0
            $Result | Should -Match '\.Class\.ps1$'
        }
    }

    Context 'Index 1 - second class' {
        It 'should produce 02_ prefix for SortIndex 1' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'DerivedModel' -SortIndex 1
            $Result | Should -Be '02_DerivedModel.Class.ps1'
        }
    }

    Context 'Index 4 - fifth class' {
        It 'should produce 05_ prefix for SortIndex 4' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'CustomerOrder' -SortIndex 4
            $Result | Should -Be '05_CustomerOrder.Class.ps1'
        }
    }

    Context 'Index 9 - tenth class' {
        It 'should produce 10_ prefix for SortIndex 9' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'TenthClass' -SortIndex 9
            $Result | Should -Be '10_TenthClass.Class.ps1'
        }
    }

    Context 'Index 99 - hundredth class' {
        It 'should produce 100_ prefix for SortIndex 99' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'HundredthClass' -SortIndex 99
            $Result | Should -Be '100_HundredthClass.Class.ps1'
        }
    }

    Context 'Return type' {
        It 'should return a string' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'MyClass' -SortIndex 0
            $Result | Should -BeOfType [string]
        }
    }

    Context 'Class name with dots (dotted name)' {
        It 'should preserve dots in the class name verbatim' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'My.Special.Class' -SortIndex 0
            $Result | Should -Be '01_My.Special.Class.Class.ps1'
        }
    }

    Context 'Class name with underscores' {
        It 'should preserve underscores in the class name verbatim' {
            $Result = ConvertTo-SortedClassFileName -ClassName 'My_Class_Name' -SortIndex 2
            $Result | Should -Be '03_My_Class_Name.Class.ps1'
        }
    }

    Context 'Sequential classes produce sorted file names' {
        It 'should produce sequentially sortable names for a list of classes' {
            $Classes = @('Alpha', 'Beta', 'Gamma', 'Delta')
            $Results = for ($i = 0; $i -lt $Classes.Count; $i++) {
                ConvertTo-SortedClassFileName -ClassName $Classes[$i] -SortIndex $i
            }

            $Results[0] | Should -Be '01_Alpha.Class.ps1'
            $Results[1] | Should -Be '02_Beta.Class.ps1'
            $Results[2] | Should -Be '03_Gamma.Class.ps1'
            $Results[3] | Should -Be '04_Delta.Class.ps1'
        }
    }
}
