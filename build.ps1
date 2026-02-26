#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Builds YFridelance.PS.ModuleFactory using itself (dogfooding).

.DESCRIPTION
    This script imports the dev version of YFridelance.PS.ModuleFactory and uses
    Build-PSModule to create the distributable version in ./dist/.

.EXAMPLE
    ./build.ps1

    Builds the module to ./dist/YFridelance.PS.ModuleFactory/

.EXAMPLE
    ./build.ps1 -Clean

    Cleans the output directory before building.
#>
[CmdletBinding()]
param(
    [switch]$Clean,

    [string]$Prerelease
)

$ErrorActionPreference = 'Stop'

# Import the dev version of the module
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'YFridelance.PS.ModuleFactory'
Write-Host "Importing module from: $ModulePath" -ForegroundColor Cyan
Import-Module -Name $ModulePath -Force -Verbose:$false

# Build the module
$OutputPath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path 'dist' -ChildPath 'YFridelance.PS.ModuleFactory')

$BuildParams = @{
    Path       = $ModulePath
    OutputPath = $OutputPath
    Verbose    = $true
}

if ($Clean) {
    $BuildParams['Clean'] = $true
}

Write-Host "`nBuilding YFridelance.PS.ModuleFactory..." -ForegroundColor Cyan
$Result = Build-PSModule @BuildParams

if ($Result.Success) {
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "  Output:    $($Result.OutputPath)" -ForegroundColor Green
    Write-Host "  Functions: $($Result.FunctionsExported -join ', ')" -ForegroundColor Green
    Write-Host "  Aliases:   $($Result.AliasesExported -join ', ')" -ForegroundColor Green
    Write-Host "  Files:     $($Result.FilesMerged) files merged" -ForegroundColor Green
    if ($Prerelease) {
        # Dot-source the private helper (not exported by the module)
        . (Join-Path -Path $ModulePath -ChildPath (Join-Path -Path 'Private' -ChildPath 'Update-ManifestField.ps1'))
        $Script:DefaultEncoding = [System.Text.UTF8Encoding]::new($true)
        $BuiltManifestPath = Join-Path -Path $OutputPath -ChildPath 'YFridelance.PS.ModuleFactory.psd1'
        Update-ManifestField -ManifestPath $BuiltManifestPath -FieldName 'Prerelease' -Value $Prerelease
        Write-Host "  Prerelease: $Prerelease" -ForegroundColor Green
    }
}
else {
    Write-Host "`nBuild failed!" -ForegroundColor Red
    exit 1
}
