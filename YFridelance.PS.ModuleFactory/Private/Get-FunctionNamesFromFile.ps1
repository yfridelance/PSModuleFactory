function Get-FunctionNamesFromFile {
    <#
    .SYNOPSIS
        Extracts the names of all top-level function definitions from a PowerShell script file.

    .DESCRIPTION
        Uses the PowerShell Abstract Syntax Tree (AST) parser to parse the given file and
        return the names of every top-level FunctionDefinitionAst node. Nested functions
        (functions declared inside other functions) and methods inside class definitions are
        excluded.

        If parse errors occur, a non-terminating error is written and an empty array is
        returned. The function accepts pipeline input.

    .PARAMETER FilePath
        Full path to the .ps1 or .psm1 file to inspect. The file must exist.

    .EXAMPLE
        Get-FunctionNamesFromFile -FilePath 'C:\MyModule\Public\Get-Thing.ps1'
        # Returns: @('Get-Thing')

    .EXAMPLE
        Get-ChildItem -Path 'C:\MyModule\Public' -Filter '*.ps1' |
            Select-Object -ExpandProperty FullName |
            Get-FunctionNamesFromFile
        # Returns function names from all Public .ps1 files
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath
    )

    process {
        Write-Verbose "Get-FunctionNamesFromFile: Parsing '$FilePath'"

        $ParseErrors = $null
        $Tokens      = $null

        try {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $FilePath,
                [ref]$Tokens,
                [ref]$ParseErrors
            )
        }
        catch {
            Write-Error "Get-FunctionNamesFromFile: AST parser threw an exception for '$FilePath': $_"
            return [string[]]@()
        }

        if ($null -ne $ParseErrors -and $ParseErrors.Count -gt 0) {
            $ErrorMessages = ($ParseErrors | ForEach-Object { $_.Message }) -join '; '
            Write-Error "Get-FunctionNamesFromFile: Parse errors in '$FilePath': $ErrorMessages"
            return [string[]]@()
        }

        # Collect only top-level FunctionDefinitionAst nodes.
        # A top-level function has a parent that is the root ScriptBlockAst's
        # StatementAst list — i.e. its Parent.Parent is the root ScriptBlockAst.
        $FunctionNames = [System.Collections.Generic.List[string]]::new()

        $FindFunctions = {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }

        $AllFunctions = $Ast.FindAll($FindFunctions, $true)

        foreach ($FuncDef in $AllFunctions) {
            # Walk up the parent chain to determine nesting level.
            # Top-level functions: Parent is a NamedBlockAst (e.g. 'End' block) whose
            # Parent is the root ScriptBlockAst. They must NOT have any ancestor that is
            # also a FunctionDefinitionAst or a TypeDefinitionAst (class).
            $IsNested = $false
            $Current  = $FuncDef.Parent

            while ($null -ne $Current) {
                if ($Current -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    $IsNested = $true
                    break
                }
                if ($Current -is [System.Management.Automation.Language.TypeDefinitionAst]) {
                    $IsNested = $true
                    break
                }
                $Current = $Current.Parent
            }

            if (-not $IsNested) {
                Write-Verbose "  Found top-level function: '$($FuncDef.Name)'"
                $FunctionNames.Add($FuncDef.Name)
            }
            else {
                Write-Verbose "  Skipping nested/class member: '$($FuncDef.Name)'"
            }
        }

        Write-Verbose "Get-FunctionNamesFromFile: Found $($FunctionNames.Count) top-level function(s)."
        return [string[]]$FunctionNames.ToArray()
    }
}
