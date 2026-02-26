function Get-SampleData {
    # Alias: gsd
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Name = 'Default'
    )

    [PSCustomObject]@{
        Name      = $Name
        Timestamp = Get-Date
    }
}
