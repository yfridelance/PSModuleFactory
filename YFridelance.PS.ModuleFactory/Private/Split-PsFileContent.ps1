function Split-PsFileContent {
    <#
    .SYNOPSIS
        Parses a PowerShell file and splits its content into typed, named segments.

    .DESCRIPTION
        Uses the PowerShell Abstract Syntax Tree (AST) to identify top-level definitions in the
        given file: functions (FunctionDefinitionAst), classes (TypeDefinitionAst where IsClass),
        and enums (TypeDefinitionAst where IsEnum).

        For each definition a [PSCustomObject] is returned with the following properties:

            Name    [string]  — The function, class, or enum name.
            Type    [string]  — 'Function', 'Class', or 'Enum'.
            Scope   [string]  — 'Public' (function in $PublicFunctionNames), 'Private'
                               (function not in $PublicFunctionNames), or 'None'
                               (classes and enums).
            Content [string]  — The full source text of the definition, including any
                               comment-based help block that immediately precedes it.

        Only top-level definitions are returned. Nested functions (inside other functions or
        classes) are excluded.

        If a comment-based help block (a block comment) immediately precedes a definition (separated
        only by whitespace / blank lines), it is included in the Content property.

    .PARAMETER FilePath
        Full path to the .ps1 or .psm1 file to parse. The file must exist.

    .PARAMETER PublicFunctionNames
        An optional list of function names to mark as Scope='Public'. Functions not present in
        this list are marked Scope='Private'. Defaults to an empty array (all functions Private).

    .EXAMPLE
        $Segments = Split-PsFileContent -FilePath 'C:\MyModule\Public\Get-Thing.ps1' `
                                        -PublicFunctionNames @('Get-Thing')
        $Segments | Format-Table Name, Type, Scope

    .EXAMPLE
        # Split a merged .psm1 to extract individual definitions
        Split-PsFileContent -FilePath 'C:\MyModule\MyModule.psm1' -Verbose |
            Where-Object { $_.Scope -eq 'Public' } |
            ForEach-Object { Write-Host "Public function: $($_.Name)" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$FilePath,

        [Parameter()]
        [string[]]$PublicFunctionNames = @()
    )

    Write-Verbose "Split-PsFileContent: Parsing '$FilePath'"

    # Read file content for preceding comment extraction
    try {
        $FileContent = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Error "Split-PsFileContent: Could not read file '$FilePath': $_"
        return [PSCustomObject[]]@()
    }

    # Parse with AST
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
        Write-Error "Split-PsFileContent: AST parser exception for '$FilePath': $_"
        return [PSCustomObject[]]@()
    }

    if ($null -ne $ParseErrors -and $ParseErrors.Count -gt 0) {
        $ErrorMessages = ($ParseErrors | ForEach-Object { $_.Message }) -join '; '
        Write-Error "Split-PsFileContent: Parse errors in '$FilePath': $ErrorMessages"
        return [PSCustomObject[]]@()
    }

    # Helper: Check whether a node has an ancestor that is a function or class definition
    # (to exclude nested/member definitions).
    function IsTopLevel {
        param($Node)
        $Current = $Node.Parent
        while ($null -ne $Current) {
            if ($Current -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                return $false
            }
            if ($Current -is [System.Management.Automation.Language.TypeDefinitionAst]) {
                return $false
            }
            $Current = $Current.Parent
        }
        return $true
    }

    # Helper: Given the start offset of a definition in the file, scan backwards through
    # the token stream to find any immediately preceding comment-based help block.
    # Returns the start offset to use for Content extraction (may be earlier than $NodeStart).
    function Get-ContentStartOffset {
        param(
            [int]$NodeStartOffset,
            [System.Management.Automation.Language.Token[]]$AllTokens
        )

        # Find the token index immediately before the definition start
        $PrecedingCommentEnd   = -1
        $PrecedingCommentStart = -1

        for ($i = 0; $i -lt $AllTokens.Count; $i++) {
            $Token = $AllTokens[$i]
            if ($Token.Extent.StartOffset -ge $NodeStartOffset) {
                break
            }

            # Look for comment tokens
            if ($Token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) {
                $TText = $Token.Text.Trim()
                # Detect a block comment that looks like comment-based help
                if ($TText.StartsWith('<#') -and $TText.EndsWith('#>')) {
                    $PrecedingCommentStart = $Token.Extent.StartOffset
                    $PrecedingCommentEnd   = $Token.Extent.EndOffset
                }
            }
        }

        # Only include if the comment is adjacent (only whitespace between end of comment and start of node)
        if ($PrecedingCommentStart -ge 0) {
            $Between = $FileContent.Substring($PrecedingCommentEnd, $NodeStartOffset - $PrecedingCommentEnd)
            if ($Between.Trim() -eq '') {
                return $PrecedingCommentStart
            }
        }

        return $NodeStartOffset
    }

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Collect FunctionDefinitionAst nodes
    $FunctionFinder = { param($N) $N -is [System.Management.Automation.Language.FunctionDefinitionAst] }
    $AllFunctions   = $Ast.FindAll($FunctionFinder, $true)

    foreach ($FuncDef in $AllFunctions) {
        if (-not (IsTopLevel $FuncDef)) {
            Write-Verbose "  Skipping nested function: '$($FuncDef.Name)'"
            continue
        }

        $Scope = if ($PublicFunctionNames -contains $FuncDef.Name) { 'Public' } else { 'Private' }

        $StartOffset = Get-ContentStartOffset -NodeStartOffset $FuncDef.Extent.StartOffset -AllTokens $Tokens
        $Length      = $FuncDef.Extent.EndOffset - $StartOffset
        $Content     = $FileContent.Substring($StartOffset, $Length)

        Write-Verbose "  Function '$($FuncDef.Name)' Scope='$Scope'"

        $Results.Add([PSCustomObject]@{
            Name    = $FuncDef.Name
            Type    = 'Function'
            Scope   = $Scope
            Content = $Content
        })
    }

    # Collect TypeDefinitionAst nodes (classes and enums)
    $TypeFinder = { param($N) $N -is [System.Management.Automation.Language.TypeDefinitionAst] }
    $AllTypes   = $Ast.FindAll($TypeFinder, $true)

    foreach ($TypeDef in $AllTypes) {
        if (-not (IsTopLevel $TypeDef)) {
            Write-Verbose "  Skipping nested type: '$($TypeDef.Name)'"
            continue
        }

        $IsClass = $TypeDef.IsClass
        $IsEnum  = $TypeDef.IsEnum
        if (-not $IsClass -and -not $IsEnum) {
            continue
        }

        $TypeKind    = if ($IsClass) { 'Class' } else { 'Enum' }
        $StartOffset = Get-ContentStartOffset -NodeStartOffset $TypeDef.Extent.StartOffset -AllTokens $Tokens
        $Length      = $TypeDef.Extent.EndOffset - $StartOffset
        $Content     = $FileContent.Substring($StartOffset, $Length)

        Write-Verbose "  $TypeKind '$($TypeDef.Name)' Scope='None'"

        $Results.Add([PSCustomObject]@{
            Name    = $TypeDef.Name
            Type    = $TypeKind
            Scope   = 'None'
            Content = $Content
        })
    }

    Write-Verbose "Split-PsFileContent: Extracted $($Results.Count) top-level definition(s)."
    return [PSCustomObject[]]$Results.ToArray()
}
