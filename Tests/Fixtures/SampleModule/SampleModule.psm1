$ModuleRoot = $PSScriptRoot
$LoadOrder = @('Enums', 'Classes', 'Private', 'Public')
foreach ($Folder in $LoadOrder) {
    $FolderPath = Join-Path -Path $ModuleRoot -ChildPath $Folder
    if (Test-Path -Path $FolderPath) {
        $Files = Get-ChildItem -Path $FolderPath -Filter '*.ps1' -File | Sort-Object Name
        foreach ($File in $Files) {
            . $File.FullName
        }
    }
}
