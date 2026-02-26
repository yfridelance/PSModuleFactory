#
# Module: YFridelance.PS.ModuleFactory
# Development loader - dot-sources all individual function files.
# For distribution, use Build-PSModule to merge into a single file.
#

$ModuleRoot = $PSScriptRoot

# Module-scope constants (not exported, used by private functions)
$Script:ModuleFactoryVersion = '0.1.1'
$Script:SupportedManifestFields = @(
    'FunctionsToExport'
    'AliasesToExport'
    'ModuleVersion'
    'Description'
    'Author'
)
$Script:DefaultEncoding = [System.Text.UTF8Encoding]::new($true)
$Script:LoadOrderFolders = @('Enums', 'Classes', 'Private', 'Public')

# Load order: Enums -> Classes -> Private -> Public
foreach ($Folder in $Script:LoadOrderFolders) {
    $FolderPath = Join-Path -Path $ModuleRoot -ChildPath $Folder
    if (Test-Path -Path $FolderPath) {
        $Files = Get-ChildItem -Path $FolderPath -Filter '*.ps1' -File | Sort-Object Name
        foreach ($File in $Files) {
            try {
                . $File.FullName
                Write-Verbose -Message "Loaded: $($File.Name)"
            }
            catch {
                Write-Error -Message "Failed to load '$($File.FullName)': $_"
            }
        }
    }
}
